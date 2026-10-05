import AppKit
import Carbon

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce background accessory mode (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // 1. Setup Status Bar Menu item
        StatusBarController.shared.setup()

        // 2. Start Clipboard Watcher (250ms polling)
        ClipboardWatcher.shared.startMonitoring(interval: 0.25)

        // 3. Register Global Hotkeys (Cmd + Shift + V & Cmd + Option + S)
        GlobalHotKeyManager.shared.registerAll()
        GlobalHotKeyManager.shared.onHUDHotKeyPressed = {
            HUDWindowController.shared.toggle()
        }
        GlobalHotKeyManager.shared.onScrollingCaptureHotKeyPressed = {
            ScrollingCaptureController.shared.startSelection()
        }

        // 4. Start Screenshot Watcher (monitors ~/Documents, Desktop, etc.)
        ScreenshotWatcher.shared.startMonitoring(interval: 1.0)
        ScreenshotWatcher.shared.onScreenshotCaptured = { item in
            HUDViewModel.shared.handleNewItem(item)
        }

        // 5. Prompt for Accessibility if not yet trusted
        if !KeySimulator.isAccessibilityEnabled() {
            KeySimulator.promptAccessibilityPermission()
        }

        print("[Stack] Started successfully. Hotkey: ⌘⇧V registered.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardWatcher.shared.stopMonitoring()
        ScreenshotWatcher.shared.stopMonitoring()
        GlobalHotKeyManager.shared.unregister()
    }
}
