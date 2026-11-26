import Foundation
import NaturalLanguage

enum PassageIssue: LocalizedError {
    case empty, tooLong, needsEnglish, groupUnavailable
    var errorDescription: String? {
        switch self {
        case .empty: return "请先输入或粘贴一段英文。"
        case .tooLong: return "每篇最多支持 12,000 个字符，请分段导入。"
        case .needsEnglish: return "请输入英文单词、句子或段落。"
        case .groupUnavailable: return "无法打开共享空间。请检查 App Group 配置后重试。"
        }
    }
}

enum PassageInput {
    static let limit = 12_000
    static func clean(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PassageIssue.empty }
        guard text.count <= limit else { throw PassageIssue.tooLong }
        guard text.range(of: "[A-Za-z]", options: .regularExpression) != nil else { throw PassageIssue.needsEnglish }
        return text
    }
}

struct SharedPassage: Codable {
    let id: UUID
    let text: String
    let date: Date
}

struct ShareInbox {
    let directory: URL

    static func live() throws -> Self {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LexoraAppGroup") as? String,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw PassageIssue.groupUnavailable }
        return Self(directory: url.appending(path: "ReadingInbox", directoryHint: .isDirectory))
    }
    func enqueue(_ text: String) throws {
        let entry = SharedPassage(id: UUID(), text: try PassageInput.clean(text), date: .now)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent(entry.id.uuidString + ".json"), options: .atomic)
    }
    func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }
}
