import AppKit

@MainActor
func benchmark(megabytes: Int) async throws {
    _ = NSApplication.shared
    let url = try await Task.detached {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("novel-\(megabytes)MB.txt")
        let paragraph = "窗外的风吹过山林，远处传来清脆的鸟鸣。他推开门，看见阳光正落在石阶上。一路走来，熟悉的风景依旧安静，只有树影在微微摇动。今天的故事从这里开始，脚下的小路通向更远的村庄。\n"
        let line = Data(paragraph.utf8)
        let lines = (megabytes * 1024 * 1024 + line.count - 1) / line.count
        var fixture = Data(capacity: lines * line.count)
        for index in 0..<lines {
            if index.isMultiple(of: 1000) {
                fixture.append(Data("第\(index / 1000 + 1)章 山林故事\n".utf8))
            }
            fixture.append(line)
        }
        try fixture.write(to: url)
        return url
    }.value

    let readStart = CFAbsoluteTimeGetCurrent()
    let text = try await FileLoader.load(url)
    let readSeconds = CFAbsoluteTimeGetCurrent() - readStart
    let parseStart = CFAbsoluteTimeGetCurrent()
    let chapters = await Task.detached { ChapterParser.parse(text) }.value
    let parseSeconds = CFAbsoluteTimeGetCurrent() - parseStart
    try verify(chapters.count > 10, "Large file chapter index")
    let length = (text as NSString).length
    let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 860, height: 720),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let scroll = ReaderScrollView()
    window.contentView = scroll
    window.orderFront(nil)
    let renderStart = CFAbsoluteTimeGetCurrent()
    scroll.load(text)
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    let renderSeconds = CFAbsoluteTimeGetCurrent() - renderStart
    try await Task.sleep(for: .milliseconds(100))

    let target = chapters.last(where: { $0.offset <= length * 4 / 5 })?.offset ?? 0
    let restoreStart = CFAbsoluteTimeGetCurrent()
    scroll.restorePosition(target)
    window.displayIfNeeded()
    let restoreSeconds = CFAbsoluteTimeGetCurrent() - restoreStart
    try await Task.sleep(for: .milliseconds(100))
    try verifyPositionVisible(scroll, target, "Large file restore")
    for chapter in [chapters[0], chapters[chapters.count - 1], chapters[chapters.count / 2]] {
        scroll.restorePosition(chapter.offset)
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try verifyPositionVisible(scroll, chapter.offset, "Large file chapter jump")
    }

    var maxScroll = 0.0
    for _ in 0..<20 {
        let start = CFAbsoluteTimeGetCurrent()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        window.displayIfNeeded()
        maxScroll = max(maxScroll, CFAbsoluteTimeGetCurrent() - start)
        try await Task.sleep(for: .milliseconds(10))
    }
    let fontStart = CFAbsoluteTimeGetCurrent()
    scroll.applyFont(24)
    window.displayIfNeeded()
    let fontSeconds = CFAbsoluteTimeGetCurrent() - fontStart
    try verify(scroll.readerTextView.textLayoutManager != nil, "Large file remains on TextKit 2")
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let peakMB = Double(usage.ru_maxrss) / 1024 / 1024
    let report = String(format: "| %d MiB | %.3f s | %.3f s | %d | %.3f s | %.3f s | %.3f s | %.3f s | %.0f MiB |",
                        megabytes, readSeconds, parseSeconds, chapters.count, renderSeconds,
                        restoreSeconds, maxScroll, fontSeconds, peakMB)
    print(report)
    let reportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/benchmark-\(megabytes)MB.md")
    try Data((report + "\n").utf8).write(to: reportURL)
    window.orderOut(nil)
}
