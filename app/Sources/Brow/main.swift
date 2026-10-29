import AppKit

// brow: Claude sessions in the notch. See README for flags.

// A hook may hang up before brow answers; that must not kill brow.
signal(SIGPIPE, SIG_IGN)

// `--install-hooks` / `--uninstall-hooks` edit ~/.claude/settings.json and
// exit; `--yes` skips the confirmation.
let args = CommandLine.arguments
if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
    let ask = !args.contains("--yes")
    if ask { _ = NSApplication.shared }
    if args.contains("--install-hooks") { HookInstaller.install(ask: ask) } else { HookInstaller.uninstall(ask: ask) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
