import SwiftUI

/// Built-in presets as pills, with the user's saved presets in a menu underneath.
struct PresetPicker: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    @State private var naming = false
    @State private var newName = ""

    private var options: WebPOptions { job.options }
    private var matched: SavedPreset? { model.savedPreset(matching: options) }
    private var isCustom: Bool { options.presetID == .custom }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedPills(options: PresetID.builtIn, selection: builtIn, title: \.shortTitle)
                .accessibilityLabel("Preset")
            HStack(spacing: 8) {
                savedMenu
                if isCustom, matched == nil {
                    Button("Save…") { beginSaving() }
                        .help("Save these settings as a preset")
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Save Preset", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { model.saveCustomPreset(named: newName, from: job.id) }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves \(SavedPreset(name: "", options: options).summary). A preset with the same name is replaced.")
        }
    }

    private var savedMenu: some View {
        Menu {
            if model.savedPresets.isEmpty {
                Text("No saved presets yet")
            }
            ForEach(model.savedPresets) { preset in
                Button {
                    model.applySavedPreset(preset, to: job.id)
                } label: {
                    if preset.id == matched?.id {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            Divider()
            Button("Save Current Settings…") { beginSaving() }
            if !model.savedPresets.isEmpty {
                Menu("Delete") {
                    ForEach(model.savedPresets) { preset in
                        Button(preset.name, role: .destructive) { model.deleteSavedPreset(preset.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: matched == nil ? "slider.horizontal.3" : "star.fill")
                    .foregroundStyle(isCustom ? Brand.blue : .secondary)
                Text(menuTitle)
                    .fontWeight(isCustom ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(isCustom ? Brand.blue.opacity(0.08) : Brand.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if isCustom {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Brand.blue.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("My presets")
        .accessibilityValue(menuTitle)
    }

    private var menuTitle: String {
        if let matched { return matched.name }
        if isCustom { return "Custom (not saved)" }
        return model.savedPresets.isEmpty ? "My Presets" : "My Presets (\(model.savedPresets.count))"
    }

    private var caption: String {
        SavedPreset(name: "", options: options).summary
    }

    private var builtIn: Binding<PresetID> {
        Binding(get: { options.presetID }, set: { model.applyPreset($0, to: job.id) })
    }

    private func beginSaving() {
        newName = matched?.name ?? ""
        naming = true
    }
}
