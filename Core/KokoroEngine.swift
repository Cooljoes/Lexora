import CoreML
import Foundation
import SQLite3

/// On-device Kokoro v1.0 synthesis. The model returns mono PCM at 24 kHz.
actor KokoroEngine {
    static let shared = KokoroEngine()
    static let bundledDirectory = Bundle.main.url(forResource: "KokoroVoicePack", withExtension: nil)
    static let hasBundledPack: Bool = {
        guard let directory = bundledDirectory else { return false }
        let models = ["kokoro_5s.mlmodelc", "G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc"]
        let modelFiles = models.flatMap { model in
            ["model.mil", "coremldata.bin", "weights/weight.bin"].map { model + "/" + $0 }
        }
        let resources = ["lexicon.sqlite", "vocab_index.json", "g2p_vocab.json", "voices/af_heart.json", "voices/bf_emma.json"]
        return (modelFiles + resources).allSatisfy {
            FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0).path)
        }
    }()

    private let directory: URL?
    private var pack: KokoroPack?

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.bundledDirectory
    }

    func synthesize(_ text: String, language: String, ipaHint: String? = nil) async throws -> [Float] {
        try Task.checkCancellation()
        guard let directory else { throw KokoroError.unavailable }
        if pack == nil { pack = try KokoroPack(directory: directory) }
        guard let pack else { throw KokoroError.unavailable }
        try Task.checkCancellation()
        return try pack.synthesize(text, language: language, ipaHint: ipaHint)
    }
}

private enum KokoroError: LocalizedError {
    case unavailable, pronunciation, tooLong, invalidAudio

    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法读取随应用安装的 Kokoro 语音包。"
        case .pronunciation: return "Kokoro 无法读出这个词，请试用系统语音。"
        case .tooLong: return "这个词超出语音包的单次朗读长度，请试用系统语音。"
        case .invalidAudio: return "语音生成失败，请重试。"
        }
    }
}

private final class KokoroPack {
    private let directory: URL
    private let model: MLModel
    private let vocab: [String: Int]
    private let styles: [String: MLMultiArray]
    private let database: OpaquePointer
    private var g2p: KokoroG2P?

