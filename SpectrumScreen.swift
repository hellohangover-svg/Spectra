import SwiftUI

struct SpectrumScreen: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var settings = AnalyzerSettings()

    private var unit: String { audio.isCalibrated ? "dB SPL" : "dBFS" }
    private var yMax: Float { audio.isCalibrated ? 120 : 0 }

    /// Dominant spectral peak with parabolic interpolation for sub-bin frequency accuracy.
    private var dominant: (freq: Double, level: Float)? {
        guard let f = audio.frame, f.levelsDB.count > 4 else { return nil }
        var k = 1
        var best = f.levelsDB[1]
        for i in 2..<(f.levelsDB.count - 1) where f.levelsDB[i] > best {
            best = f.levelsDB[i]
            k = i
        }
        guard best > -150 else { return nil }
        if k <= 1 { return (Double(k) * f.binWidth, best) }
        let a = f.levelsDB[k - 1], b = f.levelsDB[k], c = f.levelsDB[k + 1]
        let denom = a - 2 * b + c
        let delta = denom == 0 ? 0 : 0.5 * (a - c) / denom
        return ((Double(k) + Double(delta)) * f.binWidth, b - 0.25 * (a - c) * delta)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let d = dominant {
                    Text(String(format: "%.1f", d.freq))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Hz").foregroundStyle(.secondary)
                    Text(String(format: "%.1f %@", d.level, unit))
                        .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("–").font(.system(size: 48, weight: .semibold, design: .rounded))
                }
                Spacer()
            }
            .padding(.horizontal)

            SpectrumPlot(frame: audio.frame, yMax: yMax, yMin: yMax - 100, unit: unit)
                .padding(.horizontal, 8)

            controls
        }
        .padding(.top)
        .onChange(of: settings) { _, new in audio.apply(new) }
        .overlay {
            if audio.permissionDenied {
                ContentUnavailableView("Microphone access needed",
                                       systemImage: "mic.slash",
                                       description: Text("Enable microphone access in Settings."))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Window", selection: $settings.window) {
                    ForEach(WindowType.allCases) { Text($0.rawValue).tag($0) }
                }
                Spacer()
                Button("Reset peaks") { audio.resetPeaks() }
                    .buttonStyle(.glass)
                ExportMenu(image: {
                    Exporter.spectrumImage(frame: audio.frame, yMax: yMax, yMin: yMax - 100, unit: unit)
                })
            }
            HStack {
                Text("Averaging").font(.caption)
                Slider(value: $settings.averaging, in: 0.02...1)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
    }
}

struct SpectrumPlot: View {
    let frame: SpectrumFrame?
    let yMax: Float
    let yMin: Float
    let unit: String
    @State private var cursorX: CGFloat?

    private let fMin = 20.0, fMax = 20_000.0
    private let gridFreqs: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawGrid(ctx, size)
                    guard let frame else { return }
                    ctx.stroke(path(frame.peakDB, frame.binWidth, size),
                               with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    ctx.stroke(path(frame.levelsDB, frame.binWidth, size),
                               with: .color(.accentColor), lineWidth: 1.5)
                }
                if let x = cursorX, let frame {
                    cursor(x: x, size: geo.size, frame: frame)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { cursorX = $0.location.x }
                .onEnded { _ in cursorX = nil })
        }
    }

    private func xPos(_ f: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((log10(f) - log10(fMin)) / (log10(fMax) - log10(fMin))) * w
    }

    private func freq(at x: CGFloat, _ w: CGFloat) -> Double {
        let t = Double(min(max(x / w, 0), 1))
        return pow(10, log10(fMin) + t * (log10(fMax) - log10(fMin)))
    }

    private func yPos(_ db: Float, _ h: CGFloat) -> CGFloat {
        CGFloat(min(max((yMax - db) / (yMax - yMin), 0), 1)) * h
    }

    private func path(_ data: [Float], _ binWidth: Double, _ size: CGSize) -> Path {
        var p = Path()
        var started = false
        for k in 1..<data.count {
            let f = Double(k) * binWidth
            if f < fMin { continue }
            if f > fMax { break }
            let pt = CGPoint(x: xPos(f, size.width), y: yPos(data[k], size.height))
            if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
        }
        return p
    }

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        var grid = Path()
        for f in gridFreqs {
            let x = xPos(f, size.width)
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            ctx.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: x + 2, y: size.height - 2), anchor: .bottomLeading)
        }
        var db = yMin
        while db <= yMax {
            let y = yPos(db, size.height)
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            ctx.draw(Text("\(Int(db))").font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: 2, y: y - 2), anchor: .bottomLeading)
            db += 20
        }
        ctx.stroke(grid, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)
    }

    @ViewBuilder
    private func cursor(x: CGFloat, size: CGSize, frame: SpectrumFrame) -> some View {
        let f = freq(at: x, size.width)
        let k = min(max(Int((f / frame.binWidth).rounded()), 1), frame.levelsDB.count - 1)
        Rectangle().fill(.primary.opacity(0.5)).frame(width: 1, height: size.height).offset(x: x)
        Text(String(format: "%.0f Hz  %.1f %@", Double(k) * frame.binWidth, frame.levelsDB[k], unit))
            .font(.caption.monospacedDigit())
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .offset(x: min(max(x - 70, 0), size.width - 160), y: 8)
    }
}
