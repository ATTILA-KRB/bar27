// Rend un x de zone vide de la barre (le test AX y voit la barre, pas un item), au milieu du plus large creux.
import AppKit
_ = NSApplication.shared
let sys = AXUIElementCreateSystemWide()
AXUIElementSetMessagingTimeout(sys, 0.1)
func empty(_ x: Double) -> Bool {
    var el: AXUIElement?
    guard AXUIElementCopyElementAtPosition(sys, Float(x), 10, &el) == .success, let el else { return false }
    var role: CFTypeRef?; AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
    return (role as? String) == kAXMenuBarRole
}
let width = Double(NSScreen.screens.first?.frame.width ?? 1512)
var best: (Double, Double)? = nil, start: Double? = nil
for x in stride(from: 0.0, through: width, by: 8) {
    if empty(x) { if start == nil { start = x } } else if let s = start { if best == nil || x - s > best!.1 - best!.0 { best = (s, x) }; start = nil }
}
if let s = start, best == nil || width - s > best!.1 - best!.0 { best = (s, width) }
guard let b = best else { print("AUCUNE"); exit(1) }
print(Int((b.0 + b.1) / 2))
