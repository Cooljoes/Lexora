import XCTest
import SwiftData
import Translation
import AVFAudio
@testable import Lexora

final class ReadingTests: XCTestCase {
    func testBundledKokoroRendersBritishAndAmericanSpeech() async throws {
        for region in ["en-GB", "en-US"] {
            let samples = try await KokoroEngine.shared.synthesize("hospital", language: region)
            // A complete word should contain speech and end before the export's five-second padded window.
            XCTAssertTrue((4_800..<120_000).contains(samples.count), region)
            XCTAssertTrue(samples.allSatisfy(\.isFinite), region)
            let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
            XCTAssertGreaterThan(meanSquare, 0.00001, region)
        }
        do {
            _ = try await KokoroEngine.shared.synthesize("📖", language: "en-US")
            XCTFail("An unsupported symbol has no spoken-word form.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testEnglishVoicePreferenceRespectsAccentQualityAndExplicitChoice() {
        let basic = PronunciationVoice(identifier: "basic", language: "en-US", quality: .default, traits: [])
        let enhanced = PronunciationVoice(identifier: "enhanced", language: "en_US", quality: .enhanced, traits: [])
        let premium = PronunciationVoice(identifier: "premium", language: "en-US", quality: .premium, traits: [])
        let uk = PronunciationVoice(identifier: "uk", language: "en-GB", quality: .premium, traits: [])
        let novelty = PronunciationVoice(identifier: "effects", language: "en-US", quality: .premium, traits: [.isNoveltyVoice])
        let personal = PronunciationVoice(identifier: "personal", language: "en-US", quality: .premium, traits: [.isPersonalVoice])
        let voices = [basic, uk, enhanced, premium, personal, novelty]
        XCTAssertEqual(PronunciationVoice.best(in: voices, language: "en-US", preferredIdentifier: "basic")?.id, "basic")
        XCTAssertEqual(PronunciationVoice.best(in: voices, language: "en-US", preferredIdentifier: "basic", selectedIdentifier: "enhanced")?.id, "enhanced")
        XCTAssertEqual(PronunciationVoice.best(in: voices, language: "en-US", preferredIdentifier: "basic", selectedIdentifier: PronunciationVoice.highestQualityID)?.id, "premium")
        XCTAssertEqual(PronunciationVoice.best(in: voices, language: "en-US", preferredIdentifier: "basic", selectedIdentifier: "removed")?.id, "basic")
        XCTAssertEqual(PronunciationVoice.best(in: [basic, enhanced, uk], language: "en-US", preferredIdentifier: "uk")?.id, "enhanced")
        XCTAssertEqual(PronunciationVoice.best(in: voices, language: "en-GB", selectedIdentifier: "basic")?.id, "uk")
        XCTAssertNil(PronunciationVoice.best(in: [novelty, personal, uk], language: "en-US", selectedIdentifier: "effects"))
    }
    func testOfflineReferencePronunciationsAndAmbiguousHeadwords() throws {
        let lychee = try Lexicon.lookup(.standalone("lychee"))
        let zh = try XCTUnwrap(lychee.first { $0.entry.edition == "zh" && $0.entry.pos == "noun" }?.entry)
        XCTAssertEqual(zh.detail.ipa["uk"], "/ˈlaɪ̯t͡ʃiː/")
        XCTAssertEqual(zh.detail.ipa["us"], "/ˈlitʃiː/")
        let word = try Lexicon.lookupWord(.standalone("daylight"))
        XCTAssertTrue(word.senses.isEmpty)
        XCTAssertFalse(try XCTUnwrap(word.referenceIPA["us"]).isEmpty)
        XCTAssertFalse(try XCTUnwrap(word.referenceIPA["uk"]).isEmpty)
        let read = try Lexicon.lookupWord(.standalone("read"))
        XCTAssertEqual(read.referenceIPA["us"], ["/ɹɛd/", "/ɹid/"])
        XCTAssertEqual(read.referenceIPA["uk"], ["/ɹiːd/", "/ɹɛd/"])
        XCTAssertTrue(try Lexicon.lookupWord(.standalone("xyzzymissingword")).referenceIPA.isEmpty)
        XCTAssertNotNil(Bundle.main.url(forResource: "Pronunciation-Licenses", withExtension: "txt"))
    }
    @MainActor func testInstalledAmericanVoiceProducesAudio() async throws {
        try await checkSpeechOutput(language: "en-US")
    }
    @MainActor func testInstalledBritishVoiceProducesAudio() async throws {
        try await checkSpeechOutput(language: "en-GB")
    }
    @MainActor private func checkSpeechOutput(language: String) async throws {
        let available = AVSpeechSynthesisVoice.speechVoices().map {
            PronunciationVoice(identifier: $0.identifier, language: $0.language, quality: $0.quality, traits: $0.voiceTraits)
        }
        let preferred = AVSpeechSynthesisVoice(language: language)?.identifier
        guard let chosen = PronunciationVoice.best(in: available, language: language, preferredIdentifier: preferred),
              let voice = AVSpeechSynthesisVoice(identifier: chosen.id) else {
            throw XCTSkip("当前设备没有可测试的 \(language) 语音。")
        }
        let utterance = AVSpeechUtterance(string: "daylight")
        utterance.voice = voice
        let synthesizer = AVSpeechSynthesizer()
        let audibleSamples = expectation(description: "系统人声输出非静音采样")
        audibleSamples.assertForOverFulfill = false
        synthesizer.write(utterance) { audio in
            guard let pcm = audio as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            let count = Int(pcm.frameLength)
            if let samples = pcm.floatChannelData?[0], (0..<count).contains(where: { abs(samples[$0]) > 0.0001 }) {
                audibleSamples.fulfill()
            } else if let samples = pcm.int16ChannelData?[0], (0..<count).contains(where: { samples[$0] != 0 }) {
                audibleSamples.fulfill()
            }
        }
        await fulfillment(of: [audibleSamples], timeout: 30)
        synthesizer.stopSpeaking(at: .immediate)
    }
    func testRecordUsesThePronunciationOfTheSelectedPartOfSpeech() throws {
        let lookup = try Lexicon.lookupWord(.standalone("record"))
        for (pos, stressed) in [("noun", "ˈɹɛk"), ("verb", "ˈkɔ")] {
            let primary = try XCTUnwrap(lookup.senses.first { $0.entry.edition == "zh" && $0.entry.pos == pos }?.entry)
            let result = try XCTUnwrap(lookup.sourcedIPA("uk", primary: primary, extra: lookup.englishSupplement(for: primary)))
            XCTAssertTrue(result.value.contains(stressed), result.value)
            XCTAssertEqual(result.entry.edition, "en")
            XCTAssertEqual(result.entry.pos, pos)
            XCTAssertTrue(try XCTUnwrap(lookup.speechHint(for: primary, region: "uk")).contains(stressed))
            XCTAssertEqual(lookup.speechHint(for: primary, region: "uk", useDisplayedIPA: true),
                           lookup.speechHint(for: primary, region: "uk"))
        }
    }
    func testKokoroUsesSingleDisplayedRegionalPronunciation() throws {
        let endless = try Lexicon.lookupWord(.standalone("endless"))
        let entry = try XCTUnwrap(endless.senses.first?.entry)
        XCTAssertEqual(endless.speechHint(for: entry, region: "uk", useDisplayedIPA: true), "ˈɛndlɪs")
        XCTAssertEqual(endless.speechHint(for: entry, region: "us", useDisplayedIPA: true), "ˈɛndləs")
        XCTAssertNil(endless.speechHint(for: entry, region: "uk"))

        let read = try Lexicon.lookupWord(.standalone("read"))
        XCTAssertNil(read.speechHint(for: nil, region: "uk", useDisplayedIPA: true))
        XCTAssertNil(read.speechHint(for: nil, region: "us", useDisplayedIPA: true))
        let past = try XCTUnwrap(read.senses.first { $0.entry.detail.ipa["uk"] == "/ɹɛd/" }?.entry)
        XCTAssertEqual(read.speechHint(for: past, region: "uk", useDisplayedIPA: true), "ɹɛd")
    }
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
