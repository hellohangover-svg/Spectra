import SwiftUI

struct GeneratorScreen: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var kind: SignalGenerator.Kind = .off
    @State private var frequency = 1000.0
    @State private var level = -30.0

    var body: some View {
        VStack(spacing: 20) {
            Picker("Signal", selection: $kind) {
                ForEach(SignalGenerator.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("Frequency: \(Int(frequency)) Hz")
                Slider(value: Binding(get: { log10(frequency) },
                                      set: { frequency = pow(10, $0) }),
                       in: log10(20)...log10(20_000))
                    .disabled(kind != .sine)
                Text("Level: \(Int(level)) dBFS (max \(Int(SignalGenerator.maxLevelDB)))")
                Slider(value: $level, in: -80...SignalGenerator.maxLevelDB)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Spacer()
        }
        .padding()
        .onChange(of: kind) { _, v in audio.generator.kind = v }
        .onChange(of: frequency) { _, v in audio.generator.frequency = v }
        .onChange(of: level) { _, v in audio.generator.levelDB = v }
    }
}
