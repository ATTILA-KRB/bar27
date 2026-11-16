//  Masquage via l'assertion privée « assessment mode » de MenuBarAgent (macOS 27).
//  Adapté de MenuBarAssessmentAssertion27.swift d'Ice (PR #995), lui-même adapté de
//  Barometer (https://github.com/mackid1993/Barometer) et de Thaw
//  (https://github.com/thaw-app/Thaw). GPLv3, comme Bar27.

import Foundation
import OSLog

/// Une assertion active. La relâcher (`invalidate`) réaffiche tout ce qu'elle masquait.
final class ConcealmentToken {
    fileprivate let assertion: AnyObject
    let allowedBundleIDs: [String]

    fileprivate init(assertion: AnyObject, allowedBundleIDs: [String]) {
        self.assertion = assertion
        self.allowedBundleIDs = allowedBundleIDs
    }
}

/// Faits mesurés (phase 0, macOS 27.0.1) : activation acceptée en 56–72 ms pour une app
/// signée Developer ID ; une app non signée Developer ID voit l'appel réussir sans effet.
@MainActor
enum AssessmentBackend {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case rejected(String)
        case timedOut

        var description: String {
            switch self {
            case .unavailable: String(localized: "MenuBarClientCore indisponible")
            case .rejected(let reason): String(localized: "MenuBarAgent a refusé l'assertion : \(reason)")
            case .timedOut: String(localized: "MenuBarAgent n'a pas répondu en 3 s")
            }
        }
    }

    private static let logger = Logger(category: "AssessmentBackend")
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// Numéros des items système conservés. Sur 27.0 : 0 batterie, 2 horloge, 6 Wi‑Fi,
    /// 8 Control Center ; on en autorise plus pour ne pas masquer un futur item système.
    private static let systemItems = (0...63).map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard dlopen(frameworkPath, RTLD_NOW) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
              let assertion = NSClassFromString("MBAssessmentModeAssertion"),
              configuration.instancesRespond(to: configureSelector),
              assertion.instancesRespond(to: activateSelector),
              assertion.instancesRespond(to: invalidateSelector)
        else { return nil }
        return (configuration, assertion)
    }()

    static var isAvailable: Bool { classes != nil }

    static func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken {
        guard let classes,
              let configuration = (classes.configuration.alloc() as AnyObject)
                  .perform(configureSelector, with: systemItems, with: allowedBundleIDs as NSArray)?
                  .takeUnretainedValue(),
              let assertion = (classes.assertion.alloc() as AnyObject)
                  .perform(NSSelectorFromString("init"))?
                  .takeUnretainedValue()
        else { throw Failure.unavailable }

        let start = Date()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = OneShot()
                let completion: @convention(block) (Any?) -> Void = { error in
                    guard once.claim() else { return }
                    if let error { continuation.resume(throwing: Failure.rejected(String(describing: error))) } else { continuation.resume() }
                }
                _ = assertion.perform(activateSelector, with: configuration, with: completion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard once.claim() else { return }
                    continuation.resume(throwing: Failure.timedOut)
                }
            }
        } catch {
            _ = assertion.perform(invalidateSelector)
            logger.error("Activation échouée : \(String(describing: error), privacy: .public)")
            throw error
        }
        logger.info("Assertion active (\(allowedBundleIDs.count) apps autorisées, \(Int(Date().timeIntervalSince(start) * 1000)) ms)")
        return ConcealmentToken(assertion: assertion, allowedBundleIDs: allowedBundleIDs)
    }

    static func invalidate(_ token: ConcealmentToken) {
        _ = token.assertion.perform(invalidateSelector)
        logger.info("Assertion relâchée")
    }
}

/// Garde une continuation partagée entre le completion handler et le délai d'expiration.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
