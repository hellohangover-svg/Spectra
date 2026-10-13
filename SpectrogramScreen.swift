import SwiftUI

struct SpectrogramScreen: View {
    @Environment(AudioEngineManager.self) private var audio

    private var unit: String { audio.isCalibrated ? "dB SPL" : "dBFS" }
    private var top: Int { audio.isCalibrated ? 110 : -10 }
    private var seconds: Double {
        Double(SpectrogramBuffer.rows * 2 * 1024) / audio.inputSampleRate
    }
    private let ticks: [(Double, String)] = [(20, "20"), (100, "100"), (1000, "1k"), (10000, "10k"), (20000, "20k")]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Color.black
                if let img = audio.spectrogramImage {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                }
                Canvas { ctx, size in
                    for (f, label) in ticks {
                        let x = CGFloat(log10(f / 20) / 3) * size.width
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(line, with: .color(.white.opacity(0.18)), lineWidth: 0.5)
                        ctx.draw(Text(label).font(.caption2).foregroundStyle(.white.opacity(0.8)),
                                 at: CGPoint(x: min(max(x, 14), size.width - 14), y: size.height - 4),
                                 anchor: .bottom)
                    }
                    ctx.draw(Text("now").font(.caption2).foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: 6, y: 4), anchor: .topLeading)
                    ctx.draw(Text("-\(Int(seconds)) s").font(.caption2).foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: 6, y: size.height - 20), anchor: .bottomLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 8)

            Text("Color range: \(top - 80) to \(top) \(unit)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.top)
    }
}
