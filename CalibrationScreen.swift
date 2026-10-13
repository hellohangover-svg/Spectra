import SwiftUI

struct CalibrationScreen: View {
    @Environment(AudioEngineManager.self) private var audio

    var body: some View {
        VStack(spacing: 16) {
            Text("Place a 94 dB SPL, 1 kHz acoustic calibrator on the microphone, wait for the reading to settle, then tap Calibrate.")
                .multilineTextAlignment(.center)
            Text(audio.meterFrame?.lpDB ?? audio.overallDB, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(String(format: "Offset: %+.1f dB", audio.calibrationOffsetDB))
                .foregroundStyle(.secondary)
            HStack {
                Button("Calibrate to 94 dB") { audio.calibrate(toSPL: 94) }
                    .buttonStyle(.glassProminent)
                Button("Clear") { audio.clearCalibration() }
                    .buttonStyle(.glass)
            }
            Text("Built-in microphones are not measurement-grade. For traceable results use a calibrated external microphone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