    init(directory: URL) throws {
        self.directory = directory
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #else
        configuration.computeUnits = .cpuAndNeuralEngine
        #endif
        model = try MLModel(contentsOf: directory.appendingPathComponent("kokoro_5s.mlmodelc"), configuration: configuration)
        struct Vocabulary: Decodable { let vocab: [String: Int] }
        struct Voice: Decodable { let embedding: [Float] }
        vocab = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: directory.appendingPathComponent("vocab_index.json"))).vocab
        var styles: [String: MLMultiArray] = [:]
        for (accent, voice) in [("us", "af_heart"), ("gb", "bf_emma")] {
            let url = directory.appendingPathComponent("voices").appendingPathComponent(voice + ".json")
            let values = try JSONDecoder().decode(Voice.self, from: Data(contentsOf: url)).embedding
            guard values.count == 256, values.allSatisfy({ $0.isFinite }) else { throw KokoroError.unavailable }
            styles[accent] = try Self.tensor(shape: [1, 256], floats: values)
        }
        self.styles = styles
        var handle: OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("lexicon.sqlite").path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            throw KokoroError.unavailable
        }
        database = handle
    }

    deinit { sqlite3_close(database) }

    func synthesize(_ text: String, language: String, ipaHint: String?) throws -> [Float] {
        let accent = language == "en-GB" ? "gb" : "us"
        guard let style = styles[accent] else { throw KokoroError.unavailable }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'")
        guard !cleaned.isEmpty else { throw KokoroError.pronunciation }
        if let ipaHint, let ids = tokens(for: Self.modelPhonemes(ipaHint, accent: accent)) {
            return try render([ids], style: style)
        }
        if let phones = try lookup(cleaned, accent: accent), let ids = tokens(for: phones) {
            return try render([ids], style: style)
        }
        let words = cleaned.split { $0.isWhitespace || $0 == "-" }.map(String.init)
        guard !words.isEmpty else { throw KokoroError.pronunciation }
        let groups = try words.map { word -> [Int] in
            try Task.checkCancellation()
            let pronunciation: String
            if let existing = try lookup(word, accent: accent) {
                pronunciation = existing
            } else {
                // Model predictions are for speech only. They are never stored or shown as dictionary IPA.
                if g2p == nil { g2p = try KokoroG2P(directory: directory) }
                guard let inferred = try g2p?.infer(word) else { throw KokoroError.pronunciation }
                pronunciation = inferred
            }
            guard let ids = tokens(for: pronunciation) else { throw KokoroError.pronunciation }
            return ids
        }
        return try render(groups, style: style)
    }

    private func lookup(_ word: String, accent: String) throws -> String? {
        var query: OpaquePointer?
        defer { sqlite3_finalize(query) }
        guard sqlite3_prepare_v2(database, "SELECT pronunciation FROM phoneme WHERE accent=? AND word=?", -1, &query, nil) == SQLITE_OK else {
            throw KokoroError.unavailable
        }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(query, 1, accent, -1, copy)
        sqlite3_bind_text(query, 2, word.lowercased(), -1, copy)
        switch sqlite3_step(query) {
        case SQLITE_ROW: return String(cString: sqlite3_column_text(query, 0))
        case SQLITE_DONE: return nil
        default: throw KokoroError.unavailable
        }
    }

    private func tokens(for phones: String) -> [Int]? {
        let ids = phones.compactMap { vocab[String($0)] }
        return !ids.isEmpty && ids.count == phones.count ? ids : nil
    }

    /// Convert the source dictionary's regional IPA to Kokoro's English token alphabet.
    /// If a symbol has no representation, the caller uses the pack's own lexicon.
    private static func modelPhonemes(_ ipa: String, accent: String) -> String {
        var value = ipa.trimmingCharacters(in: CharacterSet(charactersIn: "/[]"))
        for (source, token) in [("͡", ""), (".", ""), ("tʃ", "ʧ"), ("dʒ", "ʤ"), ("eɪ", "A"), ("aɪ", "I"),
                                ("aʊ", "W"), ("ɔɪ", "Y"), ("oʊ", "O"), ("əʊ", "Q"), ("ɚ", "əɹ"),
                                ("ɝ", "ɜɹ"), ("r", "ɹ"), ("g", "ɡ")] {
            value = value.replacingOccurrences(of: source, with: token)
        }
        return accent == "us" ? value.replacingOccurrences(of: "ː", with: "") : value
    }

    private func render(_ groups: [[Int]], style: MLMultiArray) throws -> [Float] {
        try Task.checkCancellation()
        guard !groups.isEmpty, let space = vocab[" "] else { throw KokoroError.pronunciation }
        let content = Array(groups.joined(separator: [space]))
        // Keep each pass inside the 128-token, five-second export. Split phrases at word boundaries.
        func split() throws -> [Float] {
            guard groups.count > 1 else { throw KokoroError.tooLong }
            let middle = groups.count / 2
            return try render(Array(groups[..<middle]), style: style) + render(Array(groups[middle...]), style: style)
        }
        guard content.count <= 126, content.count <= 54 || groups.count == 1 else { return try split() }
        let tokens = [0] + content + [0]
        let input = try MLMultiArray(shape: [1, 128], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, 128], dataType: .int32)
        for i in 0..<128 {
            input[i] = NSNumber(value: i < tokens.count ? tokens[i] : 0)
            mask[i] = i < tokens.count ? 1 : 0
        }
        let phases = try Self.tensor(shape: [1, 9], floats: (0..<9).map { _ in Float.random(in: 0..<1) })
        let speed = try Self.tensor(shape: [1], floats: [1])
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": input, "attention_mask": mask, "ref_s": style, "speed": speed, "random_phases": phases
        ])
        let prediction = try model.prediction(from: features)
        try Task.checkCancellation()
        guard let wave = prediction.featureValue(for: "audio")?.multiArrayValue,
              let length = prediction.featureValue(for: "audio_length_samples")?.multiArrayValue,
              length.count == 1 else { throw KokoroError.invalidAudio }
        let n = length[0].intValue
        guard n > 0 else { throw KokoroError.invalidAudio }
        guard n < wave.count else { return try split() }
        var samples = (0..<n).map { wave[$0].floatValue }
        guard samples.allSatisfy({ $0.isFinite }), samples.contains(where: { abs($0) > 0.001 }) else { throw KokoroError.invalidAudio }
        // Fade the last 5 ms of the predicted waveform to avoid a click at playback stop.
        let fade = min(120, n)
        for i in 0..<fade { samples[n - fade + i] *= Float(fade - i - 1) / Float(fade) }
        return samples
    }

    private static func tensor(shape: [NSNumber], floats: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        for (i, value) in floats.enumerated() { array[i] = NSNumber(value: value) }
        return array
    }
}

