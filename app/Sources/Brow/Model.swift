import AppKit
import BrowShared
import Foundation
import Observation

enum SessionState {
    case working, waiting, done
}

enum Client {
    case desktop, terminal

    var symbol: String { self == .desktop ? "macwindow" : "terminal" }
    var name: String { self == .desktop ? "Claude" : tr("Terminal", "Термінал") }
}

struct QuestionOption: Hashable {
    var label: String
    var detail: String
}

/// One AskUserQuestion question as seen by the PermissionRequest hook.
struct Question: Hashable {
    var header: String
    var text: String
    var options: [QuestionOption]
    var multiSelect = false
}

/// A tool call waiting for the user's permission, as PermissionRequest sees it.
struct PermissionAsk: Equatable {
    var tool: String
    /// "wants to run a command", shown after the project name.
    var title: String
    /// The whole command, file or input, so the user sees what they approve.
    var detail: String
}

/// What Claude is doing right now.
struct Activity: Equatable {
    /// "Running a command"
    var kind: String
    /// The command, file or query. May contain secrets, so it can be hidden.
    var detail: String?
}

/// One button of the desktop app's wrap_up box.
struct WrapAction: Hashable {
    var label: String
    var message: String
}

struct WrapUp {
    var recap: String
    var ask: String?
    var actions: [WrapAction]
}

struct Session: Identifiable {
    var id = UUID().uuidString
    var project: String
    var title: String
    var client: Client
    var state: SessionState
    var updated: Date
    var lastMessage: String
    var command: String?
    var wrapUp: WrapUp?
    var questions: [Question] = []
    var permission: PermissionAsk?
    /// Messages written while Claude works, delivered at its next stop.
    var queued: [String] = []
    var activity: Activity?
    /// When the current stretch of work began; nil while Claude is not working.
    var workStarted: Date?
    /// The last hook event of any kind, unlike `updated`, which orders the list.
    var lastEvent = Date.now
    /// Marked working, but silent for a long time: possibly closed unannounced.
    var stale = false
    var usage: ContextUsage?
    var contextWarned = false
    var cwd: String?
    /// TERM_PROGRAM of a terminal session, to know which app shows it.
    var termProgram: String?

    /// What the notch can do for this session, shown as a tag in the list.
    var tag: String? {
        if permission != nil { return tr("Permission", "Дозвіл") }
        if !questions.isEmpty { return tr("Question", "Питання") }
        if !queued.isEmpty { return tr("Queued", "У черзі") }
        if wrapUp?.actions.isEmpty == false { return tr("Buttons", "Кнопки") }
        if command != nil { return tr("Command", "Команда") }
        return nil
    }

    /// Bundle id of the app this session lives in, when known.
    var appBundleID: String? {
        if client == .desktop { return "com.anthropic.claudefordesktop" }
        switch termProgram {
        case "ghostty": return "com.mitchellh.ghostty"
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        default: return nil
        }
    }
}

/// The notch sliding down for a moment to say a session is waiting.
struct Peek: Equatable {
    /// Which session to open on hover; nil when it sums up several.
    var sessionID: String?
    var title: String
    var detail: String
    var isCommand = false
}

/// A hook call brow is holding open so a reply from the notch can reach Claude.
final class Hold {
    enum Kind { case stop, question, permission }

    let kind: Kind
    let responder: Responder
    /// The tool's input: AskUserQuestion's goes back with the answers, a
    /// permission's tells which tool call a later PostToolUse settles.
    let toolInput: [String: Any]
    let permission: PermissionAsk?
    var timeout: DispatchWorkItem?

    init(kind: Kind, responder: Responder, toolInput: [String: Any] = [:], permission: PermissionAsk? = nil) {
        self.kind = kind
        self.responder = responder
        self.toolInput = toolInput
        self.permission = permission
    }
}

