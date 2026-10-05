import SwiftUI

public struct FilterChipView: View {
    public let type: ContentType
    public let isSelected: Bool
    public let count: Int
    public let onSelect: () -> Void

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: iconForType(type))
                    .font(.system(size: 11))

                Text(type.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                        )
                }
            }
            .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForType(_ type: ContentType) -> String {
        switch type {
        case .all: return "square.stack.fill"
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .url: return "link"
        case .image: return "photo.fill"
        case .color: return "paintpalette.fill"
        }
    }
}
