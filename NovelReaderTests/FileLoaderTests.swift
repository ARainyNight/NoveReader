import Foundation
import CoreFoundation

func verify(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: "NovelReaderTests", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: message]) }
}

func testFileLoader() throws {
    let text = "第一章 春天\n窗外的风吹过山林。\r\n中文、English 123。"
    for encoding: String.Encoding in [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian] {
        guard let data = text.data(using: encoding) else { fatalError("Fixture encoding failed") }
        let decoded = try FileLoader.decode(data)
        try verify(decoded == text, "Unicode encoding failed: \(encoding)")
    }
    for name in ["GBK", "GB18030"] {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringConvertIANACharSetNameToEncoding(name as CFString)))
        guard let data = text.data(using: encoding) else { fatalError("GB fixture failed") }
        let decoded = try FileLoader.decode(data)
        try verify(decoded == text, "\(name) Chinese decoding failed")
    }
    let extended = "中文扩展字符：𠀀，表情：😀。"
    let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)))
    guard let fourByteData = extended.data(using: gb18030) else { fatalError("GB18030 fixture failed") }
    try verify(try FileLoader.decode(fourByteData) == extended, "GB18030 four-byte characters")
    for encoding: String.Encoding in [.utf8, .utf16] {
        guard let data = extended.data(using: encoding) else { fatalError("Surrogate fixture failed") }
        try verify(try FileLoader.decode(data) == extended, "Unicode supplementary characters")
    }
    let bom = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    try verify(try FileLoader.decode(bom) == text, "UTF-8 BOM")
    try verify(try FileLoader.decode(Data()) == "", "Empty file")
    do {
        _ = try FileLoader.decode(Data([0xEF, 0xBB, 0xBF, 0xFF]))
        throw NSError(domain: "Invalid input accepted", code: 1)
    } catch is FileLoader.LoadError { }
    print("PASS: UTF-8/BOM, UTF-16 LE/BE, GBK/GB18030, empty and invalid BOM")
}
