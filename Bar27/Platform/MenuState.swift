import AppKit

/// Indices pour le re-masquage automatique (CGWindowList décrit encore les fenêtres sur 27).
enum MenuState {
    /// Un menu (niveau popUpMenu) est à l'écran : ne pas remasquer sous l'utilisateur.
    static var isMenuOpen: Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }

    /// Fenêtres au niveau des menus (diagnostic).
    static var menuLevelWindowOwners: [String] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.filter { ($0[kCGWindowLayer as String] as? Int) == menuLevel }.compactMap { $0[kCGWindowOwnerName as String] as? String }
    }

    static var isPointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        return point.y >= screen.visibleFrame.maxY
    }
}
