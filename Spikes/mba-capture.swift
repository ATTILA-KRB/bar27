// Capture des fenêtres de MenuBarAgent via ScreenCaptureKit (même hors écran / plein écran).
import ScreenCaptureKit
import AppKit
_ = NSApplication.shared  // initialise CoreGraphics (sinon CGS_REQUIRE_INIT)
let out = CommandLine.arguments[1]
let sem = DispatchSemaphore(value: 0)
Task {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let wins = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.apple.MenuBarAgent" && $0.frame.height < 60 && $0.frame.width > 200 }
    for (i, w) in wins.enumerated() {
        print("win \(w.windowID) layer=\(w.windowLayer) onScreen=\(w.isOnScreen) frame=\(w.frame) title=\(w.title ?? "-")")
        let cfg = SCStreamConfiguration(); cfg.width = Int(w.frame.width*2); cfg.height = Int(w.frame.height*2); cfg.showsCursor = false
        if let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) {
            let rep = NSBitmapImageRep(cgImage: img)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)-\(i).png"))
        }
    }
    sem.signal()
}
sem.wait()
