import AppKit
import Bar27Core
import Observation
import OSLog

/// Traduit layout + état de révélation en assertion MenuBarAgent, et la tient à jour.
@MainActor
@Observable
final class ConcealmentController {
    private(set) var state: RevealState = .collapsed
    private(set) var layout: Layout
    private(set) var lastScan: ItemProvider.Scan?
    private(set) var activePlan: ConcealmentPlan?
    private(set) var lastError: String?

    @ObservationIgnored private var token: ConcealmentToken?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingApply = false
    @ObservationIgnored private let store: LayoutStore
    @ObservationIgnored private let selfBundleID: String
    @ObservationIgnored private let logger = Logger(category: "ConcealmentController")
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: LayoutStore, selfBundleID: String) {
        self.store = store
        self.selfBundleID = selfBundleID
        self.layout = store.load()
    }

    func start() {
        // L'assertion est une allowlist : une app lancée pendant le masquage serait masquée
        // à tort tant qu'on ne replanifie pas.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        apply()
        Task { await refreshItems() }
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        if let token { AssessmentBackend.invalidate(token) }
        token = nil
        activePlan = nil
    }

    func toggle() {
        set(state == .collapsed ? .revealed : .collapsed)
    }

    func set(_ newState: RevealState) {
        guard newState != state else { return }
        state = newState
        apply()
    }

    func assign(_ bundleID: String, to section: Section) {
        layout.assign(bundleID, to: section)
        do { try store.save(layout) } catch { lastError = "Sauvegarde du layout : \(error.localizedDescription)" }
        apply()
    }

    func refreshItems() async {
        lastScan = await ItemProvider.scan()
    }

    /// Recalcule le plan et l'applique. Les appels rapprochés sont fusionnés.
    func apply() {
        if applyTask != nil {
            pendingApply = true
            return
        }
        applyTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                pendingApply = false
                await applyOnce()
            } while pendingApply
            applyTask = nil
        }
    }

    private func applyOnce() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let plan = ConcealmentPlanner.plan(layout: layout, state: state, runningBundleIDs: running, selfBundleID: selfBundleID)
        guard plan != activePlan || (plan != nil && token == nil) else { return }

        let previous = token
        if let plan {
            guard AssessmentBackend.isAvailable else {
                lastError = "Masquage indisponible sur ce macOS (MenuBarClientCore absent)"
                return
            }
            do {
                // Nouvelle assertion active AVANT de relâcher l'ancienne : pas de clignotement.
                token = try await AssessmentBackend.activate(allowedBundleIDs: plan.allowedBundleIDs)
                lastError = nil
            } catch {
                lastError = String(describing: error)
                return
            }
        } else {
            token = nil
        }
        if let previous { AssessmentBackend.invalidate(previous) }
        activePlan = plan
        logger.info("Plan appliqué : \(plan?.concealedBundleIDs.joined(separator: ", ") ?? "rien", privacy: .public)")
    }
}
