import Foundation
import AppKit

public enum ContentType: String, Codable, CaseIterable, Sendable {
    case all = "Tous"
    case text = "Texte"
    case code = "Code"
    case url = "Liens"
    case image = "Images"
    case color = "Couleur"
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var timestamp: Date
    public let contentType: ContentType
    public var textContent: String?
    public var codeLanguage: String?
    public var imageFileName: String?
    public var imageWidth: Double?
    public var imageHeight: Double?
    public var byteCount: Int
    public var characterCount: Int
    public var sourceAppName: String?
    public var sourceAppBundleId: String?
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentType: ContentType,
        textContent: String? = nil,
        codeLanguage: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Double? = nil,
        imageHeight: Double? = nil,
        byteCount: Int = 0,
        characterCount: Int = 0,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentType = contentType
        self.textContent = textContent
        self.codeLanguage = codeLanguage
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteCount = byteCount
        self.characterCount = characterCount
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.isPinned = isPinned
    }

    // Relative date formatting helper
    public var relativeTimeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    // Human-readable size
    public var formattedByteSize: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: Int64(byteCount))
    }

    // Title preview for card display
    public var previewTitle: String {
        switch contentType {
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "Image \(Int(w)) × \(Int(h))"
            }
            return "Image"
        case .color:
            return textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "#FFFFFF"
        case .url:
            if let text = textContent, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url.host ?? text
            }
            return textContent ?? "Lien"
        case .code:
            let lang = codeLanguage ?? "Code"
            let lines = (textContent ?? "").components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return "\(lang) • \(lines.count) lignes"
        case .text, .all:
            guard let text = textContent else { return "Élément" }
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return lines.first?.trimmingCharacters(in: .whitespaces) ?? text
        }
    }

    // Match search query
    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }

        if let text = textContent, text.lowercased().contains(q) {
            return true
        }
        if let app = sourceAppName, app.lowercased().contains(q) {
            return true
        }
        if let lang = codeLanguage, lang.lowercased().contains(q) {
            return true
        }
        if contentType.rawValue.lowercased().contains(q) {
            return true
        }
        return false
    }
}

// Heuristics for detecting content type
public enum ContentTypeDetector {
    public static func detect(text: String) -> (type: ContentType, languageHint: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Color detection (Hex: #RGB, #RGBA, #RRGGBB, #RRGGBBAA)
        let hexPattern = "^#([A-Fa-f0-9]{3}|[A-Fa-f0-9]{4}|[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"
        if trimmed.range(of: hexPattern, options: .regularExpression) != nil {
            return (.color, nil)
        }

        // 2. URL detection
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("ftp://")) && !trimmed.contains(" ") && !trimmed.contains("\n") {
            if URL(string: trimmed) != nil {
                return (.url, nil)
            }
        }

        // 3. Code detection
        if let language = detectCodeLanguage(in: trimmed) {
            return (.code, language)
        }

        return (.text, nil)
    }

    private static func detectCodeLanguage(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)

        // JSON check
        if (trimmedStartsAndEnds(text, "{", "}") || trimmedStartsAndEnds(text, "[", "]")) &&
            (text.contains("\": \"") || text.contains("\":") || text.contains("\": true") || text.contains("\": false")) {
            return "JSON"
        }

        // Swift check
        if (text.contains("func ") || text.contains("import SwiftUI") || text.contains("import Foundation") ||
            text.contains("var body: some View") || text.contains("guard let ") || text.contains("@State ") ||
            text.contains("@Binding ") || text.contains("struct ") && text.contains(": View")) {
            return "Swift"
        }

        // JavaScript / TypeScript check
        if (text.contains("const ") || text.contains("let ") || text.contains("=> {") ||
            text.contains("console.log(") || text.contains("import React") || text.contains("export default") ||
            text.contains("export function") || text.contains("npm i") || text.contains("yarn add")) {
            return "JavaScript"
        }

        // Python check
        if (text.contains("def ") && text.contains(":") || text.contains("import numpy") ||
            text.contains("import pandas") || text.contains("print(") || text.contains("__init__") ||
            text.contains("elif ") || text.contains("if __name__ ==")) {
            return "Python"
        }

        // HTML / XML check
        if (text.contains("<div") || text.contains("<span") || text.contains("<!DOCTYPE html>") ||
            text.contains("<html") || text.contains("</p>") || text.contains("<script")) {
            return "HTML"
        }

        // SQL check
        if (text.contains("SELECT ") && text.contains("FROM ") || text.contains("INSERT INTO ") ||
            text.contains("UPDATE ") && text.contains("SET ") || text.contains("CREATE TABLE ")) {
            return "SQL"
        }

        // Shell check
        if (trimmedStartsAndEnds(text, "#!/bin/", "") || text.hasPrefix("curl ") || text.hasPrefix("git ") ||
            text.hasPrefix("brew ") || text.hasPrefix("docker ") || text.hasPrefix("cd ") || text.hasPrefix("mkdir ")) {
            return "Shell"
        }

        // Generic code check: curly braces with indentation or semicolon patterns
        if lines.count >= 2 {
            var syntaxHits = 0
            let keywords = ["class ", "func ", "function", "return ", "if (", "while (", "for (", "import ", "export ", "public ", "private "]
            for kw in keywords where text.contains(kw) {
                syntaxHits += 1
            }
            if text.contains("{") && text.contains("}") {
                syntaxHits += 1
            }
            if text.contains(";") && lines.count >= 3 {
                syntaxHits += 1
            }

            if syntaxHits >= 2 {
                return "Code"
            }
        }

        return nil
    }

    private static func trimmedStartsAndEnds(_ text: String, _ prefix: String, _ suffix: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty && !t.hasPrefix(prefix) { return false }
        if !suffix.isEmpty && !t.hasSuffix(suffix) { return false }
        return true
    }
}
