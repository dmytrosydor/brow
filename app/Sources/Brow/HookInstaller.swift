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
        ("PreToolUse", "AskUserQuestion|mcp__ccd_turn__wrap_up"),
        ("PostToolUse", "AskUserQuestion"),
        ("PermissionRequest", "AskUserQuestion"),
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

    static func isInstalled() -> Bool {
        guard let hooks = readSettings()?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { entries in
            (entries as? [[String: Any]] ?? []).contains(where: isBrowEntry)
        }
    }

    /// Asks first (unless `ask` is false), keeps a copy of the old file, then
    /// writes the new one.
    static func install(ask: Bool = true) {
        confirmAndWrite(ask: ask,
            title: "Підключити brow до всіх сесій Claude?",
            text: "brow додасть свій хук у \(settingsURL.path) для подій: \(events.map(\.name).joined(separator: ", ")).\n\nКоманда: \(hookPath)\n\nСтара версія файлу збережеться поруч. Файл буде записано заново (ключі по алфавіту).",
            button: "Підключити"
        ) { settings in
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            removeBrow(from: &hooks)
            for event in events {
                var entry: [String: Any] = ["hooks": [[
                    "type": "command",
                    "command": "\"\(hookPath)\"",
                    "timeout": event.name == "Stop" || event.name == "PermissionRequest" ? 1900 : 5,
                ]]]
                if let matcher = event.matcher { entry["matcher"] = matcher }
                hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [entry]
            }
            settings["hooks"] = hooks
        }
    }

    static func uninstall(ask: Bool = true) {
        confirmAndWrite(ask: ask,
            title: "Відключити brow від сесій Claude?",
            text: "brow прибере свої хуки з \(settingsURL.path). Стара версія файлу збережеться поруч.",
            button: "Відключити"
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
            alert("Не вдалося прочитати \(settingsURL.path)", "Файл існує, але це не JSON. Нічого не змінено.")
            return
        }
        if ask {
            let confirm = NSAlert()
            confirm.messageText = title
            confirm.informativeText = text
            confirm.addButton(withTitle: button)
            confirm.addButton(withTitle: "Скасувати")
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
            alert("Не вдалося записати налаштування", error.localizedDescription)
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
