import AppKit
import SwiftUI

struct TextReaderView: NSViewRepresentable {
    let text: String
    var fontSize: Double = 20
    var theme: ReaderTheme = .light
    @ObservedObject var state: ReadingState

    func makeCoordinator() -> ReaderCoordinator { ReaderCoordinator(state: state) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ReaderScrollView()
        scroll.load(text)
        scroll.applyFont(fontSize)
        scroll.applyTheme(theme)
        scroll.applyColors(foreground: state.foregroundColor, background: state.backgroundColor)
        context.coordinator.attach(scroll)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: ReaderCoordinator) {
        coordinator.detach()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll as? ReaderScrollView)?.applyFont(fontSize)
        (scroll as? ReaderScrollView)?.applyTheme(theme)
        (scroll as? ReaderScrollView)?.applyColors(foreground: state.foregroundColor, background: state.backgroundColor)
        context.coordinator.handleChapterJump()
    }
}

@MainActor
final class ReaderScrollView: NSScrollView {
    let readerTextView = NSTextView(usingTextLayoutManager: true)
    private var currentTheme: ReaderTheme?
    private var resizeAnchor: Int?
    private var resizeScheduled = false
    var initialPosition: Int? { didSet { needsLayout = true } }
    var didRestoreInitialPosition: (() -> Void)?

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        borderType = .noBorder
        let view = readerTextView
        view.isEditable = false
        view.isRichText = false
        view.allowsUndo = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: 12, height: 56)
        documentView = view
    }

    required init?(coder: NSCoder) { nil }

    func applyTheme(_ theme: ReaderTheme) {
        guard currentTheme != theme else { return }
        currentTheme = theme
        applyColors(foreground: theme.foreground, background: theme.background)
        appearance = NSAppearance(named: theme == .light ? .aqua : .darkAqua)
    }

    func applyColors(foreground: NSColor, background: NSColor) {
        if backgroundColor != background { backgroundColor = background }
        if readerTextView.backgroundColor != background { readerTextView.backgroundColor = background }
        if readerTextView.textColor != foreground { readerTextView.textColor = foreground }
    }

    func applyFont(_ size: Double) {
        guard readerTextView.font?.pointSize != CGFloat(size) else { return }
        let anchor = topCharacterIndex()
        readerTextView.font = .systemFont(ofSize: CGFloat(size))
        restorePosition(anchor)
    }

    func topCharacterIndex() -> Int {
        let range = readerTextView.accessibilityVisibleCharacterRange()
        guard range.location != NSNotFound else { return 0 }
        return min(readerTextView.textStorage?.length ?? 0, max(0, range.location))
    }

    func restorePosition(_ position: Int) {
        let length = readerTextView.textStorage?.length ?? 0
        guard length > 0, contentSize.width > 0 else { return }
        resizeAnchor = nil
        let index = min(max(0, position), length - 1)
        // Let NSTextView maintain TextKit 2's viewport anchor; fragment frames are estimates.
        let range = (readerTextView.string as NSString).rangeOfComposedCharacterSequence(at: index)
        readerTextView.scrollRangeToVisible(range)
        readerTextView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        if initialPosition == nil, resizeAnchor == nil, abs(newSize.width - frame.width) > 0.5 {
            resizeAnchor = topCharacterIndex()
        }
        super.setFrameSize(newSize)
    }

    func load(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 9
        readerTextView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 20),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.textColor
        ]))
    }

    override func layout() {
        super.layout()
        if initialPosition != nil || resizeAnchor != nil, !resizeScheduled,
           window != nil, contentSize.width > 0, contentSize.height > 0 {
            resizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                if let initial = self.initialPosition {
                    self.initialPosition = nil
                    self.resizeAnchor = nil
                    self.restorePosition(initial)
                    self.didRestoreInitialPosition?()
                    self.didRestoreInitialPosition = nil
                } else if let anchor = self.resizeAnchor {
                    self.resizeAnchor = nil
                    self.restorePosition(anchor)
                }
            }
        }
    }
}
