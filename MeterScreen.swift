import SwiftUI

struct MeterScreen: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var settings = MeterSettings()

    private var unit: String { audio.isCalibrated ? "dB SPL" : "dBFS" }
    private var yMax: Float { audio.isCalibrated ? 120 : 0 }

    private func fmt(_ v: Float?) -> String {
        guard let v, v > -150 else { return "–" }
        return String(format: "%.1f", v)
    }

    var body: some View {
        let m = audio.meterFrame
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt(m?.lpDB))
                        .font(.system(size: 72, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading) {
                        Text("L\(settings.weighting.rawValue)\(settings.slow ? "S" : "F")")
                            .font(.title3.weight(.semibold))
                        Text(unit).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ExportMenu()
                }
                .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    stat("Leq", fmt(m?.leqDB))
                    stat("Lmax", fmt(m?.maxDB))
                    stat("Lmin", fmt(m?.minDB))
                    stat("Lpeak", fmt(m?.peakDB))
                    stat("L10", fmt(m?.l10))
                    stat("L50", fmt(m?.l50))
                    stat("L90", fmt(m?.l90))
                    stat("Time", m.map { String(format: "%.0f s", $0.elapsed) } ?? "–")
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal)

                MeterHistory(values: m?.history ?? [], yMax: yMax, yMin: yMax - 100)
                    .frame(height: 160)
                    .padding(.horizontal, 8)

                VStack(spacing: 10) {
                    HStack {
                        Picker("Weighting", selection: $settings.weighting) {
                            ForEach(Weighting.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Time", selection: $settings.slow) {
                            Text("Fast").tag(false)
                            Text("Slow").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Button("Reset Leq / Max / Min / statistics") { audio.resetMeter() }
                        .buttonStyle(.glass)
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .onChange(of: settings) { _, new in audio.applyMeter(new) }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
    }
}

struct MeterHistory: View {
    let values: [Float]
    let yMax: Float
    let yMin: Float

    var body: some View {
        Canvas { ctx, size in
            func y(_ db: Float) -> CGFloat {
                CGFloat(min(max((yMax - db) / (yMax - yMin), 0), 1)) * size.height
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

            guard values.count > 1 else { return }
            var p = Path()
            let step = size.width / 239 // 240 points = 60 s, newest on the right
            let offset = size.width - CGFloat(values.count - 1) * step
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: offset + CGFloat(i) * step, y: y(v))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(.accentColor), lineWidth: 1.5)
            ctx.draw(Text("60 s").font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: size.width - 2, y: size.height - 2), anchor: .bottomTrailing)
        }
    }
}
