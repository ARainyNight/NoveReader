import AppKit
import SwiftUI

func testChapterParser() throws {
    let text = "😀书名\r\n　第一卷 风起\r\n\t第一章 初入江湖\r\n正文提到第二章，仍然是正文。\n第002章：归来\r第三回再会\n第十二节 夜行\u{2028}CHAPTER 4 — Home\u{2029}Chapter V\n序章\n番外 二：重逢\n尾声\n"
    let titles = ["第一卷 风起", "第一章 初入江湖", "第002章：归来", "第三回再会", "第十二节 夜行",
                  "CHAPTER 4 — Home", "Chapter V", "序章", "番外 二：重逢", "尾声"]
    let chapters = ChapterParser.parse(text)
    try verify(chapters.map(\.title) == titles, "Common Chinese/English headings and line endings")
    for chapter in chapters {
        try verify(chapter.offset == (text as NSString).range(of: chapter.title).location,
                   "UTF-16 offset includes emoji, indentation and CRLF: \(chapter.title)")
    }
    let invalid = ["", "普通正文", "第一章讲述了他的经历。", "第一章 他想：“回家！”", "序章已经结束",
                   "Chapter One begins here", "Chapter 12abc", "第章", "第abc章", "123", "目录",
                   "第1章 " + String(repeating: "长", count: 150)]
    for text in invalid {
        try verify(ChapterParser.parse(text).isEmpty, "Reject prose or malformed heading: \(text.prefix(30))")
    }
    try verify(ChapterParser.parse("第１章　开始").count == 1, "Full-width number, final line without newline")
    try verify(ChapterParser.parse("第1章 我是谁？\n第2章 出发！").count == 2, "Questions and exclamations in headings")
    try verify(ChapterParser.parse("第一章\n正文\n第一章").map(\.offset) == [0, 7], "Repeated titles retain distinct locations")
    print("PASS: chapter formats, prose filtering, UTF-16 offsets, mixed newlines, empty and long lines")
}

@MainActor
func testChapterJump() async throws {
    guard let defaults = UserDefaults(suiteName: "NovelReaderChapterTests.\(UUID())") else {
        throw NSError(domain: "Test defaults unavailable", code: 1)
    }
    let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("chapters-\(UUID()).txt")
    let body = String(repeating: "😀窗外的风吹过山林，远处传来清脆的鸟鸣。\r\n", count: 1500)
    let text = "第一章 出发\r\n" + body + "第二章 重逢\r\n" + body + "尾声\r\n" + body
    try Data(text.utf8).write(to: url)
    let state = ReadingState(defaults: defaults)
    await state.open(url)
    try verify(state.errorMessage == nil && state.chapters.count == 3, "Async open publishes chapter index")
    let first = state.chapters[0]
    let second = state.chapters[1]
    let last = state.chapters[2]
    // Queue a selection before the AppKit view is ready; initial restore must not overwrite it.
    state.chaptersPresented = true
    state.selectChapter(last)
    try verify(!state.chaptersPresented, "Selection dismisses chapter popup")
    let window = ReaderNativeWindow(contentRect: NSRect(x: 50, y: 50, width: 860, height: 720),
                                   styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: ReaderView(state: state))
    host.sizingOptions = []
    window.contentView = host
    window.orderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(250))
    func findScroll(_ view: NSView) -> ReaderScrollView? {
        if let scroll = view as? ReaderScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScroll($0) }.first
    }
    guard let scroll = findScroll(host) else { throw NSError(domain: "Reader view missing", code: 1) }
    try verifyPositionVisible(scroll, last.offset, "Pending chapter selection after initial restore")
    for chapter in [first, second, last, last, first, second] {
        state.selectChapter(chapter)
        try await Task.sleep(for: .milliseconds(100))
        try verifyPositionVisible(scroll, chapter.offset, "Forward/backward/repeated chapter selection")
    }
    try verify(scroll.readerTextView.textLayoutManager != nil, "Chapter jump retains TextKit 2")
    state.flushProgress?()
    let saved = state.progressStore.position(for: url)
    try verify(saved == second.offset, "Save selected heading while it remains visible")
    let restored = ReadingState(defaults: defaults)
    await restored.restoreLastFile()
    try verify(restored.chapters == state.chapters, "Restart rebuilds chapter index")
    try verify(restored.progressStore.position(for: url) == saved, "Restart preserves jumped progress")
    let restoreWindow = ReaderNativeWindow(contentRect: NSRect(x: 50, y: 50, width: 860, height: 720),
                                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let restoreHost = NSHostingView(rootView: ReaderView(state: restored))
    restoreHost.sizingOptions = []
    restoreWindow.contentView = restoreHost
    restoreWindow.orderFront(nil)
    restoreHost.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(250))
    guard let restoredScroll = findScroll(restoreHost) else { throw NSError(domain: "Restored reader missing", code: 1) }
    try verifyPositionVisible(restoredScroll, second.offset, "New window restores selected heading")
    let emojiOffset = (text as NSString).range(of: "😀", options: [],
                                              range: NSRange(location: second.offset, length: (text as NSString).length - second.offset)).location
    restoredScroll.restorePosition(0)
    restoredScroll.restorePosition(emojiOffset + 1)
    try await Task.sleep(for: .milliseconds(100))
    try verifyPositionVisible(restoredScroll, emojiOffset, "Restore inside emoji uses complete character range")
    scroll.restorePosition(last.offset + 2000)
    try await Task.sleep(for: .milliseconds(100))
    state.flushProgress?()
    try verify(state.progressStore.position(for: url) == scroll.topCharacterIndex(), "Scrolling beyond heading resumes normal progress")
    let oldRequest = state.chapterJump
    state.selectChapter(Chapter(title: "invalid", offset: -1))
    try verify(state.chapterJump == oldRequest, "Reject unknown chapter")
    try verify(try String(contentsOf: url, encoding: .utf8) == text, "Novel file is unchanged")
    let emptyURL = dir.appendingPathComponent("no-chapters-\(UUID()).txt")
    try Data("只有普通正文。".utf8).write(to: emptyURL)
    await state.open(emptyURL)
    try await Task.sleep(for: .milliseconds(100))
    try verify(state.chapters.isEmpty && state.chapterJump == nil, "Switching file clears index and jump")
    window.orderOut(nil)
    restoreWindow.orderOut(nil)
    print("PASS: hosted chapter selection, distant/repeated jumps, queued selection, saved restore, file switch")
}
