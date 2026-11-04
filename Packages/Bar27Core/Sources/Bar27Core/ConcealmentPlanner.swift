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
