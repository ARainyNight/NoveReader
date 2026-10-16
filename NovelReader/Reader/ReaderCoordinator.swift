import AppKit

@MainActor
final class ReaderCoordinator: NSObject {
    private weak var state: ReadingState?
    private weak var scroll: ReaderScrollView?
    private var saveTask: Task<Void, Never>?
    private var fileURL: URL?
    private var ready = false
    private var handledJumpID: UUID?

    init(state: ReadingState) { self.state = state }

    func attach(_ scroll: ReaderScrollView) {
        self.scroll = scroll
        fileURL = state?.fileURL
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        state?.flushProgress = { [weak self] in self?.saveNow() }
        let position = fileURL.map { state?.progressStore.position(for: $0) ?? 0 } ?? 0
        scroll.didRestoreInitialPosition = { [weak self] in
            self?.ready = true
            self?.handleChapterJump()
        }
        scroll.initialPosition = position
    }

    func handleChapterJump() {
        guard ready, let state,
              let jump = state.chapterJump, jump.documentID == state.documentID,
              jump.id != handledJumpID else { return }
        handledJumpID = jump.id
        // Scroll after SwiftUI's view update so TextKit can establish its viewport first.
        DispatchQueue.main.async { [weak self] in
            guard let self, let state = self.state, let scroll = self.scroll, let fileURL = self.fileURL,
                  state.chapterJump?.id == jump.id, state.documentID == jump.documentID else { return }
            self.saveTask?.cancel()
            scroll.restorePosition(jump.offset)
            state.progressStore.savePosition(jump.offset, for: fileURL)
        }
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
        let visible = scroll.readerTextView.accessibilityVisibleCharacterRange()
        let jump = state?.chapterJump
        let position: Int
        if let jump, jump.documentID == state?.documentID, NSLocationInRange(jump.offset, visible) {
            position = jump.offset
        } else {
            position = scroll.topCharacterIndex()
        }
        state?.progressStore.savePosition(position, for: fileURL)
    }

    func detach() {
        saveNow()
        saveTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
