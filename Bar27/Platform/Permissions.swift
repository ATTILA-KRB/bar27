import AppKit
import ApplicationServices
import CoreGraphics

/// Accessibility : obligatoire (lecture des items, clics système).
/// Accès complet au disque : facultatif mais recommandé (interrupteur natif, voir NativeAllowListBackend).
/// Screen Recording : facultatif (images réelles des items, phase 3).
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Affiche l'invite système qui renvoie vers Réglages > Confidentialité > Accessibilité.
    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Pas d'API de requête ni d'invite : on mesure en lisant la préférence protégée.
    @MainActor static var fullDiskAccess: Bool { NativeAllowListBackend.isAvailable }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case fullDiskAccess = "Privacy_AllFiles"
    }

    static func openSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Montre l'app dans le Finder, à glisser dans la liste « Accès complet au disque ».
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
