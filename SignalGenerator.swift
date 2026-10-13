import AVFoundation
import os

/// Test-signal source. Parameters live behind an unfair lock; the render callback copies them
/// once per buffer, so the lock is held only for a few nanoseconds.
final class SignalGenerator: @unchecked Sendable {
    enum Kind: String, CaseIterable, Identifiable {
        case off = "Off", sine = "Sine", white = "White noise", pink = "Pink noise"
        var id: String { rawValue }
    }

    private struct Params {
        var kind: Kind = .off
        var frequency = 1000.0
        var levelDB = -30.0
    }

    /// Hard output cap (dBFS) for hearing safety.
    static let maxLevelDB: Double = -6

    private let params = OSAllocatedUnfairLock(initialState: Params())

    var kind: Kind {
        get { params.withLock { $0.kind } }
        set { params.withLock { $0.kind = newValue } }
    }
    var frequency: Double {
        get { params.withLock { $0.frequency } }
        set { params.withLock { $0.frequency = newValue } }
    }
    var levelDB: Double {
        get { params.withLock { $0.levelDB } }
        set { params.withLock { $0.levelDB = newValue } }
    }

    // Audio-thread state
    private var phase = 0.0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0

    func makeNode(sampleRate: Double) -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        return AVAudioSourceNode(format: format) { [self] _, _, frameCount, audioBufferList in
            let p = params.withLock { $0 }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let gain = Float(pow(10, min(p.levelDB, Self.maxLevelDB) / 20))
            let step = 2 * Double.pi * p.frequency / sampleRate
            for frame in 0..<Int(frameCount) {
                var v: Float = 0
                switch p.kind {
                case .off:
                    v = 0
                case .sine:
                    v = Float(sin(phase)) * gain
                    phase += step
                    if phase > 2 * .pi { phase -= 2 * .pi }
                case .white:
                    v = Float.random(in: -1...1) * gain
                case .pink:
                    let w = Float.random(in: -1...1)
                    b0 = 0.99765 * b0 + w * 0.0990460
                    b1 = 0.96300 * b1 + w * 0.2965164
                    b2 = 0.57000 * b2 + w * 1.0526913
                    v = (b0 + b1 + b2 + w * 0.1848) * 0.11 * gain
                }
                for buf in abl {
                    buf.mData!.assumingMemoryBound(to: Float.self)[frame] = v
                }
            }
            return noErr
        }
    }
}
