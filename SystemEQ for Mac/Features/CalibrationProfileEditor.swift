import SwiftUI

struct CalibrationProfileEditor: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var draft: CalibrationProfileDraft
    @State private var saveFailed = false
    @State private var isSaving = false
    private let frequencies = EQBandMode.thirtyOneBand.frequencies
    private let save: (CalibrationProfile) async -> Bool
    private let cancel: () -> Void

    init(
        profile: CalibrationProfile,
        save: @escaping (CalibrationProfile) async -> Bool,
        cancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: CalibrationProfileDraft(profile))
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.editProfile))
                .font(.title2)
            TextField(localization.localized(.profileName), text: $draft.name)
                .textFieldStyle(.roundedBorder)
            TextField(localization.localized(.profileNotes), text: $draft.notes)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(draft.bandInputs.indices), id: \.self) { index in
                        HStack {
                            if frequencies.indices.contains(index) {
                                Text("\(frequencies[index].formatted(.number)) \(localization.localized(.frequencyHz))")
                            }
                            Spacer()
                            TextField(localization.localized(.gain), text: $draft.bandInputs[index])
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text(localization.localized(.dB))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            if saveFailed || draft.updatedProfile == nil {
                Text(localization.localized(.profileSaveFailed))
                    .foregroundColor(.red)
                    .font(.caption)
            }
            HStack {
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button(localization.localized(.cancel), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(localization.localized(.save)) {
                    guard !isSaving, let profile = draft.updatedProfile else { return }
                    isSaving = true
                    Task {
                        saveFailed = await !save(profile)
                        isSaving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.updatedProfile == nil)
            }
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .padding(24)
        .frame(width: 480, height: 600)
    }
}
