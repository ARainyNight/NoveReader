import Foundation

@MainActor
final class ReadingProgressStore {
    private struct Snapshot: Codable {
        var recentPath: String?
        var bookmark: Data?
        var positions: [String: Int] = [:]
    }

    private let defaults: UserDefaults
    private var snapshot: Snapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: "readingProgress")
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    func position(for url: URL) -> Int { max(0, snapshot.positions[url.standardizedFileURL.path] ?? 0) }

    func savePosition(_ position: Int, for url: URL) {
        snapshot.positions[url.standardizedFileURL.path] = max(0, position)
        persist()
    }

    func remember(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        snapshot.recentPath = url.standardizedFileURL.path
        snapshot.bookmark = bookmark
        persist()
    }

    func recentURL() throws -> URL? {
        guard let bookmark = snapshot.bookmark else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let previousPath = snapshot.recentPath
        if stale { try remember(url) }
        // A moved file keeps its reading position when the bookmark resolves to its new path.
        if let oldPath = previousPath, oldPath != url.standardizedFileURL.path {
            snapshot.positions[url.standardizedFileURL.path] = snapshot.positions[oldPath]
            snapshot.recentPath = url.standardizedFileURL.path
            persist()
        }
        return url
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "readingProgress") }
    }
}
