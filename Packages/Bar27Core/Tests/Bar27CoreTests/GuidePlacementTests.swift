import CoreGraphics
import Testing
@testable import Bar27Core

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
private let panel = CGSize(width: 260, height: 200)

/// Fenêtre Réglages mesurée sur macOS 27.0.1 (AX : x 515, y 33, 885 × 913).
@Test func axFrameConvertsToCocoa() {
    let cocoa = GuidePlacement.cocoaRect(fromAX: CGRect(x: 515, y: 33, width: 885, height: 913), primaryScreenHeight: 982)
    #expect(cocoa == CGRect(x: 515, y: 36, width: 885, height: 913))
}

@Test func prefersLeftOfSettings() {
    let window = CGRect(x: 515, y: 36, width: 885, height: 913)
    let (frame, side) = GuidePlacement.frame(panel: panel, beside: window, in: screen)
    #expect(side == .left)
    #expect(frame.maxX == 503)
    #expect(frame.midY == window.midY)
}

@Test func fallsBackRightThenInside() {
    let right = GuidePlacement.frame(panel: panel, beside: CGRect(x: 100, y: 100, width: 800, height: 600), in: screen)
    #expect(right.1 == .right)
    #expect(right.0.minX == 912)
    let inside = GuidePlacement.frame(panel: panel, beside: CGRect(x: 100, y: 100, width: 1300, height: 600), in: screen)
    #expect(inside.1 == .inside)
    #expect(inside.0.minY == 112)
    #expect(inside.0.midX == 750)
}

@Test func staysOnScreen() {
    let (frame, _) = GuidePlacement.frame(panel: panel, beside: CGRect(x: 400, y: -50, width: 800, height: 120), in: screen)
    #expect(frame.minY == 0)
    #expect(screen.contains(frame))
}
