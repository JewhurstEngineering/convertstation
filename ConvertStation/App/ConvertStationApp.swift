import SwiftUI

@main
struct ConvertStationApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 960, minHeight: 720)
        }
        .defaultSize(width: 1240, height: 860)

        Settings {
            SettingsView(model: model)
                .frame(width: 540, height: 480)
        }
    }
}
