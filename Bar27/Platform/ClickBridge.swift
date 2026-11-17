//  Relais des clics vers les items système pendant une assertion (macOS 27).
//  Logique adaptée de HIDEventManager (Ice PR #995, GPLv3) : MenuBarAgent ignore les clics
//  sur horloge/batterie/Wi‑Fi tant que l'assertion tient. Le tap retient le clic ; l'app
//  presse l'item par Accessibility (sans rien lever) ou, pour l'horloge, lève l'assertion,
//  rejoue le clic sur l'item retrouvé par identifiant, puis remasque (`ClickBridgeRule`).
//
//  Le tap tourne sur son propre fil : sur le fil principal, chaque clic du système attendrait
//  l'app, macOS désactiverait le tap pour lenteur, et un appui retenu deviendrait un glisser.
//  Le rappel ne lit que de l'état protégé par verrou.

import AppKit
import Bar27Core
import os

final class ClickBridge: @unchecked Sendable {
    struct Shared {
        var assertionActive = false
        var systemItems: [SystemItem] = []
        var heldPressNumber: Int64?
        var heldUntil: ContinuousClock.Instant?
    }

    /// Marque nos clics rejoués pour que le tap les laisse passer.
    static let replayMarker: Int64 = 0xB427_C11C
    private static let logger = Logger(category: "ClickBridge")

    let state = OSAllocatedUnfairLock(initialState: Shared())
    /// Clic retenu et item système visé (identifiant + cadre au moment du clic).
    private let onBridge: @Sendable (CGPoint, SystemItem) -> Void
    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    init(onBridge: @escaping @Sendable (CGPoint, SystemItem) -> Void) {
        self.onBridge = onBridge
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            let bridge = Unmanaged<ClickBridge>.fromOpaque(refcon!).takeUnretainedValue()
            return bridge.handle(type: type, event: event)
        }, userInfo: refcon) else {
            Self.logger.error("Tap impossible (Accessibilité refusée ?)")
            return
        }
        tap = port
        let thread = Thread { [weak self] in
            guard let self, let port = self.tap else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Bar27.ClickBridge"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        Self.logger.info("Tap actif")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
        thread = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS coupe un tap trop lent ou sur entrée sécurisée : on le rallume.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Self.logger.notice("Tap réactivé après \(type == .tapDisabledByTimeout ? "délai" : "saisie", privacy: .public)")
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else { return Unmanaged.passUnretained(event) }
        let number = event.getIntegerValueField(.mouseEventNumber)

        if type == .leftMouseUp {
            // On ne retient QUE le relâchement de l'appui retenu ; avaler un autre relâchement
            // laisserait le bouton « enfoncé » et transformerait le prochain mouvement en glisser.
            let swallow = state.withLock { s -> Bool in
                guard let until = s.heldUntil, ContinuousClock.now < until, s.heldPressNumber == number else {
                    if let until = s.heldUntil, ContinuousClock.now >= until { s.heldUntil = nil; s.heldPressNumber = nil }
                    return false
                }
                s.heldUntil = nil
                s.heldPressNumber = nil
                return true
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        let location = event.location
        let target = state.withLock { s -> SystemItem? in
            guard s.assertionActive, let item = ClickBridgeRule.target(click: location, systemItems: s.systemItems) else { return nil }
            s.heldPressNumber = number
            s.heldUntil = .now + .seconds(1)
            return item
        }
        guard let target else { return Unmanaged.passUnretained(event) }
        onBridge(location, target)
        return nil
    }

    static func replayClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
