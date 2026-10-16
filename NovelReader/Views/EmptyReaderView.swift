import SwiftUI

struct EmptyReaderView: View {
    var open: () -> Void

    var body: some View {
        Button("打开小说", action: open)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
