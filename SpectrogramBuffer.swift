import CoreGraphics
import Foundation

/// Scrolling log-frequency waterfall rendered into an RGBA pixel buffer (newest row on top).
/// Not thread-safe: use from a single serial queue.
final class SpectrogramBuffer {
    static let columns = 256
    static let rows = 240

    private var pixels = [UInt32](repeating: 0xFF00_0000, count: columns * rows)
    private var columnBins: [(lo: Int, hi: Int)] = []
    private let lut: [UInt32]
    private let fMin = 20.0, fMax = 20_000.0

    init(sampleRate: Double, fftSize: Int) {
        let binWidth = sampleRate / Double(fftSize)
        let half = fftSize / 2
        let ratio = fMax / fMin
        columnBins = (0..<SpectrogramBuffer.columns).map { c in
            let f0 = fMin * pow(ratio, Double(c) / Double(SpectrogramBuffer.columns))
            let f1 = fMin * pow(ratio, Double(c + 1) / Double(SpectrogramBuffer.columns))
            let lo = min(max(Int((f0 / binWidth).rounded()), 1), half - 1)
            let hi = min(max(Int((f1 / binWidth).rounded()), lo), half - 1)
            return (lo, hi)
        }
        // black -> indigo -> magenta -> orange -> pale yellow
        let stops: [(Double, Double, Double)] = [(0, 0, 0), (35, 10, 100), (175, 30, 115),
                                                 (250, 140, 20), (255, 250, 190)]
        lut = (0..<256).map { i in
            let t = Double(i) / 255 * Double(stops.count - 1)
            let k = min(Int(t), stops.count - 2)
            let u = t - Double(k)
            func mix(_ a: Double, _ b: Double) -> UInt32 { UInt32((a + (b - a) * u).rounded()) }
            let r = mix(stops[k].0, stops[k + 1].0)
            let g = mix(stops[k].1, stops[k + 1].1)
            let b = mix(stops[k].2, stops[k + 1].2)
            return r | (g << 8) | (b << 16) | (0xFF << 24)
        }
    }

    /// `top` is the level mapped to the brightest color; `range` dB below it map to black.
    func push(levelsDB: [Float], top: Float, range: Float) {
        var row = [UInt32](repeating: 0, count: SpectrogramBuffer.columns)
        for (c, bins) in columnBins.enumerated() {
            var m: Float = -200
            for k in bins.lo...bins.hi where levelsDB[k] > m { m = levelsDB[k] }
            let t = min(max((m - (top - range)) / range, 0), 1)
            row[c] = lut[Int(t * 255)]
        }
        pixels.removeLast(SpectrogramBuffer.columns)
        pixels.insert(contentsOf: row, at: 0)
    }

    func makeImage() -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: SpectrogramBuffer.columns, height: SpectrogramBuffer.rows,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: SpectrogramBuffer.columns * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