@Observable
final class SessionStore {
    var sessions: [Session]
    var expanded = false
    var selectedID: Session.ID?
    var toast: String?
    /// Set when launched straight into a state, so the notch stays open for a
    /// screenshot until the mouse visits it.
    var pinned = false
    /// Demo data: replies only change the picture, nothing is sent.
    var demo = false
    let prefs = Preferences()
    var holds: [String: Hold] = [:]
    /// Parallel tool calls ask at once: further permissions wait here, one is
    /// shown at a time.
    var queuedPermissions: [String: [Hold]] = [:]
    private let transcripts = TranscriptUsage()
    /// When each session's transcript was last read, to read at most every few seconds.
    private var usageRead: [String: Date] = [:]
    /// Opened with the hot key: show the key hints, close after answering.
    var keyboardMode = false
    var optionPress: OptionPress?
    /// A key typed outside the reply field, to put into it.
    var replySeed: String?
    var onClose: (() -> Void)?
    /// Test hook: presses the hot key.
    var onDebugHotKey: (() -> Void)?
    var peek: Peek?
    /// The first-run card is showing.
    var welcome = false
    /// What each session last alerted about, so one request alerts once
    /// although several hook events report it.
    private var peekKeys: [String: String] = [:]
    private var peekTimeout: DispatchWorkItem?

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var selected: Session? { sessions.first { $0.id == selectedID } }

    func forget(_ id: String) {
        peekKeys[id] = nil
        usageRead[id] = nil
        transcripts.forget(session: id)
        if peek?.sessionID == id { hidePeek() }
    }

    func select(_ session: Session?) {
        selectedID = session?.id
    }

    func canReply(_ session: Session) -> Bool {
        demo || holds[session.id] != nil
    }

    // MARK: Replies

    /// Free text or a wrap_up button: becomes the user's next message (for a
    /// question: the answer to every question).
    func send(_ text: String, to session: Session) {
        if session.permission != nil, holds[session.id]?.kind == .permission {
            decide(allow: false, message: text, session: session)
            return
        }
        if let hold = takeHold(session) {
            switch hold.kind {
            case .stop:
                hold.responder.send(["decision": "block", "reason": Self.replyReason(text)])
            case .question:
                let answers = session.questions.reduce(into: [String: String]()) { $0[$1.text] = text }
                hold.responder.send(Self.answerOutput(hold.toolInput, answers))
            case .permission:
                break
            }
        } else if !demo {
            showToast(tr("\(session.project) is no longer waiting for a reply", "«\(session.project)» вже не чекає відповіді"))
            return
        }
        replied(session, note: tr("Sent to \(session.project): \(text)", "Відправлено в «\(session.project)»: \(text)"))
    }

    /// Answers to AskUserQuestion, question text → chosen label(s) or own text.
    func answer(_ answers: [String: String], to session: Session) {
        if let hold = takeHold(session) {
            hold.responder.send(Self.answerOutput(hold.toolInput, answers))
        } else if !demo {
            showToast(tr("\(session.project) is no longer waiting for a reply", "«\(session.project)» вже не чекає відповіді"))
            return
        }
        replied(session, note: tr("Answered \(session.project): ", "Відповідь у «\(session.project)»: ") + answers.values.joined(separator: "; "))
    }

    /// Allows or denies the tool call on the card. A denial's message reaches
    /// Claude, which carries on with it.
    func decide(allow: Bool, message: String? = nil, session: Session) {
        if let hold = takeHold(session) {
            var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
            if !allow {
                decision["message"] = message ?? "The user denied this from brow, the notch app that shows this session."
            }
            hold.responder.send(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        } else if !demo {
            showToast(tr("\(session.project) is no longer waiting for a reply", "«\(session.project)» вже не чекає відповіді"))
            return
        }
        replied(session, note: allow ? tr("Allowed in \(session.project)", "Дозволено в «\(session.project)»")
                                     : tr("Denied in \(session.project)", "Відхилено в «\(session.project)»"))
        showNextPermission(session.id)
    }

    // MARK: Queue

    /// A message for a session that is still working; it goes out at the next stop.
    func enqueue(_ text: String, for session: Session) {
        guard !text.isEmpty, let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i].queued.append(text)
    }

