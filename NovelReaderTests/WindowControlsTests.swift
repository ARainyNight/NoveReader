import AppKit
import SwiftUI

@MainActor
func testWindowControls() async throws {
    guard let defaults = UserDefaults(suiteName: "NovelReaderControls.\(UUID())") else {
        throw NSError(domain: "Test defaults unavailable", code: 1)
    }
    let state = ReadingState(defaults: defaults)
    let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/fixtures/hosting-\(UUID()).txt")
    let text = String(repeating: "窗外的风吹过山林，远处传来清脆的鸟鸣。\n", count: 10_000)
    try Data(text.utf8).write(to: fixture)
    await state.open(fixture)
    state.progressStore.savePosition(70_000, for: fixture)
    let host = NSHostingView(rootView: ReaderView(state: state))
    host.sizingOptions = []
    let window = ReaderNativeWindow(contentRect: NSRect(x: 50, y: 50, width: 860, height: 720),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    func findDragView(_ view: NSView) -> WindowDragHandle.DragView? {
        if let drag = view as? WindowDragHandle.DragView { return drag }
        return view.subviews.lazy.compactMap { findDragView($0) }.first
    }
    guard let drag = findDragView(host) else { throw NSError(domain: "Missing drag region", code: 1) }
    try verify(drag.bounds.width >= 800 && drag.bounds.height == 62,
               "Drag region fills top edge: \(drag.bounds)")
    func findReader(_ view: NSView) -> ReaderScrollView? {
        if let scroll = view as? ReaderScrollView { return scroll }
        return view.subviews.lazy.compactMap { findReader($0) }.first
    }
    guard let scroll = findReader(host) else { throw NSError(domain: "Missing hosted reader", code: 1) }
    try verifyPositionVisible(scroll, 70_000, "SwiftUI initial layout restores visible position")
    let hit = host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.height - 10))
    try verify(hit is WindowDragHandle.DragView, "Top edge receives native dragging events")
    let edgeHit = host.hitTest(NSPoint(x: 2, y: host.bounds.midY))
    try verify(edgeHit is WindowResizeEdges.ResizeView, "Resize edge receives dragging events")
    try verify(edgeHit?.mouseDownCanMoveWindow == false, "Resize edge bypasses background window movement")
    try verify(window.resizeEdges(at: NSPoint(x: 2, y: 2)) == [.left, .bottom],
               "Native bottom edge ignores flipped hosting coordinates")
    try verify(window.resizeEdges(at: NSPoint(x: host.bounds.width - 2, y: host.bounds.height - 2)) == [.right, .top],
               "Native top edge ignores flipped hosting coordinates")
    typealias Resize = WindowResizeEdges.ResizeView
    let frame = NSRect(x: 100, y: 200, width: 500, height: 400)
    for horizontal in [Resize.Edges.left, .right] {
        for vertical in [Resize.Edges.bottom, .top] {
            let resized = Resize.resizedFrame(frame, delta: NSPoint(x: 50, y: 30), edges: [horizontal, vertical])
            try verify(resized.width == (horizontal == .left ? 450 : 550), "Corner resizes width")
            try verify(resized.height == (vertical == .bottom ? 370 : 430), "Corner resizes height")
            try verify(horizontal == .left ? resized.maxX == frame.maxX : resized.minX == frame.minX,
                       "Opposite horizontal edge remains fixed")
            try verify(vertical == .bottom ? resized.maxY == frame.maxY : resized.minY == frame.minY,
                       "Opposite vertical edge remains fixed")
        }
    }
    let crossed = Resize.resizedFrame(frame, delta: NSPoint(x: 1000, y: 1000), edges: [.left, .bottom])
    try verify(crossed.width == 1 && crossed.height == 1 && crossed.maxX == frame.maxX && crossed.maxY == frame.maxY,
               "Crossed edges clamp to positive dimensions")
    let anchor = scroll.topCharacterIndex()
    window.setContentSize(NSSize(width: 280, height: 240))
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    try verify(host.bounds.width <= 281 && host.bounds.height <= 241, "Window shrinks below old minimum: \(host.bounds)")
    try verify(scroll.bounds.width <= 281, "Reader follows narrow window")
    try verifyPositionVisible(scroll, anchor, "Narrow resize preserves anchor")
    state.hidesWindowBorder = true
    try await Task.sleep(for: .milliseconds(150))
    try verify(!window.styleMask.contains(.titled) && !window.hasShadow, "Hosted window switches to borderless")
    let rightEdgeHit = host.hitTest(NSPoint(x: host.bounds.width - 2, y: host.bounds.midY))
    try verify(rightEdgeHit is WindowResizeEdges.ResizeView, "Borderless right edge receives resize events")
    try verify(rightEdgeHit?.mouseDownCanMoveWindow == false, "Borderless edge bypasses background dragging")
    try verify(window.dragHandle(at: NSPoint(x: window.frame.width / 2, y: window.frame.height - 20)) === drag,
               "Borderless native window routes top dragging to drag handle")
    try verify(window.dragHandle(at: NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)) == nil,
               "Body remains available for text selection")
    try verifyPositionVisible(scroll, anchor, "Border switch preserves anchor")
    state.hidesWindowBorder = false
    try await Task.sleep(for: .milliseconds(150))
    try verify(window.styleMask.contains(.titled), "Hosted window restores border")
    print("PASS: SwiftUI/AppKit drag region geometry and hidden-title window integration")
    window.orderOut(nil)
}
