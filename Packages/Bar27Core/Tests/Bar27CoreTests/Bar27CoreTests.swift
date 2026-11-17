import Foundation
import Testing
@testable import Bar27Core

private let me = "com.attila-krb.Bar27"
private let running: Set<String> = [me, menuBarAgentBundleID, "a.vis", "b.hid", "c.always", "d.unknown"]
private let layout = Layout(sections: ["b.hid": .hidden, "c.always": .alwaysHidden])

@Test func collapsedHidesHiddenAndAlwaysHidden() throws {
    let plan = try #require(ConcealmentPlanner.plan(layout: layout, state: .collapsed, runningBundleIDs: running, selfBundleID: me))
    #expect(plan.concealedBundleIDs == ["b.hid", "c.always"])
    #expect(plan.allowedBundleIDs.contains("a.vis"))
    #expect(plan.allowedBundleIDs.contains("d.unknown"), "une app inconnue est visible par défaut")
    #expect(plan.allowedBundleIDs.contains(me))
}

@Test func revealedKeepsAlwaysHiddenConcealed() throws {
    let plan = try #require(ConcealmentPlanner.plan(layout: layout, state: .revealed, runningBundleIDs: running, selfBundleID: me))
    #expect(plan.concealedBundleIDs == ["c.always"])
    #expect(plan.allowedBundleIDs.contains("b.hid"))
}

@Test func revealedAllNeedsNoAssertion() {
    #expect(ConcealmentPlanner.plan(layout: layout, state: .revealedAll, runningBundleIDs: running, selfBundleID: me) == nil)
}

@Test func nothingToHideNeedsNoAssertion() {
    #expect(ConcealmentPlanner.plan(layout: Layout(), state: .collapsed, runningBundleIDs: running, selfBundleID: me) == nil)
    // Une app masquée mais non lancée ne justifie pas d'assertion.
    #expect(ConcealmentPlanner.plan(layout: Layout(sections: ["z.off": .hidden]), state: .collapsed, runningBundleIDs: running, selfBundleID: me) == nil)
}

@Test func selfAndSystemAreNeverConcealed() throws {
    let hostile = Layout(sections: [me: .alwaysHidden, menuBarAgentBundleID: .alwaysHidden, "b.hid": .hidden])
    let plan = try #require(ConcealmentPlanner.plan(layout: hostile, state: .collapsed, runningBundleIDs: running, selfBundleID: me))
    #expect(plan.concealedBundleIDs == ["b.hid"])
    #expect(plan.allowedBundleIDs.contains(me))
}

@Test func assigningVisibleRemovesEntry() {
    var l = layout
    l.assign("b.hid", to: .visible)
    #expect(l.sections["b.hid"] == nil)
    #expect(l.section(for: "b.hid") == .visible)
}

@Test func layoutStoreRoundTripAndCorruptFile() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = LayoutStore(url: dir.appending(path: "layout.json"))
    #expect(store.load() == Layout())
    try store.save(layout)
    #expect(store.load() == layout)
    try Data("{oops".utf8).write(to: store.url)
    #expect(store.load() == Layout(), "fichier corrompu → layout vide, pas de crash")
    try? FileManager.default.removeItem(at: dir)
}

@Test func bridgesOnlySystemClicksUnderAssertion() {
    let clock = [SystemItem(identifier: "com.apple.menuextra.clock", frame: CGRect(x: 1382, y: 0, width: 110, height: 33))]
    #expect(ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 10), systemItems: clock, assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 10), systemItems: clock, assertionActive: false))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 500, y: 10), systemItems: clock, assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 300), systemItems: clock, assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: .zero, systemItems: [SystemItem(identifier: "x", frame: .zero)], assertionActive: true), "item sans cadre AX")
}

