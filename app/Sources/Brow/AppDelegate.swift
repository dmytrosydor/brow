import AppKit
import SwiftUI

/// Size of the physical notch, or of a pill of the same height on Macs without one.
struct NotchGeometry {
    var width: CGFloat
    var height: CGFloat

    init(screen: NSScreen) {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        if screen.safeAreaInsets.top > 0, left > 0, right > 0 {
            width = screen.frame.width - left - right
            height = screen.safeAreaInsets.top
        } else {
            width = 190
            height = NSStatusBar.system.thickness
        }
    }
}

/// Borderless panel glued to the top edge. It can take keyboard focus (for the
/// reply field) without activating the app; transparent areas pass clicks through.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    // Keep the panel over the menu bar instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private let store = SessionStore.demo()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--state"), i + 1 < args.count {
            store.applyDemoState(args[i + 1])
        }

        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let notch = NotchGeometry(screen: screen)
        let size = NSSize(width: 720, height: 640)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = NotchPanel(frame: frame)
        let host = NSHostingView(rootView: NotchRoot(notch: notch).environment(store))
        host.frame = NSRect(origin: .zero, size: size)
        // The panel has a fixed frame; don't let SwiftUI resize the window on
        // every animation frame.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
