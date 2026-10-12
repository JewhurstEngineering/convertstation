import SwiftUI

struct FormatPicker: View {
    @Bindable var model: AppModel
    var job: ConversionJob

    var body: some View {
        let targets = model.targets(for: job)
        let current = targets.first { $0.id == job.profileID }
        Menu {
            if targets.isEmpty {
                Text("No formats for this file")
            } else {
                ForEach(OutputFamily.allCases) { family in
                    let group = targets.filter { $0.family == family }
                    if !group.isEmpty {
                        Section(family.title) {
                            ForEach(group) { target in
                                Button {
                                    model.selectProfile(target.id, for: job.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if target.id == job.profileID {
                                            Label(target.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(target.displayName)
                                        }
                                        Text(target.lossNotice)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(job.state.isActive)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(current?.displayName ?? "Output", systemImage: symbol(for: current?.family))
                .labelStyle(.titleAndIcon)
        }
        .help(current?.lossNotice ?? "Output format")
        .accessibilityLabel("Output format")
        .accessibilityValue(current?.displayName ?? "None")
        .disabled(targets.isEmpty || job.state.isActive)
    }

    private func symbol(for family: OutputFamily?) -> String {
        switch family {
        case .video: "film"
        case .animation: "play.rectangle"
        case .image: "photo"
        case .audio: "waveform"
        case .document: "doc.text"
        case nil: "square.and.arrow.down"
        }
    }
}
