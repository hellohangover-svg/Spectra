import AVFoundation
import CoreGraphics
import Observation

@Observable
final class AudioEngineManager {
    // Published to the UI (main thread only)
    var frame: SpectrumFrame?
    var octaveFrame: OctaveFrame?
    var meterFrame: MeterFrame?
    var spectrogramImage: CGImage?
    var scopeSamples: [Float] = []
    var inputSampleRate = 48_000.0
    var overallDB: Float = -120
    var isRunning = false
    var permissionDenied = false
    var errorMessage: String?
    private(set) var calibrationOffsetDB: Float
    var isCalibrated: Bool { calibrationOffsetDB != 0 }

    @ObservationIgnored let generator = SignalGenerator()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var generatorNode: AVAudioSourceNode?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let dspQueue = DispatchQueue(label: "spectra.dsp", qos: .userInitiated)
    // Everything below is touched only on dspQueue.
    @ObservationIgnored private var analyzer: FFTAnalyzer?
    @ObservationIgnored private var octaveBank: OctaveBank?
    @ObservationIgnored private var meter: LevelMeter?
    @ObservationIgnored private var spectrogram: SpectrogramBuffer?
    @ObservationIgnored private var settings = AnalyzerSettings()
    @ObservationIgnored private var octaveSettings = OctaveSettings()
    @ObservationIgnored private var meterSettings = MeterSettings()
    @ObservationIgnored private var dspCalibration: Float = 0
    @ObservationIgnored private var sampleRate = 48_000.0
    @ObservationIgnored private var ring: [Float] = []
    @ObservationIgnored private var scopeRing: [Float] = []
    @ObservationIgnored private var samplesSinceFrame = 0
    @ObservationIgnored private var frameCounter = 0
    private let scopeLength = 8192
    private let fftSize = 4096
    private let hopSamples = 1024

    init() {
        calibrationOffsetDB = Float(UserDefaults.standard.double(forKey: "calibrationOffsetDB"))
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        registerObservers()
        runEngine()
    }

    private func runEngine() {
        do {
            try configureAndRun()
            errorMessage = nil
        } catch {
            isRunning = false
            errorMessage = error.localizedDescription
        }
    }

    private func configureAndRun() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement disables AGC and voice processing: essential for accurate levels.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        if let node = generatorNode { engine.detach(node); generatorNode = nil }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Spectra", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input is available."])
        }

        let a = FFTAnalyzer(size: fftSize, sampleRate: format.sampleRate)
        let cal = calibrationOffsetDB
        dspQueue.sync {
            a.calibrationOffsetDB = cal
            a.apply(settings)
            analyzer = a
            dspCalibration = cal
            sampleRate = format.sampleRate
            octaveBank = OctaveBank(resolution: octaveSettings.resolution,
                                    sampleRate: format.sampleRate,
                                    timeConstant: octaveSettings.timeConstant)
            meter = LevelMeter(settings: meterSettings, sampleRate: format.sampleRate)
            spectrogram = SpectrogramBuffer(sampleRate: format.sampleRate, fftSize: fftSize)
            ring.removeAll()
            scopeRing.removeAll()
            samplesSinceFrame = 0
            frameCounter = 0
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            self.dspQueue.async { self.ingest(samples) }
        }

        let node = generator.makeNode(sampleRate: format.sampleRate)
        generatorNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
        engine.prepare()
        try engine.start()
        inputSampleRate = format.sampleRate
        isRunning = true
    }

    private func registerObservers() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self.isRunning = false } else { self.restart() }
        })
        // Fires on route changes (headset, USB interface) and sample-rate changes.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                                        object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        })
    }

    private func restart() {
        engine.stop()
        isRunning = false
        runEngine()
    }

    // MARK: - Settings

    func apply(_ s: AnalyzerSettings) {
        dspQueue.async { [self] in
            settings = s
            analyzer?.apply(s)
        }
    }

    func applyOctave(_ s: OctaveSettings) {
        dspQueue.async { [self] in
            let rebuild = s.resolution != octaveSettings.resolution
            octaveSettings = s
            if rebuild {
                octaveBank = OctaveBank(resolution: s.resolution, sampleRate: sampleRate,
                                        timeConstant: s.timeConstant)
            } else {
                octaveBank?.timeConstant = s.timeConstant
            }
        }
    }

    /// Changing the weighting restarts the measurement (statistics belong to one weighting);
    /// changing only Fast/Slow keeps Leq, Lmax and statistics.
    func applyMeter(_ s: MeterSettings) {
        dspQueue.async { [self] in
            let rebuild = s.weighting != meterSettings.weighting
            meterSettings = s
            if rebuild {
                meter = LevelMeter(settings: s, sampleRate: sampleRate)
            } else {
                meter?.timeConstant = s.timeConstant
            }
        }
    }

    func resetPeaks() { dspQueue.async { [self] in analyzer?.resetPeaks() } }
    func resetOctaveIntegration() { dspQueue.async { [self] in octaveBank?.resetIntegration() } }
    func resetMeter() { dspQueue.async { [self] in meter?.reset() } }

    // MARK: - Calibration

    /// Call while a reference calibrator (e.g. 94 dB SPL at 1 kHz) is on the microphone.
    func calibrate(toSPL target: Float) {
        let reading = meterFrame?.lpDB ?? overallDB
        setOffset(target - (reading - calibrationOffsetDB))
    }

    func clearCalibration() { setOffset(0) }

    private func setOffset(_ value: Float) {
        calibrationOffsetDB = value
        UserDefaults.standard.set(Double(value), forKey: "calibrationOffsetDB")
        dspQueue.async { [self] in
            dspCalibration = value
            analyzer?.calibrationOffsetDB = value
            analyzer?.reset()
            meter?.reset()
            octaveBank?.resetIntegration()
        }
    }

    // MARK: - DSP (dspQueue)

    private func ingest(_ samples: [Float]) {
        guard let analyzer else { return }
        octaveBank?.process(samples)     // every sample goes through the filter bank
        meter?.process(samples)          // and through the sound level meter
        ring.append(contentsOf: samples)
        if ring.count > fftSize { ring.removeFirst(ring.count - fftSize) }
        scopeRing.append(contentsOf: samples)
        if scopeRing.count > scopeLength { scopeRing.removeFirst(scopeRing.count - scopeLength) }
        samplesSinceFrame += samples.count
        guard ring.count == fftSize, samplesSinceFrame >= hopSamples else { return }

        let hop = Double(samplesSinceFrame) / analyzer.sampleRate
        samplesSinceFrame = 0
        let result = analyzer.analyze(ring, hop: hop)
        frameCounter += 1

        var image: CGImage?
        if let spectrogram, frameCounter % 2 == 0 {
            spectrogram.push(levelsDB: result.levelsDB, top: dspCalibration != 0 ? 110 : -10, range: 80)
            image = spectrogram.makeImage()
        }
        let oct = octaveBank?.snapshot(weighting: octaveSettings.weighting, calibrationOffsetDB: dspCalibration)
        let met = meter?.snapshot(calibrationOffsetDB: dspCalibration)
        let scope = scopeRing
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frame = result
            self.octaveFrame = oct
            self.meterFrame = met
            self.scopeSamples = scope
            self.overallDB = result.overallDB
            if let image { self.spectrogramImage = image }
        }
    }
}
