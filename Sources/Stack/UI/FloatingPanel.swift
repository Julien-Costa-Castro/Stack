import AppKit
import SwiftUI

public final class FloatingPanel: NSPanel {
    public var onEscapePressed: (() -> Void)?
    public var onLeftArrowPressed: (() -> Void)?
    public var onRightArrowPressed: (() -> Void)?
    public var onReturnPressed: (() -> Void)?
    public var onDeletePressed: (() -> Void)?
    public var onNumberPressed: ((Int) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
    }

    override public var contentView: NSView? {
        didSet {
            contentView?.wantsLayer = true
            contentView?.layer?.cornerRadius = 26
            contentView?.layer?.cornerCurve = .continuous
            contentView?.layer?.masksToBounds = true
            invalidateShadow()
        }
    }

    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return true
    }

    override public func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Check for Cmd + 1..9
            if event.modifierFlags.contains(.command) {
                if let chars = event.charactersIgnoringModifiers, let num = Int(chars), num >= 1 && num <= 9 {
                    onNumberPressed?(num - 1)
                    return
                }
                // Cmd + Delete (keyCode 51)
                if event.keyCode == 51 {
                    onDeletePressed?()
                    return
                }
            }

            switch event.keyCode {
            case 53: // Escape
                onEscapePressed?()
                return
            case 123: // Left Arrow
                onLeftArrowPressed?()
                return
            case 124: // Right Arrow
                onRightArrowPressed?()
                return
            case 36, 76: // Enter / Return / Keypad Enter
                onReturnPressed?()
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}
