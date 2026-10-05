import Foundation
import AppKit

@MainActor
public final class ClipboardWatcher {
    public static let shared = ClipboardWatcher()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var isPaused: Bool = false

    public var onItemCaptured: ((ClipboardItem) -> Void)?

    private init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    public func startMonitoring(interval: TimeInterval = 0.25) {
        stopMonitoring()
        self.lastChangeCount = pasteboard.changeCount
        self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForChanges()
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
        lastChangeCount = pasteboard.changeCount
    }

    public func updateLastChangeCount(to count: Int) {
        lastChangeCount = count
    }

    /// Immediately checks pasteboard without waiting for timer tick
    public func checkForChangesNow() {
        checkForChanges()
    }

    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        if isPaused { return }

        // Ignore events triggered while Stack is the active frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier == NSRunningApplication.current.processIdentifier {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Application"
        let appBundleId = frontApp?.bundleIdentifier

        captureCurrentPasteboard(appName: appName, appBundleId: appBundleId)
    }

    private func captureCurrentPasteboard(appName: String, appBundleId: String?) {
        // 1. Try capturing Image first (Pixel data, screenshots, browser 'Copy Image', or Finder files)
        if captureImageFromPasteboard(appName: appName, appBundleId: appBundleId) {
            return
        }

        // 2. Try capturing Text / URL / Code
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let detection = ContentTypeDetector.detect(text: text)
            let byteCount = text.utf8.count
            let characterCount = text.count

            let item = ClipboardItem(
                id: UUID(),
                timestamp: Date(),
                contentType: detection.type,
                textContent: text,
                codeLanguage: detection.languageHint,
                byteCount: byteCount,
                characterCount: characterCount,
                sourceAppName: appName,
                sourceAppBundleId: appBundleId
            )
            onItemCaptured?(item)
        }
    }

    private func captureImageFromPasteboard(appName: String, appBundleId: String?) -> Bool {
        // A. Priority: Raw PNG Data (Screenshots, Arc / Chrome / Safari right-click 'Copy Image', Figma)
        let pngTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("image/png")
        ]
        for type in pngTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty,
               let image = NSImage(data: data), image.size.width > 0 {
                let itemId = UUID()
                if let saved = ClipboardStorage.shared.saveImageFromData(data, id: itemId, image: image) {
                    let item = ClipboardItem(
                        id: itemId,
                        timestamp: Date(),
                        contentType: .image,
                        imageFileName: saved.fileName,
                        imageWidth: saved.width,
                        imageHeight: saved.height,
                        byteCount: saved.byteSize,
                        characterCount: 0,
                        sourceAppName: appName,
                        sourceAppBundleId: appBundleId
                    )
                    onItemCaptured?(item)
                    return true
                }
            }
        }

        // B. Priority: Direct TIFF, JPEG, WebP, GIF Data
        let otherTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("image/jpeg"),
            NSPasteboard.PasteboardType("org.webmproject.webp"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]
        for type in otherTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty,
               let image = NSImage(data: data), image.size.width > 0 {
                let itemId = UUID()
                if let saved = ClipboardStorage.shared.saveImage(image, id: itemId) {
                    let item = ClipboardItem(
                        id: itemId,
                        timestamp: Date(),
                        contentType: .image,
                        imageFileName: saved.fileName,
                        imageWidth: saved.width,
                        imageHeight: saved.height,
                        byteCount: saved.byteSize,
                        characterCount: 0,
                        sourceAppName: appName,
                        sourceAppBundleId: appBundleId
                    )
                    onItemCaptured?(item)
                    return true
                }
            }
        }

        // C. Priority: AppKit's general image initializer
        if pasteboard.canReadItem(withDataConformingToTypes: NSImage.imageTypes) {
            if let image = NSImage(pasteboard: pasteboard), image.size.width > 0 && image.size.height > 0 {
                let itemId = UUID()
                if let saved = ClipboardStorage.shared.saveImage(image, id: itemId) {
                    let item = ClipboardItem(
                        id: itemId,
                        timestamp: Date(),
                        contentType: .image,
                        imageFileName: saved.fileName,
                        imageWidth: saved.width,
                        imageHeight: saved.height,
                        byteCount: saved.byteSize,
                        characterCount: 0,
                        sourceAppName: appName,
                        sourceAppBundleId: appBundleId
                    )
                    onItemCaptured?(item)
                    return true
                }
            }
        }

        // D. Priority: Image file copied in Finder (Cmd + C on a photo file)
        if let fileURL = readImageFileURLFromPasteboard(),
           let image = NSImage(contentsOf: fileURL), image.size.width > 0 {
            let itemId = UUID()
            if let saved = ClipboardStorage.shared.saveImage(image, id: itemId) {
                let item = ClipboardItem(
                    id: itemId,
                    timestamp: Date(),
                    contentType: .image,
                    imageFileName: saved.fileName,
                    imageWidth: saved.width,
                    imageHeight: saved.height,
                    byteCount: saved.byteSize,
                    characterCount: 0,
                    sourceAppName: appName,
                    sourceAppBundleId: appBundleId
                )
                onItemCaptured?(item)
                return true
            }
        }

        return false
    }

    private func readImageFileURLFromPasteboard() -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where url.isFileURL {
                let ext = url.pathExtension.lowercased()
                let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "heic", "bmp", "ico", "svg"]
                if imageExtensions.contains(ext) {
                    return url
                }
            }
        }
        return nil
    }
}
