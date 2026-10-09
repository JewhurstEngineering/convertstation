import AppKit
import QuickLookUI

final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    private let lock = NSLock()
    private var urls: [NSURL] = []

    @MainActor
    func show(_ url: URL) {
        lock.lock()
        urls = [url as NSURL]
        lock.unlock()
        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(url)
            return
        }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        lock.lock()
        defer { lock.unlock() }
        guard urls.indices.contains(index) else { return nil }
        return urls[index]
    }
}
