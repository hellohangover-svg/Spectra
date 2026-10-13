import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor
enum Exporter {
    private static func tempURL(_ ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("Spectra-\(f.string(from: Date())).\(ext)")
    }

    private static func num(_ v: Float) -> String { String(format: "%.2f", v) }

    static func csv(_ audio: AudioEngineManager) -> URL? {
        var s = "Spectra export\n"
        s += "date,\(ISO8601DateFormatter().string(from: Date()))\n"
        s += "unit,\(audio.isCalibrated ? "dB SPL" : "dBFS")\n"
        s += "calibration offset dB,\(num(audio.calibrationOffsetDB))\n\n"

        if let m = audio.meterFrame {
            s += "Level meter\n"
            s += "weighting,time weighting,Lp,Leq,Lmax,Lmin,Lpeak,L10,L50,L90,elapsed s\n"
            s += "\(m.weighting.rawValue),\(m.slow ? "Slow" : "Fast"),\(num(m.lpDB)),\(num(m.leqDB)),"
            s += "\(num(m.maxDB)),\(num(m.minDB)),\(num(m.peakDB)),\(num(m.l10)),\(num(m.l50)),"
            s += "\(num(m.l90)),\(String(format: "%.1f", m.elapsed))\n\n"
        }
        if let o = audio.octaveFrame {
            s += "Octave bands\ncenter Hz,label,level (time-weighted),Leq,Lmax\n"
            for i in o.centers.indices {
                s += "\(String(format: "%.2f", o.centers[i])),\(o.labels[i]),\(num(o.levelsDB[i])),"
                s += "\(num(o.leqDB[i])),\(num(o.maxDB[i]))\n"
            }
            s += "\n"
        }
        if let f = audio.frame {
            s += "Spectrum\nfrequency Hz,level,peak hold\n"
            for k in 1..<f.levelsDB.count {
                let hz = Double(k) * f.binWidth
                if hz < 20 || hz > 20_000 { continue }
                s += "\(String(format: "%.2f", hz)),\(num(f.levelsDB[k])),\(num(f.peakDB[k]))\n"
            }
        }
        let url = tempURL("csv")
        do { try s.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }

    static func spectrumImage(frame: SpectrumFrame?, yMax: Float, yMin: Float, unit: String) -> URL? {
        let content = SpectrumPlot(frame: frame, yMax: yMax, yMin: yMin, unit: unit)
            .frame(width: 1200, height: 600)
            .padding(24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        let url = tempURL("png")
        do { try data.write(to: url) } catch { return nil }
        return url
    }
}

struct ExportMenu: View {
    @Environment(AudioEngineManager.self) private var audio
    @State private var item: ShareItem?
    var image: (() -> URL?)? = nil

    var body: some View {
        Menu {
            Button("Export CSV", systemImage: "tablecells") {
                if let url = Exporter.csv(audio) { item = ShareItem(url: url) }
            }
            if let image {
                Button("Export image", systemImage: "photo") {
                    if let url = image() { item = ShareItem(url: url) }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.glass)
        .sheet(item: $item) { ShareSheet(url: $0.url) }
    }
}
