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

/// Faut-il relayer un clic vers un item système ? Seulement sous assertion (MenuBarAgent
/// ignore alors les clics sur horloge, batterie, Wi‑Fi) et si le clic tombe sur l'un d'eux.
public enum ClickBridgeRule {
    public static func shouldBridge(click: CGPoint, systemItemFrames: [CGRect], assertionActive: Bool) -> Bool {
        assertionActive && targetIndex(click: click, systemItemFrames: systemItemFrames) != nil
    }

    /// Rang (dans MenuBarAgent) de l'item système sous le clic. Les cadres vides (item sans
    /// position AX) sont ignorés : `.zero` élargi contiendrait le coin de l'écran.
    public static func targetIndex(click: CGPoint, systemItemFrames: [CGRect]) -> Int? {
        systemItemFrames.firstIndex { !$0.isEmpty && $0.insetBy(dx: -1, dy: -1).contains(click) }
    }

    /// Point de rejeu après la levée. Lever l'assertion réaffiche ce qu'elle masquait (Spotlight,
    /// apps) et décale les items système : rejouer aux coordonnées d'origine tomberait sur le
    /// voisin (clic Wi‑Fi → batterie, mesuré le 17/11/2026 : −32 pt). On garde la position
    /// relative du clic dans le nouveau cadre de l'item visé.
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
