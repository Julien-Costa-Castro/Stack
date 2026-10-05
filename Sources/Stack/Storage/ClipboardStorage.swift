import Foundation
import AppKit

public final class ClipboardStorage: @unchecked Sendable {
    public static let shared = ClipboardStorage()

    private let maxItemCount = 100
    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, NSImage>()
    private let appIconCache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.stack.storage", qos: .utility)

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stackDir = appSupport.appendingPathComponent("Stack", isDirectory: true)
        if !fileManager.fileExists(atPath: stackDir.path) {
            try? fileManager.createDirectory(at: stackDir, withIntermediateDirectories: true)
        }
        return stackDir
    }

    private var imagesDirectory: URL {
        let dir = storageDirectory.appendingPathComponent("images", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }

    init() {
        imageCache.countLimit = 150
        appIconCache.countLimit = 50
    }

    // MARK: - History Persistence

    public func loadHistory() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([ClipboardItem].self, from: data)
            return items
        } catch {
            print("[ClipboardStorage] Error loading history: \(error)")
            return []
        }
    }

    public func saveHistory(_ items: [ClipboardItem]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(items)
                try data.write(to: self.historyFileURL, options: .atomic)
            } catch {
                print("[ClipboardStorage] Error saving history: \(error)")
            }
        }
    }

    // MARK: - Images Management

    /// Saves raw PNG/JPEG data directly to disk without lossy re-encoding
    public func saveImageFromData(_ data: Data, id: UUID, image: NSImage?) -> (fileName: String, width: Double, height: Double, byteSize: Int)? {
        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            let width = Double(image?.size.width ?? 0)
            let height = Double(image?.size.height ?? 0)
            let size = data.count

            if let img = image {
                imageCache.setObject(img, forKey: fileName as NSString)
            }
            return (fileName, width, height, size)
        } catch {
            print("[ClipboardStorage] Failed to save raw image data: \(error)")
            return nil
        }
    }

    /// Saves an NSImage by converting to PNG data with robust drawing fallback
    public func saveImage(_ image: NSImage, id: UUID) -> (fileName: String, width: Double, height: Double, byteSize: Int)? {
        let width = Double(image.size.width)
        let height = Double(image.size.height)
        guard width > 0 && height > 0 else { return nil }

        var pngData: Data? = nil

        // Method A: Check existing representations
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }

        // Method B: Draw directly into a brand new bitmap representation
        if pngData == nil {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(width),
                pixelsHigh: Int(height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            if let rep = rep {
                rep.size = image.size
                NSGraphicsContext.saveGraphicsState()
                if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                    NSGraphicsContext.current = ctx
                    image.draw(in: NSRect(origin: .zero, size: image.size))
                }
                NSGraphicsContext.restoreGraphicsState()
                pngData = rep.representation(using: .png, properties: [:])
            }
        }

        guard let data = pngData, !data.isEmpty else {
            print("[ClipboardStorage] Could not generate PNG data from NSImage.")
            return nil
        }

        let fileName = "\(id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            imageCache.setObject(image, forKey: fileName as NSString)
            return (fileName, width, height, data.count)
        } catch {
            print("[ClipboardStorage] Failed to write image: \(error)")
            return nil
        }
    }

    public func loadImage(fileName: String) -> NSImage? {
        if let cached = imageCache.object(forKey: fileName as NSString) {
            return cached
        }

        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        imageCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    public func deleteImage(fileName: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.imageCache.removeObject(forKey: fileName as NSString)
            let fileURL = self.imagesDirectory.appendingPathComponent(fileName)
            try? self.fileManager.removeItem(at: fileURL)
        }
    }

    // Prune unreferenced images when history changes
    public func pruneUnusedImages(validFileNames: Set<String>) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let files = try? self.fileManager.contentsOfDirectory(atPath: self.imagesDirectory.path) else { return }
            for file in files {
                if !validFileNames.contains(file) {
                    let fileURL = self.imagesDirectory.appendingPathComponent(file)
                    try? self.fileManager.removeItem(at: fileURL)
                    self.imageCache.removeObject(forKey: file as NSString)
                }
            }
        }
    }

    // MARK: - App Icon Caching

    public func getAppIcon(bundleId: String?) -> NSImage {
        guard let bundleId = bundleId, !bundleId.isEmpty else {
            return NSWorkspace.shared.icon(for: .application)
        }

        if let cached = appIconCache.object(forKey: bundleId as NSString) {
            return cached
        }

        var icon: NSImage?
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        }

        let finalIcon = icon ?? NSWorkspace.shared.icon(for: .application)
        appIconCache.setObject(finalIcon, forKey: bundleId as NSString)
        return finalIcon
    }
}
