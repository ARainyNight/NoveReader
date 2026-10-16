import SwiftUI

struct ChapterListView: View {
    @ObservedObject var state: ReadingState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("章节").font(.headline)
                Spacer()
                Text("\(state.chapters.count) 章").foregroundStyle(.secondary)
            }
            if state.chapters.isEmpty {
                Spacer()
                Text("未识别到章节标题")
                    .frame(maxWidth: .infinity)
                Text("支持「第一章」「第001章」「序章」及「Chapter 1」等独立标题行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.chapters) { chapter in
                            Button { state.selectChapter(chapter) } label: {
                                Text(chapter.title)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300, height: 380)
    }
}
