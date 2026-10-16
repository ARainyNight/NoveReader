import Foundation

struct Chapter: Identifiable, Equatable, Sendable {
    let title: String
    let offset: Int
    var id: Int { offset }
}

struct ChapterJump: Equatable {
    let id = UUID()
    let documentID: UUID
    let offset: Int
}
