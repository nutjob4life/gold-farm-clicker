import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum InputSender {
    private static let keyHoldNanoseconds: UInt64 = 40_000_000

    /// Virtual key codes for hotbar slots 1–9 (ANSI digit keys).
    private static let hotbarKeyCodes: [CGKeyCode] = [
        CGKeyCode(kVK_ANSI_1),
        CGKeyCode(kVK_ANSI_2),
        CGKeyCode(kVK_ANSI_3),
        CGKeyCode(kVK_ANSI_4),
        CGKeyCode(kVK_ANSI_5),
        CGKeyCode(kVK_ANSI_6),
        CGKeyCode(kVK_ANSI_7),
        CGKeyCode(kVK_ANSI_8),
        CGKeyCode(kVK_ANSI_9),
    ]

    static func leftClick(at point: CGPoint) {
        postMouse(type: .leftMouseDown, point: point, button: .left)
        postMouse(type: .leftMouseUp, point: point, button: .left)
    }

    static func rightMouseDown(at point: CGPoint) {
        postMouse(type: .rightMouseDown, point: point, button: .right)
    }

    static func rightMouseUp(at point: CGPoint) {
        postMouse(type: .rightMouseUp, point: point, button: .right)
    }

    /// Presses hotbar key for slot `1...9`.
    static func pressHotbarSlot(_ slot: Int) async {
        let index = min(9, max(1, slot)) - 1
        await pressKey(keyCode: hotbarKeyCodes[index])
    }

    // MARK: - Private

    private static func postMouse(type: CGEventType, point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private static func pressKey(keyCode: CGKeyCode) async {
        postKey(keyCode: keyCode, keyDown: true)
        try? await Task.sleep(nanoseconds: keyHoldNanoseconds)
        postKey(keyCode: keyCode, keyDown: false)
    }

    private static func postKey(keyCode: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
