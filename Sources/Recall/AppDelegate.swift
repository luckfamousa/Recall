import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private let layoutStorage = LayoutStorage()
    private let windowManager = WindowManager()
    private let loginItemManager = LoginItemManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (backup - Info.plist should handle this)
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(
            layoutStorage: layoutStorage,
            windowManager: windowManager,
            loginItemManager: loginItemManager
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }
}
