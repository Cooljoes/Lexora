import SwiftUI
import SwiftData
import AVFAudio

struct WordSheet: View {
    let token: WordToken
    var preferredGloss: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedWord]
    @State private var lookup = WordLookup(senses: [], referenceIPA: [:])
    private var senses: [RankedSense] { lookup.senses }
    @State private var selected: Int?
    @State private var choosingSense = false
    @State private var showingSentence = false
    @State private var loaded = false
    @State private var lookupError: String?
    @State private var saveError: String?
    @AppStorage("lexora.voice.en-GB") private var britishVoiceID = ""
    @AppStorage("lexora.voice.en-US") private var americanVoiceID = ""
    @State private var installedVoices: [PronunciationVoice]?
    @State private var voiceRevision = 0
    @State private var lastPlayback: (locale: String, voice: PronunciationVoice?)?
    @State private var requestID: UUID?
    @State private var playback: Task<Void, Never>?
    @State private var preparingVoice: String?
    var chosen: RankedSense? { senses.first { $0.id == selected } ?? senses.first }
    var savedMatches: [SavedWord] { saved.filter { $0.lemma == token.lemma && $0.pos == token.pos } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(token.lemma).font(.custom("Baskerville-SemiBold", size: 41, relativeTo: .largeTitle))
                            .fixedSize(horizontal: false, vertical: true).foregroundStyle(Ink.text)
                        let pos = token.pos.isEmpty ? chosen?.entry.pos : token.pos
                        let subtitle = [pos.map(TextAnalysis.partName),
                                        token.lemma == token.surface.lowercased() ? nil : "文中词形 " + token.surface]
                            .compactMap { $0 }.joined(separator: "  ·  ")
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.subheadline).foregroundStyle(Ink.muted)
                        }
                    }
                    if !loaded { ProgressView("查阅离线词典…") }
                    else if let choice = chosen {
                        VStack(alignment: .leading, spacing: 9) {
                            SectionLine(title: token.sentence.isEmpty ? "词典释义" : "语境候选释义", detail: TextAnalysis.partName(choice.entry.pos))
                            Text(choice.sense.gloss).font(.title3).lineSpacing(3).textSelection(.enabled)
                            Link(choice.entry.sourceName, destination: choice.entry.sourceURL).font(.caption)
                            if senses.count > 1 {
                                Button { choosingSense = true } label: {
                                    HStack {
                                        Text("查看其他释义")
                                        Spacer()
                                        Image(systemName: "chevron.forward").font(.caption).accessibilityHidden(true)
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.font(.subheadline).accessibilityIdentifier("sensePicker")
                            }
                        }.padding(15).paperCard()
                        let primary = choice.entry
                        let extra = lookup.englishSupplement(for: primary)
                        let parts = primary.detail.parts.isEmpty ? (extra ?? primary) : primary
                        let etym = primary.detail.etymology.isEmpty ? (extra ?? primary) : primary
                        pronunciation(primary: primary, extra: extra)
                        sentenceSection
                        Divider()
                        section("词根与词缀", parts.detail.parts.isEmpty ? "此来源未提供明确的构词拆分。" : parts.detail.parts.joined(separator: "\n"))
                        if !parts.detail.parts.isEmpty {
                            Link(parts.sourceName + " · 构词", destination: parts.sourceURL).font(.caption)
                        }
                        section("词源", etym.detail.etymology.isEmpty ? "此词条未收录词源说明。" : etym.detail.etymology)
                        if !etym.detail.etymology.isEmpty {
                            Link(etym.sourceName + " · 词源", destination: etym.sourceURL).font(.caption)
                        }
                    } else {
                        if let lookupError {
                            Text(lookupError).font(.footnote).foregroundStyle(.red)
                        } else {
                            Label("离线词库未收录此词的释义", systemImage: "book.closed").foregroundStyle(Ink.muted)
                        }
                        pronunciation(primary: nil, extra: nil)
                        sentenceSection
                    }
                    if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                }.padding(22).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Ink.paper).navigationTitle("词条").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $choosingSense) {
                let currentID = chosen?.id
                List(senses) { hit in
                    Button {
                        selected = hit.id
                        choosingSense = false
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TextAnalysis.partName(hit.entry.pos) + " · " + hit.entry.sourceName)
                                    .font(.caption).foregroundStyle(Ink.muted)
                                Text(hit.sense.gloss).font(.body).foregroundStyle(Ink.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if currentID == hit.id {
                                Image(systemName: "checkmark").foregroundStyle(Ink.green).accessibilityHidden(true)
                            }
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(currentID == hit.id ? .isSelected : [])
                    .accessibilityIdentifier("sense-\(hit.id)")
                    .listRowBackground(Ink.card)
                }
                .scrollContentBackground(.hidden).background(Ink.paper)
                .navigationTitle("选择释义").navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { toggle() } label: {
                        Label(savedMatches.isEmpty ? "收藏" : "取消收藏", systemImage: savedMatches.isEmpty ? "bookmark" : "bookmark.fill")
                    }.accessibilityIdentifier("toggleFavorite").disabled(!loaded)
                }
            }
        }
        .task(id: token) {
            loaded = false
            lookup = WordLookup(senses: [], referenceIPA: [:])
            selected = nil
            showingSentence = false
            lookupError = nil
            stopPlayback()
            saveError = nil
            do {
                let result = try await Task.detached { try Lexicon.lookupWord(token) }.value
                guard !Task.isCancelled else { return }
                lookup = result
                if let preferredGloss { selected = senses.first { $0.sense.gloss == preferredGloss }?.id }
            } catch {
                guard !Task.isCancelled else { return }
                lookupError = error.localizedDescription
            }
            loaded = true
        }
        .task(id: voiceRevision) {
            let voices = await WordPronunciation.shared.installedVoices(refresh: true)
            if !Task.isCancelled { installedVoices = voices }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in voiceRevision += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { voiceRevision += 1 } }
        .onChange(of: selected) { stopPlayback() }
        .onDisappear { stopPlayback() }
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).lineSpacing(4).foregroundStyle(Ink.muted).textSelection(.enabled)
        }
    }
    @ViewBuilder private var sentenceSection: some View {
        if !token.sentence.isEmpty {
            DisclosureGroup(isExpanded: $showingSentence) {
                Text(token.sentence)
                    .font(.system(.body, design: .serif).italic()).lineSpacing(3)
                    .foregroundStyle(Ink.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Text("文中原句").font(.headline).foregroundStyle(Ink.text)
            }
            .padding(15).paperCard()
        }
    }
    private func pronunciation(primary: DictionaryEntry?, extra: DictionaryEntry?) -> some View {
        let uk = lookup.sourcedIPA("uk", primary: primary, extra: extra)
        let us = lookup.sourcedIPA("us", primary: primary, extra: extra)
        let general = lookup.sourcedIPA("general", primary: primary, extra: extra)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLine(title: "音标与发音")
            if let general {
                Text("未分地区  " + general.value).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("generalIPA")
                Link(general.entry.sourceName + " · 未分地区 IPA", destination: general.entry.sourceURL)
                    .font(.caption).accessibilityIdentifier("generalIPASource")
            }
            regionalPronunciation("英式", locale: "en-GB", attested: uk,
                                  variants: lookup.referenceIPA["uk"] ?? [], source: "Britfone",
                                  sourceURL: URL(string: "https://github.com/JoseLlarena/Britfone/tree/1062be14adc96c358f2087ac5449d72130c7a6f4")!)
            regionalPronunciation("美式", locale: "en-US", attested: us,
                                  variants: lookup.referenceIPA["us"] ?? [], source: "CMUdict（转写为 IPA）",
                                  sourceURL: URL(string: "https://github.com/cmusphinx/cmudict/tree/74790861f652b15e4ac49015a90074ad62a27690")!)
            if loaded && lookupError == nil && uk == nil && us == nil && general == nil && lookup.referenceIPA.isEmpty {
                Text("离线来源暂未收录此词的音标。").font(.footnote).foregroundStyle(Ink.muted)
            }
        }
    }
    @ViewBuilder private func regionalPronunciation(_ label: String, locale: String,
                                                    attested: (value: String, entry: DictionaryEntry)?,
                                                    variants: [String], source: String, sourceURL: URL) -> some View {
        let transcription = attested?.value ?? (variants.isEmpty ? nil : variants.joined(separator: "、"))
        soundRow(label, transcription, locale)
        if let attested {
            Link(attested.entry.sourceName + " · " + label + " IPA", destination: attested.entry.sourceURL).font(.caption)
        } else if !variants.isEmpty {
            Link(source + " · 词头读音", destination: sourceURL).font(.caption)
                .accessibilityIdentifier("ipaSource-" + locale)
            if variants.count > 1 {
                Text("词典列出 \(variants.count) 种读音，未区分义项。").font(.caption).foregroundStyle(Ink.muted)
            }
        }
    }
    private func soundRow(_ label: String, _ ipa: String?, _ locale: String) -> some View {
        let region = Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Ink.green)
        let preference = locale == "en-GB" ? $britishVoiceID : $americanVoiceID
        let options = installedVoices?.filter { $0.matches(language: locale) } ?? []
        let selection = options.contains { $0.id == preference.wrappedValue } || preference.wrappedValue == PronunciationVoice.highestQualityID
            ? preference.wrappedValue : ""
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let ipa {
                    let phonetics = Text(ipa).font(.body).foregroundStyle(Ink.text)
                    ViewThatFits(in: .horizontal) {
                        HStack { region; phonetics }.fixedSize()
                        VStack(alignment: .leading, spacing: 4) {
                            region
                            phonetics.fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    region
                }
                Spacer(minLength: 2)
                Menu {
                    Picker(label + "声音", selection: Binding(
                        get: { selection },
                        set: { id in
                            preference.wrappedValue = id
                            playWord(locale: locale, selectedID: id)
                        }
                    )) {
                        Text("跟随系统").tag("")
                        Text("自动选择最高音质").tag(PronunciationVoice.highestQualityID)
                        ForEach(options) { voice in Text(voice.displayName).tag(voice.id) }
                    }.pickerStyle(.inline)
                    if installedVoices == nil {
                        Text("正在查找设备语音…")
                    } else if options.isEmpty {
                        Text("可在设置中搜索“阅读与朗读”，从“声音”下载英语语音。")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("选择" + label + "声音")
                .accessibilityValue(options.first { $0.id == selection }?.displayName ??
                                    (selection == PronunciationVoice.highestQualityID ? "自动选择最高音质" : "跟随系统"))
                Button {
                    playWord(locale: locale, selectedID: preference.wrappedValue)
                } label: {
                    Group {
                        if preparingVoice == locale { ProgressView().controlSize(.small) }
                        else { Image(systemName: "speaker.wave.2") }
                    }.frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("播放" + label + "发音")
            }
            if let lastPlayback, lastPlayback.locale == locale {
                if let voice = lastPlayback.voice {
                    Text(voice.displayName).font(.caption).foregroundStyle(Ink.muted)
                    if voice.quality == .default && !options.contains(where: { $0.quality.rawValue > voice.quality.rawValue }) {
                        Text("可在设置中搜索“阅读与朗读”，从“声音”下载更高音质的英语语音。")
                            .font(.caption).foregroundStyle(Ink.muted)
                    }
                } else {
                    Text("此设备暂无可用的" + label + "英语语音。请在设置中搜索“阅读与朗读”，从“声音”下载。")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
            }
        }
    }

    private func playWord(locale: String, selectedID: String) {
        playback?.cancel()
        let id = UUID()
        requestID = id
        let word = chosen?.entry.word ?? token.lemma
        let hint = chosen.flatMap { lookup.speechHint(for: $0.entry, region: locale == "en-GB" ? "uk" : "us") }
        lastPlayback = nil
        preparingVoice = locale
        playback = Task {
            let voice = await WordPronunciation.shared.play(word, locale: locale, ipa: hint, selectedID: selectedID, request: id)
            guard !Task.isCancelled, requestID == id else { return }
            preparingVoice = nil
            lastPlayback = (locale, voice)
        }
    }

    private func stopPlayback() {
        playback?.cancel()
        if let requestID { Task { await WordPronunciation.shared.stop(request: requestID) } }
        requestID = nil
        preparingVoice = nil
        lastPlayback = nil
    }
    private func toggle() {
        saveError = nil
        if savedMatches.isEmpty { context.insert(SavedWord(token: token, gloss: chosen?.sense.gloss ?? "")) }
        else { savedMatches.forEach { context.delete($0) } }
        do { try Library.commit(context) } catch { saveError = error.localizedDescription }
    }
}

struct PronunciationVoice: Identifiable, Sendable {
    static let highestQualityID = "lexora.mode.highestQuality"
    let identifier: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let traits: AVSpeechSynthesisVoice.Traits
    var name: String = ""

    var id: String { identifier }
    var displayName: String {
        let grade: String
        switch quality {
        case .premium: grade = "精品"
        case .enhanced: grade = "增强"
        case .default: grade = "基础"
        @unknown default: grade = "系统语音"
        }
        return name + " · " + grade
    }

    func matches(language requested: String) -> Bool {
        language.replacingOccurrences(of: "_", with: "-").caseInsensitiveCompare(requested) == .orderedSame &&
            traits.intersection([.isNoveltyVoice, .isPersonalVoice]).isEmpty
    }

    static func best(in voices: [Self], language: String, preferredIdentifier: String? = nil,
                     selectedIdentifier: String? = nil) -> Self? {
        let eligible = voices.filter { $0.matches(language: language) }
        if let chosen = eligible.first(where: { $0.id == selectedIdentifier }) { return chosen }
        if selectedIdentifier != highestQualityID, let systemVoice = eligible.first(where: { $0.id == preferredIdentifier }) {
            return systemVoice
        }
        guard let bestQuality = eligible.map(\.quality.rawValue).max() else { return nil }
        let best = eligible.filter { $0.quality.rawValue == bestQuality }
        return best.first { $0.id == preferredIdentifier } ?? best.min { $0.id < $1.id }
    }
}

extension PronunciationVoice {
    init(_ voice: AVSpeechSynthesisVoice) {
        self.init(identifier: voice.identifier, language: voice.language, quality: voice.quality,
                  traits: voice.voiceTraits, name: voice.name)
    }
}

// The speech-asset service can block on a cold device. Resolve voices and play words
// off the main actor; the request ID prevents a dismissed sheet from stopping a newer word.
private actor WordPronunciation {
    static let shared = WordPronunciation()
    private var synthesizer: AVSpeechSynthesizer?
    private var inventory: [PronunciationVoice]?
    private var systemPreferences: [String: String] = [:]
    private var activeRequest: UUID?

    func installedVoices(refresh: Bool) -> [PronunciationVoice] {
        if !refresh, let inventory { return inventory }
        let locales = ["en-GB", "en-US"]
        var voices = AVSpeechSynthesisVoice.speechVoices().map(PronunciationVoice.init)
        let defaultVoice = AVSpeechSynthesisVoice(language: nil).map(PronunciationVoice.init)
        systemPreferences.removeAll()
        for locale in locales {
            let preferred: PronunciationVoice?
            if let defaultVoice, defaultVoice.matches(language: locale) {
                preferred = defaultVoice
            } else {
                preferred = AVSpeechSynthesisVoice(language: locale).map(PronunciationVoice.init)
            }
            if let preferred, preferred.matches(language: locale) {
                systemPreferences[locale] = preferred.id
                if !voices.contains(where: { $0.id == preferred.id }) { voices.append(preferred) }
            }
        }
        let available = voices.filter { voice in locales.contains { voice.matches(language: $0) } }
        .sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        inventory = available
        return available
    }

    func play(_ word: String, locale: String, ipa: String?, selectedID: String, request: UUID) -> PronunciationVoice? {
        guard !Task.isCancelled else { return nil }
        synthesizer?.stopSpeaking(at: .immediate)
        activeRequest = request
        var available = installedVoices(refresh: false)
        // A voice can be removed in Settings between building the menu and playing.
        while let choice = PronunciationVoice.best(in: available, language: locale,
                                                    preferredIdentifier: systemPreferences[locale], selectedIdentifier: selectedID) {
            guard !Task.isCancelled else { return nil }
            if let voice = AVSpeechSynthesisVoice(identifier: choice.id) {
                guard !Task.isCancelled else { return nil }
                let speech = synthesizer ?? AVSpeechSynthesizer()
                synthesizer = speech
                let utterance: AVSpeechUtterance
                if let ipa {
                    let text = NSAttributedString(string: word, attributes: [NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute): ipa])
                    utterance = AVSpeechUtterance(attributedString: text)
                } else {
                    utterance = AVSpeechUtterance(string: word)
                }
                utterance.voice = voice
                speech.speak(utterance)
                return choice
            }
            available.removeAll { $0.id == choice.id }
            inventory = available
        }
        return nil
    }

    func stop(request: UUID) {
        guard request == activeRequest else { return }
        synthesizer?.stopSpeaking(at: .immediate)
        activeRequest = nil
    }
}
