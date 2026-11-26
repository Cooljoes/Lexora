import Foundation
import NaturalLanguage
import Translation

enum TranslationChunks {
    static func split(_ paragraph: String, limit: Int = 900) -> [String] {
        guard paragraph.count > limit else { return [paragraph] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        tokenizer.setLanguage(.english)
        var pieces = [String]()
        var remaining = paragraph[...]
        while remaining.count > limit {
            let bound = remaining.index(remaining.startIndex, offsetBy: limit)
            let inside = remaining.startIndex..<bound
            // A complete sentence is preferred, followed by a word boundary.
            let sentenceEnd = tokenizer.tokens(for: inside).last { $0.upperBound <= bound && $0.upperBound > remaining.startIndex }?.upperBound
            let whitespace = remaining[..<bound].lastIndex(where: { $0.isWhitespace })
            let boundary = sentenceEnd ?? whitespace.map { remaining.index(after: $0) } ?? bound
            pieces.append(String(remaining[..<boundary]))
            remaining = remaining[boundary...]
        }
        if !remaining.isEmpty { pieces.append(String(remaining)) }
        return pieces
    }
}

enum FullTextTranslator {
    static func translate(_ source: String, using session: TranslationSession) async throws -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        var translated = [String]()
        for paragraph in normalized.components(separatedBy: .newlines) {
            if paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                translated.append("")
                continue
            }
            var fragments = [String]()
            for fragment in TranslationChunks.split(paragraph) {
                try Task.checkCancellation()
                fragments.append(try await session.translate(fragment).targetText)
            }
            translated.append(fragments.joined())
        }
        return translated.joined(separator: "\n")
    }
}
