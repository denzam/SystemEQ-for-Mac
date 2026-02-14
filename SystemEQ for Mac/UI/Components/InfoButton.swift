import SwiftUI

/// Info button with popover help text
struct InfoButton: View {
    let title: String
    let content: String
    @State private var showInfo = false

    var body: some View {
        Button(action: {
            showInfo = true
        }) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Learn more")
        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text(title)
                    .font(.headline)

                Divider()

                // Content
                Text(content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Close button
                HStack {
                    Spacer()
                    Button("Got it") {
                        showInfo = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .frame(width: 300)
            .padding()
        }
    }
}

/// Info button with markdown support
struct InfoButtonMarkdown: View {
    let title: String
    let sections: [(String, String)] // [(heading, content)]
    @State private var showInfo = false

    var body: some View {
        Button(action: {
            showInfo = true
        }) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Learn more")
        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Divider()

                    // Sections
                    ForEach(sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sections[index].0)
                                .font(.headline)

                            Text(sections[index].1)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Close button
                    HStack {
                        Spacer()
                        Button("Got it") {
                            showInfo = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .frame(width: 350, height: 400)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack {
            Button("Enable EQ") {}
                .buttonStyle(.borderedProminent)

            InfoButton(
                title: "Enable EQ",
                content: """
                Routes system audio through EQ processing.

                What happens:
                • System Output → BlackHole
                • CoreAudioEngine starts
                • Audio flows through EQ

                Requirements:
                • BlackHole installed
                • SystemEQ running
                """
            )
        }

        HStack {
            Button("Quick Import") {}
                .buttonStyle(.bordered)

            InfoButtonMarkdown(
                title: "Quick Import",
                sections: [
                    ("What it does", "Instantly loads EQ preset for your headphones from database"),
                    ("How to use", "1. Type headphone name\n2. Click Quick Import\n3. Done!"),
                    ("Database", "2,347 models\n8,850 presets\n100% offline")
                ]
            )
        }
    }
    .padding()
}
