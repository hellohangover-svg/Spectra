import SwiftUI

struct ScopeScreen: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var windowMs = 20.0
    @State private var gain = 1.0
    @State private var trigger = 0.0
    @State private var triggerOn = true
    @State private var frozen: [Float]?

    private var samples: [Float] { frozen ?? audio.scopeSamples }

    /// Returns the visible window starting at a rising-edge trigger (or the start if none).
    private var visible: [Float] {
        let s = samples
        let n = max(Int(windowMs / 1000 * audio.inputSampleRate), 16)
        guard s.count > n else { return s }
        var start = 0
        if triggerOn {
            let level = Float(trigger)
            for i in 1..<(s.count - n) where s[i - 1] < level && s[i] >= level {
                start = i
                break
            }
        }
        return Array(s[start..<(start + n)])
    }

    var body: some View {
        let v = visible
        let peak = v.map { abs($0) }.max() ?? 0
        let rms = v.isEmpty ? 0 : sqrt(v.reduce(0) { $0 + $1 * $1 } / Float(v.count))

        VStack(spacing: 12) {
            HStack(spacing: 24) {
                readout("Peak", 20 * log10(max(peak, 1e-9)))
                readout("RMS", 20 * log10(max(rms, 1e-9)))
                Text("dBFS").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            ScopeTrace(samples: v, gain: Float(gain), trigger: Float(trigger), triggerOn: triggerOn)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                labeledSlider("Time/screen: \(Int(windowMs)) ms", value: $windowMs, range: 2...80)
                labeledSlider("Gain: x\(String(format: "%.1f", gain))", value: Binding(
                    get: { log2(gain) }, set: { gain = pow(2, $0) }), range: 0...5)
                HStack {
                    Toggle("Trigger", isOn: $triggerOn).fixedSize()
                    Slider(value: $trigger, in: -1...1).disabled(!triggerOn)
                    Button(frozen == nil ? "Freeze" : "Run") {
                        frozen = frozen == nil ? audio.scopeSamples : nil
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.horizontal)
        }
        .padding(.top)
    }

    private func readout(_ title: String, _ value: Float) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption)
            Slider(value: value, in: range)
        }
    }
}

struct ScopeTrace: View {
    let samples: [Float]
    let gain: Float
    let trigger: Float
    let triggerOn: Bool

    var body: some View {
        Canvas { ctx, size in
            var grid = Path()
            for i in 0...10 {
                let x = size.width * CGFloat(i) / 10
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for i in 0...8 {
                let y = size.height * CGFloat(i) / 8
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)

            let mid = size.height / 2
            func y(_ v: Float) -> CGFloat { mid - CGFloat(min(max(v * gain, -1), 1)) * mid }

            if triggerOn {
                var t = Path()
                t.move(to: CGPoint(x: 0, y: y(trigger)))
                t.addLine(to: CGPoint(x: size.width, y: y(trigger)))
                ctx.stroke(t, with: .color(.orange.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            guard samples.count > 1 else { return }
            var p = Path()
            let step = size.width / CGFloat(samples.count - 1)
            // Decimate to ~2 points per pixel, keeping min/max so peaks are never lost.
            let stride = max(samples.count / Int(max(size.width, 1) * 2), 1)
            var i = 0
            var first = true
            while i < samples.count {
                let end = min(i + stride, samples.count)
                let chunk = samples[i..<end]
                let lo = chunk.min()!, hi = chunk.max()!
                let x = CGFloat(i) * step
                if first { p.move(to: CGPoint(x: x, y: y(lo))); first = false }
                else { p.addLine(to: CGPoint(x: x, y: y(lo))) }
                p.addLine(to: CGPoint(x: x, y: y(hi)))
                i = end
            }
            ctx.stroke(p, with: .color(.accentColor), lineWidth: 1.5)
        }
    }
}
