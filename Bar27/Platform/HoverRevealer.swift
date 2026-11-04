import AppKit
import ApplicationServices
import Bar27Core

/// Survol d'une zone vide de la barre des menus → révélation.
/// Indispensable sous assertion, où MenuBarAgent retire aussi l'icône de Bar27.
/// Zone vide = le test AX sous le pointeur rend la barre elle-même (`AXMenuBar`), pas un item
/// (`AXMenuBarItem`). Le test ne tourne que pointeur dans la barre, hors du fil principal.
@MainActor
final class HoverRevealer {
    private var timer: Timer?
    private var trigger = DwellTrigger(threshold: 0.35)
    private var probing = false
    private let onReveal: () -> Void
    private static let queue = DispatchQueue(label: "com.attila-krb.Bar27.HoverRevealer", qos: .userInitiated)

    init(onReveal: @escaping () -> Void) {
        self.onReveal = onReveal
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        trigger = DwellTrigger(threshold: trigger.threshold)
    }

    private func tick() {
        // Bouton enfoncé : glisser ou clic en cours, ce n'est pas un survol.
        guard MenuState.isPointerInMenuBar, NSEvent.pressedMouseButtons == 0 else {
            _ = trigger.update(hovering: false, now: Date())
            return
        }
        guard !probing, let point = Self.pointerInScreenCoordinates() else { return }
        probing = true
        Self.queue.async { [weak self] in
            let empty = Self.isEmptyMenuBar(at: point)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.probing = false
                    if self.trigger.update(hovering: empty, now: Date()) { self.onReveal() }
                }
            }
        }
    }

    /// AX travaille en coordonnées écran à origine en haut à gauche de l'écran principal.
    private static func pointerInScreenCoordinates() -> CGPoint? {
        guard let primary = NSScreen.screens.first else { return nil }
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primary.frame.maxY - p.y)
    }

    nonisolated private static func isEmptyMenuBar(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success, let element else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return (role as? String) == (kAXMenuBarRole as String)
    }
}
