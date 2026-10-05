import AppKit
import Foundation

/// Custom AppKit view for selecting a rectangular capture zone with interactive handles
public final class SelectionOverlayView: NSView {
    public var onSelectionConfirmed: ((CGRect) -> Void)?
    public var onCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isSelecting: Bool = false
    private var hasSelectedZone: Bool = false

    private var actionButton: NSButton?
    private var cancelButton: NSButton?
    private var infoLabel: NSTextField?

    override public var acceptsFirstResponder: Bool { true }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        // Info Label
        let label = NSTextField(labelWithString: "Tracez un rectangle autour du site web ou de la zone à capturer • Échap pour annuler")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        label.layer?.cornerRadius = 14
        label.layer?.masksToBounds = true
        self.infoLabel = label
        addSubview(label)

        // Start capture button
        let startBtn = NSButton(title: "📸 Démarrer le défilement", target: self, action: #selector(didClickStart))
        startBtn.bezelStyle = .rounded
        startBtn.wantsLayer = true
        startBtn.font = .systemFont(ofSize: 13, weight: .bold)
        startBtn.contentTintColor = .white
        startBtn.layer?.backgroundColor = NSColor.systemBlue.cgColor
        startBtn.layer?.cornerRadius = 10
        startBtn.isHidden = true
        self.actionButton = startBtn
        addSubview(startBtn)

        // Cancel button
        let cancelBtn = NSButton(title: "Annuler", target: self, action: #selector(didClickCancel))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.wantsLayer = true
        cancelBtn.font = .systemFont(ofSize: 13, weight: .medium)
        cancelBtn.contentTintColor = .white
        cancelBtn.layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.8).cgColor
        cancelBtn.layer?.cornerRadius = 10
        cancelBtn.isHidden = true
        self.cancelButton = cancelBtn
        addSubview(cancelBtn)

        layoutInfoLabel()
    }

    private func layoutInfoLabel() {
        guard let label = infoLabel else { return }
        let size = label.intrinsicContentSize
        let width = size.width + 36
        let height = size.height + 14
        label.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - 80,
            width: width,
            height: height
        )
    }

    override public func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse Events

    override public func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        startPoint = loc
        currentRect = NSRect(origin: loc, size: .zero)
        isSelecting = true
        hasSelectedZone = false
        hideActionButtons()
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let loc = convert(event.locationInWindow, from: nil)

        let x = min(start.x, loc.x)
        let y = min(start.y, loc.y)
        let w = abs(start.x - loc.x)
        let h = abs(start.y - loc.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)
        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false

        if currentRect.width > 50 && currentRect.height > 50 {
            hasSelectedZone = true
            showActionButtons()
        } else {
            hasSelectedZone = false
            currentRect = .zero
        }
        needsDisplay = true
    }

    // MARK: - Keyboard Events

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancelled?()
        } else if (event.keyCode == 36 || event.keyCode == 49) && hasSelectedZone { // Return or Space
            didClickStart()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw darkened overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.fill(bounds)

        // 2. Clear selected rectangle
        if (isSelecting || hasSelectedZone) && currentRect.width > 0 && currentRect.height > 0 {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(currentRect)
            context.restoreGState()

            // 3. Draw neon border
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.5)
            context.stroke(currentRect)

            // 4. Draw dimension badge
            let dimString = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attrString = NSAttributedString(string: dimString, attributes: attrs)
            let badgeSize = attrString.size()
            let badgeRect = NSRect(
                x: currentRect.midX - (badgeSize.width + 16) / 2,
                y: currentRect.minY + 8,
                width: badgeSize.width + 16,
                height: badgeSize.height + 6
            )

            context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.addPath(badgePath)
            context.fillPath()

            attrString.draw(at: NSPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 3))
        }
    }

    // MARK: - Actions

    private func showActionButtons() {
        guard let startBtn = actionButton, let cancelBtn = cancelButton else { return }

        let btnWidth: CGFloat = 200
        let btnHeight: CGFloat = 34
        let spacing: CGFloat = 12

        // Position toolbar below selection, or above if close to bottom
        var yPos = currentRect.minY - btnHeight - 16
        if yPos < 40 {
            yPos = currentRect.maxY + 16
        }

        let totalWidth = btnWidth + 100 + spacing
        let startX = currentRect.midX - totalWidth / 2

        startBtn.frame = NSRect(x: startX, y: yPos, width: btnWidth, height: btnHeight)
        cancelBtn.frame = NSRect(x: startX + btnWidth + spacing, y: yPos, width: 100, height: btnHeight)

        startBtn.isHidden = false
        cancelBtn.isHidden = false

        if let label = infoLabel {
            label.stringValue = "Zone prête ! Cliquez sur Démarrer puis faites défiler la page web • Entrée pour valider"
            layoutInfoLabel()
        }
    }

    private func hideActionButtons() {
        actionButton?.isHidden = true
        cancelButton?.isHidden = true
        if let label = infoLabel {
            label.stringValue = "Tracez un rectangle autour du site web ou de la zone à capturer • Échap pour annuler"
            layoutInfoLabel()
        }
    }

    @objc private func didClickStart() {
        guard hasSelectedZone && currentRect.width > 20 && currentRect.height > 20 else { return }
        // Convert local view coordinates to Cocoa screen coordinates
        let screenRect = window?.convertToScreen(currentRect) ?? currentRect
        onSelectionConfirmed?(screenRect)
    }

    @objc private func didClickCancel() {
        onCancelled?()
    }
}
