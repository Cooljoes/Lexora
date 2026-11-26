import XCTest
import SwiftData
import Translation
@testable import Lexora

final class ReadingTests: XCTestCase {
    func testRealTokenizerAndLemmaOffsets() throws {
        let text = "🌿 The birds were singing. A beautiful fern grew."
        let tokens = TextAnalysis.analyze(text)
        let birds = try XCTUnwrap(tokens.first { $0.surface == "birds" })
        XCTAssertEqual(birds.lemma, "bird")
        XCTAssertEqual(birds.pos, "noun")
        XCTAssertEqual(birds.sentence, "🌿 The birds were singing.")
        XCTAssertEqual((text as NSString).substring(with: NSRange(location: birds.location, length: birds.length)), "birds")
        XCTAssertTrue(tokens.contains(where: \.isFocus))
    }
    func testBundledDictionaryAndNamedAccents() throws {
        let hits = try Lexicon.lookup(.standalone("hospital", pos: "noun", sentence: "The doctor works at the hospital."))
        let zh = try XCTUnwrap(hits.first { $0.entry.edition == "zh" && $0.entry.pos == "noun" })
        XCTAssertFalse(zh.sense.gloss.isEmpty)
        XCTAssertTrue(zh.entry.detail.ipa["uk"]?.contains("ɒ") == true)
        XCTAssertTrue(zh.entry.detail.ipa["us"]?.contains("ɑ") == true)
        XCTAssertEqual(zh.entry.sourceURL.host, "zh.wiktionary.org")
        let formed = try Lexicon.lookup(.standalone("happiness"))
        XCTAssertTrue(formed.contains { !$0.entry.detail.parts.isEmpty })
        XCTAssertTrue(formed.contains { !$0.entry.detail.etymology.isEmpty })
        XCTAssertTrue(try Lexicon.lookup(.standalone("xyzzymissingword")).isEmpty)
    }
    func testContextRankingUsesLocalEntryExamples() throws {
        let bank = WordToken.standalone("bank", pos: "noun", sentence: "A fisherman sat by the river near the water.")
        let all = try Lexicon.lookup(bank)
        let best = try XCTUnwrap(all.first)
        XCTAssertEqual(best.entry.pos, "noun")
        XCTAssertTrue(all.contains { $0.sense.cues.contains("river") })
        XCTAssertTrue(best.sense.cues.contains("water") || best.sense.cues.contains("river"))
    }
    func testTranslationChunkBoundaries() {
        let sentences = String(repeating: "A fern lives here. ", count: 150)
        for source in [sentences, String(repeating: "a", count: 1300), "A short sentence."] {
            let chunks = TranslationChunks.split(source)
            XCTAssertEqual(chunks.joined(), source)
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 900 })
        }
    }
    #if !targetEnvironment(simulator)
    func testInstalledAppleTranslationOnDevice() async throws {
        let en = Locale.Language(identifier: "en")
        let zh = Locale.Language(identifier: "zh-Hans")
        let status = await LanguageAvailability().status(from: en, to: zh)
        try XCTSkipUnless(status == .installed, "先在真机安装英译简中的语言包。")
        let session = TranslationSession(installedSource: en, target: zh)
        let output = try await FullTextTranslator.translate("The river flows.\n\nA fern grows here.", using: session)
        let paragraphs = output.components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertTrue(paragraphs.allSatisfy { $0.range(of: "[\\p{Han}]", options: .regularExpression) != nil })
    }
    #endif
    @MainActor func testPersistenceAndIdempotentShareImport() throws {
        let schema = Library.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let db = container.mainContext
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ShareInbox(directory: directory)
        try inbox.enqueue("A river runs through the valley.")
        let file = try XCTUnwrap(inbox.files().first)
        let bytes = try Data(contentsOf: file)
        try Library.importInbox(inbox, into: db)
        try bytes.write(to: file)
        try Library.importInbox(inbox, into: db)
        XCTAssertEqual(try db.fetchCount(FetchDescriptor<Reading>()), 1)
        XCTAssertTrue(try inbox.files().isEmpty)
        let item = try Library.store("A river runs through the valley.", origin: "输入", in: db)
        item.translated = "一条河流穿过山谷。"
        db.insert(SavedWord(token: .standalone("river"), gloss: "河流"))
        try Library.commit(db)
        let next = ModelContext(container)
        XCTAssertEqual(try next.fetch(FetchDescriptor<Reading>()).first?.translated, item.translated)
        XCTAssertEqual(try next.fetchCount(FetchDescriptor<SavedWord>()), 1)
    }
}
