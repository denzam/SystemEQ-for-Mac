import SwiftUI

struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("eqEnabled") private var eqEnabled: Bool = true
    @AppStorage("outputGain") private var outputGain: Double = 0
    @AppStorage("presetName") private var preset: String = "Default"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable EQ", isOn: $eqEnabled)
            HStack {
                Text("Preset")
                Spacer()
                Picker("", selection: $preset) {
                    Text("Default").tag("Default")
                }
                .labelsHidden()
                .frame(width: 140)
            }
            VStack(alignment: .leading) {
                Text("Gain")
                Slider(value: $outputGain, in: -12...12, step: 0.5)
            }
            Button("Open Main Window") { openWindow(id: "main") }
        }
        .padding(12)
        .frame(width: 280)
    }
}

