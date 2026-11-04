//  Règles pures sur la liste `trackedApplications` de MenuBarAgent (interrupteur natif
//  « Autoriser dans la barre des menus », Réglages > Centre de contrôle, macOS 27).
//  Format relevé par Ice (PR #995, TrackedApplications27.swift), GPLv3 : tableau plat
//  alternant clé, valeur ; clé `{"bundle": {"_0": id}}` ; valeur `{location, menuItemLocations, isAllowed}`.
//  Seul `isAllowed` des clés bundle est modifié ; tout le reste est rendu tel quel.

import Foundation

public enum TrackedApplications {
    public struct Entry: Equatable, Sendable {
        public let bundleID: String?
        public let isAllowed: Bool?
        public let valueIndex: Int
    }

    public static func entries(in array: [Any]) -> [Entry] {
        stride(from: 0, to: array.count - 1, by: 2).map { keyIndex in
            Entry(
                bundleID: bundleID(ofKey: array[keyIndex]),
                isAllowed: (array[keyIndex + 1] as? [String: Any])?["isAllowed"] as? Bool,
                valueIndex: keyIndex + 1
            )
        }
    }

    public static func bundleID(ofKey key: Any) -> String? {
        guard let key = key as? [String: Any], key.count == 1, let bundle = key["bundle"] as? [String: Any] else { return nil }
        return bundle["_0"] as? String
    }

    /// `isAllowed` de chaque bundle. Doublon : autorisé si l'une des entrées l'est.
    public static func allowedStates(in array: [Any]) -> [String: Bool] {
        var states = [String: Bool]()
        for entry in entries(in: array) {
            guard let id = entry.bundleID, let allowed = entry.isAllowed else { continue }
            states[id] = (states[id] ?? false) || allowed
        }
        return states
    }

    public static func settingAllowed(_ allowed: Bool, for bundleIDs: Set<String>, in array: [Any]) -> (array: [Any], changed: Set<String>) {
        guard !bundleIDs.isEmpty else { return (array, []) }
        var result = array
        var changed = Set<String>()
        for entry in entries(in: array) {
            guard let id = entry.bundleID, bundleIDs.contains(id),
                  let current = entry.isAllowed, current != allowed,
                  var value = array[entry.valueIndex] as? [String: Any]
            else { continue }
            value["isAllowed"] = allowed
            result[entry.valueIndex] = value
            changed.insert(id)
        }
        return (result, changed)
    }

    public static func decode(_ data: Data) -> [Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
    }

    public static func encode(_ array: [Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: array, format: .binary, options: 0)
    }
}

/// Calcule ce qu'il faut basculer, sans jamais toucher un choix fait par l'utilisateur :
/// on n'éteint que ce qui est allumé, et on ne rallume que ce que Bar27 a éteint (`recorded`).
public struct NativeTogglePlan: Equatable, Sendable {
    public let toDisallow: Set<String>
    public let toAllow: Set<String>
    /// Apps à masquer que MenuBarAgent ne suit pas encore (aucune icône créée) : à réessayer.
    public let untracked: Set<String>

    public static func make(concealed: Set<String>, states: [String: Bool], recorded: Set<String>) -> NativeTogglePlan {
        NativeTogglePlan(
            toDisallow: concealed.filter { states[$0] == true },
            toAllow: recorded.subtracting(concealed),
            untracked: concealed.filter { states[$0] == nil }
        )
    }
}
