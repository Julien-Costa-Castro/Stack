import Foundation
import CoreGraphics
import AppKit

/// High-performance vertical image stitcher for scrolling screen capture
public final class ImageStitcher: @unchecked Sendable {
    public let pixelWidth: Int
    public let initialHeight: Int
    public let scaleFactor: CGFloat
    private let bytesPerRow: Int

    private var stitchedRows: [Data] = []
    private var lastFrame: CGImage?
    private let stripHeight: Int = 32
    private let maxScrollDeltaPerFrame: Int = 300

    public private(set) var totalHeight: Int = 0

    public init(initialFrame: CGImage, scaleFactor: CGFloat = 2.0) {
        self.pixelWidth = initialFrame.width
        self.initialHeight = initialFrame.height
        self.scaleFactor = scaleFactor
        self.bytesPerRow = initialFrame.bytesPerRow
        self.lastFrame = initialFrame
        self.totalHeight = initialFrame.height

        // Extract initial rows
        if let data = initialFrame.dataProvider?.data as Data? {
            stitchedRows.reserveCapacity(initialFrame.height * 4)
            for r in 0..<initialFrame.height {
                let start = r * bytesPerRow
                let end = start + bytesPerRow
                if end <= data.count {
                    stitchedRows.append(data.subdata(in: start..<end))
                }
            }
        }
    }

    /// Compares a new video frame with the previous frame, detects vertical scroll offset,
    /// and appends newly revealed pixels at the bottom.
    /// Returns the detected vertical delta (in pixels).
    public func append(frame: CGImage) -> Int {
        guard frame.width == pixelWidth,
              let prev = lastFrame,
              let data1 = prev.dataProvider?.data as Data?,
              let data2 = frame.dataProvider?.data as Data? else {
            return 0
        }

        let height = frame.height
        let bpr = frame.bytesPerRow

        // Find reference strip in previous frame with high visual contrast/variance
        let stripTop1 = findBestContrastStrip(data: data1, height: height, width: pixelWidth, bytesPerRow: bpr)

        var bestDelta = 0
        var minDiff = Double.infinity

        // 1. Check if user didn't scroll (delta = 0)
        let diff0 = calculateStripDifference(
            data1: data1, top1: stripTop1,
            data2: data2, top2: stripTop1,
            stripHeight: stripHeight, width: pixelWidth, bpr: bpr, step: 4
        )
        if diff0 < 3.0 {
            // Content is virtually identical, no scroll occurred
            return 0
        }

        // 2. Scan possible downward scroll deltas (strip in next frame moved UP: stripTop2 = stripTop1 - delta)
        let maxDelta = min(stripTop1, maxScrollDeltaPerFrame)
        guard maxDelta > 0 else { return 0 }

        for delta in 1...maxDelta {
            let stripTop2 = stripTop1 - delta
            if stripTop2 < 0 { break }

            let diff = calculateStripDifference(
                data1: data1, top1: stripTop1,
                data2: data2, top2: stripTop2,
                stripHeight: stripHeight, width: pixelWidth, bpr: bpr, step: 6
            )

            if diff < minDiff {
                minDiff = diff
                bestDelta = delta
            }
        }

        // 3. If a confident match is found, append newly revealed bottom rows
        if minDiff < 12.0 && bestDelta >= 2 {
            // Guard against excessive page length (e.g. max 40,000 pixels)
            if stitchedRows.count >= 40000 {
                return 0
            }

            let startRow = height - bestDelta
            for r in startRow..<height {
                let start = r * bpr
                let end = start + bpr
                if end <= data2.count {
                    stitchedRows.append(data2.subdata(in: start..<end))
                }
            }

            totalHeight = stitchedRows.count
            lastFrame = frame
            return bestDelta
        }

        return 0
    }

    /// Assembles all stitched rows into a final NSImage at native Retina resolution
    public func generateFinalImage() -> NSImage? {
        guard !stitchedRows.isEmpty, pixelWidth > 0 else { return nil }

        let finalHeight = stitchedRows.count
        var fullData = Data(capacity: finalHeight * bytesPerRow)
        for row in stitchedRows {
            fullData.append(row)
        }

        guard let provider = CGDataProvider(data: fullData as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let cgImage = CGImage(
            width: pixelWidth,
            height: finalHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        let ptWidth = CGFloat(pixelWidth) / scaleFactor
        let ptHeight = CGFloat(finalHeight) / scaleFactor
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ptWidth, height: ptHeight))
        return nsImage
    }

    // MARK: - Internal Pixel Math

    private func findBestContrastStrip(data: Data, height: Int, width: Int, bytesPerRow: Int) -> Int {
        var bestRow = height / 2
        var maxVariance = -1.0

        // Search candidate strips between 35% and 80% of image height
        let minRow = Int(Double(height) * 0.35)
        let maxRow = Int(Double(height) * 0.80)

        for r in stride(from: minRow, to: maxRow, by: 12) {
            let v = computeStripVariance(data: data, startRow: r, height: stripHeight, bytesPerRow: bytesPerRow, width: width)
            if v > maxVariance {
                maxVariance = v
                bestRow = r
            }
        }

        return bestRow
    }

    private func computeStripVariance(data: Data, startRow: Int, height: Int, bytesPerRow: Int, width: Int) -> Double {
        var sum: Double = 0
        var sumSq: Double = 0
        var count: Double = 0

        for r in 0..<height {
            let offset = (startRow + r) * bytesPerRow
            for x in stride(from: 0, to: width * 4, by: 8) {
                if offset + x + 2 < data.count {
                    let r = Double(data[offset + x])
                    let g = Double(data[offset + x + 1])
                    let b = Double(data[offset + x + 2])
                    let lum = r * 0.299 + g * 0.587 + b * 0.114
                    sum += lum
                    sumSq += lum * lum
                    count += 1
                }
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        return (sumSq / count) - (mean * mean)
    }

    private func calculateStripDifference(
        data1: Data, top1: Int,
        data2: Data, top2: Int,
        stripHeight: Int, width: Int, bpr: Int, step: Int
    ) -> Double {
        var diff: Double = 0
        var samples: Double = 0

        for r in 0..<stripHeight {
            let row1 = (top1 + r) * bpr
            let row2 = (top2 + r) * bpr

            for x in stride(from: 0, to: width * 4, by: step * 4) {
                if row1 + x + 2 < data1.count && row2 + x + 2 < data2.count {
                    let dr = abs(Double(data1[row1 + x]) - Double(data2[row2 + x]))
                    let dg = abs(Double(data1[row1 + x + 1]) - Double(data2[row2 + x + 1]))
                    let db = abs(Double(data1[row1 + x + 2]) - Double(data2[row2 + x + 2]))
                    diff += (dr + dg + db)
                    samples += 3
                }
            }
        }

        return samples > 0 ? diff / samples : Double.infinity
    }
}
