import Foundation

enum ChapterParser {
    static func parse(_ text: String) -> [Chapter] {
        let source = text as NSString
        // Numbered headings allow compact titles; prose punctuation excludes sentence-like lines.
        let numbered = try? NSRegularExpression(pattern:
            #"^(?:第\s*[0-9０-９零〇一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章回节卷部集篇]|Chapter\s+(?:[0-9]+|[IVXLCDM]+)(?=\s|[:：.、\-—]|$))"#,
            options: .caseInsensitive)
        let special = try? NSRegularExpression(pattern:
            #"^(?:序章|序言|楔子|引子|前言|尾声|后记|终章|番外(?:\s*[0-9０-９一二三四五六七八九十]+)?)(?=\s|[:：、\-—]|$)"#)
        var chapters: [Chapter] = []
        var offset = 0
        while offset < source.length {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: offset, length: 0))
            let length = contentsEnd - offset
            if length > 0, length <= 120 {
                let line = source.substring(with: NSRange(location: offset, length: length)) as NSString
                let title = (line as String).trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(location: 0, length: (title as NSString).length)
                if !title.isEmpty, title.count <= 80,
                   title.rangeOfCharacter(from: CharacterSet(charactersIn: "。；;“”‘’")) == nil,
                   numbered?.firstMatch(in: title, range: range) != nil
                    || special?.firstMatch(in: title, range: range) != nil {
                    let leading = line.rangeOfCharacter(from: .whitespacesAndNewlines.inverted).location
                    chapters.append(Chapter(title: title, offset: offset + leading))
                }
            }
            offset = end
        }
        return chapters
    }
}
