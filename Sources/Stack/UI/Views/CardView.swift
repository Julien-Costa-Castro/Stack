import SwiftUI
import AppKit

public struct CardView: View {
    public let item: ClipboardItem
    public let index: Int
    public let isSelected: Bool
    public let onPaste: () -> Void
    public let onCopy: () -> Void
    public let onDelete: () -> Void
    public let onTogglePin: () -> Void

    @State private var isHovered: Bool = false
    @State private var loadedImage: NSImage?
    @State private var appIcon: NSImage?

    private var shortcutKey: String? {
        if index < 9 {
            return "⌘\(index + 1)"
        }
        return nil
    }

    public var body: some View {
        Button(action: onPaste) {
            VStack(alignment: .leading, spacing: 0) {
                // Header: App icon + App name + Relative time + Shortcut badge
                headerView
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Body: Content preview based on type
                contentBodyView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Footer: Metadata & Quick action buttons
                footerView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .frame(width: 250, height: 260)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .windowBackgroundColor).opacity(0.75) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.3) : Color.white.opacity(0.12)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.black.opacity(0.35) : Color.black.opacity(0.2)), radius: isSelected ? 10 : (isHovered ? 8 : 4), x: 0, y: isSelected ? 4 : 2)
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            loadAssets()
        }
        .onChange(of: item.id) { _ in
            loadAssets()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.sourceAppName ?? "Inconnu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(item.relativeTimeFormatted)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }

            if let shortcut = shortcutKey {
                Text(shortcut)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.accentColor : Color.white.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Body Preview
    @ViewBuilder
    private var contentBodyView: some View {
        switch item.contentType {
        case .image:
            imageContentView

        case .code:
            codeContentView

        case .url:
            urlContentView

        case .color:
            colorContentView

        case .text, .all:
            textContentView
        }
    }

    // Text View
    private var textContentView: some View {
        Text(item.textContent ?? "")
            .font(.system(size: 12.5, weight: .regular))
            .foregroundColor(.primary.opacity(0.95))
            .lineSpacing(3)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // Code View
    private var codeContentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.codeLanguage ?? "CODE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)

                Spacer()

                if let text = item.textContent {
                    let lineCount = text.components(separatedBy: .newlines).count
                    Text("\(lineCount)L")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Text(item.textContent ?? "")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.green.opacity(0.9))
                .lineLimit(6)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
                .background(Color.black.opacity(0.35))
                .cornerRadius(8)
        }
    }

    // URL View
    private var urlContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)

                Text(item.previewTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }

            Text(item.textContent ?? "")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(5)
                .lineSpacing(2)
        }
    }

    // Image View
    private var imageContentView: some View {
        VStack(spacing: 6) {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 110)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .frame(maxWidth: .infinity, maxHeight: 110)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.7)
                    )
            }

            if let w = item.imageWidth, let h = item.imageHeight {
                HStack {
                    Text("\(Int(w)) × \(Int(h)) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(item.formattedByteSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // Color View
    private var colorContentView: some View {
        let hex = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "#FFFFFF"
        let color = Color(hex: hex) ?? .white

        return VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(maxWidth: .infinity)
                .frame(height: 75)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Text(hex.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                Spacer()

                Text("Couleur")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 8) {
            // Stats / Type label
            HStack(spacing: 4) {
                Image(systemName: iconForContentType(item.contentType))
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)

                if item.contentType == .text || item.contentType == .code {
                    Text("\(item.characterCount) car.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                } else if item.contentType == .image {
                    Text("Image")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                } else {
                    Text(item.contentType.rawValue)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick actions on hover or keyboard selection
            if isHovered || isSelected {
                HStack(spacing: 6) {
                    Button(action: onTogglePin) {
                        Image(systemName: item.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 10))
                            .foregroundColor(item.isPinned ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Désépingler" : "Épingler")

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copier seulement")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Supprimer de l'historique")

                    Button(action: onPaste) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("Coller")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .frame(height: 24)
    }

    private func iconForContentType(_ type: ContentType) -> String {
        switch type {
        case .all: return "square.stack"
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .url: return "link"
        case .image: return "photo"
        case .color: return "paintpalette"
        }
    }

    private func loadAssets() {
        self.appIcon = ClipboardStorage.shared.getAppIcon(bundleId: item.sourceAppBundleId)
        if item.contentType == .image, let fileName = item.imageFileName {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = ClipboardStorage.shared.loadImage(fileName: fileName)
                DispatchQueue.main.async {
                    self.loadedImage = img
                }
            }
        }
    }
}

// Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        let r, g, b, a: Double
        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else if length == 3 {
            r = Double((rgb & 0xF00) >> 8) / 15.0
            g = Double((rgb & 0x0F0) >> 4) / 15.0
            b = Double(rgb & 0x00F) / 15.0
            a = 1.0
        } else {
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
