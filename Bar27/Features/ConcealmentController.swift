import AppKit
import Bar27Core
import Observation
import OSLog

/// Méthode de masquage effectivement utilisée.
enum HidingBackend: String, CaseIterable {
    /// Interrupteur natif « Autoriser dans la barre des menus » : propre, clics système intacts,
    /// mais exige l'accès complet au disque (conteneur Centre de contrôle protégé, sans invite).
    case native
    /// Assertion « assessment mode » : aucune permission en plus, clics système relayés.
    case assessment
}

/// Traduit layout + état de révélation en masquage, et le tient à jour.
@MainActor
@Observable
final class ConcealmentController {
    private(set) var state: RevealState = .collapsed
    private(set) var layout: Layout
    private(set) var lastScan: ItemProvider.Scan?
    private(set) var concealed: [String] = []
    private(set) var lastError: String?
    private(set) var backend: HidingBackend = .assessment
    private(set) var bridgedClicks = 0

    /// Préférence utilisateur ; `nil` = automatique (natif si accessible).
    var preferredBackend: HidingBackend? {
        didSet {
            UserDefaults.standard.set(preferredBackend?.rawValue, forKey: Keys.backend)
            switchBackendIfNeeded()
        }
    }

    /// Délai de re-masquage après révélation (s) ; 0 = jamais.
    var autoRehideDelay: TimeInterval {
        didSet { UserDefaults.standard.set(autoRehideDelay, forKey: Keys.autoRehide) }
    }

    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private var token: ConcealmentToken?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingApply = false
    @ObservationIgnored private var bridging = false
    @ObservationIgnored private var revealedAt = Date.distantPast
    @ObservationIgnored private var rehideTimer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private let store: LayoutStore
    @ObservationIgnored private let selfBundleID: String
    @ObservationIgnored private let logger = Logger(category: "ConcealmentController")
    @ObservationIgnored private(set) lazy var clickBridge = ClickBridge { [weak self] location in
        Task { @MainActor in await self?.bridgeClick(at: location) }
    }

    private enum Keys {
        static let backend = "HidingBackend"
        static let autoRehide = "AutoRehideDelay"
    }

    init(store: LayoutStore, selfBundleID: String) {
        self.store = store
        self.selfBundleID = selfBundleID
        self.layout = store.load()
        self.preferredBackend = UserDefaults.standard.string(forKey: Keys.backend).flatMap(HidingBackend.init(rawValue:))
        // `double(forKey:)` convertit aussi les chaînes du domaine d'arguments (`-AutoRehideDelay 3`).
        self.autoRehideDelay = UserDefaults.standard.object(forKey: Keys.autoRehide) == nil ? 10 : UserDefaults.standard.double(forKey: Keys.autoRehide)
    }

    // MARK: Cycle de vie

    func start() {
        // Un plantage précédent a pu laisser des apps éteintes : on les rallume d'abord.
        if NativeAllowListBackend.isAvailable { NativeAllowListBackend.releaseAll() }
        backend = resolvedBackend()
        logger.info("Backend : \(self.backend.rawValue, privacy: .public)")

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { controller in
            controller.apply()
            // En natif, une app n'est suivie par MenuBarAgent qu'une fois son icône créée.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak controller] in controller?.apply() }
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { $0.apply() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.refreshSystemFrames() }
        // `-DisableClickBridge YES` : contrôle négatif de scripts/verify-click-bridge.sh.
        if !UserDefaults.standard.bool(forKey: "DisableClickBridge") { clickBridge.start() }
        apply()
        Task { await refreshItems() }
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        rehideTimer?.invalidate()
        clickBridge.stop()
        releaseEverything()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (ConcealmentController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { body(self) } }
        }
        observers.append((center, token))
    }

    // MARK: Actions

    func toggle() {
        set(state == .collapsed ? .revealed : .collapsed)
    }

    func set(_ newState: RevealState) {
        guard newState != state else { return }
        state = newState
        if newState == .revealed {
            revealedAt = Date()
            scheduleRehide()
        }
        apply()
        onStateChange?()
    }

    func assign(_ bundleID: String, to section: Section) {
        layout.assign(bundleID, to: section)
        do { try store.save(layout) } catch { lastError = "Sauvegarde du layout : \(error.localizedDescription)" }
        apply()
    }

    func refreshItems() async {
        lastScan = await ItemProvider.scan()
        refreshSystemFrames()
    }

    var nativeAvailable: Bool { NativeAllowListBackend.isAvailable }

