import AppKit
import Carbon

/// The combinations offered in the menu. Carbon's hot key API needs no
/// accessibility permission, unlike a global event monitor.
enum HotKeyChoice: Int, CaseIterable {
    case optionSpace, controlOptionSpace, optionBacktick, commandShiftSpace, off

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .optionBacktick: "⌥ `"
        case .commandShiftSpace: "⌘⇧ Space"
        case .off: tr("Off", "Вимкнено")
        }
    }

    fileprivate var carbon: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .optionSpace: (UInt32(kVK_Space), UInt32(optionKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .optionBacktick: (UInt32(kVK_ANSI_Grave), UInt32(optionKey))
        case .commandShiftSpace: (UInt32(kVK_Space), UInt32(cmdKey | shiftKey))
        case .off: nil
        }
    }
}

/// Owns the system-wide combination.
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?
    private static var installed = false

    init(action: @escaping () -> Void) {
        HotKey.action = action
        guard !HotKey.installed else { return }
        HotKey.installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Replaces the current combination. False if another app already took it.
    @discardableResult
    func register(_ choice: HotKeyChoice) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let carbon = choice.carbon else { return true }
        let id = EventHotKeyID(signature: OSType(0x42524F57), id: 1) // "BROW"
        let status = RegisterEventHotKey(carbon.key, carbon.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }
}

/// A key pressed while the panel has the keyboard.
enum BrowKey {
    case up, down, escape, enter, commandEnter, commandDelete
    case digit(Int)
    case text(String)

    init?(_ event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_UpArrow: self = .up
        case kVK_DownArrow: self = .down
        case kVK_Escape: self = .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: self = command ? .commandEnter : .enter
        case kVK_Delete: if command { self = .commandDelete } else { return nil }
        default:
            guard !command, !event.modifierFlags.contains(.control),
                  let characters = event.characters, let first = characters.first, !first.isNewline,
                  first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else { return nil }
            if let digit = first.wholeNumberValue, (1...9).contains(digit) {
                self = .digit(digit)
            } else {
                self = .text(characters)
            }
        }
    }

    /// While the reply field has the cursor, these still act; the rest is typing.
    var worksWhileTyping: Bool {
        switch self {
        case .escape, .commandEnter, .commandDelete: true
        default: false
        }
    }
}

extension SessionStore {
    /// The hot key: opens on the session that has waited longest, or closes.
    func openFromHotKey() {
        guard !welcome else { return }
        hidePeek()
        pinned = true
        keyboardMode = true
        selectedID = sessions.filter { $0.state == .waiting }.min { $0.updated < $1.updated }?.id
        expanded = true
    }

    func closePanel() {
        expanded = false
        selectedID = nil
        pinned = false
        keyboardMode = false
        onClose?()
    }

    /// Returns false to let the key go on to the view that has the cursor.
    func handle(_ key: BrowKey) -> Bool {
        guard expanded else { return false }
        switch key {
        case .escape:
            closePanel()
        case .up, .down:
            moveSelection(by: { if case .up = key { return -1 } else { return 1 } }())
        case .enter:
            if selected == nil {
                selectedID = sessions.first?.id
            } else {
                optionPress = OptionPress(index: -1)
            }
        case .commandEnter:
            guard let session = selected, session.permission != nil, canReply(session) else { break }
            decide(allow: true, session: session)
        case .commandDelete:
            guard let session = selected, session.permission != nil, canReply(session) else { break }
            decide(allow: false, session: session)
        case .digit(let number):
            guard let session = selected else { break }
            if session.permission != nil { break } // Never approve with a stray key.
            if !session.questions.isEmpty {
                if canReply(session) { optionPress = OptionPress(index: number - 1) }
            } else if canReply(session), let actions = session.wrapUp?.actions, !actions.isEmpty {
                if actions.indices.contains(number - 1) { send(actions[number - 1].message, to: session) }
            } else {
                seedReply(String(number), session)
            }
        case .text(let text):
            if let session = selected { seedReply(text, session) }
        }
        return true
    }

    private func moveSelection(by step: Int) {
        guard !sessions.isEmpty else { return }
        let current = sessions.firstIndex { $0.id == selectedID }
        let next = current.map { $0 + step } ?? (step > 0 ? 0 : sessions.count - 1)
        selectedID = sessions[(next + sessions.count) % sessions.count].id
    }

    /// Typing starts the reply: the key goes into the field and moves the cursor there.
    private func seedReply(_ text: String, _ session: Session) {
        if canReply(session) || session.state == .working { replySeed = text }
    }
}

/// One press of a digit (or -1: Enter) for the question card to act on.
struct OptionPress: Equatable {
    let id = UUID()
    var index: Int
}
