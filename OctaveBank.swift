import Foundation

enum OctaveResolution: String, CaseIterable, Identifiable, Sendable {
    case full = "1/1"
    case third = "1/3"
    var id: String { rawValue }
    var bandsPerOctave: Int { self == .full ? 1 : 3 }
}

struct OctaveSettings: Equatable, Sendable {
    var resolution: OctaveResolution = .third
    var weighting: Weighting = .z
    var slow: Bool = false
    var timeConstant: Double { slow ? 1.0 : 0.125 }
}

struct OctaveFrame: Sendable {
    var centers: [Double]
    var labels: [String]
    var levelsDB: [Float]   // exponentially time-weighted (Fast / Slow)
    var leqDB: [Float]      // equivalent continuous level since last reset
    var maxDB: [Float]      // maximum time-weighted level since last reset
    var overallDB: Float    // sum of weighted bands, time-weighted
    var overallLeqDB: Float
}

/// Fractional-octave filter bank: base-10 band layout (IEC 61260-1), 6th-order Butterworth
/// band-pass per band (3 biquads, double precision), mean-square detector with exponential
/// time weighting plus Leq / Lmax integration.
/// Not thread-safe: use from a single serial queue.
final class OctaveBank {
    struct Biquad { var b0: Double; var a1: Double; var a2: Double } // b1 = 0, b2 = -b0

    private final class Band {
        let center: Double
        let label: String
        let sections: [Biquad]
        var s1: [Double], s2: [Double]
        var ms = 0.0, sumSq = 0.0, maxMS = 0.0
        var count = 0
        init(center: Double, label: String, sections: [Biquad]) {
            self.center = center
            self.label = label
            self.sections = sections
            s1 = [Double](repeating: 0, count: sections.count)
            s2 = s1
        }
        func run(_ x: [Double], alpha: Double, warmup: Int) {
            let n = sections.count
            for v in x {
                var y = v
                for i in 0..<n {
                    let c = sections[i]
                    let out = c.b0 * y + s1[i]
                    s1[i] = s2[i] - c.a1 * out
                    s2[i] = -c.b0 * y - c.a2 * out
                    y = out
                }
                let p = y * y
                ms += alpha * (p - ms)
                sumSq += p
                count += 1
                if count > warmup && ms > maxMS { maxMS = ms }
            }
        }
        func resetIntegration() { sumSq = 0; count = 0; maxMS = 0 }
    }

    let resolution: OctaveResolution
    let sampleRate: Double
    var timeConstant: Double { didSet { alpha = OctaveBank.alpha(timeConstant, sampleRate) } }
    private var alpha: Double
    private let bands: [Band]

    private static let labels3 = ["20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160", "200",
                                  "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k", "2k",
                                  "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k", "20k"]
    private static let labels1 = ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private static func alpha(_ tau: Double, _ fs: Double) -> Double { 1 - exp(-1 / (fs * tau)) }

    init(resolution: OctaveResolution, sampleRate: Double, timeConstant: Double = 0.125) {
        self.resolution = resolution
        self.sampleRate = sampleRate
        self.timeConstant = timeConstant
        self.alpha = OctaveBank.alpha(timeConstant, sampleRate)

        let b = resolution.bandsPerOctave
        let indices = b == 3 ? Array(-17...13) : Array(-5...4)
        let names = b == 3 ? OctaveBank.labels3 : OctaveBank.labels1
        let g = pow(10.0, 0.3)
        var made: [Band] = []
        for (i, x) in indices.enumerated() {
            let fm = 1000 * pow(g, Double(x) / Double(b))
            let upper = fm * pow(g, 1 / (2 * Double(b)))
            guard upper < sampleRate / 2 else { continue } // band would reach Nyquist
            let sections = OctaveBank.design(centerHz: fm, bandsPerOctave: b, sampleRate: sampleRate)
            made.append(Band(center: fm, label: names[i], sections: sections))
        }
        bands = made
    }

    func process(_ input: [Float]) {
        let x = input.map(Double.init)
        let warmup = Int(sampleRate) // ignore Lmax during the first second after a reset
        for band in bands { band.run(x, alpha: alpha, warmup: warmup) }
    }

    func resetIntegration() { bands.forEach { $0.resetIntegration() } }

