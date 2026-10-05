import SwiftUI

public struct PermissionBanner: View {
    public let onAuthorize: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))

            Text("Pour coller au clic : glissez Stack.app dans Réglages Système > Accessibilité.")
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.9))

            Spacer()

            Button(action: onAuthorize) {
                Text("Configurer (Glisser-Déposer)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.orange)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
