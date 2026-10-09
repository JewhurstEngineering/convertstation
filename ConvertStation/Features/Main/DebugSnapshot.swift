#if DEBUG
import AppKit

/// Debug builds only. Launch with `-DebugSnapshot name.png` (optionally
/// `-DebugWindowSize 1300x860` and `-layoutMode batch`) and the app writes its
/// window to its temporary folder, then quits. Lets layout be checked without
/// screen-recording permission.
enum DebugSnapshot {
    @MainActor
    static func scheduleIfRequested() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "DebugSnapshot") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
            if let size = defaults.string(forKey: "DebugWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
            }
            try? await Task.sleep(for: .seconds(defaults.double(forKey: "DebugSnapshotDelay") > 0 ? defaults.double(forKey: "DebugSnapshotDelay") : 3))
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSApp.terminate(nil)
        }
    }
}
#endif
