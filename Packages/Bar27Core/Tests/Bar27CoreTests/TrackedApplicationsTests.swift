import Foundation
import Testing
@testable import Bar27Core

private func key(_ id: String) -> [String: Any] { ["bundle": ["_0": id]] }
private func value(_ id: String, _ allowed: Bool) -> [String: Any] { ["location": key(id), "menuItemLocations": [key(id)], "isAllowed": allowed] }
nonisolated(unsafe) private let adhoc: [String: Any] = ["adhocBinary": ["_0": ["relative": "file:///tmp/x"]]]
nonisolated(unsafe) private let sample: [Any] = [key("a"), value("a", true), adhoc, ["isAllowed": true], key("b"), value("b", false), key("c"), value("c", true)]

@Test func readsStatesIgnoringNonBundleKeys() {
    #expect(TrackedApplications.allowedStates(in: sample) == ["a": true, "b": false, "c": true])
}

@Test func togglesOnlyIsAllowedAndKeepsTheRest() throws {
    let (result, changed) = TrackedApplications.settingAllowed(false, for: ["a", "b", "zz"], in: sample)
    #expect(changed == ["a"], "b déjà éteint, zz absent")
    #expect(TrackedApplications.allowedStates(in: result) == ["a": false, "b": false, "c": true])
    #expect(result.count == sample.count)
    let a = try #require(result[1] as? [String: Any])
    #expect(a["menuItemLocations"] != nil && a["location"] != nil)
    #expect((result[3] as? [String: Any])?["isAllowed"] as? Bool == true, "entrée adhoc intacte")
}

@Test func roundTripsBinaryPlist() throws {
    let data = try TrackedApplications.encode(sample)
    let back = try #require(TrackedApplications.decode(data))
    #expect(TrackedApplications.allowedStates(in: back) == TrackedApplications.allowedStates(in: sample))
}

@Test func resolvesHelperToContainingTrackedApp() {
    let states = ["com.google.GeminiMacOS": true, "a": false]
    #expect(TrackedApplications.trackedKey(for: "a", states: states, containers: ["com.google.GeminiMacOS"]) == "a", "suivie elle-même")
    #expect(TrackedApplications.trackedKey(for: "com.google.GeminiMacOS.launcher", states: states, containers: ["com.google.GeminiMacOS"]) == "com.google.GeminiMacOS")
    #expect(TrackedApplications.trackedKey(for: "com.apple.campo", states: states, containers: []) == nil, "élément système non suivi")
}

@Test func planNeverTouchesUserChoices() {
    // b a été éteint par l'utilisateur (non enregistré) : jamais rallumé.
    let plan = NativeTogglePlan.make(concealed: ["a", "new"], states: ["a": true, "b": false, "c": false], recorded: ["c"])
    #expect(plan.toDisallow == ["a"])
    #expect(plan.toAllow == ["c"], "c éteint par Bar27 et plus masqué → rallumé")
    #expect(plan.untracked == ["new"])
}
