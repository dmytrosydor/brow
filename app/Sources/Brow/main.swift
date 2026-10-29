import AppKit

// brow: Claude sessions in the notch. See README for flags.

// A hook may hang up before brow answers; that must not kill brow.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
