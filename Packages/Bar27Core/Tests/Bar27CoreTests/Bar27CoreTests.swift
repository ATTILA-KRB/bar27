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
    let clock = CGRect(x: 1382, y: 0, width: 110, height: 33)
    #expect(ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 10), systemItemFrames: [clock], assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 10), systemItemFrames: [clock], assertionActive: false))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 500, y: 10), systemItemFrames: [clock], assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 1400, y: 300), systemItemFrames: [clock], assertionActive: true))
    #expect(!ClickBridgeRule.shouldBridge(click: CGPoint(x: 0, y: 0), systemItemFrames: [.zero], assertionActive: true), "item sans cadre AX")
}

/// Relevé réel (17/11/2026) : Spotlight masqué par l'assertion ; à la levée il réapparaît et
/// Wi‑Fi (1252 → 1220) et batterie (1290 → 1258) glissent de 32 pt vers la gauche.
@Test func replaysOnTheSameItemAfterTheBarShifts() {
    let wifi = CGRect(x: 1252, y: 0, width: 22, height: 33), battery = CGRect(x: 1290, y: 0, width: 26, height: 33)
    let frames = [CGRect.zero, wifi, battery]
    let click = CGPoint(x: 1263, y: 12)
    let index = ClickBridgeRule.targetIndex(click: click, systemItemFrames: frames)
    #expect(index == 1)
    let wifiAfter = wifi.offsetBy(dx: -32, dy: 0), batteryAfter = battery.offsetBy(dx: -32, dy: 0)
    #expect(batteryAfter.contains(click), "rejouer aux coordonnées d'origine ouvrirait la batterie")
    let replay = ClickBridgeRule.replayPoint(click: click, from: wifi, to: wifiAfter)
    #expect(wifiAfter.contains(replay) && !batteryAfter.contains(replay))
    #expect(ClickBridgeRule.replayPoint(click: click, from: wifi, to: wifi) == click, "barre immobile : clic inchangé")
    #expect(ClickBridgeRule.replayPoint(click: click, from: wifi, to: .zero) == click, "cadre perdu : clic inchangé")
    let edge = ClickBridgeRule.replayPoint(click: CGPoint(x: 1251.5, y: 12), from: wifi, to: wifiAfter)
    #expect(wifiAfter.contains(edge), "clic dans la marge de 1 pt : ramené dans l'item")
}

@Test func autoRehideWaitsForMenusAndPointer() {
    #expect(AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 5, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: true, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: true))
    #expect(!AutoRehideRule.shouldRehide(state: .revealedAll, elapsed: 10, delay: 8, menuOpen: false, pointerInMenuBar: false))
    #expect(!AutoRehideRule.shouldRehide(state: .revealed, elapsed: 99, delay: 0, menuOpen: false, pointerInMenuBar: false), "0 = désactivé")
}
