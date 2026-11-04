// Spike A — inventaire des items de la barre des menus via Accessibility (macOS 27).
import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

let t0 = Date()
var rows: [(Double, String)] = []
var slow: [(String, Double)] = []
for app in NSWorkspace.shared.runningApplications {
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 0.25)
    let s = Date()
    guard let bar = attr(ax, "AXExtrasMenuBar") else {
        let d = Date().timeIntervalSince(s); if d > 0.1 { slow.append((app.bundleIdentifier ?? "?", d)) }; continue
    }
    for child in (attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        let id = attr(child, kAXIdentifierAttribute) as? String ?? "-"
        let title = (attr(child, kAXTitleAttribute) as? String) ?? (attr(child, kAXDescriptionAttribute) as? String) ?? "-"
        let f = frame(child) ?? .zero
        rows.append((f.minX, String(format: "x=%7.1f w=%5.1f  %@  pid=%d  id=%@  « %@ »",
            f.minX, f.width, app.bundleIdentifier ?? "?", app.processIdentifier, id, title)))
    }
}
for r in rows.sorted(by: { $0.0 < $1.0 }) { print(r.1) }
print("items=\(rows.count) apps=\(NSWorkspace.shared.runningApplications.count) durée=\(String(format: "%.0f", Date().timeIntervalSince(t0)*1000)) ms")
for s in slow { print("lent:", s.0, String(format: "%.0f ms", s.1*1000)) }
