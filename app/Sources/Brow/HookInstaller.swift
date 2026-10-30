import AppKit

/// Adds brow-hook to the user's Claude Code settings (~/.claude/settings.json)
/// so every session, in any folder, shows up in the notch. Removes it again.
enum HookInstaller {
    /// Event → tool matcher (nil: every call). Stop and PermissionRequest wait
    /// for a reply, so their timeout must outlast the longest hold.
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("Notification", nil),
        ("SessionEnd", nil),
        ("PreToolUse", nil),
        ("PostToolUse", nil),
        ("PostToolUseFailure", nil),
        ("PermissionRequest", nil),
    ]

    static var settingsURL: URL {
        if let path = ProcessInfo.processInfo.environment["BROW_CLAUDE_SETTINGS"] {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// brow-hook next to the running brow binary (Contents/MacOS in brow.app).
    static var hookPath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("brow-hook").path
    }

    private static var eventList: String { events.map(\.name).joined(separator: ", ") }

    static func isInstalled() -> Bool {
        installedHookPath() != nil
    }

    /// Asks first (unless `ask` is false), keeps a copy of the old file, then
    /// writes the new one.
    static func install(ask: Bool = true) {
        confirmAndWrite(ask: ask,
            title: tr("Connect brow to all Claude sessions?", "Підключити brow до всіх сесій Claude?"),
            text: tr("brow will add its hook to \(settingsURL.path) for: \(eventList).\n\nCommand: \(hookPath)\n\nA copy of the old file is kept next to it. The file is rewritten with keys in alphabetical order.",
                     "brow додасть свій хук у \(settingsURL.path) для подій: \(eventList).\n\nКоманда: \(hookPath)\n\nСтара версія файлу збережеться поруч. Файл буде записано заново (ключі по алфавіту)."),
            button: tr("Connect", "Підключити"),
            change: addBrow)
    }

    /// The command written to the settings. If brow.app is deleted without
    /// disconnecting, the check makes the hook exit quietly; a bare path would
    /// make Claude report a hook error at every stop.
    static func command(for path: String) -> String {
        "test -x \"\(path)\" && \"\(path)\" || true"
    }

    /// The hooks are from an older brow: missing events or without the check.
    static var isOutdated: Bool {
        let hooks = readSettings()?["hooks"] as? [String: Any] ?? [:]
        return events.contains { event in
            !(hooks[event.name] as? [[String: Any]] ?? []).contains { entry in
                isBrowEntry(entry) && entry["matcher"] as? String == event.matcher
                    && (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.hasPrefix("test -x ") == true }
            }
        }
    }

    /// Offers to rewrite the hooks when they are from an older brow, or point at
    /// another brow-hook: one that is gone (brow.app was moved), or any other
    /// while this copy runs from /Applications.
    static func offerUpdate() {
        guard let installed = installedHookPath() else { return }
        if isOutdated {
            confirmAndWrite(ask: true,
                title: tr("Update brow's Claude hooks?", "Оновити хуки brow для Claude?"),
                text: tr("This version needs its hook on every tool call, and the hook now stays quiet if brow is ever deleted: \(eventList).\n\nCommand: \(hookPath)\n\nA copy of \(settingsURL.path) is kept next to it.",
                         "Цій версії потрібен хук на кожен виклик інструмента, а ще він тепер мовчить, якщо brow колись видалять: \(eventList).\n\nКоманда: \(hookPath)\n\nКопія \(settingsURL.path) збережеться поруч."),
                button: tr("Update", "Оновити"),
                change: addBrow)
            return
        }
        guard installed != hookPath,
              !FileManager.default.fileExists(atPath: installed) || hookPath.hasPrefix("/Applications/") else { return }
        confirmAndWrite(ask: true,
            title: tr("brow was moved", "brow перемістили"),
            text: tr("The Claude hooks still point at \(installed). Point them at \(hookPath)?",
                     "Хуки Claude досі вказують на \(installed). Перевести їх на \(hookPath)?"),
            button: tr("Update", "Оновити"),
            change: addBrow)
    }

    static func installedHookPath() -> String? {
        let hooks = readSettings()?["hooks"] as? [String: Any] ?? [:]
        for entries in hooks.values {
            for entry in entries as? [[String: Any]] ?? [] {
                for hook in entry["hooks"] as? [[String: Any]] ?? [] {
                    if let command = hook["command"] as? String, command.contains("brow-hook"),
                       let path = command.split(separator: "\"").first(where: { $0.hasSuffix("brow-hook") }) {
                        return String(path)
                    }
                }
            }
        }
        return nil
    }

    private static func addBrow(to settings: inout [String: Any]) {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        removeBrow(from: &hooks)
        for event in events {
            var entry: [String: Any] = ["hooks": [[
                "type": "command",
                "command": command(for: hookPath),
                "timeout": event.name == "Stop" || event.name == "PermissionRequest" ? 1900 : 5,
            ]]]
            if let matcher = event.matcher { entry["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [entry]
        }
        settings["hooks"] = hooks
    }

    static func uninstall(ask: Bool = true) {
        confirmAndWrite(ask: ask,
            title: tr("Disconnect brow from Claude sessions?", "Відключити brow від сесій Claude?"),
            text: tr("brow will remove its hooks from \(settingsURL.path). A copy of the old file is kept next to it.",
                     "brow прибере свої хуки з \(settingsURL.path). Стара версія файлу збережеться поруч."),
            button: tr("Disconnect", "Відключити")
        ) { settings in
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            removeBrow(from: &hooks)
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }

    // MARK: -

    private static func isBrowEntry(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains("brow-hook") == true
        }
    }

    private static func removeBrow(from hooks: inout [String: Any]) {
        for (name, value) in hooks {
            let kept = (value as? [[String: Any]] ?? []).filter { !isBrowEntry($0) }
            hooks[name] = kept.isEmpty ? nil : kept
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func confirmAndWrite(ask: Bool, title: String, text: String, button: String,
                                        change: (inout [String: Any]) -> Void) {
        interactive = ask
        if ask { NSApp.activate(ignoringOtherApps: true) }
        guard var settings = readSettings() else {
            alert(tr("Could not read \(settingsURL.path)", "Не вдалося прочитати \(settingsURL.path)"),
                  tr("The file exists but is not JSON. Nothing was changed.", "Файл існує, але це не JSON. Нічого не змінено."))
            return
        }
        if ask {
            let confirm = NSAlert()
            confirm.messageText = title
            confirm.informativeText = text
            confirm.addButton(withTitle: button)
            confirm.addButton(withTitle: tr("Cancel", "Скасувати"))
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }

        change(&settings)
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: settingsURL.path) {
                let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
                var backup = settingsURL.appendingPathExtension("brow-backup-\(stamp)")
                var n = 2
                while fm.fileExists(atPath: backup.path) {
                    backup = settingsURL.appendingPathExtension("brow-backup-\(stamp)-\(n)")
                    n += 1
                }
                try fm.copyItem(at: settingsURL, to: backup)
            }
            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try (data + Data([0x0A])).write(to: settingsURL, options: .atomic)
        } catch {
            alert(tr("Could not write the settings", "Не вдалося записати налаштування"), error.localizedDescription)
        }
    }

    /// False when run from the command line with --yes: report to stderr.
    private static var interactive = true

    private static func alert(_ title: String, _ text: String) {
        guard interactive else {
            FileHandle.standardError.write(Data("\(title): \(text)\n".utf8))
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
