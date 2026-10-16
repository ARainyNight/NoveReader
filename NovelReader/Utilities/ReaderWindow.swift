import AppKit
import SwiftUI

final class ReaderNativeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !styleMask.contains(.fullScreen) {
            let edges = resizeEdges(at: event.locationInWindow)
            if !edges.isEmpty {
                WindowResizeEdges.ResizeView.resize(self, with: event, edges: edges)
                return
            }
            if let drag = dragHandle(at: event.locationInWindow) {
                drag.mouseDown(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    func dragHandle(at point: NSPoint) -> WindowDragHandle.DragView? {
        guard let contentView else { return nil }
        let parentPoint = contentView.superview?.convert(point, from: nil) ?? point
        return contentView.hitTest(parentPoint) as? WindowDragHandle.DragView
    }

    func resizeEdges(at point: NSPoint) -> WindowResizeEdges.ResizeView.Edges {
        guard let contentView else { return [] }
        let rect = contentView.convert(contentView.bounds, to: nil)
        let local = NSPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        return WindowResizeEdges.ResizeView.edges(at: local, in: NSRect(origin: .zero, size: rect.size))
    }
}

@MainActor
func configureReaderWindow(_ window: NSWindow, hidesBorder: Bool = false) {
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    if !window.styleMask.contains(.fullScreen) {
        var style = window.styleMask
        if hidesBorder { style.remove([.titled, .fullSizeContentView]) }
        else { style.insert([.titled, .fullSizeContentView]) }
        style.insert(.resizable)
        if style != window.styleMask {
            let frame = window.frame
            window.styleMask = style
            window.setFrame(frame, display: true)
        }
    }
    window.hasShadow = !hidesBorder
    window.contentMinSize = .zero
    window.minSize = .zero
    window.isMovableByWindowBackground = false
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.toolbar = nil
}

struct ReaderWindow: NSViewRepresentable {
    var hidesBorder = false
    var backgroundColor: NSColor = ReaderTheme.light.background

    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ view: WindowProbe, context: Context) {
        view.hidesBorder = hidesBorder
        view.readerBackground = backgroundColor
        view.configure()
    }

    final class WindowProbe: NSView {
        var hidesBorder = false
        var readerBackground: NSColor = ReaderTheme.light.background

        func configure() {
            guard let window else { return }
            configureReaderWindow(window, hidesBorder: hidesBorder)
            window.backgroundColor = readerBackground
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(didExitFullScreen),
                    name: NSWindow.didExitFullScreenNotification, object: window)
                configure()
            }
        }

        @objc private func didExitFullScreen() { configure() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct WindowDragHandle: NSViewRepresentable {
    var hover: (Bool) -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.hover = hover
        return view
    }
    func updateNSView(_ view: DragView, context: Context) { view.hover = hover }

    final class DragView: NSView {
        var hover: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { hover?(true) }
        override func mouseExited(with event: NSEvent) { hover?(false) }

        override func mouseDown(with event: NSEvent) {
            hover?(true)
            window?.performDrag(with: event)
        }
    }
}

struct WindowResizeEdges: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeView { ResizeView() }
    func updateNSView(_ view: ResizeView, context: Context) { }

    final class ResizeView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        struct Edges: OptionSet {
            let rawValue: Int
            static let left = Edges(rawValue: 1)
            static let right = Edges(rawValue: 2)
            static let bottom = Edges(rawValue: 4)
            static let top = Edges(rawValue: 8)
        }

        static func edges(at point: NSPoint, in bounds: NSRect) -> Edges {
            guard bounds.contains(point) else { return [] }
            var edges: Edges = []
            if point.x < 6 { edges.insert(.left) }
            else if point.x > bounds.width - 6 { edges.insert(.right) }
            if point.y < 6 { edges.insert(.bottom) }
            else if point.y > bounds.height - 6 { edges.insert(.top) }
            return edges
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard bounds.contains(local), window?.styleMask.contains(.fullScreen) == false,
                  !Self.edges(at: local, in: bounds).isEmpty else { return nil }
            return self
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard window?.styleMask.contains(.fullScreen) == false else { return }
            addCursorRect(NSRect(x: 0, y: 6, width: 6, height: max(0, bounds.height - 12)), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: max(0, bounds.width - 6), y: 6, width: 6, height: max(0, bounds.height - 12)), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: 6), cursor: .resizeUpDown)
            addCursorRect(NSRect(x: 0, y: max(0, bounds.height - 6), width: bounds.width, height: 6), cursor: .resizeUpDown)
        }

        static func resizedFrame(_ frame: NSRect, delta: NSPoint, edges: Edges) -> NSRect {
            var result = frame
            if edges.contains(.left) {
                result.size.width = max(1, frame.width - delta.x)
                result.origin.x = frame.maxX - result.width
            } else if edges.contains(.right) { result.size.width = max(1, frame.width + delta.x) }
            if edges.contains(.bottom) {
                result.size.height = max(1, frame.height - delta.y)
                result.origin.y = frame.maxY - result.height
            } else if edges.contains(.top) { result.size.height = max(1, frame.height + delta.y) }
            return result
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            Self.resize(window, with: event, edges: Self.edges(at: convert(event.locationInWindow, from: nil), in: bounds))
        }

        static func resize(_ window: NSWindow, with event: NSEvent, edges: Edges) {
            let start = window.convertPoint(toScreen: event.locationInWindow)
            let frame = window.frame
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .leftMouseUp { break }
                let point = window.convertPoint(toScreen: next.locationInWindow)
                let delta = NSPoint(x: point.x - start.x, y: point.y - start.y)
                window.setFrame(Self.resizedFrame(frame, delta: delta, edges: edges), display: true)
            }
        }
    }
}
