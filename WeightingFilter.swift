import Foundation

/// Time-domain A / C frequency weighting (IEC 61672 pole/zero definition).
/// Cascade of first-order sections (bilinear transform with prewarped corners), double precision,
/// normalized to exactly 0 dB at 1 kHz. Z weighting is a pass-through.
/// Not thread-safe: use from a single serial queue.
final class WeightingFilter {
    private struct Section { var b0: Double; var b1: Double; var a1: Double; var z = 0.0 }

    let weighting: Weighting
    let sampleRate: Double
    private var sections: [Section] = []
    private var gain = 1.0

    init(_ weighting: Weighting, sampleRate fs: Double) {
        self.weighting = weighting
        self.sampleRate = fs
        guard weighting != .z else { return }

        let c = 2 * fs
        func corner(_ f: Double) -> Double { c * tan(Double.pi * f / fs) }
        func highPass(_ f: Double) -> Section {
            let w = corner(f), d = c + w
            return Section(b0: c / d, b1: -c / d, a1: (w - c) / d)
        }
        func lowPass(_ f: Double) -> Section {
            let w = corner(f), d = c + w
            return Section(b0: w / d, b1: w / d, a1: (w - c) / d)
        }
        let f1 = 20.598997, f2 = 107.65265, f3 = 737.86223, f4 = 12194.217
        switch weighting {
        case .a: sections = [highPass(f1), highPass(f1), highPass(f2), highPass(f3), lowPass(f4), lowPass(f4)]
        case .c: sections = [highPass(f1), highPass(f1), lowPass(f4), lowPass(f4)]
        case .z: break
        }
        gain = 1 / rawMagnitude(at: 1000)
    }

    private func rawMagnitude(at f: Double) -> Double {
        let w = 2 * Double.pi * f / sampleRate
        var m = 1.0
        for s in sections {
            let nr = s.b0 + s.b1 * cos(w), ni = -s.b1 * sin(w)
            let dr = 1 + s.a1 * cos(w), di = -s.a1 * sin(w)
            m *= hypot(nr, ni) / hypot(dr, di)
        }
        return m
    }

    /// Magnitude response in dB (for tests and display).
    func responseDB(at f: Double) -> Double { 20 * log10(gain * rawMagnitude(at: f)) }

    @inline(__always)
    func process(_ x: Double) -> Double {
        var y = x
        for i in sections.indices {
            let out = sections[i].b0 * y + sections[i].z
            sections[i].z = sections[i].b1 * y - sections[i].a1 * out
            y = out
        }
        return y * gain
    }
}
