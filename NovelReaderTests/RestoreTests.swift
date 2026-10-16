import AppKit

@MainActor
func testRestore() async throws {
    guard let defaults = UserDefaults(suiteName: "NovelReaderRestoreTests.\(UUID())") else {
        throw NSError(domain: "Test defaults unavailable", code: 1)
    }
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("restore-\(UUID()).txt")
    let text = "第一章\n" + String(repeating: "这是重启恢复测试的中文正文。\n", count: 1000)
    try Data(text.utf8).write(to: url)
    let state = ReadingState(defaults: defaults)
    await state.open(url)
    try verify(state.text == text, "Async file loading")
    try verify(state.errorMessage == nil, "Bookmark creation: \(state.errorMessage ?? "")")
    state.progressStore.savePosition(9000, for: url)
    state.adjustFont(by: 4)
    state.toggleTheme()
    let restored = ReadingState(defaults: defaults)
    await restored.restoreLastFile()
    try verify(restored.text == text, "Restart restores file")
    try verify(restored.progressStore.position(for: url) == 9000, "Restart restores position")
    try verify(restored.fontSize == 24 && restored.theme == .dark, "Restart restores preferences")

    let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 860, height: 720),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let scroll = ReaderScrollView()
    window.contentView = scroll
    scroll.load(text)
    let coordinator = ReaderCoordinator(state: restored)
    coordinator.attach(scroll)
    window.orderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    try verifyPositionVisible(scroll, 9000, "Coordinator restores visible position")
    scroll.restorePosition(5000)
    restored.flushProgress?()
    try verify(restored.progressStore.position(for: url) == scroll.topCharacterIndex(), "Flush before exit")
    coordinator.detach()
    window.orderOut(nil)

    let missing = dir.appendingPathComponent("does-not-exist-\(UUID()).txt")
    do { _ = try await FileLoader.load(missing); throw NSError(domain: "Missing file accepted", code: 1) }
    catch is CocoaError { }
    let fresh = ReadingState(defaults: UserDefaults(suiteName: "NovelReaderFresh.\(UUID())") ?? defaults)
    await fresh.restoreLastFile()
    try verify(fresh.text == nil && !fresh.isLoading, "First launch empty state")
    print("PASS: security bookmark, async loading, restart restore, visible coordinator anchor, exit flush")
}
