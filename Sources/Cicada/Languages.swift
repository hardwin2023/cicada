// Pure Foundation: the iOS app shares this file (ios/shared-sources.txt).
import Foundation

// MARK: - Languages

struct Lang: Equatable {
    let name: String
    /// Locale used by SpeechTranscriber.
    let locale: String
    /// Language code used by the translation endpoint.
    let code: String
}

let sourceLanguages: [Lang] = [
    .init(name: "English", locale: "en-US", code: "en"),
    .init(name: "日本語", locale: "ja-JP", code: "ja"),
    .init(name: "中文", locale: "zh-CN", code: "zh-CN"),
    .init(name: "한국어", locale: "ko-KR", code: "ko"),
    .init(name: "Español", locale: "es-ES", code: "es"),
    .init(name: "Français", locale: "fr-FR", code: "fr"),
    .init(name: "Deutsch", locale: "de-DE", code: "de"),
    .init(name: "Português", locale: "pt-BR", code: "pt"),
]

let targetLanguages: [Lang] = [
    .init(name: "简体中文", locale: "zh-Hans", code: "zh-CN"),
    .init(name: "繁體中文", locale: "zh-Hant", code: "zh-TW"),
    .init(name: "English", locale: "en", code: "en"),
    .init(name: "日本語", locale: "ja", code: "ja"),
    .init(name: "한국어", locale: "ko", code: "ko"),
    .init(name: "Español", locale: "es", code: "es"),
    .init(name: "Français", locale: "fr", code: "fr"),
    .init(name: "Deutsch", locale: "de", code: "de"),
    .init(name: "Português", locale: "pt", code: "pt"),
]

/// Maps a system language identifier ("zh-Hans-CA", "en-CA", "zh-TW") to a translation code.
func translationCode(forSystemLanguage id: String) -> String {
    let locale = Locale(identifier: id)
    let lang = locale.language.languageCode?.identifier ?? "en"
    guard lang == "zh" else { return lang }
    let script = locale.language.script?.identifier
    let region = locale.region?.identifier
    if script == "Hant" { return "zh-TW" }
    if script == nil, let region, ["TW", "HK", "MO"].contains(region) { return "zh-TW" }
    return "zh-CN"
}

/// The reader's own language under "follow system": Chinese when the system list has it (the
/// app speaks Chinese), otherwise the first system language. Subtitles, notes and speak-back
/// all start from this one answer, so they never disagree.
func myLanguage(systemLanguages prefs: [String]) -> String {
    translationCode(forSystemLanguage: prefs.first { $0.hasPrefix("zh") } ?? prefs.first ?? "zh-Hans")
}

/// What "follow system" translates into: my language, unless that is what they speak; then the
/// next system language, or between Chinese and English when the system has only one.
func followSystemTarget(source: String?, systemLanguages prefs: [String]) -> String {
    let mine = myLanguage(systemLanguages: prefs)
    guard let source, source == mine else { return mine }
    return prefs.map(translationCode(forSystemLanguage:)).first { $0 != mine }
        ?? (mine.hasPrefix("zh") ? "en" : "zh-CN")
}

/// The languages "auto" most likely hears, most likely first: the last one detected, the Mac's
/// own languages, then English. Detection compares two or more models, so a Mac with fewer
/// fetches the first ones of these it lacks; and they are what 听不出 offers to pick from.
func likelySourceLanguages(last: String?, systemLanguages prefs: [String]) -> [Lang] {
    var out: [Lang] = []
    func add(_ lang: Lang?) { if let lang, !out.contains(lang) { out.append(lang) } }
    add(sourceLanguages.first { $0.locale == last })
    for id in prefs {
        let code = translationCode(forSystemLanguage: id)
        // The only Chinese model listed is Mandarin (zh-CN); it hears Taiwanese Mandarin as well.
        add(sourceLanguages.first { $0.code == (code.hasPrefix("zh") ? "zh-CN" : code) })
    }
    add(sourceLanguages.first { $0.code == "en" })
    return out
}

/// The model auto starts with: the room's own language, else the last meeting's, else the
/// Mac's language before the remaining installed models. `candidates` is in `sourceLanguages`
/// order (English first), so taking `candidates.first` would start every fresh Mac in English.
func initialSourceLanguage(candidates: [Lang], last: String?, systemLanguages prefs: [String],
                           mine: Lang? = nil) -> Lang {
    if let mine { return mine }
    if let last, let lang = candidates.first(where: { $0.locale == last }) { return lang }
    let likely = likelySourceLanguages(last: last, systemLanguages: prefs)
    return likely.first(where: { candidates.contains($0) })
        ?? likely.first
        ?? candidates.first
        ?? sourceLanguages[0]
}

/// The speech locale to listen for when I speak my language (English when it isn't one we recognize).
func speakLocale(forLanguage code: String) -> String {
    if code.hasPrefix("zh") { return "zh-CN" }
    return sourceLanguages.first { $0.code == code }?.locale ?? "en-US"
}

func targetName(_ code: String) -> String {
    targetLanguages.first(where: { $0.code == code })?.name
        ?? Locale.current.localizedString(forIdentifier: code) ?? code
}

/// CJK text is joined without spaces.
func joiner(for code: String) -> String {
    (code.hasPrefix("zh") || code == "ja") ? "" : " "
}

