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

/// AskUserQuestion as seen by the PermissionRequest hook.
struct Question {
    var header: String
    var text: String
    var options: [QuestionOption]
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
    let id = UUID()
    var project: String
    var title: String
    var client: Client
    var state: SessionState
    var updated: Date
    var lastMessage: String
    var command: String?
    var wrapUp: WrapUp?
    var question: Question?

    /// What the notch can do for this session, shown as a tag in the list.
    var tag: String? {
        if question != nil { return "Питання" }
        if wrapUp?.actions.isEmpty == false { return "Кнопки" }
        if command != nil { return "Команда" }
        return nil
    }
}

@Observable
final class SessionStore {
    var sessions: [Session]
    var expanded = false
    var selectedID: Session.ID?
    var toast: String?
    /// Set when the prototype is launched straight into a state, so it stays
    /// open for a screenshot until the mouse visits it.
    var pinned = false

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var selected: Session? { sessions.first { $0.id == selectedID } }

    func select(_ session: Session?) {
        selectedID = session?.id
    }

    /// Stand-in for handing the reply to the waiting hook: the session goes back to work.
    func send(_ text: String, to session: Session, note: String? = nil) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i].state = .working
        sessions[i].question = nil
        sessions[i].wrapUp = nil
        sessions[i].command = nil
        sessions[i].updated = .now
        showToast(note ?? "Відправлено в «\(session.project)»: \(text)")
        selectedID = nil
    }

    func runCommand(of session: Session) {
        guard let command = session.command else { return }
        showToast("Ghostty: \(command)")
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
            selectedID = sessions.first { $0.question != nil }?.id
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
        return SessionStore(sessions: [
            Session(
                project: "brow",
                title: "Нотч для сесій Claude",
                client: .desktop,
                state: .waiting,
                updated: now.addingTimeInterval(-40),
                lastMessage: "План першої версії готовий. Перед тим як писати міст між хуками і нотчем, треба вирішити, як brow отримує події.",
                question: Question(
                    header: "Зв'язок",
                    text: "Як brow-hook передає події в нотч?",
                    options: [
                        QuestionOption(label: "Unix-сокет", detail: "Швидко, відповідь приходить одразу"),
                        QuestionOption(label: "Файли в теці", detail: "Простіше, але з затримкою"),
                    ]
                )
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
    }
}
