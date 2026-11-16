import AppKit
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    /// Enregistré, mais l'utilisateur doit l'autoriser dans Réglages Système.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// Réglage depuis le menu : l'échec ou l'autorisation manquante sont signalés (ils passaient sous silence).
    @MainActor static func toggleReportingProblems() {
        let alert = NSAlert()
        do {
            try set(!isEnabled && !needsApproval)
            guard needsApproval else { return }
            alert.messageText = String(localized: "Autorisation requise")
            alert.informativeText = String(localized: "Autorisez Bar27 dans Réglages Système > Général > Ouverture et extensions pour qu'il s'ouvre à la connexion.")
            alert.addButton(withTitle: String(localized: "Ouvrir Réglages"))
            alert.addButton(withTitle: String(localized: "Annuler"))
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Ouverture à la connexion impossible")
            alert.informativeText = String(localized: "Bar27 n'a pas pu modifier l'ouverture à la connexion : \(error.localizedDescription)")
            NSApp.activate()
            alert.runModal()
        }
    }
}
