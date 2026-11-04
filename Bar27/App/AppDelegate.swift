import AppKit
import Bar27Core
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ConcealmentController!
    private var statusItem: StatusItemController?
    private var layoutWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.attila-krb.Bar27"
        if HeadlessCommands.run(arguments: CommandLine.arguments, selfBundleID: bundleID) { return }

        controller = ConcealmentController(store: .applicationSupport(bundleID: bundleID), selfBundleID: bundleID)
        statusItem = StatusItemController(controller: controller) { [weak self] in self?.showLayout() }
        if !Permissions.accessibility { Permissions.requestAccessibility() }
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func showLayout() {
        if layoutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: LayoutView(controller: controller)))
            window.title = "Organiser la barre des menus"
            window.isReleasedWhenClosed = false
            window.center()
            layoutWindow = window
        }
        NSApp.activate()
        layoutWindow?.makeKeyAndOrderFront(nil)
    }
}
