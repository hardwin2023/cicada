import Testing
@testable import Cicada

@Suite struct LanguageTests {
    @Test(arguments: [
        ("zh-Hans-CN", "zh-CN"), ("zh-Hans-CA", "zh-CN"), ("zh-Hant-TW", "zh-TW"),
        ("zh-TW", "zh-TW"), ("zh-HK", "zh-TW"), ("zh-CN", "zh-CN"),
        ("en-CA", "en"), ("ja-JP", "ja"), ("pt-BR", "pt"),
    ])
    func systemLanguageMapsToTranslationCode(id: String, code: String) {
        #expect(translationCode(forSystemLanguage: id) == code)
    }

    @Test func cjkJoinsWithoutSpaces() {
        #expect(joiner(for: "zh-CN") == "")
        #expect(joiner(for: "ja") == "")
        #expect(joiner(for: "en") == " ")
    }

    private let english = sourceLanguages.first { $0.code == "en" }!
    private let japanese = sourceLanguages.first { $0.code == "ja" }!

    @Test func detectionScoreFollowsConfidence() {
        let text = "hello there everyone"
        #expect(LanguageDetector.score(conf: 0.9, chars: text.count, text: text, lang: english) == 0.9)
        #expect(LanguageDetector.score(conf: 0.9, chars: 0, text: "", lang: english) == 0)
    }

    @Test func shortOutputCountsAsNoise() {
        #expect(LanguageDetector.score(conf: 0.9, chars: 3, text: "abc", lang: english) == 0.45)
    }

    @Test func aClipWithNextToNothingWrittenSaysNothing() {
        let zh = sourceLanguages.first { $0.code == "zh-CN" }!
        func c(_ lang: Lang, _ chars: Int, _ score: Double) -> LanguageDetector.Candidate {
            .init(lang: lang, confidence: score, chars: chars, text: "", score: score)
        }
        // The room before anyone spoke, and a two-character fragment.
        #expect(LanguageDetector.saysNothing([c(zh, 3, 0.09), c(english, 0, 0)]))
        #expect(LanguageDetector.saysNothing([c(zh, 2, 0.26), c(japanese, 0, 0)]))
        // A short sentence, and Chinese that the English model writes out as words.
        #expect(!LanguageDetector.saysNothing([c(zh, 7, 0.86), c(english, 0, 0)]))
        #expect(!LanguageDetector.saysNothing([c(zh, 3, 0.44), c(english, 10, 0.2)]))
        // One model only: its answer still decides.
        #expect(!LanguageDetector.saysNothing([c(zh, 2, 0.26)]))
    }

    @Test func cjkModelWritingLatinIsPenalised() {
        let latin = "hello there everyone"
        let native = "こんにちは皆さん"
        #expect(LanguageDetector.score(conf: 0.8, chars: latin.count, text: latin, lang: japanese) == 0.8 * 0.75)
        #expect(LanguageDetector.score(conf: 0.8, chars: native.count, text: native, lang: japanese) == 0.8)
    }
}

@Suite struct FollowSystemTests {
    @Test(arguments: [
        (["zh-Hans-CN"], "zh-CN"), (["en-US"], "en"), (["en-CA", "zh-Hans-CA"], "zh-CN"),
        (["ja-JP", "zh-Hant-TW"], "zh-TW"), (["ja-JP", "en-US"], "ja"), ([String](), "zh-CN"),
    ])
    func myLanguageIsChineseWhenListed(prefs: [String], mine: String) {
        #expect(myLanguage(systemLanguages: prefs) == mine)
    }

    /// Subtitles and notes agree: unless they speak my language, subtitles are in it.
    @Test(arguments: [["en-CA", "zh-Hans-CA"], ["zh-Hans-CN", "en-US"], ["ja-JP", "en-US"], ["en-US"]])
    func subtitlesFollowMyLanguage(prefs: [String]) {
        let mine = myLanguage(systemLanguages: prefs)
        for source in ["en", "ja", "ko", "zh-CN", nil] as [String?] where source != mine {
            #expect(followSystemTarget(source: source, systemLanguages: prefs) == mine)
        }
    }

    @Test func speakingMyLanguageTranslatesIntoTheNextOne() {
        #expect(followSystemTarget(source: "zh-CN", systemLanguages: ["en-CA", "zh-Hans-CA"]) == "en")
        #expect(followSystemTarget(source: "ja", systemLanguages: ["ja-JP", "en-US"]) == "en")
        #expect(followSystemTarget(source: "zh-CN", systemLanguages: ["zh-Hans-CN"]) == "en")
        #expect(followSystemTarget(source: "en", systemLanguages: ["en-US"]) == "zh-CN")
    }

    @Test func speakLocaleComesFromMyLanguage() {
        #expect(speakLocale(forLanguage: "zh-TW") == "zh-CN")
        #expect(speakLocale(forLanguage: "ja") == "ja-JP")
        #expect(speakLocale(forLanguage: "it") == "en-US")
    }

    @Test func likelyLanguagesPutLastThenSystemThenEnglish() {
        let locales = { (l: [Lang]) in l.map(\.locale) }
        // A Chinese Mac with nothing detected yet: Chinese first, English to compare it with.
        #expect(locales(likelySourceLanguages(last: nil, systemLanguages: ["zh-Hans-CN"])) == ["zh-CN", "en-US"])
        // Traditional Chinese still listens with the Mandarin model.
        #expect(locales(likelySourceLanguages(last: nil, systemLanguages: ["zh-Hant-TW", "en-US"])) == ["zh-CN", "en-US"])
        #expect(locales(likelySourceLanguages(last: "ja-JP", systemLanguages: ["fr-FR", "en-GB"])) == ["ja-JP", "fr-FR", "en-US"])
        // Languages with no speech model are skipped; English is always there.
        #expect(locales(likelySourceLanguages(last: "xx", systemLanguages: ["it-IT"])) == ["en-US"])
    }

    @Test func autoStartsInTheMacLanguageNotEnglish() {
        let en = sourceLanguages.first { $0.code == "en" }!
        let zh = sourceLanguages.first { $0.code == "zh-CN" }!
        // `candidates` comes in sourceLanguages order, English first. A fresh Chinese Mac must
        // still start in Chinese; otherwise the English model transcribes Chinese as English.
        #expect(initialSourceLanguage(candidates: [en, zh], last: nil,
                                      systemLanguages: ["zh-Hans-CN"]) == zh)
        // A last meeting in English still wins, as before.
        #expect(initialSourceLanguage(candidates: [en, zh], last: "en-US",
                                      systemLanguages: ["zh-Hans-CN"]) == en)
        // Only English installed: English is the only thing it can start.
        #expect(initialSourceLanguage(candidates: [en], last: nil,
                                      systemLanguages: ["zh-Hans-CN"]) == en)
    }
}
