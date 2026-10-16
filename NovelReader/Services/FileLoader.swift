import Foundation
import CoreFoundation

enum FileLoader {
    enum LoadError: LocalizedError {
        case unsupportedFile
        case unknownEncoding

        var errorDescription: String? {
            switch self {
            case .unsupportedFile: "请选择 TXT 小说文件。"
            case .unknownEncoding: "无法识别文本编码，请将文件另存为 UTF-8 后重试。"
            }
        }
    }

    static func load(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard url.pathExtension.lowercased() == "txt" else {
                throw LoadError.unsupportedFile
            }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            return try decode(Data(contentsOf: url, options: .mappedIfSafe))
        }.value
    }

    static func decode(_ data: Data) throws -> String {
        if data.isEmpty { return "" }
        let prefix = Array(data.prefix(4))
        let encoding: String.Encoding?
        let skip: Int
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = .utf8; skip = 3
        } else if prefix.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian; skip = 2
        } else if prefix.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian; skip = 2
        } else {
            encoding = nil; skip = 0
        }
        if let encoding {
            guard let text = String(data: data.dropFirst(skip), encoding: encoding) else {
                throw LoadError.unknownEncoding
            }
            return text
        }
        // Detect BOM-less UTF-16 from the ASCII punctuation/whitespace byte lanes.
        let sample = Array(data.prefix(4096))
        if data.count.isMultiple(of: 2), sample.count >= 4 {
            let pairs = sample.count / 2
            let evenZeros = stride(from: 0, to: pairs * 2, by: 2).filter { sample[$0] == 0 }.count
            let oddZeros = stride(from: 1, to: pairs * 2, by: 2).filter { sample[$0] == 0 }.count
            let guessed: String.Encoding? = oddZeros > pairs / 5 && oddZeros > evenZeros * 4 ? .utf16LittleEndian
                : evenZeros > pairs / 5 && evenZeros > oddZeros * 4 ? .utf16BigEndian : nil
            if let guessed, let text = String(data: data, encoding: guessed) { return text }
        }
        guard !sample.contains(0) else { throw LoadError.unknownEncoding }
        if let text = String(data: data, encoding: .utf8) { return text }
        // GB18030 includes GBK; Foundation performs strict decoding without substitution.
        for name in ["GB18030", "GBK"] {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { continue }
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw LoadError.unknownEncoding
    }
}
