import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var features: FeatureRegistry
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features.ordered()) { (feature: Feature) in
                Button {
                    if !WindowCoordinator.shared.focus(id: feature.id.rawValue) {
                        openWindow(id: feature.id.rawValue)
                    }
                } label: {
                    HStack {
                        Text(verbatim: feature.title)
                        Spacer()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(16)
        .frame(width: 360, height: 340)
    }
}

