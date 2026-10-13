import XCTest
@testable import Spectra

final class DSPTests: XCTestCase {
    let n = 4096, fs = 48_000.0

    private func sine(_ f: Double, amp: Float) -> [Float] {
        (0..<n).map { amp * Float(sin(2 * Double.pi * f * Double($0) / fs)) }
    }

    func testBinCenteredSineLevelHann() {
        let a = FFTAnalyzer(size: n, sampleRate: fs)
        a.windowType = .hann
        a.averaging = 1
        let f = 350.0 * fs / Double(n)
        let frame = a.analyze(sine(f, amp: 0.5), hop: 0.02)
        // 0.5 peak = 0.3536 RMS = -9.03 dBFS
        XCTAssertEqual(frame.levelsDB.max()!, -9.03, accuracy: 0.1)
    }

    func testFlatTopOffBinAccuracy() {
        let a = FFTAnalyzer(size: n, sampleRate: fs)
        a.windowType = .flatTop
        a.averaging = 1
        let f = 350.5 * fs / Double(n) // worst-case scalloping position
        let frame = a.analyze(sine(f, amp: 0.5), hop: 0.02)
        XCTAssertEqual(frame.levelsDB.max()!, -9.03, accuracy: 0.1)
    }

    func testBroadbandLevelParseval() {
        let a = FFTAnalyzer(size: n, sampleRate: fs)
        a.windowType = .hann
        a.weighting = .a
        a.timeConstant = 0.125
        var frame = a.analyze(sine(1000, amp: 0.5), hop: 0.1)
        for _ in 0..<200 { frame = a.analyze(sine(1000, amp: 0.5), hop: 0.1) }
        // A-weighting is ~0 dB at 1 kHz
        XCTAssertEqual(frame.overallDB, -9.03, accuracy: 0.15)
    }

    func testWeightingCurves() {
        XCTAssertEqual(Weighting.a.gainDB(at: 1000), 0, accuracy: 0.1)
        XCTAssertEqual(Weighting.a.gainDB(at: 100), -19.1, accuracy: 0.2)
        XCTAssertEqual(Weighting.a.gainDB(at: 10_000), -2.5, accuracy: 0.2)
        XCTAssertEqual(Weighting.c.gainDB(at: 1000), 0, accuracy: 0.1)
    }
}
