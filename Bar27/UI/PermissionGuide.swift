import AppKit
import ApplicationServices
import Bar27Core
import OSLog
import SwiftUI

/// Assistant d'autorisation : ouvre le volet de Réglages Système et cale à côté de sa fenêtre
/// un panneau avec l'icône de Bar27 à glisser dans la liste. Utile pour « Accès complet au disque »,
/// qui n'a ni API de requête ni invite : l'app doit être ajoutée à la main.
/// Il ne touche pas aux autorisations : il suit leur état et se ferme une fois l'accès accordé.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()

    private static let logger = Logger(category: "PermissionGuide")
    private static let settingsBundleID = "com.apple.systempreferences"
    /// Délai pour que Réglages s'ouvre ; au-delà, repli sur le Finder.
    private static let launchTimeout: TimeInterval = 5

    private let model = GuideModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var isGranted: @MainActor () -> Bool = { false }
    private var startedAt = Date()
    private var sawSettingsWindow = false
    private var grantedAt: Date?

    func show(_ pane: Permissions.Pane, isGranted: @escaping @MainActor () -> Bool) {
        Permissions.openSettings(pane)
        // Sans Accessibilité, la fenêtre Réglages est illisible : on garde l'ancien repli.
        guard Permissions.accessibility else {
            Permissions.revealAppInFinder()
            return
        }
        self.isGranted = isGranted
        startedAt = Date()
        sawSettingsWindow = false
        grantedAt = nil
        model.granted = false
        if panel == nil { panel = makePanel() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionGuide.shared.tick() }
        }
        tick()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func tick() {
        guard let panel else { return }
        if grantedAt == nil, isGranted() {
            grantedAt = Date()
            model.granted = true
            Self.logger.notice("Autorisation accordée, fermeture de l'assistant")
        }
        if let grantedAt, Date().timeIntervalSince(grantedAt) > 1.5 { return close() }

        guard let axFrame = Self.settingsWindowFrame() else {
            if sawSettingsWindow {
                close() // Réglages fermé par l'utilisateur.
            } else if Date().timeIntervalSince(startedAt) > Self.launchTimeout {
                Self.logger.error("Fenêtre Réglages introuvable, repli sur le Finder")
                Permissions.revealAppInFinder()
                close()
            }
            return
        }
        sawSettingsWindow = true

        // Le panneau flotte au-dessus de tout : on le cache quand l'utilisateur passe à une autre app.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == Self.settingsBundleID || front == Bundle.main.bundleIdentifier || grantedAt != nil else {
            panel.orderOut(nil)
            return
        }

        guard let primary = NSScreen.screens.first else { return }
        let window = GuidePlacement.cocoaRect(fromAX: axFrame, primaryScreenHeight: primary.frame.height)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: window.midX, y: window.midY)) } ?? primary
        let size = panel.contentView?.fittingSize ?? CGSize(width: 260, height: 220)
        let (frame, placement) = GuidePlacement.frame(panel: size, beside: window, in: screen.visibleFrame)
        if model.placement != placement { model.placement = placement }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // Réglages peut s'ouvrir sur un autre espace : `.moveToActiveSpace` y ramène le panneau à l'affichage.
        if !panel.isVisible || !panel.isOnActiveSpace { panel.orderFrontRegardless() }
    }

    /// Cadre AX (origine haut-gauche) de la fenêtre principale de Réglages Système.
    private static func settingsWindowFrame() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        var window: AXUIElement?
        if AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute as CFString, &value) == .success, let value {
            window = (value as! AXUIElement)
        } else if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success {
            window = (value as? [AXUIElement])?.first
        }
        guard let window else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &raw) == .success, let raw,
              AXValueGetValue(raw as! AXValue, .cgPoint, &position) else { return nil }
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success, let rawSize,
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size), size.width > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = GuidePanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: GuideView(model: model, onClose: { PermissionGuide.shared.close() }))
        return panel
    }
}

/// Panneau sans bordure qui peut devenir clé (bouton Fermer) sans activer Bar27.
private final class GuidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor @Observable
private final class GuideModel {
    var granted = false
    var placement: GuidePlacement = .left
}

private struct GuideView: View {
    let model: GuideModel
    let onClose: () -> Void

    private var arrow: String {
        switch model.placement {
        case .left: "arrow.right"
        case .right: "arrow.left"
        case .inside: "arrow.up"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Fermer"))
            }
            if model.granted {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("Accès accordé").font(.headline)
            } else {
                Text("Glissez Bar27 dans la liste").font(.headline)
                HStack(spacing: 14) {
                    AppDragSource().frame(width: 64, height: 64)
                    Image(systemName: arrow).font(.title).foregroundStyle(.tint)
                }
                Text("Ou cliquez sur « + » sous la liste et choisissez Bar27. Validez si macOS le demande ; Bar27 bascule tout seul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Icône de Bar27 glissable : dépose l'URL du bundle, comme un glisser depuis le Finder.
private struct AppDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragSourceView { AppDragSourceView() }
    func updateNSView(_ view: AppDragSourceView, context: Context) {}
}

final class AppDragSourceView: NSImageView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL

    init() {
        super.init(frame: .zero)
        let icon = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
        icon.size = CGSize(width: 64, height: 64)
        image = icon
        imageScaling = .scaleProportionallyUpOrDown
        isEditable = false
        setAccessibilityLabel(String(localized: "Glissez Bar27 dans la liste"))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 64) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}
