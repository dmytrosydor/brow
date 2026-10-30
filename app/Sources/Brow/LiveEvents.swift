import Foundation

/// Turns hook events forwarded by brow-hook into session state, and decides
/// which hook calls to hold for a reply.
/// Payload: {"event": <hook input>, "env": {CLAUDE_CODE_ENTRYPOINT, ...}}.
extension SessionStore {
    func apply(_ payload: [String: Any], responder: Responder) {
        if payload["brow"] != nil {
            control(payload)
            responder.release()
            return
        }
        guard let event = payload["event"] as? [String: Any],
              let id = event["session_id"] as? String,
              let name = event["hook_event_name"] as? String else {
            responder.release()
            return
        }
        let env = payload["env"] as? [String: String] ?? [:]
        let tool = event["tool_name"] as? String
        let input = event["tool_input"] as? [String: Any] ?? [:]
        debugLog("event \(name) \(tool ?? "") \(id)")
        // Whatever is not held below is let go right away.
        var held = false
        defer { if !held { responder.release() } }

        if name == "SessionEnd" {
            release(id)
            forget(id)
            if let lost = sessions.first(where: { $0.id == id }), !lost.queued.isEmpty {
                showToast(tr("\(lost.project) ended with messages still in the queue", "«\(lost.project)» закрилась, а повідомлення лишились у черзі"))
            }
            sessions.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
            return
        }

        var session = sessions.first { $0.id == id } ?? newSession(id: id, event: event, env: env)
        let before = session.updated
        session.updated = .now
        let mayHold = prefs.holdReplies && !prefs.skippedSessions.contains(id)

        switch (name, tool) {
        case ("SessionStart", _):
            break
        case ("UserPromptSubmit", _):
            // The user wrote in the app or terminal: nothing to answer from the notch.
            release(id)
            session.state = .working
            session.wrapUp = nil
            session.questions = []
            session.permission = nil
            session.command = nil
            session.activity = nil
            session.workStarted = .now
            if session.title.isEmpty, let prompt = event["prompt"] as? String {
                session.title = Self.title(from: prompt)
            }
            if session.lastMessage == Self.newSessionText { session.lastMessage = tr("Working…", "Працює…") }
        case ("PreToolUse", "mcp__ccd_turn__wrap_up"):
            session.wrapUp = Self.wrapUp(from: input)
        case ("PreToolUse", "AskUserQuestion"):
            session.questions = Self.questions(from: input)
            session.state = .waiting
        case ("PreToolUse", let tool?):
            // Runs before every tool call: keeps the card current, not the list order.
            session.updated = before
            session.activity = Self.activity(tool: tool, input: input)
            if session.workStarted == nil { session.workStarted = .now }
            if session.questions.isEmpty, session.permission == nil { session.state = .working }
        case ("PermissionRequest", "AskUserQuestion"):
            session.questions = Self.questions(from: input)
            session.state = .waiting
            if mayHold {
                hold(.question, session: id, responder: responder, toolInput: input)
                held = true
            }
        case ("PermissionRequest", let tool?):
            let ask = Self.permissionAsk(tool: tool, input: input)
            session.state = .waiting
            if mayHold {
                held = true
                if holdPermission(ask, session: id, responder: responder, toolInput: input) { session.permission = ask }
            } else {
                session.permission = ask
            }
        case ("PostToolUse", "AskUserQuestion"):
            // Answered in the app, or by us: drop the question from the notch.
            release(id, only: .question)
            session.questions = []
            session.state = .working
        case ("PostToolUse", let tool?), ("PostToolUseFailure", let tool?):
            // Every tool call ends here. It says the session is busy, and may
            // settle a permission given in the app. It should not reorder the list.
            session.updated = before
            settlePermission(id, tool: tool, input: input)
            session.permission = holds[id]?.permission
            if session.questions.isEmpty {
                session.state = session.permission == nil ? .working : .waiting
            }
        case ("Notification", _):
            session.state = .waiting
            // Refusing a permission in the app or terminal sends no event; the
            // session just goes idle at the prompt, which is announced after a minute.
            if event["notification_type"] as? String == "idle_prompt" {
                release(id, only: .permission)
                session.permission = nil
                session.activity = nil
                session.workStarted = nil
            }
            // Keep Claude's own last words; a notice only fills an empty card.
            // ("needs your permission to use AskUserQuestion" comes with every question.)
            let placeholder = session.lastMessage == Self.newSessionText || session.lastMessage == tr("Working…", "Працює…")
            if placeholder, session.questions.isEmpty, let message = event["message"] as? String {
                session.lastMessage = message
            }
        case ("Stop", _):
            if let message = event["last_assistant_message"] as? String, !message.isEmpty {
                session.lastMessage = message
                session.command = Self.command(in: message)
            }
            // A permission refused in the app ends the turn without a PostToolUse.
            release(id, only: .permission)
            session.permission = nil
            // The queue goes out whatever is in front: the user asked for it.
            if !session.queued.isEmpty {
                responder.send(["decision": "block", "reason": Self.replyReason(session.queued.joined(separator: "\n\n"))])
                debugLog("queue delivered to \(id)")
                showToast(tr("Sent the queue to \(session.project)", "Чергу відправлено в «\(session.project)»"))
                session.queued = []
                session.activity = nil
                session.workStarted = .now
                session.state = .working
                session.wrapUp = nil
                session.command = nil
                break
            }
            session.activity = nil
            session.workStarted = nil
            let asks = !session.questions.isEmpty || session.wrapUp?.ask != nil
            session.state = asks ? .waiting : .done
            if mayHold && !isFrontmost(session) {
                hold(.stop, session: id, responder: responder)
                held = true
                // Held means Claude is waiting for the user, even with no question.
                session.state = .waiting
            }
        default:
            return
        }

        if let i = sessions.firstIndex(where: { $0.id == id }) {
            sessions[i] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updated > $1.updated }
        considerPeek(session)
    }

