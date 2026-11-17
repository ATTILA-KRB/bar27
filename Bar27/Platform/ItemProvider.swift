import AppKit
import ApplicationServices
import Bar27Core
import OSLog

/// Lit les items de la barre des menus via Accessibility (macOS 27).
///
/// Chaque process publie ses items sous `AXExtrasMenuBar` ; MenuBarAgent publie les items
/// système. Les appels AX bloquent : ils tournent hors du pool Swift, en parallèle, avec un
/// délai court par process (une app figée ne doit pas retenir tout le balayage).
/// Mesure phase 0 : 1,9 s en séquentiel sur 129 apps.
enum ItemProvider {
    struct Scan: Sendable {
        let items: [MenuBarItem]
        let duration: TimeInterval
        let unresponsive: [String]
    }

    private static let logger = Logger(category: "ItemProvider")
    private static let queue = DispatchQueue(label: "com.attila-krb.Bar27.ItemProvider", qos: .userInitiated)
    private static let messagingTimeout: Float = 0.25

    static func scan() async -> Scan {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: scanSync()) }
        }
    }

    static func scanSync() -> Scan {
        let start = Date()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        // Notre propre process est exclu : l'interroger depuis un autre fil attendrait le fil principal.
        let apps = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != selfPID && $0.bundleIdentifier != nil }
        let collector = Collector()
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let app = apps[i]
            let t = Date()
            let found = items(of: app)
            collector.add(found ?? [], slow: Date().timeIntervalSince(t) > Double(messagingTimeout) ? app.bundleIdentifier : nil)
        }

        let (collected, unresponsive) = collector.result
        let items = collected.sorted { $0.frame.minX < $1.frame.minX }
        let duration = Date().timeIntervalSince(start)
        logger.debug("Scan: \(items.count) items, \(apps.count) apps, \(Int(duration * 1000)) ms")
        return Scan(items: items, duration: duration, unresponsive: unresponsive)
    }

    /// Cadres des items système (un seul process, ~quelques ms). Sert au relais de clics.
    /// Non filtré : l'indice est le rang de l'item dans MenuBarAgent et sert à le retrouver
    /// après la levée (`ClickBridgeRule.replayPoint`) ; les cadres vides sont ignorés par la règle.
    static func systemItemFrames() -> [CGRect] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgentBundleID).first else { return [] }
        // Cadres seuls (pas de titre) : appelé pendant la levée d'un clic relayé, chaque ms compte.
        let element = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute)
        else { return [] }
        return children.map { frame(of: $0) ?? .zero }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [MenuBarItem] = []
        private var slow: [String] = []

        func add(_ found: [MenuBarItem], slow bundleID: String?) {
            lock.withLock {
                items += found
                if let bundleID { slow.append(bundleID) }
            }
        }

        var result: ([MenuBarItem], [String]) { lock.withLock { (items, slow.sorted()) } }
    }

    private static func items(of app: NSRunningApplication) -> [MenuBarItem]? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute)
        else { return nil }
        return children.enumerated().map { index, child in
            let title: String? = attribute(child, kAXTitleAttribute) ?? attribute(child, kAXDescriptionAttribute)
            return MenuBarItem(
                id: ItemID(bundleID: bundleID, index: index),
                pid: app.processIdentifier,
                appName: app.localizedName,
                title: title.flatMap { $0.isEmpty ? nil : $0 },
                frame: frame(of: child) ?? .zero
            )
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
