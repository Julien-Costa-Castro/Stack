import SwiftUI

public struct EmptyStateView: View {
    public let isSearching: Bool
    public let searchQuery: String

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "clipboard")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary.opacity(0.8))

            if isSearching {
                Text("Aucun résultat trouvé")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Aucun élément ne correspond à « \(searchQuery) ».")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text("Votre presse-papiers est vide")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Copiez du texte, du code, un lien ou une image (⌘C) dans n'importe quelle application pour commencer.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
