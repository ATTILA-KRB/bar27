import AppKit
import Bar27Core
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ConcealmentController!
    private var statusItem: StatusItemController?
    private var layoutWindow: NSWindow?
    private var hotKey: HotKey?

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

        // `-LayoutPath <fichier>` : layout de test (scripts/verify-*.sh), sans toucher au vrai.
        let store = UserDefaults.standard.string(forKey: "LayoutPath").map { LayoutStore(url: URL(fileURLWithPath: $0)) }
            ?? .applicationSupport(bundleID: bundleID)
        let demo = DemoMode.isEnabled(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        controller = ConcealmentController(store: store, selfBundleID: bundleID, demo: demo)
        statusItem = StatusItemController(controller: controller) { [weak self] in self?.showLayout() }
        controller.onStateChange = { [weak self] in self?.statusItem?.updateIcon() }
        hotKey = HotKey { [weak self] in self?.controller.toggle() }
        if !demo, !Permissions.accessibility { Permissions.requestAccessibility() }
        installTerminationSignals()
        controller.start()
        // Premier lancement (rien n'est rangé, l'icône peut finir derrière l'encoche) ou test : on ouvre la fenêtre.
        let defaults = UserDefaults.standard
        if demo || !defaults.bool(forKey: "Onboarded") || defaults.bool(forKey: "OpenLayout") {
            if !demo { defaults.set(true, forKey: "Onboarded") }
            showLayout()
        }
    }

    /// Double-clic sur Bar27 dans le Finder alors qu'il tourne : seul accès garanti si l'icône est cachée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLayout()
        return false
    }

    /// En natif, l'interrupteur survit au processus : SIGTERM/SIGINT passent par
    /// `terminate` pour tout rallumer. (SIGKILL/plantage : rallumé au lancement suivant.)
    private var signalSources: [DispatchSourceSignal] = []

    private func installTerminationSignals() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func showLayout() {
        if layoutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: LayoutView(controller: controller)))
            window.title = String(localized: "Organiser la barre des menus")
            window.isReleasedWhenClosed = false
            window.center()
            layoutWindow = window
        }
        NSApp.activate()
        layoutWindow?.makeKeyAndOrderFront(nil)
    }
}