    func snapshot(weighting: Weighting, calibrationOffsetDB: Float) -> OctaveFrame {
        func db(_ ms: Double) -> Float { 10 * log10f(Float(ms) + 1e-20) + calibrationOffsetDB }
        var overallMS = 0.0, overallLeqMS = 0.0
        var levels: [Float] = [], leq: [Float] = [], mx: [Float] = []
        for band in bands {
            let w = pow(10, weighting.gainDB(at: band.center) / 10)
            let leqMS = band.count > 0 ? band.sumSq / Double(band.count) : 0
            overallMS += band.ms * w
            overallLeqMS += leqMS * w
            levels.append(db(band.ms))
            leq.append(db(leqMS))
            mx.append(band.maxMS > 0 ? db(band.maxMS) : -200)
        }
        return OctaveFrame(centers: bands.map(\.center), labels: bands.map(\.label),
                           levelsDB: levels, leqDB: leq, maxDB: mx,
                           overallDB: db(overallMS), overallLeqDB: db(overallLeqMS))
    }

    // MARK: - Filter design

    private struct Cx {
        var re: Double, im: Double
        init(_ re: Double, _ im: Double) { self.re = re; self.im = im }
        static func + (a: Cx, b: Cx) -> Cx { Cx(a.re + b.re, a.im + b.im) }
        static func - (a: Cx, b: Cx) -> Cx { Cx(a.re - b.re, a.im - b.im) }
        static func * (a: Cx, b: Cx) -> Cx { Cx(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re) }
        static func * (a: Cx, k: Double) -> Cx { Cx(a.re * k, a.im * k) }
        static func / (a: Cx, b: Cx) -> Cx {
            let d = b.re * b.re + b.im * b.im
            return Cx((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
        }
        func sqrt() -> Cx {
            let r = hypot(re, im)
            let sr = Foundation.sqrt((r + re) / 2)
            let si = Foundation.sqrt(max((r - re) / 2, 0))
            return Cx(sr, im < 0 ? -si : si)
        }
    }

    /// Butterworth band-pass (order `order` low-pass prototype -> 2*order poles) via the
    /// band-pass transform with prewarped edges, then the bilinear transform. Returns `order`
    /// biquads, each with zeros at z = +1 and z = -1, normalized to unity gain at band center.
    static func design(centerHz fc: Double, bandsPerOctave b: Int, sampleRate fs: Double,
                       order n: Int = 3) -> [Biquad] {
        let g = pow(10.0, 0.3)
        let f1 = fc * pow(g, -1 / (2 * Double(b)))
        let f2 = fc * pow(g, 1 / (2 * Double(b)))
        let w1 = 2 * fs * tan(Double.pi * f1 / fs)
        let w2 = 2 * fs * tan(Double.pi * f2 / fs)
        let w0sq = w1 * w2
        let bw = w2 - w1

        var zPoles: [Cx] = []
        for k in 0..<n {
            let ang = Double.pi * Double(2 * k + n + 1) / Double(2 * n)
            let p = Cx(cos(ang), sin(ang))
            let bp = p * bw
            let disc = (bp * bp - Cx(4 * w0sq, 0)).sqrt()
            for sign in [1.0, -1.0] {
                let s = (bp + disc * sign) * 0.5
                let z = (Cx(2 * fs, 0) + s) / (Cx(2 * fs, 0) - s)
                if z.im > 1e-12 { zPoles.append(z) }
            }
        }
        var sections = zPoles.map { Biquad(b0: 1, a1: -2 * $0.re, a2: $0.re * $0.re + $0.im * $0.im) }

        // Unity gain at the band's digital center (peak of the Butterworth band-pass).
        let w = 2 * atan(sqrt(w0sq) / (2 * fs))
        var total = 1.0
        for s in sections {
            let numRe = 1 - cos(2 * w), numIm = sin(2 * w)
            let denRe = 1 + s.a1 * cos(w) + s.a2 * cos(2 * w)
            let denIm = -s.a1 * sin(w) - s.a2 * sin(2 * w)
            total *= hypot(numRe, numIm) / hypot(denRe, denIm)
        }
        let b0 = pow(1 / total, 1 / Double(sections.count))
        for i in sections.indices { sections[i].b0 = b0 }
        return sections
    }
}
