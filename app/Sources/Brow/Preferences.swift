import BrowShared
import Foundation
import Observation
import ServiceManagement

/// User settings, kept in UserDefaults.
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    /// Hold a session after Claude stops (when its window is not in front), so
    /// a reply from the notch can reach it.
    var holdReplies: Bool {
        didSet { defaults.set(holdReplies, forKey: "holdReplies") }
    }

    /// How long to hold before letting the session go without a reply.
    var holdMinutes: Int {
        didSet { defaults.set(holdMinutes, forKey: "holdMinutes") }
    }

    /// Slide the notch down for a moment when a session starts waiting.
    var peekAlerts: Bool {
        didSet { defaults.set(peekAlerts, forKey: "peekAlerts") }
    }

    /// Play a soft sound with that alert.
    var peekSound: Bool {
        didSet { defaults.set(peekSound, forKey: "peekSound") }
    }

    /// Show the text of what Claude runs. Off: only the kind of action, for
    /// when the screen is visible to others or commands may carry secrets.
    var showActivityDetail: Bool {
        didSet { defaults.set(showActivityDetail, forKey: "showActivityDetail") }
    }

    /// The first-run card was answered, so it does not come back.
    var welcomeDone: Bool {
        didSet { defaults.set(welcomeDone, forKey: "welcomeDone") }
    }

    /// The system-wide combination that opens the notch.
    var hotKey: HotKeyChoice {
        didSet {
            defaults.set(hotKey.rawValue, forKey: "hotKey")
            onHotKeyChange?()
        }
    }
    var onHotKeyChange: (() -> Void)?

    init() {
        hotKey = (defaults.object(forKey: "hotKey") as? Int).flatMap(HotKeyChoice.init) ?? .optionSpace
        welcomeDone = defaults.bool(forKey: "welcomeDone")
        showActivityDetail = defaults.object(forKey: "showActivityDetail") as? Bool ?? true
        peekAlerts = defaults.object(forKey: "peekAlerts") as? Bool ?? true
        peekSound = defaults.object(forKey: "peekSound") as? Bool ?? false
        holdReplies = defaults.object(forKey: "holdReplies") as? Bool ?? true
        holdMinutes = defaults.object(forKey: "holdMinutes") as? Int ?? 10
    }

    /// The activity as one line, with or without its text.
    func text(of activity: Activity) -> String {
        guard showActivityDetail, let detail = activity.detail, !detail.isEmpty else { return activity.kind }
        let firstLine = detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? detail
        return "\(activity.kind): \(firstLine)"
    }

    /// Session ids (one per line) brow must never hold, e.g. a session that is
    /// working on brow itself.
    var skippedSessions: Set<String> {
        let url = BrowSocket.directory.appendingPathComponent("skip_sessions")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// Start at login; works only when running from brow.app.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("brow: launch at login: \(error)")
            }
        }
    }

    var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
}
