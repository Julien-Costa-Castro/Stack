import Foundation
import AppKit

@MainActor
public final class ScreenshotWatcher {
    public static let shared = ScreenshotWatcher()

    private var timer: Timer?
    private var lastSeenFileDates: [String: Date] = [:]
    private var processedFilePaths = Set<String>()
    private var monitoringDirectories: [URL] = []

    public var onScreenshotCaptured: ((ClipboardItem) -> Void)?

    private init() {
        determineDirectories()
        seedExistingScreenshots()
    }

    private func determineDirectories() {
        var dirs: [URL] = []

        // 1. User's configured screencapture location
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = NSString(string: location).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                dirs.append(url)
            }
        }

        // 2. Desktop
        let fm = FileManager.default
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first,
           !dirs.contains(desktop) {
            dirs.append(desktop)
        }

        self.monitoringDirectories = dirs
    }

    private func seedExistingScreenshots() {
        let fm = FileManager.default
        // Import recent screenshots from the last 20 minutes so current user tests appear immediately!
        let twentyMinutesAgo = Date().addingTimeInterval(-1200)

        for dir in monitoringDirectories {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
            for file in files where isScreenshotFile(file) {
                let attrs = try? fm.attributesOfItem(atPath: file.path)
                let date = attrs?[.modificationDate] as? Date ?? Date.distantPast
                lastSeenFileDates[file.path] = date

                if date > twentyMinutesAgo && !processedFilePaths.contains(file.path) {
                    importScreenshot(file: file, date: date)
                }
            }
        }
    }

    public func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scanDirectories()
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func isScreenshotFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else { return false }
        let name = url.lastPathComponent
        return name.localizedCaseInsensitiveContains("capture") ||
               name.localizedCaseInsensitiveContains("screenshot") ||
               name.localizedCaseInsensitiveContains("screen shot")
    }

    public func scanDirectories() {
        let fm = FileManager.default

        for dir in monitoringDirectories {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []

            for file in files where isScreenshotFile(file) {
                let path = file.path
                let attrs = try? fm.attributesOfItem(atPath: path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()

                if let oldDate = lastSeenFileDates[path] {
                    if modDate > oldDate && !processedFilePaths.contains(path) {
                        lastSeenFileDates[path] = modDate
                        importScreenshot(file: file, date: modDate)
                    }
                } else {
                    // New screenshot file
                    lastSeenFileDates[path] = modDate
                    importScreenshot(file: file, date: modDate)
                }
            }
        }
    }

    private func importScreenshot(file: URL, date: Date) {
        processedFilePaths.insert(file.path)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Load image with brief retry to allow macOS screencapture to finish file flush
            var loadedImage: NSImage?
            for _ in 0..<4 {
                if let img = NSImage(contentsOf: file), img.size.width > 0 {
                    loadedImage = img
                    break
                }
                usleep(60000) // 60ms
            }

            guard let image = loadedImage else { return }

            let itemId = UUID()
            guard let saved = ClipboardStorage.shared.saveImage(image, id: itemId) else { return }

            let item = ClipboardItem(
                id: itemId,
                timestamp: date,
                contentType: .image,
                imageFileName: saved.fileName,
                imageWidth: saved.width,
                imageHeight: saved.height,
                byteCount: saved.byteSize,
                characterCount: 0,
                sourceAppName: "Capture d’écran",
                sourceAppBundleId: "com.apple.screencapture"
            )

            DispatchQueue.main.async {
                self?.onScreenshotCaptured?(item)
            }
        }
    }
}
