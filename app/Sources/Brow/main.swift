import AppKit

// Prototype entry point. `--state <collapsed|list|question|command|buttons>`
// opens the notch in that state (used for screenshots).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
