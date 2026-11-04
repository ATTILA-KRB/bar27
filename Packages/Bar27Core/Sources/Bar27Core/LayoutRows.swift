import Foundation

/// Ligne de la fenêtre « Organiser la barre ».
public struct LayoutRow: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    /// Icônes vues dans la barre (0 si l'app n'est pas lancée).
    public let itemCount: Int
    public let isRunning: Bool
    public let section: Section
    public var id: String { bundleID }
}

public enum LayoutRows {
    /// Apps vues dans la barre + apps déjà rangées mais absentes (non lancées, ou masquées et
    /// donc invisibles à l'AX sous assertion) : sans elles, impossible de les réafficher.
    public static func make(
        scanned: [(bundleID: String, name: String?)],
        layout: Layout,
        running: Set<String>,
        selfBundleID: String,
        displayName: (String) -> String?
    ) -> [LayoutRow] {
        var counts = [String: Int]()
        var names = [String: String]()
        for item in scanned where item.bundleID != selfBundleID && item.bundleID != menuBarAgentBundleID {
            counts[item.bundleID, default: 0] += 1
            if names[item.bundleID] == nil, let name = item.name, !name.isEmpty { names[item.bundleID] = name }
        }
        let ids = Set(counts.keys).union(layout.sections.keys).subtracting([selfBundleID, menuBarAgentBundleID])
        return ids.map { id in
            LayoutRow(
                bundleID: id,
                name: names[id] ?? displayName(id) ?? id,
                itemCount: counts[id] ?? 0,
                isRunning: running.contains(id),
                section: layout.section(for: id)
            )
        }
        .sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
        }
    }
}

/// Survol d'une zone vide de la barre : révèle après un temps d'arrêt, une seule fois par survol.
public struct DwellTrigger: Sendable {
    public let threshold: TimeInterval
    private var since: Date?
    private var fired = false

    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    /// Rend `true` au moment où le temps d'arrêt est atteint ; quitter la zone réarme.
    public mutating func update(hovering: Bool, now: Date) -> Bool {
        guard hovering else {
            since = nil
            fired = false
            return false
        }
        let start = since ?? now
        since = start
        guard !fired, now.timeIntervalSince(start) >= threshold else { return false }
        fired = true
        return true
    }
}