/// Relevé réel (17/11/2026, macOS 27.0.1). Sous assertion : son, Wi‑Fi, batterie, Control Center,
/// horloge. À la levée, Spotlight réapparaît et « À l'écoute » s'insère AVANT le Wi‑Fi (seulement
/// si un média a joué : bug intermittent) — Wi‑Fi et batterie glissent de −32 pt ET changent de rang.
private func item(_ name: String, _ x: CGFloat, _ w: CGFloat) -> SystemItem {
    SystemItem(identifier: "com.apple.menuextra.\(name)", frame: CGRect(x: x, y: 0, width: w, height: 33))
}
private let concealedBar = [item("sound", 1032, 22), item("wifi", 1252, 22), item("battery", 1290, 26), item("controlcenter", 1332, 26), item("clock", 1374, 118)]
private let liftedBar = [item("sound", 967, 22), item("now-playing", 1041, 17), item("wifi", 1220, 22), item("battery", 1258, 26), item("controlcenter", 1332, 26), item("clock", 1374, 118)]

@Test func pressesSystemItemsWithoutLiftingExceptTheClock() {
    let battery = ClickBridgeRule.target(click: CGPoint(x: 1300, y: 12), systemItems: concealedBar)
    #expect(battery?.identifier == "com.apple.menuextra.battery")
    #expect(battery.map(ClickBridgeRule.canPress) == true, "batterie : AXPress, pas de levée, la barre ne bouge pas")
    for name in ["wifi", "sound", "controlcenter"] { #expect(ClickBridgeRule.canPress(item(name, 0, 10))) }
    #expect(!ClickBridgeRule.canPress(item("clock", 1374, 118)), "l'horloge ignore AXPress")
    #expect(!ClickBridgeRule.canPress(SystemItem(identifier: nil, frame: CGRect(x: 0, y: 0, width: 10, height: 10))))
}

@Test func liftReplayFindsTheItemByIdentifierNotRank() {
    let click = CGPoint(x: 1300, y: 12)
    let battery = ClickBridgeRule.target(click: click, systemItems: concealedBar)!
    let index = concealedBar.firstIndex(of: battery)!
    #expect(liftedBar[index].identifier == "com.apple.menuextra.wifi", "par rang on viserait le Wi‑Fi")
    #expect(liftedBar.first { $0.frame.contains(click) }?.identifier != "com.apple.menuextra.battery", "aux coordonnées d'origine on raterait la batterie")
    let now = ClickBridgeRule.relocate(battery, in: liftedBar)
    #expect(now == CGRect(x: 1258, y: 0, width: 26, height: 33))
    let replay = ClickBridgeRule.replayPoint(click: click, from: battery.frame, to: now!)
    #expect(ClickBridgeRule.target(click: replay, systemItems: liftedBar)?.identifier == "com.apple.menuextra.battery")
    // Horloge : avant le correctif, le rang 4 désignait Control Center après la levée (−77 pt).
    let clock = ClickBridgeRule.target(click: CGPoint(x: 1420, y: 12), systemItems: concealedBar)!
    let clockNow = ClickBridgeRule.relocate(clock, in: liftedBar)!
    #expect(ClickBridgeRule.target(click: ClickBridgeRule.replayPoint(click: CGPoint(x: 1420, y: 12), from: clock.frame, to: clockNow), systemItems: liftedBar)?.identifier == "com.apple.menuextra.clock")
    #expect(ClickBridgeRule.relocate(SystemItem(identifier: nil, frame: battery.frame), in: liftedBar) == nil)
    #expect(ClickBridgeRule.relocate(item("gone", 0, 10), in: liftedBar) == nil)
    let edge = ClickBridgeRule.replayPoint(click: CGPoint(x: 1251.5, y: 12), from: concealedBar[1].frame, to: liftedBar[2].frame)
    #expect(liftedBar[2].frame.contains(edge), "clic dans la marge de 1 pt : ramené dans l'item")
    #expect(ClickBridgeRule.replayPoint(click: click, from: battery.frame, to: battery.frame) == click)
}

@Test func autoRehideWaitsForMenusAndPointer() {
    #expect(AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 5, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: true, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: true))
    #expect(!AutoRehideRule.shouldRehide(state: .revealedAll, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 99, delay: 0, menuOpen: false, pointerInMenuBar: false), "0 = désactivé")
}