    func removeQueued(at index: Int, from session: Session) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }),
              sessions[i].queued.indices.contains(index) else { return }
        sessions[i].queued.remove(at: index)
    }

    /// Claude sees a Stop block reason as hook feedback; say it is the user
    /// talking, or it may treat the reply as a message from the hook.
    static func replyReason(_ text: String) -> String {
        "The user replied from brow, the notch app that shows this session, instead of the chat. "
            + "Treat it as their next message:\n\n" + text
    }

    static func answerOutput(_ toolInput: [String: Any], _ answers: [String: String]) -> [String: Any] {
        var input = toolInput
        input["answers"] = answers
        return ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": ["behavior": "allow", "updatedInput": input],
        ]]
    }

    private func takeHold(_ session: Session) -> Hold? {
        guard let hold = holds.removeValue(forKey: session.id) else { return nil }
        hold.timeout?.cancel()
        debugLog("reply from the notch to \(session.id)")
        return hold
    }

    private func replied(_ session: Session, note: String) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i].state = .working
        sessions[i].questions = []
        sessions[i].permission = nil
        sessions[i].activity = nil
        sessions[i].workStarted = .now
        sessions[i].wrapUp = nil
        sessions[i].command = nil
        sessions[i].updated = .now
        showToast(note)
        selectedID = nil
        if keyboardMode { closePanel() }
    }

    // MARK: Holding sessions

    func hold(_ kind: Hold.Kind, session id: String, responder: Responder, toolInput: [String: Any] = [:]) {
        place(Hold(kind: kind, responder: responder, toolInput: toolInput), session: id)
    }

    /// Holds a permission request. Returns false if another one is on the card
    /// and this one has to wait its turn.
    func holdPermission(_ ask: PermissionAsk, session id: String, responder: Responder, toolInput: [String: Any]) -> Bool {
        let hold = Hold(kind: .permission, responder: responder, toolInput: toolInput, permission: ask)
        if holds[id]?.kind == .permission {
            queuedPermissions[id, default: []].append(hold)
            return false
        }
        place(hold, session: id)
        return true
    }

    private func place(_ hold: Hold, session id: String) {
        release(id)
        let timeout = DispatchWorkItem { [weak self] in self?.release(id) }
        hold.timeout = timeout
        holds[id] = hold
        let seconds = min(prefs.holdMinutes * 60, BrowSocket.maxHoldSeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: timeout)
    }

    /// Lets the session's hook go without a reply.
    func release(_ id: String, only kind: Hold.Kind? = nil) {
        guard let hold = holds[id], kind == nil || hold.kind == kind else { return }
        holds[id] = nil
        hold.timeout?.cancel()
        hold.responder.release()
        debugLog("released \(id) without a reply")
        for queued in queuedPermissions.removeValue(forKey: id) ?? [] { queued.responder.release() }
        // Nothing left to answer from the notch: a plain stop is just done.
        if hold.kind == .stop, let i = sessions.firstIndex(where: { $0.id == id }),
           sessions[i].state == .waiting, sessions[i].questions.isEmpty, sessions[i].wrapUp?.ask == nil {
            sessions[i].state = .done
        }
    }

    /// A tool ran, so its permission was settled in the app or terminal. Lets
    /// that hook go and shows the next permission, if any.
    func settlePermission(_ id: String, tool: String, input: [String: Any]) {
        func matches(_ hold: Hold) -> Bool {
            hold.permission?.tool == tool && NSDictionary(dictionary: hold.toolInput).isEqual(to: input)
        }
        if let hold = holds[id], hold.kind == .permission, matches(hold) {
            holds[id] = nil
            hold.timeout?.cancel()
            hold.responder.release()
            showNextPermission(id)
        } else if let i = queuedPermissions[id]?.firstIndex(where: matches) {
            queuedPermissions[id]?.remove(at: i).responder.release()
        }
    }

    private func showNextPermission(_ id: String) {
        guard let next = queuedPermissions[id]?.first else { return }
        queuedPermissions[id]?.removeFirst()
        if queuedPermissions[id]?.isEmpty == true { queuedPermissions[id] = nil }
        let rest = queuedPermissions.removeValue(forKey: id)
        place(next, session: id)
        queuedPermissions[id] = rest
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            sessions[i].permission = next.permission
            sessions[i].state = .waiting
        }
    }

    func releaseAll() {
        for id in holds.keys { release(id) }
    }

    /// The user went to the app that shows these sessions: let their Stop
    /// hooks go so the app works as usual. Questions stay, the app shows them too.
    func appActivated(_ bundleID: String?) {
        for session in sessions where session.appBundleID == bundleID {
            release(session.id, only: .stop)
        }
    }

    func isFrontmost(_ session: Session) -> Bool {
        guard let id = session.appBundleID else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id
    }

    // MARK: Context

    /// Reads the transcript on Stop, and at most every 15 seconds while working.
    func refreshUsage(session id: String, path: String?, force: Bool) {
        guard let path, !path.isEmpty else { return }
        if !force, let last = usageRead[id], Date.now.timeIntervalSince(last) < 15 { return }
        usageRead[id] = .now
        transcripts.read(session: id, path: path) { [weak self] usage in
            self?.apply(usage: usage, session: id)
        }
    }

    private func apply(usage: ContextUsage, session id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].usage = usage
        // Warn once per climb; a compaction brings the use down and re-arms it.
        if usage.fraction < 0.8 { sessions[i].contextWarned = false }
        guard usage.fraction >= 0.9, !sessions[i].contextWarned else { return }
        sessions[i].contextWarned = true
        guard !expanded, prefs.peekAlerts else { return }
        show(peek: Peek(sessionID: id,
                        title: tr("\(sessions[i].project): context is ≈\(usage.percent)% full",
                                  "\(sessions[i].project): контекст заповнено на ≈\(usage.percent)%"),
                        detail: tr("Time to compact it or start a new session", "Час стиснути його або почати нову сесію")))
    }

    // MARK: Old sessions

    /// A killed terminal or a sleeping Mac sends no SessionEnd, so silence is
    /// the only sign. Working sessions gray out first; a next event revives them.
    private static let staleAfter: TimeInterval = 30 * 60
    private static let removeAfter: TimeInterval = 6 * 60 * 60

    func startSweeping() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.sweep() }
    }

    func sweep(now: Date = .now) {
        for session in sessions {
            let silent = now.timeIntervalSince(session.lastEvent)
            // Queued messages are the user's words: keep them until sent or cancelled.
            if silent > Self.removeAfter, session.queued.isEmpty {
                remove(session)
            } else if let i = sessions.firstIndex(where: { $0.id == session.id }) {
                let stale = session.state == .working && silent > Self.staleAfter
                if sessions[i].stale != stale { sessions[i].stale = stale }
            }
        }
    }

    /// Drops the session from the list. Its next event, if any, brings it back.
    func remove(_ session: Session) {
        release(session.id)
        forget(session.id)
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = nil }
    }

    // MARK: First run

    func connectFromWelcome() {
        HookInstaller.install()
        guard HookInstaller.isInstalled() else { return }
        prefs.welcomeDone = true
        welcome = false
        show(peek: Peek(sessionID: nil, title: tr("brow is connected", "brow підключено"),
                        detail: tr("Hover the notch to see your sessions", "Наведи мишку на нотч, щоб побачити сесії")))
    }

    func dismissWelcome() {
        prefs.welcomeDone = true
        welcome = false
    }

    // MARK: Alerts

    private static let peekSeconds = 4.0

    /// Called after each event: alerts once when the session starts waiting for
    /// something the user has to answer, unless they are looking at it.
    func considerPeek(_ session: Session) {
        let key = peekKey(session)
        let known = peekKeys[session.id]
        peekKeys[session.id] = key
        guard let key else {
            if peek?.sessionID == session.id { hidePeek() }
            return
        }
        guard key != known, !expanded, prefs.peekAlerts, !isFrontmost(session) else { return }
        show(peek: makePeek(session))
    }

    private func peekKey(_ session: Session) -> String? {
        if let permission = session.permission { return "permission " + permission.detail }
        if let question = session.questions.first { return "question " + question.text }
        if session.state == .waiting, holds[session.id]?.kind == .stop { return "stop " + session.lastMessage }
        return nil
    }

    private func makePeek(_ session: Session) -> Peek {
        let firstLine: (String) -> String = { $0.split(whereSeparator: \.isNewline).first.map(String.init) ?? $0 }
        if let permission = session.permission {
            return Peek(sessionID: session.id, title: "\(session.project) \(permission.title)",
                        detail: firstLine(permission.detail), isCommand: true)
        }
        if let question = session.questions.first {
            return Peek(sessionID: session.id, title: tr("\(session.project) is asking", "\(session.project) питає"), detail: question.text)
        }
        return Peek(sessionID: session.id, title: tr("\(session.project) finished", "\(session.project) закінчив"),
                    detail: MarkdownBlock.plain(session.lastMessage))
    }

    private func show(peek new: Peek) {
        // A second session while one is showing: sum up instead of a new slide.
        if let peek, peek.sessionID != new.sessionID {
            self.peek = Peek(sessionID: nil, title: tr("Sessions are waiting: \(waitingCount)", "Сесії чекають: \(waitingCount)"),
                             detail: tr("Hover to see them", "Наведи мишку, щоб побачити"))
        } else {
            self.peek = new
        }
        debugLog("peek \(self.peek?.title ?? "")")
        if prefs.peekSound { NSSound(named: "Tink")?.play() }
        peekTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.hidePeek() }
        peekTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekSeconds, execute: timeout)
    }

    func hidePeek() {
        peekTimeout?.cancel()
        peek = nil
    }

    /// The mouse reached the notch: turn an alert into the open panel.
    func openFromPeek() {
        if let id = peek?.sessionID { selectedID = id }
        hidePeek()
    }

    // MARK: Actions

    func runCommand(of session: Session) {
        guard let command = session.command else { return }
        if demo {
            showToast("Ghostty: \(command)")
            return
        }
        Launcher.runInGhostty(command, cwd: session.cwd)
        showToast("Ghostty: \(command)")
    }

    func open(_ session: Session) {
        if !demo { Launcher.open(session) }
        showToast(tr("Opening \(session.project) in \(session.client.name)", "Відкриваю «\(session.project)» у \(session.client.name)"))
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    func applyDemoState(_ state: String) {
        pinned = true
        switch state {
        case "collapsed":
            pinned = false
        case "list":
            expanded = true
        case "question":
            expanded = true
            selectedID = sessions.first { !$0.questions.isEmpty }?.id
        case "command":
            expanded = true
            selectedID = sessions.first { $0.command != nil }?.id
        case "welcome":
            welcome = true
        case "peek":
            let session = sessions.first { $0.permission != nil }
            peek = session.map(makePeek)
        case "queued":
            expanded = true
            if let i = sessions.firstIndex(where: { $0.state == .working }) {
                sessions[i].queued = [tr("Then run the tests and commit", "Потім запусти тести й закоміть")]
                selectedID = sessions[i].id
            }
        case "permission":
            expanded = true
            selectedID = sessions.first { $0.permission != nil }?.id
        case "buttons":
            expanded = true
            selectedID = sessions.first { $0.wrapUp?.actions.isEmpty == false }?.id
        case "sent":
            expanded = true
            if let session = sessions.first(where: { $0.wrapUp != nil }), let action = session.wrapUp?.actions.first {
                send(action.label, to: session)
            }
        default:
            pinned = false
        }
    }
}

