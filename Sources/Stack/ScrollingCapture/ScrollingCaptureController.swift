import AppKit
import CoreGraphics
import Foundation
import AudioToolbox

@MainActor
public final class ScrollingCaptureController: NSObject {
    public static let shared = ScrollingCaptureController()

    private var overlayWindow: SelectionOverlayWindow?
    private var hudWindow: ScrollHUDWindow?
    private var outlineWindow: ScrollOutlineWindow?

    private var captureTimer: Timer?
    private var keyMonitor: Any?

    private var stitcher: ImageStitcher?
    private var captureRect: CGRect = .zero
    private var scaleFactor: CGFloat = 2.0

    private override init() {
        super.init()
    }

    /// Entry point: starts the screen area selection process
    public func startSelection() {
        // 1. Check Screen Recording permission
        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                showPermissionAlert()
                return
            }
        }

        // 2. Hide Stack HUD if currently visible
        HUDWindowController.shared.hide()

        // 3. Cancel any ongoing capture
        cancelCapture()

        // 4. Create and present selection overlay on active screen
        let activeScreen = NSScreen.main ?? NSScreen.screens.first!
        let overlay = SelectionOverlayWindow(
            screen: activeScreen,
            onConfirmed: { [weak self] rect in
                self?.beginScrollingCapture(in: rect)
            },
            onCancelled: { [weak self] in
                self?.cancelCapture()
            }
        )

        self.overlayWindow = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Step 2: Starts active scrolling capture within chosen rectangle
    private func beginScrollingCapture(in rect: NSRect) {
        // Close selection overlay
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main!
        self.scaleFactor = screen.backingScaleFactor

        // Convert Cocoa screen coordinates (origin at bottom-left) to CoreGraphics coordinates (origin at top-left)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgY = primaryScreenHeight - rect.maxY
        self.captureRect = CGRect(x: rect.origin.x, y: cgY, width: rect.width, height: rect.height)

        // Capture initial frame
        guard let initialFrame = captureScreenRect(captureRect) else {
            print("[ScrollingCapture] Failed to capture initial frame")
            cancelCapture()
            return
        }

        // Initialize high-performance stitcher
        self.stitcher = ImageStitcher(initialFrame: initialFrame, scaleFactor: scaleFactor)

        // Show outline frame around capture zone (ignores mouse clicks so user can interact with page)
        let outline = ScrollOutlineWindow(targetRect: rect)
        outline.orderFront(nil)
        self.outlineWindow = outline

        // Show floating HUD controls
        let hud = ScrollHUDWindow(
            targetRect: rect,
            onFinish: { [weak self] in
                self?.finishCapture()
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )
        hud.state.currentHeight = Int(CGFloat(initialFrame.height) / scaleFactor)
        hud.makeKeyAndOrderFront(nil)
        self.hudWindow = hud

        // Keyboard monitor for Return / Space to finish, Escape to cancel
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 36 || event.keyCode == 49 { // Return or Space
                self?.finishCapture()
                return nil
            } else if event.keyCode == 53 { // Escape
                self?.cancelCapture()
                return nil
            }
            return event
        }

        // Start capture loop (polls at 10 Hz)
        self.captureTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickCapture()
            }
        }
    }

    private func tickCapture() {
        guard let stitcher = stitcher else { return }
        guard let frame = captureScreenRect(captureRect) else { return }

        let delta = stitcher.append(frame: frame)
        if delta > 0 {
            let currentPtHeight = Int(CGFloat(stitcher.totalHeight) / scaleFactor)
            hudWindow?.state.currentHeight = currentPtHeight
        }
    }

    /// Step 3: Completes capture, generates long screenshot, and saves to Stack
    public func finishCapture() {
        // Stop timer and monitors
        cleanupWindows()

        guard let stitcher = stitcher, let finalImage = stitcher.generateFinalImage() else {
            print("[ScrollingCapture] Failed to generate final stitched image")
            return
        }

        // Play camera shutter sound
        AudioServicesPlaySystemSound(1108)

        // Save image to persistent storage
        let newItemId = UUID()
        if let saved = ClipboardStorage.shared.saveImage(finalImage, id: newItemId) {
            var item = ClipboardItem(
                id: newItemId,
                contentType: .image,
                textContent: nil,
                imageFileName: saved.fileName,
                imageWidth: saved.width,
                imageHeight: saved.height,
                byteCount: saved.byteSize
            )
            item.sourceAppName = "Capture Défilante"
            item.sourceAppBundleId = "com.stack.app.scrollingcapture"

            // 1. Add to Stack history
            HUDViewModel.shared.handleNewItem(item)

            // 2. Copy to system pasteboard
            KeySimulator.copyToPasteboard(item)

            // 3. Re-open HUD to reveal the newly captured long screenshot
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HUDWindowController.shared.show()
            }
        }

        self.stitcher = nil
    }

    /// Cancels capture and closes all windows
    public func cancelCapture() {
        cleanupWindows()
        self.stitcher = nil
    }

    private func cleanupWindows() {
        captureTimer?.invalidate()
        captureTimer = nil

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        hudWindow?.orderOut(nil)
        hudWindow = nil

        outlineWindow?.orderOut(nil)
        outlineWindow = nil
    }

    private func captureScreenRect(_ rect: CGRect) -> CGImage? {
        return CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Autorisation d'enregistrement d'écran requise"
        alert.informativeText = "Pour capturer des pages web et défiler, Stack a besoin d'accéder à l'enregistrement de l'écran dans Réglages Système > Confidentialité et sécurité > Enregistrement de l'écran."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Ouvrir Réglages Système")
        alert.addButton(withTitle: "Plus tard")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
