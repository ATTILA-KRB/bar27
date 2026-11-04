import Carbon.HIToolbox
import OSLog

/// Raccourci global via Carbon (aucune permission requise). Défaut : ⌃⌥⌘B.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32 = UInt32(kVK_ANSI_B), modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey), action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated {
                Logger(category: "HotKey").info("Raccourci pressé")
                hotKey.action()
            }
            return noErr
        }, 1, &spec, me, &handler)
        let registered = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4232_3721), id: 1), GetApplicationEventTarget(), 0, &ref)
        Logger(category: "HotKey").info("Raccourci : handler=\(installed) register=\(registered)")
    }

    func invalidate() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
