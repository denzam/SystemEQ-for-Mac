import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title)
            Text("General • Language • Links")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 500)
    }
}

