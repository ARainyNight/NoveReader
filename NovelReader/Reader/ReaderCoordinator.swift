import AppKit

@MainActor
final class ReaderCoordinator: NSObject {
    private weak var state: ReadingState?
    private weak var scroll: ReaderScrollView?
    private var saveTask: Task<Void, Never>?
    private var fileURL: URL?
    private var ready = false

    init(state: ReadingState) { self.state = state }

    func attach(_ scroll: ReaderScrollView) {
        self.scroll = scroll
        fileURL = state?.fileURL
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        state?.flushProgress = { [weak self] in self?.saveNow() }
        let position = fileURL.map { state?.progressStore.position(for: $0) ?? 0 } ?? 0
        scroll.didRestoreInitialPosition = { [weak self] in self?.ready = true }
        scroll.initialPosition = position
    }

    @objc private func didScroll() {
        guard ready else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard ready, let scroll, let fileURL else { return }
        state?.progressStore.savePosition(scroll.topCharacterIndex(), for: fileURL)
    }

    func detach() {
        saveNow()
        saveTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
