import SwiftUI

struct OctaveScreen: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var settings = OctaveSettings()

    private var unit: String { audio.isCalibrated ? "dB SPL" : "dBFS" }
    private var yMax: Float { audio.isCalibrated ? 120 : 0 }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                readout("L\(settings.slow ? "S" : "F")", audio.octaveFrame?.overallDB)
                readout("Leq", audio.octaveFrame?.overallLeqDB)
                Text("\(unit)(\(settings.weighting.rawValue))").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            OctaveChart(frame: audio.octaveFrame, yMax: yMax, yMin: yMax - 100)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(OctaveResolution.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Picker("Weighting", selection: $settings.weighting) {
                        ForEach(Weighting.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Time", selection: $settings.slow) {
                        Text("Fast").tag(false)
                        Text("Slow").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button("Reset Leq / Max") { audio.resetOctaveIntegration() }
                        .buttonStyle(.glass)
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.horizontal)
        }
        .padding(.top)
        .onChange(of: settings) { _, new in audio.applyOctave(new) }
    }

    private func readout(_ title: String, _ value: Float?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? -120, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct OctaveChart: View {
    let frame: OctaveFrame?
    let yMax: Float
    let yMin: Float
    private let labelHeight: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let plotH = size.height - labelHeight
            func y(_ db: Float) -> CGFloat {
                CGFloat(min(max((yMax - db) / (yMax - yMin), 0), 1)) * plotH
            }

            var grid = Path()
            var db = yMin
            while db <= yMax {
                grid.move(to: CGPoint(x: 0, y: y(db)))
                grid.addLine(to: CGPoint(x: size.width, y: y(db)))
                ctx.draw(Text("\(Int(db))").font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: 2, y: y(db) - 2), anchor: .bottomLeading)
                db += 20
            }
            ctx.stroke(grid, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)

            guard let frame, !frame.centers.isEmpty else { return }
            let n = frame.centers.count
            let slot = size.width / CGFloat(n)
            let barW = slot * 0.72
            for i in 0..<n {
                let x = CGFloat(i) * slot + (slot - barW) / 2
                let top = y(frame.levelsDB[i])
                ctx.fill(Path(roundedRect: CGRect(x: x, y: top, width: barW, height: plotH - top),
                              cornerRadius: 2),
                         with: .color(.accentColor.opacity(0.85)))
                if frame.maxDB[i] > -190 {
                    let my = y(frame.maxDB[i])
                    ctx.fill(Path(CGRect(x: x, y: my, width: barW, height: 2)),
                             with: .color(.primary.opacity(0.7)))
                }
                if n <= 12 || i % 3 == 0 {
                    ctx.draw(Text(frame.labels[i]).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x + barW / 2, y: size.height - 1), anchor: .bottom)
                }
            }
        }
    }
}
