import CoreGraphics
import Foundation

/// Mode démo : données fictives et neutres pour les captures d'écran, sans toucher aux vraies apps.
/// Activé par `BAR27_DEMO=1` ou l'argument de lancement `-demo`, jamais autrement.
public enum DemoMode {
    public struct App: Sendable {
        public let bundleID: String
        public let name: String
        public let symbol: String
        public let section: Section
        public let itemCount: Int
    }

    public static func isEnabled(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-demo") || environment["BAR27_DEMO"] == "1" || isSnapshot(environment: environment)
    }

    /// Mode capture (`BAR27_SNAPSHOT=1`, implique la démo) : retire les marqueurs de démo et simule
    /// l'interrupteur natif pour les captures publiques. Inactif sans cette variable.
    public static func isSnapshot(environment: [String: String]) -> Bool {
        environment["BAR27_SNAPSHOT"] == "1"
    }

    public static let snapshot = isSnapshot(environment: ProcessInfo.processInfo.environment)

    public static let apps: [App] = [
        App(bundleID: "com.apple.clock", name: "Horloge", symbol: "clock", section: .visible, itemCount: 1),
        App(bundleID: "com.apple.menuextra.wifi", name: "Wi‑Fi", symbol: "wifi", section: .visible, itemCount: 1),
        App(bundleID: "com.apple.menuextra.battery", name: "Batterie", symbol: "battery.100", section: .visible, itemCount: 1),
        App(bundleID: "com.apple.Spotlight", name: "Spotlight", symbol: "magnifyingglass", section: .visible, itemCount: 1),
        App(bundleID: "com.apple.iCal", name: "Calendrier", symbol: "calendar", section: .hidden, itemCount: 1),
        App(bundleID: "com.apple.Music", name: "Musique", symbol: "music.note", section: .hidden, itemCount: 2),
        App(bundleID: "com.apple.Notes", name: "Notes", symbol: "note.text", section: .alwaysHidden, itemCount: 1),
        App(bundleID: "com.apple.weather", name: "Météo", symbol: "cloud.sun", section: .alwaysHidden, itemCount: 1),
    ]

    public static var layout: Layout {
        Layout(sections: Dictionary(uniqueKeysWithValues: apps.filter { $0.section != .visible }.map { ($0.bundleID, $0.section) }))
    }

    public static var items: [MenuBarItem] {
        var x = 600.0
        return apps.flatMap { app in
            (0..<app.itemCount).map { index -> MenuBarItem in
                defer { x += 28 }
                return MenuBarItem(
                    id: ItemID(bundleID: app.bundleID, index: index), pid: 0, appName: app.name, title: app.name,
                    frame: CGRect(x: x, y: 0, width: 24, height: 24)
                )
            }
        }
    }

    public static func symbol(for bundleID: String) -> String? {
        apps.first { $0.bundleID == bundleID }?.symbol
    }

    public static func name(for bundleID: String) -> String? {
        apps.first { $0.bundleID == bundleID }?.name
    }

    /// Apps que le plan de masquage cache quand la barre est repliée : en démo rien n'est
    /// réellement masqué, mais le pied de fenêtre doit refléter les sections affichées.
    public static func concealedBundleIDs(layout: Layout) -> [String] {
        ConcealmentPlanner.plan(
            layout: layout, state: .collapsed, runningBundleIDs: Set(apps.map(\.bundleID)), selfBundleID: ""
        )?.concealedBundleIDs ?? []
    }
}
