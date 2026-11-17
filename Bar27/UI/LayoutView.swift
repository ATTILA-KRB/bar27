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
        if controller.isDemo {
            return LayoutRows.make(
                scanned: DemoMode.items.map { ($0.bundleID, $0.appName.map(AppInfo.demoName)) }, layout: controller.layout,
                running: Set(DemoMode.apps.map(\.bundleID)), selfBundleID: "", displayName: { _ in nil }
            )
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return LayoutRows.make(
            scanned: (controller.lastScan?.items ?? []).map { ($0.bundleID, $0.appName) },
            layout: controller.layout,
            running: running,
            selfBundleID: Bundle.main.bundleIdentifier ?? "",
            displayName: AppInfo.name(for:)
        )
    }

    /// En démo rien n'est réellement masqué : on affiche ce que le layout masquerait.
    private var concealedIDs: [String] {
        controller.isDemo ? DemoMode.concealedBundleIDs(layout: controller.layout) : controller.concealed
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
        if !controller.isDemo, !accessibility || !fullDiskAccess {
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

    private func permissionRow(title: LocalizedStringKey, detail: LocalizedStringKey, action: (LocalizedStringKey, () -> Void)) -> some View {
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

    /// Les éléments système (Spotlight…) ne figurent pas dans l'interrupteur natif ; une app tierce
    /// y apparaît seulement après avoir créé son icône.
    private static func unconcealableHint(_ bundleID: String) -> String {
        bundleID.hasPrefix("com.apple.")
            ? String(localized: "Élément système : activez « Masquer aussi Spotlight… » ci-dessous, ou retirez-le dans Réglages > Centre de contrôle")
            : String(localized: "Pas encore suivie par macOS : réessai au prochain changement")
    }

    private var table: some View {
        Table(rows) {
            TableColumn("App") { row in
                HStack(spacing: 8) {
                    Image(nsImage: AppInfo.icon(for: row.bundleID))
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading) {
                        Text(row.name)
                        Text(row.isRunning ? row.bundleID : String(localized: "\(row.bundleID) · non lancée"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if controller.unconcealable.contains(row.bundleID) {
                            Label(Self.unconcealableHint(row.bundleID), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
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
            if controller.backend == .native || DemoMode.snapshot {
                Toggle(isOn: $controller.concealSystemItems) {
                    Text("Masquer aussi Spotlight et les éléments système")
                    Text("Hors de portée de l'interrupteur natif : méthode de secours pour eux seuls ; les clics sur l'horloge, le Wi‑Fi et la batterie sont alors relayés.")
                }
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

    private func scanSummary(_ scan: ItemProvider.Scan) -> String {
        let icons = String(localized: "\(scan.items.count) icônes")
        var line = String(localized: "\(icons) · lecture \(Int(scan.duration * 1000)) ms")
        if !scan.unresponsive.isEmpty { line += String(localized: " · lentes : \(scan.unresponsive.joined(separator: ", "))") }
        return line
    }

    private var diagnostics: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if controller.isDemo, DemoMode.snapshot {
                    Text("\(DemoMode.items.count) icônes")
                } else if controller.isDemo {
                    Text("\(String(localized: "\(DemoMode.items.count) icônes")) · mode démo (données fictives)")
                } else if let scan = controller.lastScan {
                    Text(verbatim: scanSummary(scan))
                }
                Text("Méthode : \(controller.backend == .native || DemoMode.snapshot ? String(localized: "interrupteur natif") : String(localized: "méthode de secours (clics système relayés : \(controller.bridgedClicks))"))")
                Text("Masquées : \(concealedIDs.isEmpty ? String(localized: "aucune") : concealedIDs.map(AppInfo.displayName(for:)).joined(separator: ", "))")
                if !controller.unconcealable.isEmpty {
                    Text("Restent visibles (hors de portée de l'interrupteur natif) : \(controller.unconcealable.map(AppInfo.displayName(for:)).joined(separator: ", "))")
                        .foregroundStyle(.orange)
                }
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

    static func displayName(for bundleID: String) -> String { DemoMode.name(for: bundleID).map(demoName) ?? name(for: bundleID) ?? bundleID }

    /// Noms fictifs du mode démo : la clé du catalogue est le nom français.
    static func demoName(_ name: String) -> String { String(localized: String.LocalizationValue(name)) }

    @MainActor static func icon(for bundleID: String) -> NSImage {
        if let symbol = DemoMode.symbol(for: bundleID), let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) { return image }
        if let url = url(for: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}
