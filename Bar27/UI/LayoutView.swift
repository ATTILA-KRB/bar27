import Bar27Core
import SwiftUI

/// Fenêtre « Organiser la barre » : apps qui ont des items, section par app, diagnostic.
struct LayoutView: View {
    let controller: ConcealmentController

    private struct AppRow: Identifiable {
        let bundleID: String
        let name: String
        let itemCount: Int
        var id: String { bundleID }
    }

    private var rows: [AppRow] {
        let items = controller.lastScan?.items.filter { !$0.isSystem } ?? []
        let grouped = Dictionary(grouping: items, by: \.bundleID)
        return grouped.map { AppRow(bundleID: $0.key, name: $0.value.first?.appName ?? $0.key, itemCount: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !Permissions.accessibility {
                Label("Bar27 a besoin de l'accès Accessibilité pour lire la barre des menus.", systemImage: "exclamationmark.triangle")
                Button("Ouvrir l'autorisation") { Permissions.requestAccessibility() }
            }
            Table(rows) {
                TableColumn("App") { row in
                    VStack(alignment: .leading) {
                        Text(row.name)
                        Text(row.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Icônes") { row in Text("\(row.itemCount)") }.width(50)
                TableColumn("Section") { row in
                    Picker("", selection: Binding(
                        get: { controller.layout.section(for: row.bundleID) },
                        set: { controller.assign(row.bundleID, to: $0) }
                    )) {
                        Text("Visible").tag(Section.visible)
                        Text("Masqué").tag(Section.hidden)
                        Text("Toujours masqué").tag(Section.alwaysHidden)
                    }
                    .labelsHidden()
                }.width(170)
            }
            settings
            diagnostics
        }
        .padding()
        .frame(minWidth: 600, minHeight: 640)
        .task { await controller.refreshItems() }
    }

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private var settings: some View {
        @Bindable var controller = controller
        return Form {
            Picker("Re-masquer après", selection: $controller.autoRehideDelay) {
                Text("Jamais").tag(0.0)
                Text("5 s").tag(5.0)
                Text("10 s").tag(10.0)
                Text("30 s").tag(30.0)
            }
            Picker("Méthode de masquage", selection: $controller.preferredBackend) {
                Text("Automatique").tag(HidingBackend?.none)
                Text("Interrupteur natif (accès complet au disque)").tag(HidingBackend?.some(.native))
                Text("Assertion").tag(HidingBackend?.some(.assessment))
            }
            if controller.preferredBackend == .native && !controller.nativeAvailable {
                Text("Ajoutez Bar27 dans Réglages > Confidentialité > Accès complet au disque, puis relancez.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Ouvrir à la connexion", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do { try LoginItem.set(enabled); loginError = nil } catch { loginError = error.localizedDescription; launchAtLogin = LoginItem.isEnabled }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            Text("Raccourci : ⌃⌥⌘B").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(maxHeight: 230)
    }

    private var diagnostics: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let scan = controller.lastScan {
                    Text("\(scan.items.count) icônes · lecture \(Int(scan.duration * 1000)) ms" + (scan.unresponsive.isEmpty ? "" : " · lentes : \(scan.unresponsive.joined(separator: ", "))"))
                }
                Text("Méthode : " + (controller.backend == .native ? "interrupteur natif" : "assertion (clics système relayés : \(controller.bridgedClicks))"))
                Text("Masquées : " + (controller.concealed.isEmpty ? "aucune" : controller.concealed.joined(separator: ", ")))
                if let error = controller.lastError { Text(error).foregroundStyle(.red) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Actualiser") { Task { await controller.refreshItems() } }
        }
    }
}
