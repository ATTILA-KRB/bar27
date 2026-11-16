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
        // Pas de double chevron : c'est le glyphe du bouton de débordement natif de macOS 27
        // (« Afficher les éléments masqués »), les deux se confondaient.
        let collapsed = controller.state == .collapsed
        let symbol = collapsed ? "menubar.arrow.down.rectangle" : "menubar.arrow.up.rectangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bar27")
        statusItem.button?.toolTip = collapsed ? String(localized: "Bar27 — afficher les icônes masquées (⌃⌥⌘B)") : String(localized: "Bar27 — masquer (⌃⌥⌘B)")
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
        let toggleTitle = controller.state == .collapsed ? String(localized: "Afficher les éléments masqués") : String(localized: "Masquer les éléments")
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Tout afficher"), action: #selector(revealAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: String(localized: "Ouvrir à la connexion"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : (LoginItem.needsApproval ? .mixed : .off)
        menu.addItem(withTitle: String(localized: "Organiser la barre…"), action: #selector(diagnostic), keyEquivalent: ",").target = self
        if !Permissions.accessibility {
            menu.addItem(withTitle: String(localized: "Autoriser l'accessibilité…"), action: #selector(requestAX), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quitter Bar27"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleFromMenu() { controller.toggle(); updateIcon() }
    @objc private func revealAll() { controller.set(.revealedAll); updateIcon() }
    @objc private func diagnostic() { openDiagnostic() }
    @objc private func toggleLogin() { LoginItem.toggleReportingProblems() }
    @objc private func requestAX() { Permissions.requestAccessibility() }
}
