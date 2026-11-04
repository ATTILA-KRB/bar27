// Clique (événement non marqué, comme un vrai clic) en x,y et mesure l'ouverture d'un panneau
// système (Centre de notifications / Centre de contrôle : fenêtre haute, couche >= 20). Puis Échap.
import AppKit
_ = NSApplication.shared
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let owners = Set(NSWorkspace.shared.runningApplications.filter { ["com.apple.notificationcenterui", "com.apple.controlcenter"].contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
func panels() -> Set<Int> {
    let w = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return Set(w.compactMap { d in
        guard let n = d[kCGWindowNumber as String] as? Int, let l = d[kCGWindowLayer as String] as? Int, l >= 20,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
              let b = d[kCGWindowBounds as String] as? [String: CGFloat], (b["Height"] ?? 0) > 150 else { return nil }
        return n
    })
}
let before = panels()
let src = CGEventSource(stateID: .hidSystemState)
let t0 = Date()
for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(30_000)
}
var opened: Int? = nil
for _ in 0..<40 { if !panels().subtracting(before).isEmpty { opened = Int(Date().timeIntervalSince(t0) * 1000); break }; usleep(25_000) }
print(opened.map { "OUVERT \($0) ms" } ?? "RIEN")
usleep(300_000)
for down in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: down)!.post(tap: .cghidEventTap) }
usleep(500_000)
