import AppKit
import Bar27Core

/// Commandes sans interface pour la vérification automatisée (scripts/verify.sh).
///   --dump-items                     inventaire JSON des items puis sortie
///   --conceal <bundleID> <secondes>  masque une app via l'assertion puis relâche et sort
@MainActor
enum HeadlessCommands {
    static func run(arguments: [String], selfBundleID: String) -> Bool {
        // --native <fichier> [off|on <bundleID>] : lit/bascule l'interrupteur natif, écrit le résultat dans <fichier>
        // (lancé par `open` pour avoir l'identité TCC de l'app, pas celle du terminal).
        if let i = arguments.firstIndex(of: "--native"), arguments.count > i + 1 {
            let out = URL(fileURLWithPath: arguments[i + 1])
            var text = ""
            if !NativeAllowListBackend.isAvailable {
                NativeAllowListBackend.requestAccess()
                for _ in 0..<6 where !NativeAllowListBackend.isAvailable { Thread.sleep(forTimeInterval: 0.5) }
            }
            do {
                if arguments.count > i + 3 {
                    let target = arguments[i + 3]
                    try NativeAllowListBackend.apply(concealed: arguments[i + 2] == "off" ? [target] : [])
                    text += "APPLIED \(arguments[i + 2]) \(target)\n"
                }
                for (id, allowed) in try NativeAllowListBackend.states().sorted(by: { $0.key < $1.key }) { text += "\(id) \(allowed)\n" }
                text += "recorded=\(NativeAllowListBackend.recorded.sorted())\n"
            } catch {
                text += "ERREUR \(error)\n"
                // Diagnostic : lecture directe du fichier (FDA effectif ? clé présente ?).
                do {
                    let data = try Data(contentsOf: NativeAllowListBackend.plistURL)
                    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
                    text += "FICHIER lisible, clés : \(plist.keys.sorted())\n"
                } catch {
                    text += "FICHIER illisible : \(error.localizedDescription)\n"
                }
            }
            try? text.write(to: out, atomically: true, encoding: .utf8)
            exit(0)
        }
        // --login-item on|off|status : ouverture à la connexion (SMAppService), sortie sur stdout.
        if let i = arguments.firstIndex(of: "--login-item") {
            let action = arguments.count > i + 1 ? arguments[i + 1] : "status"
            do {
                if action != "status" { try LoginItem.set(action == "on") }
                print("LOGIN \(LoginItem.isEnabled ? "on" : "off")")
            } catch {
                print("ERREUR \(error.localizedDescription)")
            }
            exit(0)
        }
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
