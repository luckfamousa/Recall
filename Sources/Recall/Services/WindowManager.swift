import AppKit
import ApplicationServices

private func debugLog(_ message: String) {
    let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("recall_debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

class WindowManager {

    // MARK: - Accessibility Check

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Display Utilities

    private func displayUUID(for screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func screen(for displayUUID: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            self.displayUUID(for: screen) == displayUUID
        }
    }

    private func screenContaining(axPoint: CGPoint) -> NSScreen? {
        // Convert from AX coordinates (top-left origin, Y down) to NSScreen coordinates (bottom-left origin, Y up)
        // The main screen's height is the reference for conversion
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let mainScreenHeight = mainScreen.frame.height + mainScreen.frame.origin.y

        let screenPoint = CGPoint(
            x: axPoint.x,
            y: mainScreenHeight - axPoint.y
        )

        debugLog("AX point: (\(axPoint.x), \(axPoint.y)) -> Screen point: (\(screenPoint.x), \(screenPoint.y))")

        for screen in NSScreen.screens {
            debugLog("  Screen frame: \(screen.frame)")
            if screen.frame.contains(screenPoint) {
                debugLog("  -> Found in screen: \(displayUUID(for: screen) ?? "unknown")")
                return screen
            }
        }

        debugLog("  -> No screen found, using main")
        return NSScreen.main
    }

    // MARK: - Capture Layout

    func captureLayout(name: String) -> Layout? {
        // Don't pre-check AXIsProcessTrusted - it's unreliable with ad-hoc signing
        // Just try to capture and handle failures gracefully

        var displaySnapshots: [String: [WindowSnapshot]] = [:]

        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isHidden
        }

        // If there are running apps but we capture zero windows, it's likely a permission issue
        let hasRunningApps = !apps.isEmpty

        // Track window indices per app
        var appWindowIndices: [String: Int] = [:]

        for app in apps {
            guard let bundleId = app.bundleIdentifier else { continue }

            let windows = getWindows(for: app.processIdentifier)
            for (title, frame) in windows {
                // Determine which display this window is on
                let centerPoint = CGPoint(
                    x: frame.origin.x + frame.size.width / 2,
                    y: frame.origin.y + frame.size.height / 2
                )

                guard let screen = screenContaining(axPoint: centerPoint),
                      let uuid = displayUUID(for: screen) else {
                    continue
                }

                // Get and increment window index for this app
                let windowIndex = appWindowIndices[bundleId, default: 0]
                appWindowIndices[bundleId] = windowIndex + 1

                let snapshot = WindowSnapshot(
                    bundleId: bundleId,
                    windowTitle: title,
                    windowIndex: windowIndex,
                    frame: WindowFrame(origin: frame.origin, size: frame.size)
                )

                displaySnapshots[uuid, default: []].append(snapshot)
            }
        }

        let displays = displaySnapshots.map { uuid, windows in
            DisplaySnapshot(displayUUID: uuid, windows: windows)
        }

        let totalWindows = displays.reduce(0) { $0 + $1.windows.count }

        // If we have running apps but captured zero windows, it's likely a permission issue
        if hasRunningApps && totalWindows == 0 {
            debugLog("captureLayout: No windows captured despite \(apps.count) running apps - likely permission issue")
            return nil
        }

        return Layout(name: name, displays: displays)
    }

    private func getWindows(for pid: pid_t) -> [(title: String, frame: CGRect)] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        var result: [(String, CGRect)] = []

        for window in windows {
            // Skip minimized windows
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized {
                continue
            }

            // Get window role - only capture standard windows
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role != kAXWindowRole as String {
                continue
            }

            // Get subrole to filter out dialogs, sheets, etc.
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String {
                let ignoredSubroles = [
                    kAXDialogSubrole as String,
                    kAXSystemDialogSubrole as String,
                    kAXFloatingWindowSubrole as String
                ]
                if ignoredSubroles.contains(subrole) {
                    continue
                }
            }

            guard let title = getWindowTitle(window),
                  let frame = getWindowFrame(window) else {
                continue
            }

            result.append((title, frame))
        }

        return result
    }

    private func getWindowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String ?? ""
    }

    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    // MARK: - Restore Layout

    func restoreLayout(_ layout: Layout, completion: @escaping (Int, Int) -> Void) {
        debugLog("restoreLayout called for: \(layout.name)")

        // Don't check AXIsProcessTrusted - it's unreliable with ad-hoc signing
        // Just try to restore and handle failures gracefully
        debugLog("Starting restore on background thread...")

        DispatchQueue.global(qos: .userInitiated).async {
            var totalWindows = 0
            var restoredWindows = 0

            debugLog("Processing \(layout.displays.count) displays")

            for display in layout.displays {
                totalWindows += display.windows.count
                debugLog("Display \(display.displayUUID): \(display.windows.count) windows")

                for windowSnapshot in display.windows {
                    if self.restoreWindow(windowSnapshot, displayUUID: display.displayUUID) {
                        restoredWindows += 1
                    }
                }
            }

            debugLog("Restore complete: \(restoredWindows)/\(totalWindows)")

            DispatchQueue.main.async {
                completion(restoredWindows, totalWindows)
            }
        }
    }

    private func restoreWindow(_ snapshot: WindowSnapshot, displayUUID: String) -> Bool {
        debugLog("Restoring window: \(snapshot.bundleId) - \(snapshot.windowTitle)")

        // Ensure app is running
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == snapshot.bundleId
        }

        if runningApps.isEmpty {
            debugLog("App not running, launching: \(snapshot.bundleId)")
            // Launch the app
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false

            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: snapshot.bundleId) else {
                debugLog("Could not find app URL for: \(snapshot.bundleId)")
                return false
            }

            let semaphore = DispatchSemaphore(value: 0)
            var launchSucceeded = false

            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                launchSucceeded = (error == nil && app != nil)
                if let error = error {
                    debugLog("Launch error: \(error.localizedDescription)")
                }
                semaphore.signal()
            }

            semaphore.wait()

            if !launchSucceeded {
                debugLog("Launch failed for: \(snapshot.bundleId)")
                return false
            }

            // Wait for app to initialize
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            debugLog("App already running: \(snapshot.bundleId)")
        }

        // Get the app's PID
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == snapshot.bundleId
        }) else {
            debugLog("Could not find running app: \(snapshot.bundleId)")
            return false
        }

        let pid = app.processIdentifier
        debugLog("App PID: \(pid)")

        // Find all windows for this app
        var allWindows = getAllWindows(pid: pid)
        debugLog("Found \(allWindows.count) windows for \(snapshot.bundleId)")

        // If app is running but has no windows, activate it to open a new window
        if allWindows.isEmpty {
            debugLog("App running but no windows - activating to open new window")

            // First try activating the app
            app.activate(options: [.activateIgnoringOtherApps])
            Thread.sleep(forTimeInterval: 0.5)

            // Check for windows again
            allWindows = getAllWindows(pid: pid)
            debugLog("After activation: \(allWindows.count) windows")

            // If still no windows, try using AppleScript to open a new window
            if allWindows.isEmpty {
                debugLog("Activation didn't create window, trying AppleScript")
                openNewWindowViaAppleScript(bundleId: snapshot.bundleId)
                Thread.sleep(forTimeInterval: 0.5)
                allWindows = getAllWindows(pid: pid)
                debugLog("After AppleScript: \(allWindows.count) windows")
            }
        }

        for (title, _) in allWindows {
            debugLog("  Window: \(title)")
        }

        // Try to find best matching window using multiple strategies
        let targetWindow = findBestMatchingWindow(
            windows: allWindows,
            snapshot: snapshot
        )

        guard let window = targetWindow else {
            debugLog("No window found for: \(snapshot.bundleId)")
            return false
        }

        // Move and resize to saved position
        debugLog("Setting frame to: (\(snapshot.frame.x), \(snapshot.frame.y), \(snapshot.frame.width), \(snapshot.frame.height))")
        let result = setWindowFrame(window, frame: snapshot.frame.cgRect)
        debugLog("setWindowFrame result: \(result)")
        return result
    }

    private func getAllWindows(pid: pid_t) -> [(title: String, window: AXUIElement)] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        if result != .success {
            debugLog("AXUIElementCopyAttributeValue failed with error: \(result.rawValue)")
            // -25211 = kAXErrorAPIDisabled (accessibility not enabled)
            // -25212 = kAXErrorNotImplemented
            // -25204 = kAXErrorCannotComplete
            if result.rawValue == -25211 {
                debugLog("ERROR: Accessibility API is disabled - need permission")
            }
            return []
        }

        guard let windows = windowsRef as? [AXUIElement] else {
            debugLog("Could not cast windows to [AXUIElement]")
            return []
        }

        return windows.compactMap { window -> (String, AXUIElement)? in
            guard let title = getWindowTitle(window) else { return nil }
            return (title, window)
        }
    }

    /// Find the best matching window using multiple strategies
    private func findBestMatchingWindow(
        windows: [(title: String, window: AXUIElement)],
        snapshot: WindowSnapshot
    ) -> AXUIElement? {
        guard !windows.isEmpty else { return nil }

        // Strategy 1: Exact title match
        if let match = windows.first(where: { $0.title == snapshot.windowTitle }) {
            debugLog("Match strategy: exact title")
            return match.window
        }

        // Strategy 2: Stable title match (handles dynamic suffixes)
        let savedStable = snapshot.stableTitle
        if let match = windows.first(where: {
            WindowSnapshot.extractStableTitle(from: $0.title) == savedStable
        }) {
            debugLog("Match strategy: stable title '\(savedStable)'")
            return match.window
        }

        // Strategy 3: Stable title contains match (more lenient)
        if !savedStable.isEmpty {
            if let match = windows.first(where: {
                let currentStable = WindowSnapshot.extractStableTitle(from: $0.title)
                return currentStable.contains(savedStable) || savedStable.contains(currentStable)
            }) {
                debugLog("Match strategy: stable title partial")
                return match.window
            }
        }

        // Strategy 4: Window index fallback (same position in window list)
        if snapshot.windowIndex < windows.count {
            debugLog("Match strategy: window index \(snapshot.windowIndex)")
            return windows[snapshot.windowIndex].window
        }

        // Strategy 5: First available window
        debugLog("Match strategy: first available")
        return windows.first?.window
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) -> Bool {
        let beforeFrame = getWindowFrame(window)
        debugLog("BEFORE: \(beforeFrame?.origin.x ?? -1), \(beforeFrame?.origin.y ?? -1)")
        debugLog("TARGET: \(frame.origin.x), \(frame.origin.y)")

        var position = frame.origin
        var size = frame.size

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        // Try setting position
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        debugLog("Position result: \(positionResult) (raw: \(positionResult.rawValue))")

        // Try setting size
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        debugLog("Size result: \(sizeResult) (raw: \(sizeResult.rawValue))")

        // Wait and verify
        Thread.sleep(forTimeInterval: 0.1)
        let afterFrame = getWindowFrame(window)
        debugLog("AFTER:  \(afterFrame?.origin.x ?? -1), \(afterFrame?.origin.y ?? -1)")

        // Check if position actually changed
        if let before = beforeFrame, let after = afterFrame {
            let moved = (before.origin.x != after.origin.x || before.origin.y != after.origin.y)
            debugLog("Window actually moved: \(moved)")
        }

        return positionResult == .success && sizeResult == .success
    }

    // Alternative: Use AppleScript for window manipulation (more stable authorization)
    private func setWindowFrameViaAppleScript(bundleId: String, windowTitle: String, frame: CGRect) -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(bundleId)"
                set frontmost to true
                repeat with w in windows
                    if name of w contains "\(windowTitle)" then
                        set position of w to {\(Int(frame.origin.x)), \(Int(frame.origin.y))}
                        set size of w to {\(Int(frame.size.width)), \(Int(frame.size.height))}
                        return true
                    end if
                end repeat
            end tell
        end tell
        return false
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        return error == nil
    }

    /// Open a new window for an app that's running but has no visible windows
    private func openNewWindowViaAppleScript(bundleId: String) {
        // Get app name from bundle ID
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            debugLog("Could not find app URL for AppleScript: \(bundleId)")
            return
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        debugLog("Opening new window via AppleScript for: \(appName)")

        // Try to activate and open a new window
        let script = """
        tell application "\(appName)"
            activate
            try
                make new document
            end try
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            debugLog("AppleScript error: \(error)")
        }
    }
}
