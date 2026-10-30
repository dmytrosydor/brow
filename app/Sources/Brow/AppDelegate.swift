import AppKit
import BrowShared
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
    private var server: EventServer?
    private var store = SessionStore(sessions: [])

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--demo") || args.contains("--state") {
            store = SessionStore.demo()
            if let i = args.firstIndex(of: "--state"), i + 1 < args.count {
                store.applyDemoState(args[i + 1])
            }
        } else {
            let store = self.store
            let server = EventServer { store.apply($0, responder: $1) }
            do {
                try server.start()
                self.server = server
            } catch {
                NSLog("brow: cannot listen on \(BrowSocket.path): \(error)")
            }
            store.startSweeping()
            if !HookInstaller.isInstalled() && !store.prefs.welcomeDone {
                store.welcome = true
            } else if store.prefs.isAppBundle {
                DispatchQueue.main.async { HookInstaller.offerUpdate() }
            }
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                store.appActivated(app?.bundleIdentifier)
            }
            if args.contains("--open") {
                store.expanded = true
                store.pinned = true
            }
        }

        place()
        // A display was plugged in or out, or the resolution changed.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.place() }
    }

    /// Puts the panel at the top centre of the notched screen (or the main one).
    private func place() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let notch = NotchGeometry(screen: screen)
        let size = NSSize(width: 720, height: min(900, screen.frame.height * 0.8))
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = self.panel ?? NotchPanel(frame: frame)
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

    func applicationWillTerminate(_ notification: Notification) {
        // Held sessions go on as if brow was never there.
        store.releaseAll()
    }
}
