import AppKit

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

class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let layoutStorage: LayoutStorage
    private let windowManager: WindowManager
    private let loginItemManager: LoginItemManager

    private var restoreSubmenu: NSMenu!
    private var loginItem: NSMenuItem!

    init(layoutStorage: LayoutStorage, windowManager: WindowManager, loginItemManager: LoginItemManager) {
        self.layoutStorage = layoutStorage
        self.windowManager = windowManager
        self.loginItemManager = loginItemManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Recall")
            button.image?.isTemplate = true
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Restore submenu
        let restoreItem = NSMenuItem(title: "Restore", action: nil, keyEquivalent: "")
        restoreSubmenu = NSMenu()
        restoreItem.submenu = restoreSubmenu
        menu.addItem(restoreItem)

        // Save current layout
        let saveItem = NSMenuItem(
            title: "Save Current Layout...",
            action: #selector(saveLayoutClicked),
            keyEquivalent: "s"
        )
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(NSMenuItem.separator())

        // Start at Login
        loginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Recall",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu

        refreshLayoutsMenu()
    }

    private func refreshLayoutsMenu() {
        debugLog("refreshLayoutsMenu called")
        restoreSubmenu.removeAllItems()

        let layouts = layoutStorage.loadAll()
        debugLog("Loaded \(layouts.count) layouts")

        if layouts.isEmpty {
            let emptyItem = NSMenuItem(title: "No saved layouts", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            restoreSubmenu.addItem(emptyItem)
        } else {
            for layout in layouts {
                debugLog("Adding menu item for: \(layout.name)")
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(restoreLayoutClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = layout
                restoreSubmenu.addItem(item)
            }

            restoreSubmenu.addItem(NSMenuItem.separator())

            // Delete submenu
            let deleteItem = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
            let deleteSubmenu = NSMenu()

            for layout in layouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(deleteLayoutClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = layout
                deleteSubmenu.addItem(item)
            }

            deleteItem.submenu = deleteSubmenu
            restoreSubmenu.addItem(deleteItem)

            // Edit submenu
            let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let editSubmenu = NSMenu()

            for layout in layouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(editLayoutClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = layout
                editSubmenu.addItem(item)
            }

            editItem.submenu = editSubmenu
            restoreSubmenu.addItem(editItem)
        }
    }

    private func updateLoginItemState() {
        loginItem.state = loginItemManager.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func saveLayoutClicked() {
        // Don't pre-check AXIsProcessTrusted - it's unreliable with ad-hoc signing
        // Instead, try to capture and handle failure gracefully

        // Prompt for layout name
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "Enter a name for this layout:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = ""
        textField.placeholderString = "Layout name"
        alert.accessoryView = textField

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else {
            showAlert(title: "Invalid Name", message: "Please enter a name for the layout.")
            return
        }

        // Check if layout with this name already exists
        if layoutStorage.exists(name) {
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "Layout Exists"
            confirmAlert.informativeText = "A layout named \"\(name)\" already exists. Do you want to replace it?"
            confirmAlert.addButton(withTitle: "Replace")
            confirmAlert.addButton(withTitle: "Cancel")

            if confirmAlert.runModal() != .alertFirstButtonReturn {
                return
            }
        }

        // Capture and save
        guard let layout = windowManager.captureLayout(name: name) else {
            // Request permission prompt if capture failed (likely permission issue)
            windowManager.requestAccessibilityPermission()
            showAlert(
                title: "Capture Failed",
                message: "Failed to capture window layout. Please ensure Recall has Accessibility permission in System Settings > Privacy & Security > Accessibility."
            )
            return
        }

        do {
            try layoutStorage.save(layout)
            refreshLayoutsMenu()
        } catch {
            showAlert(title: "Save Failed", message: "Failed to save the layout: \(error.localizedDescription)")
        }
    }

    @objc private func restoreLayoutClicked(_ sender: NSMenuItem) {
        debugLog("restoreLayoutClicked called")

        guard let layout = sender.representedObject as? Layout else {
            debugLog("ERROR: No layout in representedObject")
            return
        }

        debugLog("Restoring layout: \(layout.name)")
        debugLog("Calling windowManager.restoreLayout")

        windowManager.restoreLayout(layout) { restored, total in
            debugLog("Restore callback: \(restored)/\(total)")
            if total == 0 {
                self.showAlert(
                    title: "Accessibility Permission Required",
                    message: "Recall needs accessibility permission. Please grant access in System Settings > Privacy & Security > Accessibility."
                )
            } else if restored < total {
                self.showAlert(
                    title: "Restore Complete",
                    message: "Restored \(restored) of \(total) windows. Some windows could not be restored."
                )
            }
        }
    }

    @objc private func deleteLayoutClicked(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? Layout else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Layout"
        alert.informativeText = "Are you sure you want to delete \"\(layout.name)\"?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try layoutStorage.delete(layout)
            refreshLayoutsMenu()
        } catch {
            showAlert(title: "Delete Failed", message: "Failed to delete the layout: \(error.localizedDescription)")
        }
    }

    @objc private func editLayoutClicked(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? Layout else { return }

        let url = layoutStorage.url(for: layout)
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemManager.toggle()
            updateLoginItemState()
        } catch {
            showAlert(title: "Error", message: "Failed to update login item: \(error.localizedDescription)")
        }
    }

    @objc private func quitClicked() {
        debugLog("quitClicked called")
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        debugLog("menuWillOpen called")
        refreshLayoutsMenu()
        updateLoginItemState()
    }
}