    /// Test hook, only with BROW_DEBUG: act as if the notch was clicked.
    /// {"brow": "reply"|"answer"|"queue"|"allow"|"deny"|"release"|"select", "session": id, "text": …, "answers": {…}}
    private func control(_ payload: [String: Any]) {
        guard ProcessInfo.processInfo.environment["BROW_DEBUG"] != nil,
              let id = payload["session"] as? String,
              let session = sessions.first(where: { $0.id == id }) else { return }
        switch payload["brow"] as? String {
        case "reply": send(payload["text"] as? String ?? "", to: session)
        case "answer": answer(payload["answers"] as? [String: String] ?? [:], to: session)
        case "queue": enqueue(payload["text"] as? String ?? "", for: session)
        case "allow": decide(allow: true, session: session)
        case "deny": decide(allow: false, message: payload["text"] as? String, session: session)
        case "release": release(id)
        case "select": selectedID = id
        default: break
        }
    }

    private func newSession(id: String, event: [String: Any], env: [String: String]) -> Session {
        let cwd = event["cwd"] as? String
        return Session(
            id: id,
            project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude",
            title: "",
            client: env["CLAUDE_CODE_ENTRYPOINT"] == "claude-desktop" ? .desktop : .terminal,
            state: .done,
            updated: .now,
            lastMessage: Self.newSessionText,
            cwd: cwd,
            termProgram: env["TERM_PROGRAM"]
        )
    }

    /// One line about the tool call that is starting.
    static func activity(tool: String, input: [String: Any]) -> Activity {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Bash":
            return Activity(kind: tr("Running a command", "Запускає команду"), detail: input["command"] as? String)
        case "Read":
            return Activity(kind: tr("Reading", "Читає"), detail: file)
        case "Edit", "MultiEdit", "NotebookEdit":
            return Activity(kind: tr("Editing", "Змінює"), detail: file)
        case "Write":
            return Activity(kind: tr("Writing", "Записує"), detail: file)
        case "Grep", "Glob":
            return Activity(kind: tr("Searching the code", "Шукає в коді"), detail: input["pattern"] as? String)
        case "WebFetch":
            return Activity(kind: tr("Opening a page", "Відкриває сторінку"), detail: input["url"] as? String)
        case "WebSearch":
            return Activity(kind: tr("Searching the web", "Шукає в інтернеті"), detail: input["query"] as? String)
        case "Task", "Agent":
            return Activity(kind: tr("Running an agent", "Запускає агента"), detail: input["description"] as? String)
        default:
            return Activity(kind: tr("Using \(tool)", "Використовує \(tool)"), detail: nil)
        }
    }

    /// What to show on a permission card: the whole command, or the file and
    /// the change, or the raw input for any other tool.
    static func permissionAsk(tool: String, input: [String: Any]) -> PermissionAsk {
        let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
        switch tool {
        case "Bash":
            return PermissionAsk(tool: tool, title: tr("wants to run a command", "хоче запустити команду"),
                                 detail: input["command"] as? String ?? "")
        case "Edit":
            let change = "- \(input["old_string"] as? String ?? "")\n+ \(input["new_string"] as? String ?? "")"
            return PermissionAsk(tool: tool, title: tr("wants to edit a file", "хоче змінити файл"), detail: "\(path)\n\n\(change)")
        case "Write":
            return PermissionAsk(tool: tool, title: tr("wants to write a file", "хоче записати файл"),
                                 detail: "\(path)\n\n\(input["content"] as? String ?? "")")
        case "Read":
            return PermissionAsk(tool: tool, title: tr("wants to read a file", "хоче прочитати файл"), detail: path)
        case "WebFetch":
            return PermissionAsk(tool: tool, title: tr("wants to open a page", "хоче відкрити сторінку"),
                                 detail: input["url"] as? String ?? "")
        default:
            let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return PermissionAsk(tool: tool, title: tr("wants to use \(tool)", "хоче використати \(tool)"),
                                 detail: data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        }
    }

    static let newSessionText = tr("New session", "Нова сесія")

    static func title(from prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    static func wrapUp(from input: [String: Any]) -> WrapUp {
        // Buttons with "action" are app actions (commit, PR…), only the app can run them.
        let actions = (input["actions"] as? [[String: Any]] ?? []).compactMap { action -> WrapAction? in
            guard let label = action["label"] as? String, action["action"] == nil else { return nil }
            return WrapAction(label: label, message: action["message"] as? String ?? label)
        }
        return WrapUp(recap: input["recap"] as? String ?? "", ask: input["ask"] as? String, actions: actions)
    }

    static func questions(from input: [String: Any]) -> [Question] {
        (input["questions"] as? [[String: Any]] ?? []).map { item in
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> QuestionOption? in
                guard let label = option["label"] as? String else { return nil }
                return QuestionOption(label: label, detail: option["description"] as? String ?? "")
            }
            return Question(header: item["header"] as? String ?? "", text: item["question"] as? String ?? "",
                            options: options, multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }

    /// First shell code block in the message, the command the notch offers to run.
    static func command(in message: String) -> String? {
        let pattern = "```(?:bash|sh|zsh|shell)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        let command = message[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }
}
