import AppKit
import Bar27Core
import SwiftUI

/// Fenêtre « Organiser la barre » : autorisations, section par app, réglages, diagnostic.
struct LayoutView: View {
    let controller: ConcealmentController

    @State private var accessibility = Permissions.accessibility
    @State private var fullDiskAccess = Permissions.fullDiskAccess
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var confirmReset = false

    private var rows: [LayoutRow] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return LayoutRows.make(
            scanned: (controller.lastScan?.items ?? []).map { ($0.bundleID, $0.appName) },
            layout: controller.layout,
            running: running,
            selfBundleID: Bundle.main.bundleIdentifier ?? "",
            displayName: AppInfo.name(for:)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissions
            Text("Choisissez quelles apps restent visibles. « Masqué » : affiché d'un clic sur Bar27, au survol d'une zone vide de la barre ou avec ⌃⌥⌘B. « Toujours masqué » : seulement avec « Tout afficher ».")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            table
                .frame(minHeight: 220)
            settings
            diagnostics
        }
        .padding()
        .frame(minWidth: 640, minHeight: 720)
        .task {
            await controller.refreshItems()
            // Les autorisations s'accordent dans Réglages, hors de l'app : on suit leur état.
            while !Task.isCancelled {
                accessibility = Permissions.accessibility
                fullDiskAccess = Permissions.fullDiskAccess
                launchAtLogin = LoginItem.isEnabled
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .confirmationDialog("Tout remettre en visible ?", isPresented: $confirmReset) {
            Button("Tout remettre en visible", role: .destructive) { controller.resetLayout() }
        }
    }

    // MARK: Autorisations

    @ViewBuilder private var permissions: some View {
        if !accessibility || !fullDiskAccess {
            VStack(alignment: .leading, spacing: 8) {
                if !accessibility {
                    permissionRow(
                        title: "Accessibilité (obligatoire)",
                        detail: "Pour lire les icônes de la barre et relayer les clics.",
                        action: ("Autoriser…", { Permissions.requestAccessibility(); Permissions.openSettings(.accessibility) })
                    )
                }
                if !fullDiskAccess {
                    permissionRow(
                        title: "Accès complet au disque (recommandé)",
                        detail: "Pour masquer via l'interrupteur natif de macOS : l'icône de Bar27 et les clics sur l'horloge, le Wi‑Fi, la batterie restent normaux. Sans lui, méthode de secours. Ajoutez Bar27 dans la liste (« + » ou glisser-déposer) ; Bar27 bascule tout seul.",
                        action: ("Ouvrir Réglages", { Permissions.openSettings(.fullDiskAccess); Permissions.revealAppInFinder() })
                    )
                }
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func permissionRow(title: String, detail: String, action: (String, () -> Void)) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action.0, action: action.1)
        }
    }

    // MARK: Apps

    private var table: some View {
        Table(rows) {
            TableColumn("App") { row in
                HStack(spacing: 8) {
                    Image(nsImage: AppInfo.icon(for: row.bundleID))
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading) {
                        Text(row.name)
                        Text(row.isRunning ? row.bundleID : "\(row.bundleID) · non lancée")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(row.isRunning ? 1 : 0.6)
            }
            TableColumn("Icônes") { row in Text(row.itemCount > 0 ? "\(row.itemCount)" : "–") }.width(50)
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
    }

    // MARK: Réglages

    private var settings: some View {
        @Bindable var controller = controller
        return Form {
            Toggle("Afficher au survol d'une zone vide de la barre", isOn: $controller.revealOnHover)
            Picker("Re-masquer après", selection: $controller.autoRehideDelay) {
                Text("Jamais").tag(0.0)
                Text("5 s").tag(5.0)
                Text("10 s").tag(10.0)
                Text("30 s").tag(30.0)
            }
            Picker("Méthode de masquage", selection: $controller.preferredBackend) {
                Text("Automatique").tag(HidingBackend?.none)
                Text("Interrupteur natif (accès complet au disque)").tag(HidingBackend?.some(.native))
                Text("Méthode de secours").tag(HidingBackend?.some(.assessment))
            }
            Toggle("Ouvrir à la connexion", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard enabled != LoginItem.isEnabled else { return }
                    do { try LoginItem.set(enabled); loginError = nil } catch { loginError = error.localizedDescription; launchAtLogin = LoginItem.isEnabled }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            LabeledContent("Raccourci", value: "⌃⌥⌘B")
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // Hauteur idéale du formulaire : la liste des apps prend tout le reste.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Diagnostic

    private var diagnostics: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let scan = controller.lastScan {
                    Text("\(scan.items.count) icônes · lecture \(Int(scan.duration * 1000)) ms" + (scan.unresponsive.isEmpty ? "" : " · lentes : \(scan.unresponsive.joined(separator: ", "))"))
                }
                Text("Méthode : " + (controller.backend == .native ? "interrupteur natif" : "méthode de secours (clics système relayés : \(controller.bridgedClicks))"))
                Text("Masquées : " + (controller.concealed.isEmpty ? "aucune" : controller.concealed.map(AppInfo.displayName(for:)).joined(separator: ", ")))
                if let error = controller.lastError { Text(error).foregroundStyle(.red) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Tout remettre en visible") { confirmReset = true }
                .disabled(controller.layout.sections.isEmpty)
            Button("Actualiser") { Task { await controller.refreshItems() } }
        }
    }
}

/// Nom et icône d'une app, même non lancée.
enum AppInfo {
    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let name = app.localizedName { return name }
        guard let url = url(for: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func displayName(for bundleID: String) -> String { name(for: bundleID) ?? bundleID }

    @MainActor static func icon(for bundleID: String) -> NSImage {
        if let url = url(for: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}
