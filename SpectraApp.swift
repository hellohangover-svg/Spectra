import SwiftUI

@main
struct SpectraApp: App {
    @State private var audio = AudioEngineManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audio)
                .task { await audio.start() }
        }
    }
}

struct ContentView: View {
    @Environment(AudioEngineManager.self) private var audio

    var body: some View {
        TabView {
            Tab("Meter", systemImage: "gauge.with.dots.needle.67percent") { MeterScreen() }
            Tab("Spectrum", systemImage: "waveform") { SpectrumScreen() }
            Tab("Octave", systemImage: "chart.bar") { OctaveScreen() }
            Tab("Scope", systemImage: "waveform.path.ecg") { ScopeScreen() }
            Tab("Spectrogram", systemImage: "square.grid.3x3.fill") { SpectrogramScreen() }
            Tab("Generator", systemImage: "dial.medium") { GeneratorScreen() }
            Tab("Calibrate", systemImage: "ruler") { CalibrationScreen() }
        }
        // Keep the screen awake while measuring.
        .onChange(of: audio.isRunning, initial: true) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }
}