extension SessionStore {
    static func demo() -> SessionStore {
        let now = Date()
        let store = SessionStore(sessions: [
            Session(
                project: "notes-app",
                title: tr("Sync between devices", "Синхронізація між пристроями"),
                client: .desktop,
                state: .waiting,
                updated: now.addingTimeInterval(-40),
                lastMessage: tr("The sync plan is ready. Before I write the conflict handling, pick how edits on two devices should merge.",
                                "План синхронізації готовий. Перед тим як писати обробку конфліктів, вибери, як зливати зміни з двох пристроїв."),
                questions: [Question(
                    header: tr("Conflicts", "Конфлікти"),
                    text: tr("How should conflicting edits merge?", "Як зливати конфліктні зміни?"),
                    options: [
                        QuestionOption(label: tr("Last write wins", "Перемагає останній запис"),
                                       detail: tr("Simple, may lose an edit", "Просто, але можна втратити зміну")),
                        QuestionOption(label: tr("Keep both", "Зберегти обидва"),
                                       detail: tr("Shows a copy to resolve by hand", "Покаже копію, щоб вирішити вручну")),
                    ]
                )]
            ),
            Session(
                project: "thesis",
                title: tr("Chapter 3: experiments", "Розділ 3: експерименти"),
                client: .desktop,
                state: .waiting,
                updated: now.addingTimeInterval(-5 * 60),
                lastMessage: tr("Table 3.2 is updated and the plots are rebuilt. The F1 score in the text does not match the notebook: 0.87 in the text, 0.84 in the notebook.",
                                "Таблиця 3.2 оновлена, графіки перебудовані. Знайшов розбіжність у метриці F1 між ноутбуком і текстом розділу: у тексті 0.87, у ноутбуці 0.84."),
                wrapUp: WrapUp(
                    recap: tr("Table and plots updated. F1 in the text differs from the notebook.",
                              "Таблиця і графіки оновлені. F1 у тексті не збігається з ноутбуком."),
                    ask: tr("Fix the text to match the notebook?", "Виправити текст під ноутбук?"),
                    actions: [
                        WrapAction(label: tr("Yes, fix it", "Так, виправ"),
                                   message: tr("Yes, fix the text to match the notebook.", "Так, виправ текст під ноутбук.")),
                        WrapAction(label: tr("Recompute F1", "Перерахуй F1"),
                                   message: tr("Recompute F1 in the notebook first.", "Спершу перерахуй F1 у ноутбуці.")),
                    ]
                )
            ),
            Session(
                project: "api-server",
                title: tr("Release build", "Збірка релізу"),
                client: .terminal,
                state: .done,
                updated: now.addingTimeInterval(-12 * 60),
                lastMessage: tr("Changes are committed locally. Run the command below to push them.",
                                "Зміни закомічені локально. Щоб відправити на GitHub, запусти команду нижче."),
                command: "git push origin main",
                usage: ContextUsage(used: 180_000, window: 1_000_000, written: 12_000)
            ),
            Session(
                project: "mobile-app",
                title: tr("Clean rebuild", "Чиста перебудова"),
                client: .terminal,
                state: .waiting,
                updated: now.addingTimeInterval(-90),
                lastMessage: tr("The stale build cache is the cause. I'll remove it and rebuild.",
                                "Причина в застарілому кеші збірки. Приберу його й перезберу."),
                permission: PermissionAsk(tool: "Bash", title: tr("wants to run a command", "хоче запустити команду"),
                                          detail: "rm -rf build && npm run build")
            ),
            Session(
                project: "website",
                title: tr("Search page", "Сторінка пошуку"),
                client: .terminal,
                state: .working,
                updated: now.addingTimeInterval(-8),
                lastMessage: tr("The search page is ready, now checking it.", "Сторінка пошуку готова, перевіряю її."),
                activity: Activity(kind: tr("Running a command", "Запускає команду"), detail: "npm test -- search"),
                workStarted: now.addingTimeInterval(-252),
                usage: ContextUsage(used: 720_000, window: 1_000_000, written: 41_000)
            ),
        ])
        store.demo = true
        return store
    }
}
