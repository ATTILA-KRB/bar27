import CoreGraphics
import Foundation

/// Bundle identifier du process qui dessine les items système sur macOS 27.
public let menuBarAgentBundleID = "com.apple.MenuBarAgent"

/// Identité stable d'un item : macOS 27 ne fournit ni `AXIdentifier` ni titre fiable,
/// on combine donc le bundle propriétaire et le rang de l'item dans ce process.
public struct ItemID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let bundleID: String
    public let index: Int
    public init(bundleID: String, index: Int) {
        self.bundleID = bundleID
        self.index = index
    }
    public var description: String { "\(bundleID)#\(index)" }
}

public struct MenuBarItem: Hashable, Sendable, Identifiable {
    public let id: ItemID
    public let pid: Int32
    public let appName: String?
    public let title: String?
    public let frame: CGRect

    public init(id: ItemID, pid: Int32, appName: String?, title: String?, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.frame = frame
    }

    public var bundleID: String { id.bundleID }
    /// Horloge, batterie, Wi‑Fi, Control Center, débordement : jamais masqués par Bar27.
    public var isSystem: Bool { bundleID == menuBarAgentBundleID }
}

/// Section d'une app. macOS 27 masque par application, pas par icône.
public enum Section: String, Codable, CaseIterable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

/// Ce que l'utilisateur demande à voir.
public enum RevealState: Sendable, Equatable {
    /// Seule la section `visible` est affichée.
    case collapsed
    /// `visible` + `hidden` affichées, `alwaysHidden` reste masquée.
    case revealed
    /// Tout est affiché (aucune assertion).
    case revealedAll
}
