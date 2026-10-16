import SwiftUI

@main
struct NovelReaderApp: App {
    @NSApplicationDelegateAdaptor(ReaderAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            ReaderCommands(state: delegate.state, showWindow: delegate.showReader,
                           toggleFullScreen: delegate.toggleFullScreen)
        }
    }
}

@MainActor
final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    let state = ReadingState()
    private var readerWindow: ReaderNativeWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = ReaderNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "NovelReader"
        window.identifier = NSUserInterfaceItemIdentifier("reader")
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ReaderView(state: state))
        host.sizingOptions = []
        window.contentView = host
        configureReaderWindow(window, hidesBorder: state.hidesWindowBorder)
        window.center()
        window.setFrameAutosaveName("reader")
        readerWindow = window
        showReader()
    }

    func showReader() {
        readerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleFullScreen() { readerWindow?.toggleFullScreen(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showReader()
        return true
    }
}

struct ReaderCommands: Commands {
    @ObservedObject var state: ReadingState
    var showWindow: () -> Void
    var toggleFullScreen: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) { }
        CommandGroup(after: .newItem) {
            Button("打开小说…") { showWindow(); state.chooseFile() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(state.isLoading)
        }
        CommandMenu("阅读") {
            Button("增大字号") { state.adjustFont(by: 2) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(state.fontSize >= 40)
            Button("减小字号") { state.adjustFont(by: -2) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(state.fontSize <= 12)
            Divider()
            Button(state.theme == .light ? "切换深色" : "切换浅色", action: state.toggleTheme)
            Divider()
            Button("外观设置…") { showWindow(); state.appearanceSettingsPresented = true }
            Toggle("隐藏窗口边框与阴影", isOn: $state.hidesWindowBorder)
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        CommandGroup(after: .windowSize) {
            Button("进入／退出全屏", action: toggleFullScreen)
                .keyboardShortcut("f", modifiers: [.command, .control])
            Button("显示阅读窗口", action: showWindow)
        }
    }
}
