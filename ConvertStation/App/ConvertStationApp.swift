import AppKit
import SwiftUI

@main
struct ConvertStationApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 960, minHeight: 720)
                .onAppear(perform: AppIcon.install)
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(before: .toolbar) {
                ForEach(Array(LayoutMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button("Show as \(mode.title)") { model.setLayoutMode(mode) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 560)
                .frame(minHeight: 560)
                .onAppear(perform: AppIcon.install)
        }
    }
}

enum AppIcon {
    /// The menu bar uses a tiny slice of the app icon. Those slices were a blurry
    /// square. The mark is the logo itself, and AppKit scales it for the bar and the Dock.
    static func install() {
        guard let image = NSImage(named: "Mark") else { return }
        image.isTemplate = false
        NSApplication.shared.applicationIconImage = image
    }
}
