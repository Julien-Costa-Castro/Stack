import AppKit
import SwiftUI

@MainActor
public final class StatusBarController {
    public static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private init() {}

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Use standard SF Symbol or layered stack icon
        if let image = NSImage(systemSymbolName: "square.3.layers.3d.down.right", accessibilityDescription: "Stack") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "▤"
        }

        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            // Left click toggles HUD
            HUDWindowController.shared.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Stack — Gestionnaire de presse-papiers", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Ouvrir Stack", action: #selector(openHUD), keyEquivalent: "V")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let captureItem = NSMenuItem(title: "📸 Capture Défilante (Site Web / Document)...", action: #selector(startScrollingCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.command, .option]
        captureItem.target = self
        menu.addItem(captureItem)

        let clearItem = NSMenuItem(title: "Vider l'historique", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let permItem = NSMenuItem(title: "Permissions Accessibilité...", action: #selector(openPermissions), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let countItem = NSMenuItem(title: "Éléments : \(HUDViewModel.shared.items.count) / 100", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter Stack", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // reset so single click toggles again
    }

    @objc private func openHUD() {
        HUDWindowController.shared.show()
    }

    @objc private func startScrollingCapture() {
        ScrollingCaptureController.shared.startSelection()
    }

    @objc private func clearHistory() {
        HUDViewModel.shared.clearAllHistory()
    }

    @objc private func openPermissions() {
        KeySimulator.revealInFinderForDragAndDrop()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