/// English grapheme-to-phoneme networks shipped with the Core ML conversion.
/// Used lazily when neither a dictionary hint nor the regional Misaki lexicon covers a word.
private final class KokoroG2P {
    private struct Vocabulary: Decodable {
        let grapheme_to_id: [String: Int]
        let id_to_phoneme: [String: String]
        let bos_token_id: Int
        let eos_token_id: Int
    }
    private let encoder: MLModel
    private let decoder: MLModel
    private let vocab: Vocabulary

    init(directory: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        encoder = try MLModel(contentsOf: directory.appendingPathComponent("G2PEncoder.mlmodelc"), configuration: config)
        decoder = try MLModel(contentsOf: directory.appendingPathComponent("G2PDecoder.mlmodelc"), configuration: config)
        vocab = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: directory.appendingPathComponent("g2p_vocab.json")))
    }

    func infer(_ word: String) throws -> String {
        let letters = word.lowercased().map(String.init)
        let ids = letters.compactMap { vocab.grapheme_to_id[$0] }
        guard !ids.isEmpty, ids.count == letters.count, ids.count <= 62 else { throw KokoroError.pronunciation }
        let input = try integerTensor([vocab.bos_token_id] + ids + [vocab.eos_token_id])
        let state = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": input]))
        guard let hidden = state.featureValue(for: "encoder_hidden_states")?.multiArrayValue else { throw KokoroError.pronunciation }
        var decoded = [vocab.bos_token_id]
        var result = ""
        while decoded.count <= 64 {
            try Task.checkCancellation()
            let count = decoded.count
            let mask = try MLMultiArray(shape: [1, NSNumber(value: count), NSNumber(value: count)], dataType: .float32)
            for i in 0..<count {
                for j in 0..<count { mask[i * count + j] = (j <= i) ? 0 : -10000 }
            }
            let features = try MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": try integerTensor(decoded), "position_ids": try integerTensor(Array(0..<count)),
                "causal_mask": mask, "encoder_hidden_states": hidden
            ])
            let output = try decoder.prediction(from: features)
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                  let width = logits.shape.last?.intValue, width > 0, logits.count >= count * width else { throw KokoroError.pronunciation }
            let start = (count - 1) * width
            guard let best = (0..<width).max(by: { logits[start + $0].floatValue < logits[start + $1].floatValue }) else {
                throw KokoroError.pronunciation
            }
            if best == vocab.eos_token_id, !result.isEmpty { return result }
            guard let phone = vocab.id_to_phoneme[String(best)], phone.count == 1 else { throw KokoroError.pronunciation }
            result += phone
            decoded.append(best)
        }
        throw KokoroError.pronunciation
    }

    private func integerTensor(_ values: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for (i, value) in values.enumerated() { array[i] = NSNumber(value: value) }
        return array
    }
}
