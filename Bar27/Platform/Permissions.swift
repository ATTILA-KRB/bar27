import ApplicationServices
import CoreGraphics

/// Accessibility : obligatoire (lecture des items, clics système).
/// Screen Recording : facultatif (images réelles des items, phase 3).
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Affiche l'invite système qui renvoie vers Réglages > Confidentialité > Accessibilité.
    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
