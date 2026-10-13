import Accelerate
import Foundation

enum WindowType: String, CaseIterable, Identifiable, Sendable {
    case hann = "Hann"
    case blackman = "Blackman"
    case flatTop = "Flat-top"
    case rectangular = "Rectangular"
    var id: String { rawValue }
}

enum Weighting: String, CaseIterable, Identifiable, Sendable {
    case z = "Z", a = "A", c = "C"
    var id: String { rawValue }

    /// Analytic frequency weighting in dB (IEC 61672 formulas).
    func gainDB(at f: Double) -> Double {
        guard f > 0 else { return -200 }
        let f2 = f * f
        let c1 = 20.6 * 20.6, c2 = 107.7 * 107.7, c3 = 737.9 * 737.9, c4 = 12194.0 * 12194.0
        switch self {
        case .z:
            return 0
        case .a:
            let ra = (c4 * f2 * f2) / ((f2 + c1) * sqrt((f2 + c2) * (f2 + c3)) * (f2 + c4))
            return 20 * log10(ra) + 2.0
        case .c:
            let rc = (c4 * f2) / ((f2 + c1) * (f2 + c4))
            return 20 * log10(rc) + 0.06
        }
    }
}

struct AnalyzerSettings: Equatable, Sendable {
    var window: WindowType = .hann
    var weighting: Weighting = .a
    /// Exponential averaging coefficient per frame (1 = no averaging).
    var averaging: Float = 0.3
    /// false = Fast (125 ms), true = Slow (1 s)
    var slow: Bool = false
    var timeConstant: Double { slow ? 1.0 : 0.125 }
}

struct SpectrumFrame: Sendable {
    var levelsDB: [Float]      // per-bin, tone-accurate (RMS) level
    var peakDB: [Float]        // peak-hold trace
    var binWidth: Double       // Hz
    var overallDB: Float       // weighted, time-weighted broadband level
}

/// Not thread-safe: use from a single serial queue.
final class FFTAnalyzer {
    let size: Int
    let sampleRate: Double

    var windowType: WindowType = .hann { didSet { buildWindow(); reset() } }
    var weighting: Weighting = .a { didSet { buildWeightTable() } }
    var averaging: Float = 0.3
    var timeConstant: Double = 0.125
    /// dB added to dBFS so results read in dB SPL once calibrated.
    var calibrationOffsetDB: Float = 0

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float] = []
    private var cg: Float = 1       // coherent gain (tone accuracy)
    private var npg: Float = 1      // noise power gain (broadband accuracy)
    private var weightPower: [Float] = []
    private var avg: [Float]
    private var peak: [Float]
    private var smoothedMS: Float = 0

    init(size: Int, sampleRate: Double) {
        precondition(size > 8 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(size)).rounded())
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.avg = [Float](repeating: 0, count: size / 2)
        self.peak = [Float](repeating: 0, count: size / 2)
        buildWindow()
        buildWeightTable()
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func reset() {
        avg = [Float](repeating: 0, count: size / 2)
        peak = avg
        smoothedMS = 0
    }

    func resetPeaks() { peak = [Float](repeating: 0, count: size / 2) }

    func apply(_ s: AnalyzerSettings) {
        if windowType != s.window { windowType = s.window }
        if weighting != s.weighting { weighting = s.weighting }
        averaging = s.averaging
        timeConstant = s.timeConstant
    }

    private func buildWindow() {
        let coeffs: [Float]
        switch windowType {
        case .rectangular: coeffs = [1]
        case .hann: coeffs = [0.5, 0.5]
        case .blackman: coeffs = [0.42, 0.5, 0.08]
        case .flatTop: coeffs = [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368]
        }
        var w = [Float](repeating: 0, count: size)
        for i in 0..<size {
            let phase = 2 * Float.pi * Float(i) / Float(size)
            var v: Float = 0
            for (m, a) in coeffs.enumerated() {
                v += (m % 2 == 0 ? 1 : -1) * a * cos(Float(m) * phase)
            }
            w[i] = v
        }
        window = w
        cg = vDSP.mean(w)
        npg = vDSP.meanSquare(w)
    }

    private func buildWeightTable() {
        let df = sampleRate / Double(size)
        weightPower = (0..<size / 2).map { k in
            Float(pow(10, weighting.gainDB(at: Double(k) * df) / 10))
        }
    }

    func analyze(_ x: [Float], hop: Double) -> SpectrumFrame {
        precondition(x.count == size)
        let half = size / 2
        let windowed = vDSP.multiply(x, window)
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)

        windowed.withUnsafeBufferPointer { wp in
            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                re.withUnsafeMutableBufferPointer { rp in
                    im.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }
            }
        }
        mags[0] = 0 // bin 0 packs DC and Nyquist; excluded

        // zrip output is 2x the true DFT. Mean-square per bin (single-sided):
        //   tone-accurate:  |X|^2 * 2 / (N^2 * CG^2)  ->  mags / (2 N^2 CG^2)
        //   broadband:      mags / (2 N^2 NPG)
        let n2 = Float(size) * Float(size)
        let toneScale = 1 / (2 * n2 * cg * cg)
        let broadScale = 1 / (2 * n2 * npg)

        var broadMS: Float = 0
        for k in 1..<half {
            let tone = mags[k] * toneScale
            avg[k] += averaging * (tone - avg[k])
            peak[k] = max(peak[k], tone)
            broadMS += mags[k] * broadScale * weightPower[k]
        }

        let cal = calibrationOffsetDB
        var levels = [Float](repeating: -200, count: half)
        var peaks = levels
        for k in 1..<half {
            levels[k] = 10 * log10f(avg[k] + 1e-20) + cal
            peaks[k] = 10 * log10f(peak[k] + 1e-20) + cal
        }

        let alpha = Float(1 - exp(-hop / timeConstant))
        smoothedMS += alpha * (broadMS - smoothedMS)
        let overall = 10 * log10f(smoothedMS + 1e-20) + cal

        return SpectrumFrame(levelsDB: levels, peakDB: peaks,
                             binWidth: sampleRate / Double(size), overallDB: overall)
    }
}
