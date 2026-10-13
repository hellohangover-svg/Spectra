import Foundation

struct MeterSettings: Equatable, Sendable {
    var weighting: Weighting = .a
    var slow: Bool = false
    var timeConstant: Double { slow ? 1.0 : 0.125 }
}

struct MeterFrame: Sendable {
    var weighting: Weighting
    var slow: Bool
    var lpDB: Float        // exponentially time-weighted level (Fast / Slow)
    var leqDB: Float       // equivalent continuous level since reset
    var maxDB: Float       // maximum time-weighted level since reset
    var minDB: Float       // minimum time-weighted level since reset
    var peakDB: Float      // maximum instantaneous |weighted signal| since reset
    var l10: Float         // level exceeded 10 % of the time
    var l50: Float
    var l90: Float
    var elapsed: Double    // seconds since reset
    var history: [Float]   // time-weighted level every 0.25 s, newest last
}

/// Time-domain sound level meter: weighting filter, Fast/Slow detector, Leq, Lmax/Lmin, peak,
/// statistical levels (L10/L50/L90 from a 0.5 dB histogram sampled every 100 ms) and a history trace.
/// Levels are uncalibrated dBFS internally; the calibration offset is added in `snapshot`.
/// Not thread-safe: use from a single serial queue.
final class LevelMeter {
    let sampleRate: Double
    let weighting: Weighting
    var timeConstant: Double { didSet { alpha = 1 - exp(-1 / (sampleRate * timeConstant)) } }
    let slow: Bool

    private let filter: WeightingFilter
    private var alpha: Double
    private var ms = 0.0, sumSq = 0.0, maxMS = 0.0, minMS = Double.infinity, peak = 0.0
    private var count = 0
    private var sinceStat = 0, sinceHistory = 0
    private let warmup: Int, statInterval: Int, historyInterval: Int

    private static let floorDB = -140.0, binDB = 0.5, binCount = 320
    private var histogram = [Int](repeating: 0, count: LevelMeter.binCount)
    private var histogramTotal = 0
    private var history: [Float] = []

    init(settings: MeterSettings, sampleRate: Double) {
        self.sampleRate = sampleRate
        self.weighting = settings.weighting
        self.slow = settings.slow
        self.timeConstant = settings.timeConstant
        self.filter = WeightingFilter(settings.weighting, sampleRate: sampleRate)
        self.alpha = 1 - exp(-1 / (sampleRate * settings.timeConstant))
        self.warmup = Int(sampleRate)                 // skip filter start-up in statistics
        self.statInterval = Int(sampleRate * 0.1)
        self.historyInterval = Int(sampleRate * 0.25)
    }

    private static func db(_ ms: Double) -> Double { 10 * log10(ms + 1e-20) }

    func process(_ input: [Float]) {
        for x in input {
            let y = filter.process(Double(x))
            let p = y * y
            ms += alpha * (p - ms)
            sumSq += p
            count += 1
            if count > warmup {
                let a = abs(y)
                if a > peak { peak = a }
                if ms > maxMS { maxMS = ms }
                if ms < minMS { minMS = ms }
            }
            sinceStat += 1
            if sinceStat >= statInterval {
                sinceStat = 0
                if count > warmup { addToHistogram(LevelMeter.db(ms)) }
            }
            sinceHistory += 1
            if sinceHistory >= historyInterval {
                sinceHistory = 0
                history.append(Float(LevelMeter.db(ms)))
                if history.count > 240 { history.removeFirst() }
            }
        }
    }

    /// Clears Leq, Lmax/Lmin, peak and statistics (filter and detector state are kept).
    func reset() {
        sumSq = 0; count = 0; maxMS = 0; minMS = .infinity; peak = 0
        histogram = [Int](repeating: 0, count: LevelMeter.binCount)
        histogramTotal = 0
        sinceStat = 0
    }

    private func addToHistogram(_ d: Double) {
        let i = Int(((d - LevelMeter.floorDB) / LevelMeter.binDB).rounded(.down))
        histogram[min(max(i, 0), LevelMeter.binCount - 1)] += 1
        histogramTotal += 1
    }

    /// Level exceeded `n` percent of the time.
    private func percentile(_ n: Double) -> Double {
        guard histogramTotal > 0 else { return -200 }
        let target = Double(histogramTotal) * n / 100
        var acc = 0.0
        for i in stride(from: LevelMeter.binCount - 1, through: 0, by: -1) {
            acc += Double(histogram[i])
            if acc >= target { return LevelMeter.floorDB + (Double(i) + 0.5) * LevelMeter.binDB }
        }
        return LevelMeter.floorDB
    }

    func snapshot(calibrationOffsetDB cal: Float) -> MeterFrame {
        func f(_ v: Double) -> Float { Float(v) + cal }
        let leq = count > 0 ? sumSq / Double(count) : 0
        return MeterFrame(
            weighting: weighting, slow: slow,
            lpDB: f(LevelMeter.db(ms)),
            leqDB: f(LevelMeter.db(leq)),
            maxDB: maxMS > 0 ? f(LevelMeter.db(maxMS)) : -200,
            minDB: minMS.isFinite ? f(LevelMeter.db(minMS)) : -200,
            peakDB: f(20 * log10(peak + 1e-10)),
            l10: f(percentile(10)), l50: f(percentile(50)), l90: f(percentile(90)),
            elapsed: Double(count) / sampleRate,
            history: history.map { $0 + cal })
    }
}