    // MARK: Application du plan

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
        // Pendant un relais, l'assertion est levée exprès ; bridgeClick rappelle apply().
        guard !bridging else { return }
        switch backend {
        case .native:
            do {
                // En natif l'interrupteur est persistant : on éteint aussi les apps non lancées.
                let wanted = Set(layout.sections.filter { Self.isConcealed($0.value, in: state) }.keys)
                    .subtracting([selfBundleID, menuBarAgentBundleID])
                try NativeAllowListBackend.apply(concealed: wanted)
                concealed = wanted.sorted()
                lastError = nil
            } catch {
                lastError = String(describing: error)
                logger.error("Natif en échec, repli sur l'assertion : \(String(describing: error), privacy: .public)")
                backend = .assessment
                await applyAssertion()
            }
        case .assessment:
            await applyAssertion()
        }
    }

    private static func isConcealed(_ section: Section, in state: RevealState) -> Bool {
        switch state {
        case .collapsed: section != .visible
        case .revealed: section == .alwaysHidden
        case .revealedAll: false
        }
    }

    private func applyAssertion() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let plan = ConcealmentPlanner.plan(layout: layout, state: state, runningBundleIDs: running, selfBundleID: selfBundleID)
        guard plan?.allowedBundleIDs != token?.allowedBundleIDs else { return }
        let previous = token
        if let plan {
            guard AssessmentBackend.isAvailable else {
                lastError = "Masquage indisponible (MenuBarClientCore absent)"
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
        concealed = plan?.concealedBundleIDs ?? []
        let active = token != nil
        clickBridge.state.withLock { $0.assertionActive = active }
        logger.info("Plan appliqué : \(self.concealed.joined(separator: ", "), privacy: .public)")
        // Les items système bougent quand des apps disparaissent.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshSystemFrames() }
    }

    private func releaseEverything() {
        if let token { AssessmentBackend.invalidate(token) }
        token = nil
        clickBridge.state.withLock { $0.assertionActive = false }
        if NativeAllowListBackend.isAvailable { NativeAllowListBackend.releaseAll() }
        concealed = []
    }

    private func resolvedBackend() -> HidingBackend {
        switch preferredBackend {
        case .assessment: .assessment
        case .native, nil: NativeAllowListBackend.isAvailable ? .native : .assessment
        }
    }

    private func switchBackendIfNeeded() {
        let next = resolvedBackend()
        guard next != backend else { return }
        releaseEverything()
        backend = next
        apply()
    }

    private func refreshSystemFrames() {
        let bridge = clickBridge
        Task.detached {
            let frames = ItemProvider.systemItemFrames()
            bridge.state.withLock { $0.systemFrames = frames }
        }
    }

    // MARK: Relais de clic (assertion seulement)

    /// Mesures Ice (macOS 27.0, 16 essais) : levée de 40 ms → 6 clics perdus, 60 ms → 1,
    /// 80–120 ms → 0. 120 ms garde la marge et finit avant l'apparition du panneau (~166 ms).
    static var liftDuration: Duration {
        let stored = UserDefaults.standard.integer(forKey: "ClickLiftMilliseconds")
        return .milliseconds(stored > 0 ? min(max(stored, 30), 2000) : 120)
    }

    private func bridgeClick(at location: CGPoint) async {
        guard let current = token, !bridging else {
            ClickBridge.replayClick(at: location)
            return
        }
        bridging = true
        let start = ContinuousClock.now
        AssessmentBackend.invalidate(current)
        token = nil
        clickBridge.state.withLock { $0.assertionActive = false }
        // MenuBarAgent ignore un clic qui arrive avant la levée effective.
        try? await Task.sleep(for: .milliseconds(30))
        ClickBridge.replayClick(at: location)
        try? await Task.sleep(for: Self.liftDuration)
        bridging = false
        bridgedClicks += 1
        logger.info("Clic relayé, levée \(String(describing: start.duration(to: .now)), privacy: .public)")
        apply()
    }

    // MARK: Re-masquage automatique

    private func scheduleRehide() {
        rehideTimer?.invalidate()
        guard autoRehideDelay > 0 else { return }
        rehideTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rehideTick() }
        }
    }

    private func rehideTick() {
        guard state == .revealed else { rehideTimer?.invalidate(); return }
        let elapsed = Date().timeIntervalSince(revealedAt)
        let menuOpen = MenuState.isMenuOpen, pointer = MenuState.isPointerInMenuBar
        if elapsed >= autoRehideDelay, menuOpen || pointer {
            logger.debug("Re-masquage différé : menu=\(menuOpen) pointeur=\(pointer)")
        }
        if AutoRehideRule.shouldRehide(state: state, elapsed: elapsed, delay: autoRehideDelay, menuOpen: menuOpen, pointerInMenuBar: pointer) {
            rehideTimer?.invalidate()
            set(.collapsed)
        }
    }
}
