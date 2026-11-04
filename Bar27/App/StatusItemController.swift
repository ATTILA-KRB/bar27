import AppKit
import Bar27Core

/// Icône de Bar27. Clic : masquer/révéler. Clic droit ou ⌥‑clic : menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: ConcealmentController
    private let openDiagnostic: () -> Void

    init(controller: ConcealmentController, openDiagnostic: @escaping () -> Void) {
        self.controller = controller
        self.openDiagnostic = openDiagnostic
        super.init()
        statusItem.autosaveName = "Bar27.Main"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Bar27")
        }
        updateIcon()
    }

    func updateIcon() {
        let symbol = controller.state == .collapsed ? "chevron.left.2" : "chevron.right.2"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bar27")
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            showMenu()
        } else {
            controller.toggle()
            updateIcon()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleTitle = controller.state == .collapsed ? "Afficher les éléments masqués" : "Masquer les éléments"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Tout afficher", action: #selector(revealAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Organiser la barre…", action: #selector(diagnostic), keyEquivalent: ",").target = self
        if !Permissions.accessibility {
            menu.addItem(withTitle: "Autoriser l'accessibilité…", action: #selector(requestAX), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Bar27", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleFromMenu() { controller.toggle(); updateIcon() }
    @objc private func revealAll() { controller.set(.revealedAll); updateIcon() }
    @objc private func diagnostic() { openDiagnostic() }
    @objc private func requestAX() { Permissions.requestAccessibility() }
}
