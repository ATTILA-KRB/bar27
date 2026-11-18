import CoreGraphics

/// Placement de l'assistant d'autorisation à côté de la fenêtre Réglages Système.
/// Coordonnées Cocoa (origine en bas à gauche), comme `NSScreen.visibleFrame`.
public enum GuidePlacement: Equatable, Sendable {
    case left, right, inside

    /// Côté gauche si la place suffit (la liste est à droite de la barre latérale : la flèche y
    /// pointe), sinon côté droit, sinon en bas, à l'intérieur de la fenêtre. Centré verticalement
    /// sur la fenêtre, toujours ramené dans l'écran.
    public static func frame(panel size: CGSize, beside window: CGRect, in screen: CGRect, gap: CGFloat = 12) -> (CGRect, GuidePlacement) {
        let placement: GuidePlacement
        var origin: CGPoint
        if window.minX - gap - size.width >= screen.minX {
            placement = .left
            origin = CGPoint(x: window.minX - gap - size.width, y: window.midY - size.height / 2)
        } else if window.maxX + gap + size.width <= screen.maxX {
            placement = .right
            origin = CGPoint(x: window.maxX + gap, y: window.midY - size.height / 2)
        } else {
            placement = .inside
            origin = CGPoint(x: window.midX - size.width / 2, y: window.minY + gap)
        }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return (CGRect(origin: origin, size: size), placement)
    }

    /// AX donne un cadre en origine haut-gauche (écran principal) ; Cocoa en bas-gauche.
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
