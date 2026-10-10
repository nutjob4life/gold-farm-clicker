import AppKit
import CoreGraphics
import Darwin
import Foundation

struct MinecraftWindow {
    let pid: pid_t
    let bounds: CGRect
}

enum MinecraftTarget {
    /// Finds the Minecraft game window.
    ///
    /// Official Java Edition runs as a `java` process whose window title is often
    /// unavailable to other apps (macOS blanks `kCGWindowName` without Screen
    /// Recording). So we match by owner title / executable path, not window name.
    static func findMinecraftWindow() -> MinecraftWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var best: (window: MinecraftWindow, area: CGFloat)?

        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width >= 200,
                  height >= 200
            else {
                continue
            }

            let windowName = info[kCGWindowName as String] as? String ?? ""
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""

            guard isMinecraftWindow(windowName: windowName, ownerName: ownerName, pid: pid) else {
                continue
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)
            let area = width * height
            let candidate = MinecraftWindow(pid: pid, bounds: bounds)

            if best == nil || area > best!.area {
                best = (candidate, area)
            }
        }

        return best?.window
    }

    /// Activates the Minecraft process so it becomes frontmost.
    /// Returns `true` if activation was attempted successfully.
    @discardableResult
    static func activate(pid: pid_t) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }

        let wasActive = app.isActive
        let activated = app.activate()

        if !wasActive {
            // Give the window a moment to settle before posting input.
            try? await Task.sleep(for: .milliseconds(300))
        }

        return activated
    }

    /// Center point of the window in Quartz (top-left origin) coordinates,
    /// which matches what `CGEvent` mouse APIs expect.
    static func centerPoint(of window: MinecraftWindow) -> CGPoint {
        CGPoint(x: window.bounds.midX, y: window.bounds.midY)
    }

    // MARK: - Matching

    private static func isMinecraftWindow(windowName: String, ownerName: String, pid: pid_t) -> Bool {
        if windowName.localizedCaseInsensitiveContains("Minecraft") {
            return true
        }

        if ownerName.localizedCaseInsensitiveContains("Minecraft") {
            return true
        }

        // Java Edition: owner is typically "java"; confirm via executable path.
        if ownerName.caseInsensitiveCompare("java") == .orderedSame {
            return executablePathLooksLikeMinecraft(pid: pid)
        }

        return false
    }

    private static func executablePathLooksLikeMinecraft(pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return false }

        let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self).lowercased()
        // Official launcher: .../Application Support/minecraft/runtime/.../java
        // Also covers common third-party layouts that keep "minecraft" in the path.
        return path.contains("/minecraft/") || path.contains("minecraft.app")
    }
}
