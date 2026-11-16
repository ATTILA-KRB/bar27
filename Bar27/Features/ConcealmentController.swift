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
    /// Apps à masquer, lancées, que l'interrupteur natif ne peut pas éteindre (éléments système
    /// comme Spotlight, ou icône pas encore suivie par MenuBarAgent) : elles restent visibles.
    private(set) var unconcealable: [String] = []
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

    /// Révéler au survol d'une zone vide de la barre.
    var revealOnHover: Bool {
        didSet {
            UserDefaults.standard.set(revealOnHover, forKey: Keys.revealOnHover)
            revealOnHover ? hoverRevealer.start() : hoverRevealer.stop()
        }
    }

    /// En natif, masquer aussi les éléments système hors interrupteur (Spotlight…) par l'assertion.
    /// Prix : clics système relayés tant que l'assertion tient (l'icône de Bar27 reste, vérifié le 15/11/2026).
    var concealSystemItems: Bool {
        didSet {
            UserDefaults.standard.set(concealSystemItems, forKey: Keys.concealSystemItems)
            apply()
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
    @ObservationIgnored private var backendTimer: Timer?
    /// Écriture native en échec alors que la lecture passe : on reste en secours jusqu'au relancement,
    /// sinon le contrôle périodique rebasculerait en natif et échouerait en boucle.
    @ObservationIgnored private var nativeWriteFailed = false
    @ObservationIgnored private lazy var hoverRevealer = HoverRevealer { [weak self] in
        guard let self, self.state == .collapsed else { return }
        self.set(.revealed)
    }
    @ObservationIgnored private(set) lazy var clickBridge = ClickBridge { [weak self] location in
        Task { @MainActor in await self?.bridgeClick(at: location) }
    }

    private enum Keys {
        static let backend = "HidingBackend"
        static let autoRehide = "AutoRehideDelay"
        static let revealOnHover = "RevealOnHover"
        static let concealSystemItems = "ConcealSystemItems"
    }

    /// Mode démo : données fictives, rien n'est lu, masqué ni sauvegardé.
    let isDemo: Bool

    init(store: LayoutStore, selfBundleID: String, demo: Bool = false) {
        self.store = store
        self.selfBundleID = selfBundleID
        self.isDemo = demo
        self.layout = demo ? DemoMode.layout : store.load()
        self.preferredBackend = UserDefaults.standard.string(forKey: Keys.backend).flatMap(HidingBackend.init(rawValue:))
        // `double(forKey:)` convertit aussi les chaînes du domaine d'arguments (`-AutoRehideDelay 3`).
        self.revealOnHover = UserDefaults.standard.object(forKey: Keys.revealOnHover) == nil ? true : UserDefaults.standard.bool(forKey: Keys.revealOnHover)
        self.concealSystemItems = UserDefaults.standard.bool(forKey: Keys.concealSystemItems)
        self.autoRehideDelay = UserDefaults.standard.object(forKey: Keys.autoRehide) == nil ? 10 : UserDefaults.standard.double(forKey: Keys.autoRehide)
    }

    // MARK: Cycle de vie

    func start() {
        if isDemo { return }
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
        if revealOnHover { hoverRevealer.start() }
        // Accès complet au disque accordé (ou retiré) en cours de route : on change de méthode sans relancer.
        backendTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.switchBackendIfNeeded() }
        }
        apply()
        Task { await refreshItems() }
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        rehideTimer?.invalidate()
        backendTimer?.invalidate()
        hoverRevealer.stop()
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
        if isDemo { return }
        do { try store.save(layout) } catch { lastError = String(localized: "Sauvegarde du layout : \(error.localizedDescription)") }
        apply()
    }

    func refreshItems() async {
        if isDemo { return }
        lastScan = await ItemProvider.scan()
        refreshSystemFrames()
    }

    var nativeAvailable: Bool { NativeAllowListBackend.isAvailable }

    // MARK: Application du plan

    /// Recalcule le plan et l'applique. Les appels rapprochés sont fusionnés.
    func apply() {
        if isDemo { return }
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
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        switch backend {
        case .native:
            do {
                // En natif l'interrupteur est persistant : on éteint aussi les apps non lancées.
                let wanted = Set(layout.sections.filter { Self.isConcealed($0.value, in: state) }.keys)
                    .subtracting([selfBundleID, menuBarAgentBundleID])
                let untracked = try NativeAllowListBackend.apply(concealed: wanted)
                lastError = nil
                let residue = untracked.intersection(running)
                // Éléments système (Spotlight…) hors interrupteur : assertion pour eux seuls, si demandé.
                var assisted = Set<String>()
                if concealSystemItems, !residue.isEmpty {
                    let residueLayout = Layout(sections: Dictionary(uniqueKeysWithValues: residue.map { ($0, Section.hidden) }))
                    let plan = ConcealmentPlanner.plan(layout: residueLayout, state: .collapsed, runningBundleIDs: running, selfBundleID: selfBundleID)
                    if await applyAssertion(plan) { assisted = residue }
                } else {
                    _ = await applyAssertion(nil)
                }
                unconcealable = residue.subtracting(assisted).sorted()
                concealed = wanted.subtracting(untracked).union(assisted).sorted()
                if !unconcealable.isEmpty {
                    logger.notice("Non masquables en natif : \(self.unconcealable.joined(separator: " "), privacy: .public)")
                }
            } catch {
                lastError = String(describing: error)
                logger.error("Natif en échec, repli sur l'assertion : \(String(describing: error), privacy: .public)")
                nativeWriteFailed = true
                backend = .assessment
                await applyFullAssertion(running: running)
            }
        case .assessment:
            await applyFullAssertion(running: running)
        }
    }

    private static func isConcealed(_ section: Section, in state: RevealState) -> Bool {
        switch state {
        case .collapsed: section != .visible
        case .revealed: section == .alwaysHidden
        case .revealedAll: false
        }
    }

    /// Méthode de secours seule : l'assertion porte tout le layout.
    private func applyFullAssertion(running: Set<String>) async {
        let plan = ConcealmentPlanner.plan(layout: layout, state: state, runningBundleIDs: running, selfBundleID: selfBundleID)
        guard await applyAssertion(plan) else { return }
        lastError = nil
        concealed = plan?.concealedBundleIDs ?? []
        unconcealable = []
        logger.info("Plan appliqué : \(self.concealed.joined(separator: ", "), privacy: .public)")
    }

    /// Pose (ou lève, `nil`) l'assertion. Rend `false` si elle n'a pas pu être posée.
    private func applyAssertion(_ plan: ConcealmentPlan?) async -> Bool {
        guard plan?.allowedBundleIDs != token?.allowedBundleIDs else { return true }
        let previous = token
        if let plan {
            guard AssessmentBackend.isAvailable else {
                lastError = String(localized: "Masquage indisponible (MenuBarClientCore absent)")
                return false
            }
            do {
                // Nouvelle assertion active AVANT de relâcher l'ancienne : pas de clignotement.
                token = try await AssessmentBackend.activate(allowedBundleIDs: plan.allowedBundleIDs)
            } catch {
                lastError = String(describing: error)
                return false
            }
        } else {
            token = nil
        }
        if let previous { AssessmentBackend.invalidate(previous) }
        let active = token != nil
        clickBridge.state.withLock { $0.assertionActive = active }
        // Les items système bougent quand des apps disparaissent.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshSystemFrames() }
        return true
    }

    private func releaseEverything() {
        if let token { AssessmentBackend.invalidate(token) }
        token = nil
        clickBridge.state.withLock { $0.assertionActive = false }
        if NativeAllowListBackend.isAvailable { NativeAllowListBackend.releaseAll() }
        concealed = []
        unconcealable = []
    }

    private func resolvedBackend() -> HidingBackend {
        switch preferredBackend {
        case .assessment: .assessment
        case .native, nil: !nativeWriteFailed && NativeAllowListBackend.isAvailable ? .native : .assessment
        }
    }

    /// Remet tout en « visible ».
    func resetLayout() {
        layout = isDemo ? DemoMode.layout : Layout()
        if isDemo { return }
        do { try store.save(layout) } catch { lastError = String(localized: "Sauvegarde du layout : \(error.localizedDescription)") }
        apply()
    }

    func switchBackendIfNeeded() {
        let next = resolvedBackend()
        guard next != backend else { return }
        logger.notice("Méthode : \(self.backend.rawValue, privacy: .public) → \(next.rawValue, privacy: .public)")
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
