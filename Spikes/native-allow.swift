// Spike E — interrupteur natif « Autoriser dans la barre des menus » (trackedApplications).
// Usage : swift native-allow.swift list | off <bundleID> | on <bundleID>
import Foundation
typealias Copy = @convention(c) (CFString, CFString, CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
typealias SetV = @convention(c) (CFString, CFPropertyList?, CFString, CFString, CFString, CFString) -> Void
typealias Sync = @convention(c) (CFString, CFString, CFString, CFString) -> Bool
let h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW)
let copy = unsafeBitCast(dlsym(h, "_CFPreferencesCopyValueWithContainer")!, to: Copy.self)
let setv = unsafeBitCast(dlsym(h, "_CFPreferencesSetValueWithContainer")!, to: SetV.self)
let sync = unsafeBitCast(dlsym(h, "_CFPreferencesSynchronizeWithContainer")!, to: Sync.self)
let key = "trackedApplications" as CFString, app = "group.com.apple.controlcenter" as CFString
let container = (NSHomeDirectory() + "/Library/Group Containers/group.com.apple.controlcenter") as CFString
guard let raw = copy(key, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)?.takeRetainedValue() as? Data,
      var arr = try PropertyListSerialization.propertyList(from: raw, format: nil) as? [Any] else { print("ILLISIBLE"); exit(1) }
func bid(_ k: Any) -> String? { ((k as? [String: Any])?["bundle"] as? [String: Any])?["_0"] as? String }
let args = CommandLine.arguments
if args.count < 3 {
    for i in stride(from: 0, to: arr.count - 1, by: 2) { print(bid(arr[i]) ?? "(non-bundle)", ((arr[i+1] as? [String: Any])?["isAllowed"] as? Bool).map { "\($0)" } ?? "-") }
    exit(0)
}
let allowed = args[1] == "on"
var changed = false
for i in stride(from: 0, to: arr.count - 1, by: 2) where bid(arr[i]) == args[2] {
    var v = arr[i+1] as! [String: Any]; v["isAllowed"] = allowed; arr[i+1] = v; changed = true
}
guard changed else { print("NON SUIVI"); exit(2) }
let data = try PropertyListSerialization.data(fromPropertyList: arr, format: .binary, options: 0)
setv(key, data as CFData, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
print(sync(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container) ? "OK \(args[1]) \(args[2])" : "SYNC KO")
