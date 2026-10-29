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
    var name: String { self == .desktop ? "Claude" : "Термінал" }
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
        if !questions.isEmpty { return "Питання" }
        if wrapUp?.actions.isEmpty == false { return "Кнопки" }
        if command != nil { return "Команда" }
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
                hold.responder.send(["decision": "block", "reason": text])
            case .question:
                let answers = session.questions.reduce(into: [String: String]()) { $0[$1.text] = text }
                hold.responder.send(Self.answerOutput(hold.toolInput, answers))
            }
        } else if !demo {
            showToast("«\(session.project)» вже не чекає відповіді")
            return
        }
        replied(session, note: "Відправлено в «\(session.project)»: \(text)")
    }

    /// Answers to AskUserQuestion, question text → chosen label(s) or own text.
    func answer(_ answers: [String: String], to session: Session) {
        if let hold = takeHold(session) {
            hold.responder.send(Self.answerOutput(hold.toolInput, answers))
        } else if !demo {
            showToast("«\(session.project)» вже не чекає відповіді")
            return
        }
        replied(session, note: "Відповідь у «\(session.project)»: \(answers.values.joined(separator: "; "))")
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
        showToast("Відкриваю «\(session.project)» у \(session.client.name)")
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
                project: "brow",
                title: "Нотч для сесій Claude",
                client: .desktop,
                state: .waiting,
                updated: now.addingTimeInterval(-40),
                lastMessage: "План першої версії готовий. Перед тим як писати міст між хуками і нотчем, треба вирішити, як brow отримує події.",
                questions: [Question(
                    header: "Зв'язок",
                    text: "Як brow-hook передає події в нотч?",
                    options: [
                        QuestionOption(label: "Unix-сокет", detail: "Швидко, відповідь приходить одразу"),
                        QuestionOption(label: "Файли в теці", detail: "Простіше, але з затримкою"),
                    ]
                )]
            ),
            Session(
                project: "dipl",
                title: "Розділ 3: експерименти",
                client: .desktop,
                state: .waiting,
                updated: now.addingTimeInterval(-5 * 60),
                lastMessage: "Таблиця 3.2 оновлена, графіки перебудовані. Знайшов розбіжність у метриці F1 між ноутбуком і текстом розділу: у тексті 0.87, у ноутбуці 0.84.",
                wrapUp: WrapUp(
                    recap: "Таблиця і графіки оновлені. F1 у тексті не збігається з ноутбуком.",
                    ask: "Виправити текст під ноутбук?",
                    actions: [
                        WrapAction(label: "Так, виправ", message: "Так, виправ текст під ноутбук."),
                        WrapAction(label: "Перерахуй F1", message: "Спершу перерахуй F1 у ноутбуці."),
                    ]
                )
            ),
            Session(
                project: "CGRBAR",
                title: "Збірка релізу",
                client: .terminal,
                state: .done,
                updated: now.addingTimeInterval(-12 * 60),
                lastMessage: "Зміни закомічені локально. Щоб відправити на GitHub, запусти команду нижче.",
                command: "git -C ~/Desktop/laluk/CGRBAR push origin main"
            ),
            Session(
                project: "Engram",
                title: "Пошук по пам'яті",
                client: .terminal,
                state: .working,
                updated: now.addingTimeInterval(-8),
                lastMessage: "Запускаю тести пошуку…"
            ),
        ])
        store.demo = true
        return store
    }
}
