import SwiftUI
import AppKit

public struct HUDView: View {
    @ObservedObject public var viewModel: HUDViewModel

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Filter Bar
            topBarView
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Optional Accessibility banner
            if !viewModel.hasAccessibilityPermission {
                PermissionBanner {
                    KeySimulator.revealInFinderForDragAndDrop()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Cards Horizontal Shelf or Empty State
            contentAreaView
                .frame(maxHeight: .infinity)

            // Bottom Keyboard shortcuts legend & Status
            bottomBarView
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Frosted glass dark backdrop with native squircle corners
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 26)
                Color.black.opacity(0.42)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Top Bar
    private var topBarView: some View {
        HStack(spacing: 14) {
            // Logo / App Badge
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d.down.right.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("STACK")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ContentType.allCases, id: \.self) { category in
                        let count = countForCategory(category)
                        FilterChipView(
                            type: category,
                            isSelected: viewModel.selectedCategory == category,
                            count: count,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.selectedCategory = category
                                    viewModel.selectedIndex = 0
                                }
                            }
                        )
                    }
                }
            }

            Spacer(minLength: 12)

            // Search Bar
            SearchBarView(text: $viewModel.searchText)

            // Scrolling Capture quick action
            Button(action: {
                ScrollingCaptureController.shared.startSelection()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 12, weight: .bold))
                    Text("Capture Défilante")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Capturer une zone ou un site web entier avec défilement (⌘⌥S)")

            // Actions: Clear all & Dismiss
            HStack(spacing: 8) {
                if !viewModel.items.isEmpty {
                    Button(action: {
                        withAnimation {
                            viewModel.clearAllHistory()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(7)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Vider tout l'historique")
                }

                Button(action: {
                    viewModel.onDismissRequested?()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(7)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Fermer (Échap)")
            }
        }
    }

    // MARK: - Content Shelf
    @ViewBuilder
    private var contentAreaView: some View {
        let items = viewModel.filteredItems

        if items.isEmpty {
            EmptyStateView(
                isSearching: !viewModel.searchText.isEmpty,
                searchQuery: viewModel.searchText
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            CardView(
                                item: item,
                                index: index,
                                isSelected: viewModel.selectedIndex == index,
                                onPaste: {
                                    viewModel.pasteItem(item)
                                },
                                onCopy: {
                                    viewModel.copyItemOnly(item)
                                },
                                onDelete: {
                                    withAnimation {
                                        viewModel.deleteItem(item)
                                    }
                                },
                                onTogglePin: {
                                    withAnimation {
                                        viewModel.togglePin(item)
                                    }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.selectedIndex) { newIndex in
                    if newIndex >= 0 && newIndex < items.count {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(items[newIndex].id, anchor: .center)
                        }
                    }
                }
                .onChange(of: items.first?.id) { firstId in
                    if let firstId = firstId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(firstId, anchor: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar
    private var bottomBarView: some View {
        HStack {
            // Keyboard hints
            HStack(spacing: 12) {
                shortcutHint(key: "↵", label: "Coller")
                shortcutHint(key: "⌘1–9", label: "Coller rapide")
                shortcutHint(key: "⌘⌥S", label: "Capture défilante")
                shortcutHint(key: "← →", label: "Naviguer")
                shortcutHint(key: "⌘⌫", label: "Supprimer")
                shortcutHint(key: "⎋", label: "Fermer")
            }

            Spacer()

            // Count info
            Text("\(viewModel.items.count) / 100 éléments")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                )

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func countForCategory(_ category: ContentType) -> Int {
        if category == .all {
            return viewModel.items.count
        }
        return viewModel.items.filter { $0.contentType == category }.count
    }
}

// macOS Visual Effect Blur with native squircle corner masking
public struct VisualEffectBlur: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let cornerRadius: CGFloat

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        cornerRadius: CGFloat = 26
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true
        return visualEffectView
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
    }
}
