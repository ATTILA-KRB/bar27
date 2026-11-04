//  Masquage par l'interrupteur natif « Autoriser dans la barre des menus » de macOS 27.
//  Adapté de NativeAllowListConcealer27.swift d'Ice (PR #995), GPLv3.
//
//  MenuBarAgent garde l'interrupteur dans la préférence `trackedApplications` du conteneur
//  `group.com.apple.controlcenter`. L'écriture doit passer par les appels CoreFoundation
//  « avec conteneur » (privés) : un `defaults write` ne réveille pas MenuBarAgent.
//  Avantage sur l'assertion : les items système gardent leurs clics, rien à rejouer.

import Bar27Core
import Foundation
import OSLog

@MainActor
enum NativeAllowListBackend {
    enum Failure: Error, CustomStringConvertible {
        case unavailable, unreadable, notSynchronized
        var description: String {
            switch self {
            case .unavailable: "Appels CoreFoundation avec conteneur indisponibles"
            case .unreadable: "Préférence trackedApplications illisible (accès au conteneur Centre de contrôle refusé ?)"
            case .notSynchronized: "Préférence trackedApplications non synchronisée"
            }
        }
    }

    private static let logger = Logger(category: "NativeAllowListBackend")
    /// Apps éteintes par Bar27 et pas encore rallumées ; survit à un plantage (rallumées au lancement).
    private static let recordedKey = "NativeDisallowed"

    static var recorded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: recordedKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: recordedKey) }
    }

    static var isAvailable: Bool { (try? read()) != nil }

    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")
    }

    /// Une lecture directe du fichier (contrairement à cfprefsd) déclenche l'invite système
    /// « Bar27 souhaite accéder aux données d'autres apps ».
    static func requestAccess() {
        _ = try? Data(contentsOf: plistURL)
    }

    static func states() throws -> [String: Bool] {
        TrackedApplications.allowedStates(in: try read())
    }

    /// Éteint `concealed`, rallume ce que Bar27 avait éteint et qui ne doit plus l'être.
    /// Rend les apps non encore suivies par MenuBarAgent.
    @discardableResult
    static func apply(concealed: Set<String>) throws -> Set<String> {
        var array = try read()
        let plan = NativeTogglePlan.make(concealed: concealed, states: TrackedApplications.allowedStates(in: array), recorded: recorded)
        // Enregistré AVANT l'écriture : un plantage entre les deux laisse de quoi tout rallumer.
        recorded = recorded.union(plan.toDisallow)
        let off = TrackedApplications.settingAllowed(false, for: plan.toDisallow, in: array)
        let on = TrackedApplications.settingAllowed(true, for: plan.toAllow, in: off.array)
        array = on.array
        if !off.changed.isEmpty || !on.changed.isEmpty {
            try write(array)
            if !off.changed.isEmpty { logger.notice("Éteintes : \(off.changed.sorted().joined(separator: " "), privacy: .public)") }
            if !on.changed.isEmpty { logger.notice("Rallumées : \(on.changed.sorted().joined(separator: " "), privacy: .public)") }
        }
        let final = TrackedApplications.allowedStates(in: array)
        recorded = recorded.intersection(concealed).filter { final[$0] == false }
        return plan.untracked
    }

    /// Rallume tout ce que Bar27 a éteint (lancement, fin, « Tout afficher »).
    static func releaseAll() {
        guard !recorded.isEmpty else { return }
        do { try apply(concealed: []) } catch { logger.error("releaseAll : \(String(describing: error), privacy: .public)") }
    }

    // MARK: Préférences avec conteneur

    private typealias Copy = @convention(c) (CFString, CFString, CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
    private typealias SetValue = @convention(c) (CFString, CFPropertyList?, CFString, CFString, CFString, CFString) -> Void
    private typealias Synchronize = @convention(c) (CFString, CFString, CFString, CFString) -> Bool

    private static let calls: (copy: Copy, set: SetValue, sync: Synchronize)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW),
              let copy = dlsym(handle, "_CFPreferencesCopyValueWithContainer"),
              let set = dlsym(handle, "_CFPreferencesSetValueWithContainer"),
              let sync = dlsym(handle, "_CFPreferencesSynchronizeWithContainer")
        else { return nil }
        return (unsafeBitCast(copy, to: Copy.self), unsafeBitCast(set, to: SetValue.self), unsafeBitCast(sync, to: Synchronize.self))
    }()

    private static let key = "trackedApplications" as CFString
    private static let applicationID = "group.com.apple.controlcenter" as CFString
    private static var container: CFString { (NSHomeDirectory() + "/Library/Group Containers/group.com.apple.controlcenter") as CFString }

    private static func read() throws -> [Any] {
        guard let calls else { throw Failure.unavailable }
        guard let value = calls.copy(key, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)?.takeRetainedValue(),
              let data = value as? Data, let array = TrackedApplications.decode(data)
        else { throw Failure.unreadable }
        return array
    }

    private static func write(_ array: [Any]) throws {
        guard let calls else { throw Failure.unavailable }
        calls.set(key, try TrackedApplications.encode(array) as CFData, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
        guard calls.sync(applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container) else { throw Failure.notSynchronized }
    }
}
