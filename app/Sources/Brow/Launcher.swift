import AppKit

/// Opens things outside brow: a command in a new Ghostty window, or the app
/// that shows a session.
enum Launcher {
    /// Runs `command` in a new Ghostty window in `cwd`; the shell stays open
    /// afterwards so the output can be read.
    static func runInGhostty(_ command: String, cwd: String?) {
        let script = command + "\nexec \"${SHELL:-/bin/zsh}\" -l"
        var args = ["-na", "Ghostty.app", "--args"]
        if let cwd { args.append("--working-directory=\(cwd)") }
        args += ["-e", "/bin/zsh", "-lc", script]
        run("/usr/bin/open", args)
    }

    /// Brings forward the app the session lives in.
    static func open(_ session: Session) {
        guard let id = session.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }
}
