import AppKit
import Foundation

/// Full-screen transparent overlay panel for capturing user screen selection
public final class SelectionOverlayWindow: NSPanel {
    private let overlayView: SelectionOverlayView

    public init(screen: NSScreen, onConfirmed: @escaping (CGRect) -> Void, onCancelled: @escaping () -> Void) {
        let frame = screen.frame
        self.overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        overlayView.onSelectionConfirmed = onConfirmed
        overlayView.onCancelled = onCancelled

        self.contentView = overlayView
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }
}
