// Spike B — masquage via l'assertion privée « assessment mode » de MenuBarAgent (macOS 27).
// Adapté de Ice (PR #995) / Barometer / Thaw, GPLv3.
import AppKit

let log = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/bar27-spike.log")
func note(_ s: String) {
    let line = "\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) \(s)\n"
    if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: log, atomically: true, encoding: .utf8) }
}
let allowed = ["com.anthropic.claudefordesktop"]   // une app laissée visible pour tester l'allowlist
let hold: Double = 4

guard dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil,
      let C: AnyClass = NSClassFromString("MBAssessmentModeConfiguration"),
      let A: AnyClass = NSClassFromString("MBAssessmentModeAssertion") else { note("UNAVAILABLE"); exit(1) }
let cfgSel = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
let actSel = NSSelectorFromString("activateWithConfiguration:completionHandler:")
let invSel = NSSelectorFromString("invalidate")
note("classes ok cfg=\(C.instancesRespond(to: cfgSel)) act=\(A.instancesRespond(to: actSel)) inv=\(A.instancesRespond(to: invSel))")

let sys = (0...63).map { NSNumber(value: $0) } as NSArray
let cfg = (C.alloc() as AnyObject).perform(cfgSel, with: sys, with: allowed as NSArray)!.takeUnretainedValue()
let assertion = (A.alloc() as AnyObject).perform(NSSelectorFromString("init"))!.takeUnretainedValue()
let t0 = ProcessInfo.processInfo.systemUptime
let done: @convention(block) (Any?) -> Void = { err in
    DispatchQueue.main.async {
        note("ACTIVE err=\(String(describing: err)) latence=\(Int((ProcessInfo.processInfo.systemUptime - t0)*1000)) ms")
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            _ = assertion.perform(invSel); note("RELEASED")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }
    }
}
_ = assertion.perform(actSel, with: cfg, with: done)
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { note("TIMEOUT"); exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
