import XCTest
@testable import Spectra

final class WeightingFilterTests: XCTestCase {
    let fs = 48_000.0

    func testUnityAt1kHz() {
        for w in Weighting.allCases {
            XCTAssertEqual(WeightingFilter(w, sampleRate: fs).responseDB(at: 1000), 0, accuracy: 0.01)
        }
    }

    func testMatchesAnalyticCurve() {
        for w in [Weighting.a, .c] {
            let f = WeightingFilter(w, sampleRate: fs)
            for hz in [20.0, 31.5, 63, 125, 250, 500, 1000, 2000] {
                XCTAssertEqual(f.responseDB(at: hz), w.gainDB(at: hz), accuracy: 0.15, "\(w) \(hz) Hz")
            }
            // Bilinear warping grows toward Nyquist; stay inside 1 dB through 12.5 kHz.
            for hz in [4000.0, 8000, 10_000, 12_500] {
                XCTAssertEqual(f.responseDB(at: hz), w.gainDB(at: hz), accuracy: 1.0, "\(w) \(hz) Hz")
            }
        }
    }

    func testStreamingGainMatchesResponse() {
        let f = WeightingFilter(.a, sampleRate: fs)
        let n = Int(fs)
        var sumSq = 0.0
        for i in 0..<n {
            let y = f.process(sin(2 * Double.pi * 100 * Double(i) / fs))
            if i > n / 2 { sumSq += y * y }
        }
        let rmsDB = 10 * log10(sumSq / Double(n / 2 - 1) / 0.5) // relative to a unit sine
        XCTAssertEqual(rmsDB, f.responseDB(at: 100), accuracy: 0.1)
    }
}

final class LevelMeterTests: XCTestCase {
    let fs = 48_000.0

    private func tone(_ f: Double, seconds: Double, amp: Float) -> [Float] {
        (0..<Int(seconds * fs)).map { amp * Float(sin(2 * Double.pi * f * Double($0) / fs)) }
    }

    func testSteadyTone() {
        let meter = LevelMeter(settings: MeterSettings(weighting: .a, slow: false), sampleRate: fs)
        meter.process(tone(1000, seconds: 5, amp: 0.5))
        let m = meter.snapshot(calibrationOffsetDB: 0)
        XCTAssertEqual(m.lpDB, -9.03, accuracy: 0.1)
        XCTAssertEqual(m.leqDB, -9.03, accuracy: 0.1)
        XCTAssertEqual(m.peakDB, -6.02, accuracy: 0.2)
        XCTAssertEqual(m.l10, -9.03, accuracy: 0.5)
        XCTAssertEqual(m.l50, -9.03, accuracy: 0.5)
        XCTAssertEqual(m.l90, -9.03, accuracy: 0.5)
    }

    func testCalibrationOffsetIsApplied() {
        let meter = LevelMeter(settings: MeterSettings(), sampleRate: fs)
        meter.process(tone(1000, seconds: 3, amp: 0.5))
        XCTAssertEqual(meter.snapshot(calibrationOffsetDB: 103).lpDB, 103 - 9.03, accuracy: 0.1)
    }

    func testPercentilesSeeLevelChanges() {
        let meter = LevelMeter(settings: MeterSettings(), sampleRate: fs)
        meter.process(tone(1000, seconds: 8, amp: 0.5))    // loud
        meter.process(tone(1000, seconds: 3, amp: 0.05))   // quiet (-20 dB)
        let m = meter.snapshot(calibrationOffsetDB: 0)
        XCTAssertEqual(m.l10, -9.03, accuracy: 1.0)
        XCTAssertEqual(m.l90, -29.03, accuracy: 1.5)
        XCTAssertGreaterThan(m.l10, m.l50)
        XCTAssertGreaterThan(m.l50, m.l90)
        XCTAssertGreaterThan(m.maxDB, m.minDB + 15)
    }

    func testResetClearsIntegration() {
        let meter = LevelMeter(settings: MeterSettings(), sampleRate: fs)
        meter.process(tone(1000, seconds: 3, amp: 0.5))
        meter.reset()
        XCTAssertEqual(meter.snapshot(calibrationOffsetDB: 0).elapsed, 0, accuracy: 0.001)
    }
}
