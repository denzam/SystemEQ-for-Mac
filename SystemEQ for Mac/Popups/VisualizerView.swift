import SwiftUI

struct VisualizerView: View {
    @State private var style: String = "Spectrum"
    @State private var intensity: Double = 0.7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visualizer").font(.title)
            Text("Style • Colors • Sensitivity")
                .foregroundStyle(.secondary)
            Picker("Style", selection: $style) {
                Text("Spectrum").tag("Spectrum")
                Text("Waveform").tag("Waveform")
                Text("Particles").tag("Particles")
                Text("Psychedelic").tag("Psychedelic")
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("Intensity")
                Slider(value: $intensity, in: 0...1)
            }
            Rectangle().fill(Color.black.opacity(0.85)).overlay(Text("Preview").foregroundColor(.white))
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
    }
}

