import Foundation

/// Affectation persistée bundleID → section. Une app absente est `visible`.
public struct Layout: Codable, Equatable, Sendable {
    public var version = 1
    public var sections: [String: Section]

    public init(sections: [String: Section] = [:]) {
        self.sections = sections
    }

    public func section(for bundleID: String) -> Section {
        sections[bundleID] ?? .visible
    }

    public mutating func assign(_ bundleID: String, to section: Section) {
        if section == .visible { sections.removeValue(forKey: bundleID) } else { sections[bundleID] = section }
    }
}

/// Lecture/écriture atomique du layout en JSON.
public struct LayoutStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func applicationSupport(bundleID: String) -> LayoutStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LayoutStore(url: base.appending(path: bundleID).appending(path: "layout.json"))
    }

    /// Un fichier absent ou illisible rend un layout vide : on ne masque rien plutôt que de planter.
    public func load() -> Layout {
        guard let data = try? Data(contentsOf: url), let layout = try? JSONDecoder().decode(Layout.self, from: data) else {
            return Layout()
        }
        return layout
    }

    public func save(_ layout: Layout) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: url, options: .atomic)
    }
}
