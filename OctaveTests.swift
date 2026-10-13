import XCTest
@testable import Spectra

final class OctaveTests: XCTestCase {
    let fs = 48_000.0
    let expected: Float = -9.03 // 0.5 peak sine = 0.3536 RMS

    private func tone(_ f: Double, seconds: Double = 3, amp: Float = 0.5) -> [Float] {
        (0..<Int(seconds * fs)).map { amp * Float(sin(2 * Double.pi * f * Double($0) / fs)) }
    }

    private func run(_ f: Double, _ res: OctaveResolution) -> OctaveFrame {
        let bank = OctaveBank(resolution: res, sampleRate: fs, timeConstant: 0.125)
        bank.process(tone(f))
        return bank.snapshot(weighting: .z, calibrationOffsetDB: 0)
    }

    private func index(of center: Double, in frame: OctaveFrame) -> Int {
        frame.centers.firstIndex { abs($0 - center) < 1 }!
    }

    func testBandCounts() {
        let third = OctaveBank(resolution: .third, sampleRate: fs).snapshot(weighting: .z, calibrationOffsetDB: 0)
        let full = OctaveBank(resolution: .full, sampleRate: fs).snapshot(weighting: .z, calibrationOffsetDB: 0)
        XCTAssertEqual(third.centers.count, 31)
        XCTAssertEqual(full.centers.count, 10)
        XCTAssertEqual(third.centers.first!, 19.95, accuracy: 0.05)
        XCTAssertEqual(third.labels[index(of: 1000, in: third)], "1k")
    }

    func testThirdOctaveCenterBandLevel() {
        let f = run(1000, .third)
        let i = index(of: 1000, in: f)
        XCTAssertEqual(f.levelsDB[i], expected, accuracy: 0.2)
        XCTAssertEqual(f.leqDB[i], expected, accuracy: 0.15)
    }

    func testThirdOctaveRejection() {
        let f = run(1000, .third)
        let i = index(of: 1000, in: f)
        let c = f.levelsDB[i]
        XCTAssertLessThan(f.levelsDB[i - 1], c - 15)  // one band away: ~18 dB expected
        XCTAssertLessThan(f.levelsDB[i + 1], c - 15)
        XCTAssertLessThan(f.levelsDB[i - 2], c - 30)  // two bands away: ~37 dB expected
        XCTAssertLessThan(f.levelsDB[i + 2], c - 30)
    }

    func testBandEdgeIsMinusThreeDB() {
        let edge = 1000 / pow(pow(10.0, 0.3), 1.0 / 6.0)
        let f = run(edge, .third)
        let i = index(of: 1000, in: f)
        XCTAssertEqual(f.levelsDB[i], expected - 3.01, accuracy: 0.3)
    }

    func testFullOctaveRejection() {
        let f = run(1000, .full)
        let i = index(of: 1000, in: f)
        XCTAssertEqual(f.levelsDB[i], expected, accuracy: 0.2)
        XCTAssertLessThan(f.levelsDB[i - 1], f.levelsDB[i] - 15)
        XCTAssertLessThan(f.levelsDB[i + 1], f.levelsDB[i] - 15)
    }

    func testLowBandIsStableAndAccurate() {
        let bank = OctaveBank(resolution: .third, sampleRate: fs, timeConstant: 0.125)
        bank.process(tone(25.12, seconds: 6)) // 25 Hz band center
        let f = bank.snapshot(weighting: .z, calibrationOffsetDB: 0)
        let i = index(of: 25.12, in: f)
        XCTAssertEqual(f.levelsDB[i], expected, accuracy: 0.3)
    }
}
