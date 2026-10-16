import Foundation

@main
struct TestMain {
    @MainActor static func main() async {
        do {
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--benchmark",
               let size = Int(CommandLine.arguments[2]), [10, 50, 100].contains(size) {
                try await benchmark(megabytes: size)
                return
            }
            try testFileLoader()
            try testChapterParser()
            try testReader()
            try await testRestore()
            try await testWindowControls()
            try await testChapterJump()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
