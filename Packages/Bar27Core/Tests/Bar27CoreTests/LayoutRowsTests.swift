import Foundation
import Testing
@testable import Bar27Core

@Test func rowsIncludeAssignedAppsThatAreNotInTheBar() {
    let layout = Layout(sections: ["gone": .hidden, "b": .alwaysHidden])
    let rows = LayoutRows.make(
        scanned: [("b", "Bravo"), ("b", nil), ("a", "Alpha"), ("self", "Bar27"), (menuBarAgentBundleID, nil)],
        layout: layout, running: ["a", "b", "self"], selfBundleID: "self",
        displayName: { $0 == "gone" ? "Zulu" : nil }
    )
    #expect(rows.map(\.bundleID) == ["a", "b", "gone"])
    #expect(rows[1] == LayoutRow(bundleID: "b", name: "Bravo", itemCount: 2, isRunning: true, section: .alwaysHidden))
    #expect(rows[2] == LayoutRow(bundleID: "gone", name: "Zulu", itemCount: 0, isRunning: false, section: .hidden))
}

@Test func rowsFallBackToBundleIDAndSortStably() {
    let rows = LayoutRows.make(scanned: [("x.two", nil), ("x.one", nil)], layout: Layout(), running: [], selfBundleID: "s", displayName: { _ in "Même" })
    #expect(rows.map(\.bundleID) == ["x.one", "x.two"])
    let bare = LayoutRows.make(scanned: [("x.id", nil)], layout: Layout(), running: [], selfBundleID: "s", displayName: { _ in nil })
    #expect(bare.first?.name == "x.id")
}

@Test func dwellFiresOncePerHover() {
    var trigger = DwellTrigger(threshold: 0.4)
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    let steps: [(Bool, TimeInterval)] = [(true, 0), (true, 0.3), (true, 0.45), (true, 2), (false, 2.1), (true, 2.2), (true, 2.7)]
    let fired = steps.map { trigger.update(hovering: $0.0, now: t0 + $0.1) }
    // Déclenche à 0,45 s, une seule fois par survol ; quitter la zone réarme et recompte.
    #expect(fired == [false, false, true, false, false, false, true])
}

@Test func demoModeIsOptInAndSelfContained() {
    #expect(!DemoMode.isEnabled(arguments: ["Bar27"], environment: [:]))
    #expect(!DemoMode.isEnabled(arguments: [], environment: ["BAR27_DEMO": "0"]))
    #expect(DemoMode.isEnabled(arguments: ["Bar27", "-demo"], environment: [:]))
    #expect(DemoMode.isEnabled(arguments: [], environment: ["BAR27_DEMO": "1"]))
    // Aucune vraie app : tous les identifiants sont fictifs, chacun a une icône SF Symbols.
    #expect(DemoMode.apps.allSatisfy { $0.bundleID.hasPrefix("demo.bar27.") && DemoMode.symbol(for: $0.bundleID) != nil })
    let rows = LayoutRows.make(
        scanned: DemoMode.items.map { ($0.bundleID, $0.appName) }, layout: DemoMode.layout,
        running: Set(DemoMode.apps.map(\.bundleID)), selfBundleID: "self", displayName: { _ in nil }
    )
    #expect(rows.count == DemoMode.apps.count)
    #expect(rows.first { $0.name == "Musique" }?.itemCount == 2)
    #expect(rows.first { $0.name == "Notes" }?.section == .alwaysHidden)
}
