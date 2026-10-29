import Foundation

/// Turns hook events forwarded by brow-hook into session state.
/// Payload: {"event": <hook input>, "env": {CLAUDE_CODE_ENTRYPOINT, ...}}.
extension SessionStore {
    func apply(_ payload: [String: Any]) {
        guard let event = payload["event"] as? [String: Any],
              let id = event["session_id"] as? String,
              let name = event["hook_event_name"] as? String else { return }
        let env = payload["env"] as? [String: String] ?? [:]
        if ProcessInfo.processInfo.environment["BROW_DEBUG"] != nil {
            FileHandle.standardError.write(Data("event \(name) \(event["tool_name"] ?? "") \(id)\n".utf8))
        }

        if name == "SessionEnd" {
            sessions.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
            return
        }

        var session = sessions.first { $0.id == id } ?? newSession(id: id, event: event, env: env)
        session.updated = .now
        let tool = event["tool_name"] as? String
        let input = event["tool_input"] as? [String: Any] ?? [:]

        switch (name, tool) {
        case ("SessionStart", _):
            break
        case ("UserPromptSubmit", _):
            session.state = .working
            session.wrapUp = nil
            session.question = nil
            session.command = nil
            if session.title.isEmpty, let prompt = event["prompt"] as? String {
                session.title = Self.title(from: prompt)
            }
            if session.lastMessage == Self.newSessionText { session.lastMessage = "Працює…" }
        case ("PreToolUse", "mcp__ccd_turn__wrap_up"):
            session.wrapUp = Self.wrapUp(from: input)
        case ("PreToolUse", "AskUserQuestion"), ("PermissionRequest", "AskUserQuestion"):
            session.question = Self.question(from: input)
            session.state = .waiting
        case ("PostToolUse", "AskUserQuestion"):
            session.question = nil
            session.state = .working
        case ("Notification", _):
            session.state = .waiting
            if let message = event["message"] as? String { session.lastMessage = message }
        case ("Stop", _):
            if let message = event["last_assistant_message"] as? String, !message.isEmpty {
                session.lastMessage = message
                session.command = Self.command(in: message)
            }
            let asks = session.question != nil || session.wrapUp?.ask != nil
            session.state = asks ? .waiting : .done
        default:
            return
        }

        if let i = sessions.firstIndex(where: { $0.id == id }) {
            sessions[i] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updated > $1.updated }
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
            cwd: cwd
        )
    }

    static let newSessionText = "Нова сесія"

    static func title(from prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    static func wrapUp(from input: [String: Any]) -> WrapUp {
        let actions = (input["actions"] as? [[String: Any]] ?? []).compactMap { action -> WrapAction? in
            guard let label = action["label"] as? String, action["action"] == nil else { return nil }
            return WrapAction(label: label, message: action["message"] as? String ?? label)
        }
        return WrapUp(recap: input["recap"] as? String ?? "", ask: input["ask"] as? String, actions: actions)
    }

    static func question(from input: [String: Any]) -> Question? {
        guard let first = (input["questions"] as? [[String: Any]])?.first else { return nil }
        let options = (first["options"] as? [[String: Any]] ?? []).compactMap { option -> QuestionOption? in
            guard let label = option["label"] as? String else { return nil }
            return QuestionOption(label: label, detail: option["description"] as? String ?? "")
        }
        return Question(header: first["header"] as? String ?? "", text: first["question"] as? String ?? "", options: options)
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
