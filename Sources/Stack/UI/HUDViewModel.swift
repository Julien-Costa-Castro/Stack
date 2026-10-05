import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
public final class HUDViewModel: ObservableObject {
    public static let shared = HUDViewModel()

    @Published public var items: [ClipboardItem] = []
    @Published public var searchText: String = ""
    @Published public var selectedCategory: ContentType = .all
    @Published public var selectedIndex: Int = 0
    @Published public var hasAccessibilityPermission: Bool = true
    @Published public var lastCopiedItemId: UUID?

    private var cancellables = Set<AnyCancellable>()
    private var previousFrontmostApp: NSRunningApplication?

    public var onDismissRequested: (() -> Void)?

    private init() {
        loadInitialData()
        setupWatcherBindings()
        refreshAccessibilityPermission()
    }

    private func loadInitialData() {
        let loaded = ClipboardStorage.shared.loadHistory()
        var uniqueItems: [ClipboardItem] = []
        var seenTexts = Set<String>()
        var seenImages = Set<String>()

        for item in loaded {
            if let text = item.textContent {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !seenTexts.contains(trimmed) {
                    seenTexts.insert(trimmed)
                    uniqueItems.append(item)
                }
            } else if let img = item.imageFileName {
                if !seenImages.contains(img) {
                    seenImages.insert(img)
                    uniqueItems.append(item)
                }
            } else {
                uniqueItems.append(item)
            }
        }
        self.items = uniqueItems
        ClipboardStorage.shared.saveHistory(uniqueItems)
    }

    private func setupWatcherBindings() {
        ClipboardWatcher.shared.onItemCaptured = { [weak self] newItem in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleNewItem(newItem)
            }
        }
    }

    public func refreshAccessibilityPermission() {
        self.hasAccessibilityPermission = KeySimulator.isAccessibilityEnabled()
    }

    public func setPreviousApplication(_ app: NSRunningApplication?) {
        self.previousFrontmostApp = app
    }

    // MARK: - Filtering

    public var filteredItems: [ClipboardItem] {
        var list = items

        // Category filter
        if selectedCategory != .all {
            list = list.filter { $0.contentType == selectedCategory }
        }

        // Search query filter
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter { $0.matches(query: query) }
        }

        return list
    }

    // MARK: - Item Insertion & Reordering

    public func handleNewItem(_ newItem: ClipboardItem) {
        // Check if an identical text item already exists
        if let text = newItem.textContent, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingIndex = items.firstIndex(where: { ($0.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }) {
                // If it's already top item, do nothing
                if existingIndex == 0 { return }
                // Move existing item to top with updated timestamp
                var existingItem = items.remove(at: existingIndex)
                existingItem.timestamp = Date()
                existingItem.sourceAppName = newItem.sourceAppName
                existingItem.sourceAppBundleId = newItem.sourceAppBundleId
                items.insert(existingItem, at: 0)
                ClipboardStorage.shared.saveHistory(items)
                return
            }
        }

        // Check if identical image (same dimensions, size)
        if newItem.contentType == .image, let w = newItem.imageWidth, let h = newItem.imageHeight {
            if let existingIndex = items.firstIndex(where: { $0.contentType == .image && $0.imageWidth == w && $0.imageHeight == h && $0.byteCount == newItem.byteCount }) {
                if existingIndex == 0 { return }
                var existingItem = items.remove(at: existingIndex)
                existingItem.timestamp = Date()
                items.insert(existingItem, at: 0)
                ClipboardStorage.shared.saveHistory(items)
                return
            }
        }

        // Insert new item at top
        items.insert(newItem, at: 0)

        // Maintain maximum 100 items
        if items.count > 100 {
            let overflow = items.suffix(from: 100)
            for item in overflow {
                if let fileName = item.imageFileName {
                    ClipboardStorage.shared.deleteImage(fileName: fileName)
                }
            }
            items = Array(items.prefix(100))
        }

        ClipboardStorage.shared.saveHistory(items)
    }

    // MARK: - Actions

    public func pasteItem(_ item: ClipboardItem) {
        lastCopiedItemId = item.id
        let targetApp = previousFrontmostApp

        // Dismiss HUD first
        onDismissRequested?()

        // Execute paste sequence
        KeySimulator.executePaste(item: item, targetApp: targetApp) { [weak self] in
            // Re-order pasted item to top
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let index = self.items.firstIndex(where: { $0.id == item.id }), index != 0 {
                    var updated = self.items.remove(at: index)
                    updated.timestamp = Date()
                    self.items.insert(updated, at: 0)
                    ClipboardStorage.shared.saveHistory(self.items)
                }
            }
        }
    }

    public func copyItemOnly(_ item: ClipboardItem) {
        lastCopiedItemId = item.id
        KeySimulator.copyToPasteboard(item)
    }

    public func deleteItem(_ item: ClipboardItem) {
        if let fileName = item.imageFileName {
            ClipboardStorage.shared.deleteImage(fileName: fileName)
        }
        items.removeAll { $0.id == item.id }
        ClipboardStorage.shared.saveHistory(items)
        clampSelection()
    }

    public func clearAllHistory() {
        for item in items {
            if let fileName = item.imageFileName {
                ClipboardStorage.shared.deleteImage(fileName: fileName)
            }
        }
        items.removeAll()
        ClipboardStorage.shared.saveHistory(items)
        selectedIndex = 0
    }

    public func togglePin(_ item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned.toggle()
            ClipboardStorage.shared.saveHistory(items)
        }
    }

    // MARK: - Keyboard Navigation

    public func selectPrevious() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    public func selectNext() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    public func pasteSelected() {
        let currentFiltered = filteredItems
        guard selectedIndex >= 0 && selectedIndex < currentFiltered.count else { return }
        pasteItem(currentFiltered[selectedIndex])
    }

    public func pasteAtIndex(_ index: Int) {
        let currentFiltered = filteredItems
        guard index >= 0 && index < currentFiltered.count else { return }
        pasteItem(currentFiltered[index])
    }

    private func clampSelection() {
        let count = filteredItems.count
        if count == 0 {
            selectedIndex = 0
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        }
    }
}
