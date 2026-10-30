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
    var cwd: String?
    /// TERM_PROGRAM of a terminal session, to know which app shows it.
    var termProgram: String?

    /// What the notch can do for this session, shown as a tag in the list.
    var tag: String? {
        if !questions.isEmpty { return tr("Question", "Питання") }
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

/// A hook call brow is holding open so a reply from the notch can reach Claude.
final class Hold {
    enum Kind { case stop, question }

    let kind: Kind
    let responder: Responder
    /// AskUserQuestion's tool_input, sent back with the answers.
    let toolInput: [String: Any]
    var timeout: DispatchWorkItem?

    init(kind: Kind, responder: Responder, toolInput: [String: Any] = [:]) {
        self.kind = kind
        self.responder = responder
        self.toolInput = toolInput
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

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var selected: Session? { sessions.first { $0.id == selectedID } }

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
        if let hold = takeHold(session) {
            switch hold.kind {
            case .stop:
                hold.responder.send(["decision": "block", "reason": Self.replyReason(text)])
            case .question:
                let answers = session.questions.reduce(into: [String: String]()) { $0[$1.text] = text }
                hold.responder.send(Self.answerOutput(hold.toolInput, answers))
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
        sessions[i].wrapUp = nil
        sessions[i].command = nil
        sessions[i].updated = .now
        showToast(note)
        selectedID = nil
    }

    // MARK: Holding sessions

    func hold(_ kind: Hold.Kind, session id: String, responder: Responder, toolInput: [String: Any] = [:]) {
        release(id)
        let hold = Hold(kind: kind, responder: responder, toolInput: toolInput)
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
        // Nothing left to answer from the notch: a plain stop is just done.
        if hold.kind == .stop, let i = sessions.firstIndex(where: { $0.id == id }),
           sessions[i].state == .waiting, sessions[i].questions.isEmpty, sessions[i].wrapUp?.ask == nil {
            sessions[i].state = .done
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
                command: "git push origin main"
            ),
            Session(
                project: "website",
                title: tr("Search page", "Сторінка пошуку"),
                client: .terminal,
                state: .working,
                updated: now.addingTimeInterval(-8),
                lastMessage: tr("Running the search tests…", "Запускаю тести пошуку…")
            ),
        ])
        store.demo = true
        return store
    }
}
