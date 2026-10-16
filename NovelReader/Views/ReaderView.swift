import SwiftUI

struct ReaderView: View {
    @ObservedObject var state: ReadingState
    @State private var controlsVisible = false

    var body: some View {
        ZStack {
            Color(nsColor: state.backgroundColor)
            if let text = state.text {
                TextReaderView(text: text, fontSize: state.fontSize, theme: state.theme, state: state)
                    .id(state.documentID)
            } else {
                EmptyReaderView(open: state.chooseFile)
            }
            if state.isLoading {
                ProgressView("正在打开…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(alignment: .top) {
            WindowDragHandle { controlsVisible = $0 }
                .frame(maxWidth: .infinity)
                .frame(height: 62)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 14) {
                Button(action: state.chooseFile) { Image(systemName: "folder") }
                    .help("打开其他小说（⌘O）")
                    .accessibilityLabel("打开其他小说")
                    .disabled(state.isLoading)
                Button { state.adjustFont(by: -2) } label: { Image(systemName: "textformat.size.smaller") }
                    .help("减小字号（⌘−）")
                    .accessibilityLabel("减小字号")
                    .disabled(state.fontSize <= 12)
                Button { state.adjustFont(by: 2) } label: { Image(systemName: "textformat.size.larger") }
                    .help("增大字号（⌘＋）")
                    .accessibilityLabel("增大字号")
                    .disabled(state.fontSize >= 40)
                Button(action: state.toggleTheme) {
                    Image(systemName: state.theme == .light ? "moon" : "sun.max")
                }
                .help(state.theme == .light ? "切换深色" : "切换浅色")
                .accessibilityLabel(state.theme == .light ? "切换深色" : "切换浅色")
                Button { state.appearanceSettingsPresented.toggle() } label: {
                    Image(systemName: "paintpalette")
                }
                .help("外观设置")
                .accessibilityLabel("外观设置")
                .popover(isPresented: $state.appearanceSettingsPresented) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("外观设置").font(.headline)
                        colorControl("字体颜色", forBackground: false)
                        colorControl("背景颜色", forBackground: true)
                        Divider()
                        Toggle("隐藏窗口边框与阴影", isOn: $state.hidesWindowBorder)
                            .help("显示／隐藏窗口边框（⌘⇧B）")
                        Text("顶部拖动窗口，边缘调整大小。\n切换浅色／深色会恢复预设配色。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(width: 260)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
            .onHover { controlsVisible = $0 }
            .opacity(controlsVisible || state.appearanceSettingsPresented ? 1 : 0)
            .allowsHitTesting(controlsVisible || state.appearanceSettingsPresented)
            .accessibilityHidden(!controlsVisible && !state.appearanceSettingsPresented)
        }
        .overlay { WindowResizeEdges() }
        .background(ReaderWindow(hidesBorder: state.hidesWindowBorder, backgroundColor: state.backgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(state.theme == .light ? .light : .dark)
        .task { await state.restoreLastFile() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            state.flushProgress?()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            state.flushProgress?()
        }
        .alert("无法打开小说", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) { Button("好") { state.errorMessage = nil } }
        message: { Text(state.errorMessage ?? "") }
    }

    private func colorControl(_ title: String, forBackground: Bool) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(nsColor: forBackground ? state.backgroundColor : state.foregroundColor) },
                set: { color in
                    if forBackground { state.setBackgroundColor(NSColor(color)) }
                    else { state.setForegroundColor(NSColor(color)) }
                }
            ), supportsOpacity: false)
            Button { state.sampleColor(forBackground: forBackground) } label: {
                Image(systemName: "eyedropper")
            }
            .help("从屏幕吸取\(title)")
            .accessibilityLabel("吸取\(title)")
            .disabled(state.isSamplingColor)
        }
    }
}
