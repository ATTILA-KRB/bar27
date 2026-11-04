import AppKit
import Bar27Core

/// Commandes sans interface pour la vérification automatisée (scripts/verify.sh).
///   --dump-items                     inventaire JSON des items puis sortie
///   --conceal <bundleID> <secondes>  masque une app via l'assertion puis relâche et sort
@MainActor
enum HeadlessCommands {
    static func run(arguments: [String], selfBundleID: String) -> Bool {
        if arguments.contains("--dump-items") {
            let scan = ItemProvider.scanSync()
            let rows = scan.items.map { ["id": $0.id.description, "app": $0.appName ?? "", "title": $0.title ?? "", "x": "\(Int($0.frame.minX))", "w": "\(Int($0.frame.width))"] }
            let payload: [String: Any] = ["durationMs": Int(scan.duration * 1000), "count": scan.items.count, "unresponsive": scan.unresponsive, "items": rows]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            print()
            exit(0)
        }
        if let i = arguments.firstIndex(of: "--conceal"), arguments.count > i + 2, let seconds = Double(arguments[i + 2]) {
            let target = arguments[i + 1]
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let layout = Layout(sections: [target: .hidden])
            guard let plan = ConcealmentPlanner.plan(layout: layout, state: .collapsed, runningBundleIDs: running, selfBundleID: selfBundleID) else {
                print("RIEN À MASQUER (\(target) non lancé ?)"); exit(3)
            }
            Task {
                do {
                    let token = try await AssessmentBackend.activate(allowedBundleIDs: plan.allowedBundleIDs)
                    print("CONCEALED \(plan.concealedBundleIDs)"); fflush(stdout)
                    try await Task.sleep(for: .seconds(seconds))
                    AssessmentBackend.invalidate(token)
                    print("RELEASED"); fflush(stdout)
                    try await Task.sleep(for: .milliseconds(300))
                    exit(0)
                } catch {
                    print("ERREUR \(error)"); exit(4)
                }
            }
            return true
        }
        return false
    }
}
