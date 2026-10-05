import AppKit
import SwiftUI

@MainActor
public final class HUDWindowController {
    public static let shared = HUDWindowController()

    private var panel: FloatingPanel?
    private var globalClickMonitor: Any?
    private var isVisible: Bool = false

    private init() {
        setupPanel()
        setupBindings()
    }

    private func setupPanel() {
        let defaultWidth: CGFloat = 1000
        let defaultHeight: CGFloat = 370
        let contentRect = NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight)

        let floatingPanel = FloatingPanel(contentRect: contentRect)
        let hudView = HUDView(viewModel: HUDViewModel.shared)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 26
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        floatingPanel.contentView = hostingView
        floatingPanel.invalidateShadow()
        self.panel = floatingPanel

        // Keyboard callbacks from FloatingPanel.sendEvent
        floatingPanel.onEscapePressed = { [weak self] in
            self?.hide()
        }
        floatingPanel.onLeftArrowPressed = {
            HUDViewModel.shared.selectPrevious()
        }
        floatingPanel.onRightArrowPressed = {
            HUDViewModel.shared.selectNext()
        }
        floatingPanel.onReturnPressed = {
            HUDViewModel.shared.pasteSelected()
        }
        floatingPanel.onDeletePressed = {
            let filtered = HUDViewModel.shared.filteredItems
            let index = HUDViewModel.shared.selectedIndex
            if index >= 0 && index < filtered.count {
                HUDViewModel.shared.deleteItem(filtered[index])
            }
        }
        floatingPanel.onNumberPressed = { index in
            HUDViewModel.shared.pasteAtIndex(index)
        }
    }

    private func setupBindings() {
        HUDViewModel.shared.onDismissRequested = { [weak self] in
            self?.dismissImmediately()
        }
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        guard let panel = panel else { return }

        // 1. Immediately poll pasteboard & screenshot directories before showing window
        ClipboardWatcher.shared.checkForChangesNow()
        ScreenshotWatcher.shared.scanDirectories()

        // 2. Record frontmost application before Stack takes focus
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let frontApp = frontApp, frontApp.processIdentifier != NSRunningApplication.current.processIdentifier {
            HUDViewModel.shared.setPreviousApplication(frontApp)
        }

        // 3. Reset selection to top (latest) item
        HUDViewModel.shared.selectedIndex = 0

        // 4. Refresh permission status
        HUDViewModel.shared.refreshAccessibilityPermission()

        // 3. Position window at bottom of active screen
        positionAtBottom(panel: panel)

        // 4. Present panel
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        isVisible = true

        // 5. Setup outside-click monitor
        startGlobalClickMonitor()
    }

    public func hide() {
        guard isVisible, let panel = panel else { return }

        stopGlobalClickMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.isVisible = false
            }
        })
    }

    /// Immediate dismiss when pasting to prevent focus delay
    public func dismissImmediately() {
        guard let panel = panel else { return }

        stopGlobalClickMonitor()
        panel.orderOut(nil)
        panel.alphaValue = 0.0
        self.isVisible = false

        // Yield focus back to previous active application
        NSApp.hide(nil)
    }

    private func positionAtBottom(panel: FloatingPanel) {
        // Find screen with cursor, or main screen
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]

        let screenFrame = targetScreen.visibleFrame
        let targetWidth = min(1140, screenFrame.width - 48)
        let targetHeight: CGFloat = 370

        let posX = screenFrame.origin.x + (screenFrame.width - targetWidth) / 2
        let posY = screenFrame.origin.y + 24 // 24px above dock or screen bottom

        panel.setFrame(NSRect(x: posX, y: posY, width: targetWidth, height: targetHeight), display: true)
        panel.invalidateShadow()
    }

    private func startGlobalClickMonitor() {
        stopGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, self.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                MainActor.assumeIsolated {
                    self.hide()
                }
            }
        }
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}
