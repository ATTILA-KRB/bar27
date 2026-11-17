import CoreGraphics
import Foundation

/// Allowlist à passer à l'assertion « assessment mode » : MenuBarAgent masque toute app
/// qui n'y figure pas. `nil` signifie « aucune assertion » (rien à masquer).
public struct ConcealmentPlan: Equatable, Sendable {
    public let allowedBundleIDs: [String]
    public let concealedBundleIDs: [String]
}

public enum ConcealmentPlanner {
    /// - Parameters:
    ///   - runningBundleIDs: toutes les apps en cours d'exécution. L'assertion étant une
    ///     allowlist, une app lancée après coup serait masquée à tort : il faut replanifier
    ///     à chaque lancement d'app (voir `ConcealmentController`).
    ///   - selfBundleID: Bar27 reste toujours visible (sinon impossible de révéler).
    public static func plan(
        layout: Layout,
        state: RevealState,
        runningBundleIDs: Set<String>,
        selfBundleID: String
    ) -> ConcealmentPlan? {
        let concealedSections: Set<Section> = switch state {
        case .collapsed: [.hidden, .alwaysHidden]
        case .revealed: [.alwaysHidden]
        case .revealedAll: []
        }
        let candidates = runningBundleIDs.subtracting([selfBundleID, menuBarAgentBundleID])
        let concealed = candidates.filter { concealedSections.contains(layout.section(for: $0)) }
        guard !concealed.isEmpty else { return nil }
        let allowed = runningBundleIDs.subtracting(concealed).union([selfBundleID])
        return ConcealmentPlan(allowedBundleIDs: allowed.sorted(), concealedBundleIDs: concealed.sorted())
    }
}

/// Item système (MenuBarAgent) tel que lu par Accessibility : identifiant stable
/// (`com.apple.menuextra.battery`…) et cadre écran.
public struct SystemItem: Sendable, Equatable {
    public var identifier: String?
    public var frame: CGRect
    public init(identifier: String?, frame: CGRect) {
        self.identifier = identifier
        self.frame = frame
    }
}

/// Relais des clics vers les items système sous assertion : MenuBarAgent ignore alors les clics
/// souris sur horloge, batterie, Wi‑Fi…
///
/// Deux chemins (mesurés sur macOS 27.0.1, 17/11/2026) :
/// - **AXPress** sur l'item : honoré malgré l'assertion, rien n'est levé, la barre ne bouge pas.
///   Marche pour Wi‑Fi, batterie, son, Control Center ; l'horloge l'ignore (renvoie succès sans
///   rien ouvrir), d'où `pressIgnored`.
/// - **Levée + rejeu** (horloge, items inconnus) : lever l'assertion réaffiche ce qu'elle masque
///   (Spotlight, « À l'écoute »…) et décale **et renumérote** les items. On retrouve donc l'item
///   par identifiant, jamais par rang ni par coordonnées.
public enum ClickBridgeRule {
    /// Items dont AXPress n'ouvre rien : passer par la levée.
    public static let pressIgnored: Set<String> = ["com.apple.menuextra.clock"]

    public static func shouldBridge(click: CGPoint, systemItems: [SystemItem], assertionActive: Bool) -> Bool {
        assertionActive && target(click: click, systemItems: systemItems) != nil
    }

    /// Item système sous le clic. Les cadres vides (item sans position AX) sont ignorés :
    /// `.zero` élargi contiendrait le coin de l'écran.
    public static func target(click: CGPoint, systemItems: [SystemItem]) -> SystemItem? {
        systemItems.first { !$0.frame.isEmpty && $0.frame.insetBy(dx: -1, dy: -1).contains(click) }
    }

    /// AXPress possible sans lever l'assertion ?
    public static func canPress(_ item: SystemItem) -> Bool {
        guard let id = item.identifier, !id.isEmpty else { return false }
        return !pressIgnored.contains(id)
    }

    /// Cadre actuel de l'item visé, retrouvé par identifiant (nil s'il a disparu ou n'a pas d'identifiant).
    public static func relocate(_ item: SystemItem, in items: [SystemItem]) -> CGRect? {
        guard let id = item.identifier, !id.isEmpty else { return nil }
        return items.first { $0.identifier == id && !$0.frame.isEmpty }?.frame
    }

    /// Point de rejeu : même position relative du clic dans le nouveau cadre de l'item.
    public static func replayPoint(click: CGPoint, from old: CGRect, to new: CGRect) -> CGPoint {
        guard !new.isEmpty, old != new else { return click }
        func ratio(_ v: CGFloat, _ min: CGFloat, _ length: CGFloat) -> CGFloat {
            length > 0 ? Swift.min(Swift.max((v - min) / length, 0.1), 0.9) : 0.5
        }
        return CGPoint(x: new.minX + ratio(click.x, old.minX, old.width) * new.width,
                       y: new.minY + ratio(click.y, old.minY, old.height) * new.height)
    }
}

/// Re-masquage automatique : on attend qu'aucun menu ne soit ouvert.
public enum AutoRehideRule {
    public static func shouldRehide(state: RevealState, elapsed: TimeInterval, delay: TimeInterval, menuOpen: Bool, pointerInMenuBar: Bool) -> Bool {
        state == .revealed && delay > 0 && elapsed >= delay && !menuOpen && !pointerInMenuBar
    }
}
