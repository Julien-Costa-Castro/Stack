import AppKit
import SwiftUI

/// SwiftUI View displayed in the floating HUD during active scrolling capture
public struct ScrollHUDView: View {
    @ObservedObject public var state: ScrollCaptureState
    public let onFinish: () -> Void
    public let onCancel: () -> Void

    @State private var isBlinking = false

    public var body: some View {
        HStack(spacing: 16) {
            // Live indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isBlinking ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isBlinking)

                Text("Défilez la page...")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .onAppear { isBlinking = true }

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))

            // Height counter
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                Text("Hauteur : \(state.currentHeight) px")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer(minLength: 8)

            // Finish button
            Button(action: onFinish) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Terminer (Entrée)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(6)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

/// Observable state for the floating HUD
@MainActor
public final class ScrollCaptureState: ObservableObject {
    @Published public var currentHeight: Int = 0
}

/// Floating HUD window positioned near the capture zone
public final class ScrollHUDWindow: NSPanel {
    public let state = ScrollCaptureState()

    public init(targetRect: NSRect, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let hudWidth: CGFloat = 430
        let hudHeight: CGFloat = 52

        // Position HUD above the capture zone, or below if near screen top
        var yPos = targetRect.maxY + 14
        let screen = NSScreen.screens.first { $0.frame.intersects(targetRect) } ?? NSScreen.main!
        if yPos + hudHeight > screen.visibleFrame.maxY {
            yPos = max(screen.visibleFrame.minY + 20, targetRect.minY - hudHeight - 14)
        }

        let xPos = max(screen.visibleFrame.minX + 20, min(screen.visibleFrame.maxX - hudWidth - 20, targetRect.midX - hudWidth / 2))
        let frame = NSRect(x: xPos, y: yPos, width: hudWidth, height: hudHeight)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating + 20
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = ScrollHUDView(state: state, onFinish: onFinish, onCancel: onCancel)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 26
        hostingView.layer?.masksToBounds = true
        self.contentView = hostingView
    }

    override public var canBecomeKey: Bool { true }
}

/// Pass-through outline window that highlights the capture zone without blocking clicks
public final class ScrollOutlineWindow: NSPanel {
    public init(targetRect: NSRect) {
        super.init(
            contentRect: targetRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating + 10
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // CRITICAL: allows user mouse events to pass directly through to browser
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let outlineView = OutlineBorderView(frame: NSRect(origin: .zero, size: targetRect.size))
        self.contentView = outlineView
    }
}

private final class OutlineBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(2.0)
        let strokeRect = bounds.insetBy(dx: 1, dy: 1)
        ctx.stroke(strokeRect)
    }
}
