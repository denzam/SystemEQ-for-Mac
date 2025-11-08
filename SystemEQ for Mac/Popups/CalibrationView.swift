import SwiftUI

struct CalibrationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration").font(.title)
            Text("Room + Hearing Test + Profiles/A-B")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 600)
    }
}

