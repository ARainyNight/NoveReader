import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ReaderTheme: String, Codable {
    case light, dark

    var background: NSColor {
        NSColor(calibratedWhite: self == .light ? 0.97 : 0.10, alpha: 1)
    }

    var foreground: NSColor {
        NSColor(calibratedWhite: self == .light ? 0.14 : 0.84, alpha: 1)
    }
}

struct ReaderColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        red = min(1, max(0, rgb.redComponent))
        green = min(1, max(0, rgb.greenComponent))
        blue = min(1, max(0, rgb.blueComponent))
    }

    var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

@MainActor
final class ReadingState: ObservableObject {
    @Published private(set) var text: String?
    @Published private(set) var fileURL: URL?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var documentID = UUID()
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var chapterJump: ChapterJump?
    @Published var chaptersPresented = false
    @Published private(set) var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    private let defaults: UserDefaults
    let progressStore: ReadingProgressStore
    var flushProgress: (() -> Void)?
    private var didRestore = false
    @Published private(set) var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }
    @Published private(set) var customForeground: ReaderColor? {
        didSet { saveColor(customForeground, forKey: "foregroundColor") }
    }
    @Published private(set) var customBackground: ReaderColor? {
        didSet { saveColor(customBackground, forKey: "backgroundColor") }
    }
    @Published var hidesWindowBorder: Bool {
        didSet { defaults.set(hidesWindowBorder, forKey: "hidesWindowBorder") }
    }
    @Published var appearanceSettingsPresented = false
    @Published private(set) var isSamplingColor = false

    var foregroundColor: NSColor { customForeground?.nsColor ?? theme.foreground }
    var backgroundColor: NSColor { customBackground?.nsColor ?? theme.background }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progressStore = ReadingProgressStore(defaults: defaults)
        theme = ReaderTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .light
        customForeground = Self.savedColor(in: defaults, forKey: "foregroundColor")
        customBackground = Self.savedColor(in: defaults, forKey: "backgroundColor")
        hidesWindowBorder = defaults.bool(forKey: "hidesWindowBorder")
        let saved = defaults.object(forKey: "fontSize") as? Double ?? 20
        fontSize = saved.isFinite ? min(40, max(12, saved)) : 20
    }

    func toggleTheme() {
        customForeground = nil
        customBackground = nil
        theme = theme == .light ? .dark : .light
    }

    func setForegroundColor(_ color: NSColor) { customForeground = ReaderColor(color) }
    func setBackgroundColor(_ color: NSColor) { customBackground = ReaderColor(color) }

    func sampleColor(forBackground: Bool) {
        guard !isSamplingColor else { return }
        isSamplingColor = true
        Task { @MainActor in
            defer { isSamplingColor = false }
            guard let color = await NSColorSampler().sample() else { return }
            if forBackground { setBackgroundColor(color) } else { setForegroundColor(color) }
        }
    }

    private static func savedColor(in defaults: UserDefaults, forKey key: String) -> ReaderColor? {
        guard let data = defaults.data(forKey: key),
              let color = try? JSONDecoder().decode(ReaderColor.self, from: data), color.isValid else { return nil }
        return color
    }

    private func saveColor(_ color: ReaderColor?, forKey key: String) {
        if let color, let data = try? JSONEncoder().encode(color) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    func restoreLastFile() async {
        guard !didRestore else { return }
        didRestore = true
        do {
            if let url = try progressStore.recentURL() { await open(url) }
        } catch {
            // Missing or expired access returns to the normal file picker entry point.
            errorMessage = "上次小说无法访问，请重新选择 TXT 文件。"
        }
    }

    func adjustFont(by amount: Double) {
        fontSize = min(40, max(12, fontSize + amount))
    }

    func chooseFile() {
        guard !isLoading else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "txt") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "打开小说"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.open(url) }
        }
    }

    func selectChapter(_ chapter: Chapter) {
        guard !isLoading, chapters.contains(chapter) else { return }
        chapterJump = ChapterJump(documentID: documentID, offset: chapter.offset)
        chaptersPresented = false
    }

    func open(_ url: URL) async {
        guard !isLoading else { return }
        flushProgress?()
        isLoading = true
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
            isLoading = false
        }
        do {
            let loaded = try await FileLoader.load(url)
            let parsed = await Task.detached(priority: .userInitiated) {
                ChapterParser.parse(loaded)
            }.value
            try progressStore.remember(url)
            chaptersPresented = false
            chapterJump = nil
            chapters = parsed
            text = loaded
            fileURL = url
            documentID = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
