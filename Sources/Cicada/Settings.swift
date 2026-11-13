import AppKit
import Foundation

enum SourceMode: Equatable {
    case auto
    case fixed(Lang)
}

/// Persisted user choices. Everything the menu panel and settings sheet edit lives here.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var sourceMode: SourceMode {
        didSet { save() }
    }
    /// "system" or a translation code.
    @Published var target: String {
        didSet { save() }
    }
    /// What the subtitles show: "both" (original + translation), "translation", or "original"
    /// (nothing is translated, so no translator is called).
    @Published var subtitles: String {
        didSet { save() }
    }
    /// The language notes are written in: "mine" (the translate-to language, or the system's when
    /// that follows the system) or "source" (the meeting's own language).
    @Published var notesLanguage: String {
        didSet { save() }
    }
    @Published var speakEnabled: Bool {
        didSet { save() }
    }
    /// The user has seen what turning 同声传译 on changes (the panel asks once, in place).
    @Published var speakConfirmed: Bool {
        didSet { save() }
    }
    /// 不用按键: interpret whenever I speak, no key held (`HandsFreeDetector`). Mac only: the ports
    /// have no echo cancellation to hear me over the meeting.
    @Published var speakHandsFree: Bool {
        didSet { save() }
    }
    /// Locale of the language I speak.
    @Published var speakFrom: String {
        didSet { save() }
    }
    /// "room" (follow the detected room language) or a translation code.
    @Published var speakTo: String {
        didSet { save() }
    }
    /// Output device UID for spoken translations, "" = automatic.
    @Published var speakOutput: String {
        didSet { save() }
    }
    /// While speaking, make the virtual mic the system default input (and put it back after).
    @Published var autoSystemMic: Bool {
        didSet { save() }
    }
    /// The microphone Cicada records my voice from (UID), "" = the real mic the system had.
    @Published var speakMic: String {
        didSet { save() }
    }
    /// The real system input replaced by the virtual mic, kept until it's put back (survives a crash).
    @Published var savedSystemInput: String {
        didSet { save() }
    }
    @Published var recordAudio: Bool {
        didSet { save() }
    }
    /// 存到文件夹: settled meetings are also written as Markdown into `exportFolder` (a path; empty
    /// until one is chosen). Not a secret: it may sit in UserDefaults.
    @Published var exportOn: Bool {
        didSet { save() }
    }
    @Published var exportFolder: String {
        didSet { save() }
    }
    /// Imported files: the language they are in ("auto" or a locale), and whether notes are written
    /// once one is transcribed.
    @Published var importLanguage: String {
        didSet { save() }
    }
    @Published var importNotes: Bool {
        didSet { save() }
    }
    /// Subtitle bar: show only while someone talks ("auto") or always.
    @Published var overlayAuto: Bool {
        didSet { save() }
    }
    @Published var overlayHideAfter: Double {
        didSet { save() }
    }

    /// Hold to talk: the right ⌥ key (default) or a key combination.
    @Published var talkKey: Shortcut {
        didSet { save() }
    }
    /// Hide / show the subtitle bar.
    @Published var toggleKey: Shortcut {
        didSet { save() }
    }

    /// What shows while listening: "notes" (live notes window, default), "bar" (subtitle bar), "none".
    @Published var displayMode: String {
        didSet { save() }
    }
    /// The voice the room hears, per language ("en" → "ming:US_Emma", "system:<id>" or "clone").
    /// A language not listed uses `VoiceCatalog.defaultID`.
    @Published var speakVoices: [String: String] {
        didSet { save() }
    }
    /// Ling model for notes and translation.
    @Published var aiModel: String {
        didSet { save() }
    }
    /// The AI service: an `AIProvider.Kind` ("ling" unless the user picked another).
    @Published var aiProvider: String {
        didSet { save() }
    }
    /// Text and speech model per service other than Ling ("openrouter": "qwen/qwen3.8-flash"); a
    /// service not listed uses its first recommended model. "custom" in `aiVoiceModels` is the
    /// custom service's speech model, empty for none.
    @Published var aiModels: [String: String] {
        didSet { save() }
    }
    @Published var aiVoiceModels: [String: String] {
        didSet { save() }
    }
    /// The custom service: its address (an OpenAI-compatible `/v1`), and optionally another
    /// address for speech (empty: the same one) and the voice to ask for.
    @Published var aiCustomBase: String {
        didSet { save() }
    }
    @Published var aiCustomVoiceBase: String {
        didSet { save() }
    }
    @Published var aiCustomVoice: String {
        didSet { save() }
    }
    /// The custom service's speech recognition model (`/audio/transcriptions`, e.g. Qwen3-ASR) and
    /// its address (empty: the same one), and whether the meeting is recognized there instead of on
    /// this Mac (off by default: the audio then leaves the Mac).
    @Published var aiCustomHearModel: String {
        didSet { save() }
    }
    @Published var aiCustomHearBase: String {
        didSet { save() }
    }
    @Published var aiCustomRecognize: Bool {
        didSet { save() }
    }
    /// The custom service's notes: 另一个服务 (its own address, empty: the same one, and its own key
    /// in the `custom-notes` key file). Off keeps the address, so switching back and forth loses
    /// nothing. The notes model is `aiModels["custom.notes"]` (empty: the translation model).
    @Published var aiCustomNotesOwn: Bool {
        didSet { save() }
    }
    @Published var aiCustomNotesBase: String {
        didSet { save() }
    }
    /// 语音和文字只发给你的服务: with the custom service, Google Translate is never asked (partial
    /// lines show the original). Kept when another service is picked, but only acts on the custom one.
    @Published var aiCustomOnly: Bool {
        didSet { save() }
    }

    var provider: AIProvider { AIProvider.named(aiProvider) }

    /// What `LingClient` calls with: the service, its address and models.
    var aiConfig: AIConfig {
        let p = provider
        switch p.id {
        case .ling:
            return AIConfig(provider: p, base: p.base, textModel: aiModel, voiceModel: p.voiceModels.first?.id, voiceBase: p.base)
        case .custom:
            let base = AIProvider.customBase(aiCustomBase)
            let voice = (aiVoiceModels["custom"] ?? "").trimmingCharacters(in: .whitespaces)
            let voiceBase = aiCustomVoiceBase.isEmpty ? base : AIProvider.customBase(aiCustomVoiceBase)
            let name = aiCustomVoice.trimmingCharacters(in: .whitespaces)
            let hear = aiCustomHearModel.trimmingCharacters(in: .whitespaces)
            let hearBase = aiCustomHearBase.isEmpty ? base : AIProvider.customBase(aiCustomHearBase)
            let recognizes = aiCustomRecognize && !hear.isEmpty
            let textModel = aiModels["custom"] ?? ""
            let notesModel = (aiModels["custom.notes"] ?? "").trimmingCharacters(in: .whitespaces)
            let notesAddress = aiCustomNotesOwn ? aiCustomNotesBase.trimmingCharacters(in: .whitespaces) : ""
            let notesBase = notesAddress.isEmpty ? nil : AIProvider.customBase(notesAddress)
            return AIConfig(provider: p, base: base, textModel: textModel, voiceModel: voice.isEmpty ? nil : voice,
                            voiceBase: voiceBase, customVoice: name.isEmpty ? nil : name,
                            hearModel: recognizes ? hear : nil, hearBase: recognizes ? hearBase : nil,
                            notesModel: notesModel.isEmpty || notesModel == textModel ? nil : notesModel,
                            notesBase: notesBase == base ? nil : notesBase, notesOwnService: aiCustomNotesOwn,
                            notesBadAddress: !notesAddress.isEmpty && notesBase == nil)
        default:
            return AIConfig(provider: p, base: p.base, textModel: aiModels[p.id.rawValue] ?? p.textModels.first?.id ?? "",
                            voiceModel: p.hasVoices ? aiVoiceModels[p.id.rawValue] ?? p.voiceModels.first?.id : nil, voiceBase: p.base)
        }
    }

    /// The text model in use, for display.
    var textModel: String { aiConfig.textModel }

    /// Keep the icon in the Dock while Cicada runs. Off: menu bar only, the icon showing just while
    /// the main, settings or onboarding window is open.
    @Published var showInDock: Bool {
        didSet { save() }
    }

    /// End the meeting when the meeting app it was heard through hangs up.
    @Published var endWithApp: Bool {
        didSet { save() }
    }
    /// When nobody has said anything for `silenceMinutes`: "prompt" (count down, then end),
    /// "end" or "off". See `MeetingEndWatch`.
    @Published var silenceEnd: String {
        didSet { save() }
    }
    @Published var silenceMinutes: Double {
        didSet { save() }
    }

    /// Let screen recordings (and so screen sharing too: macOS has one switch for both) capture the
    /// notes window. Off by default; kept across launches like 始终置顶, so the window shows a badge.
    @Published var notesCapturable: Bool {
        didSet { save() }
    }

    /// Tell the other side's voices apart (说话人 1、2…). On by default.
    @Published var speakerVoices: Bool {
        didSet { save() }
    }

    /// Recognise people saved in the local voiceprint library. Enrolling a voice is always an
    /// explicit action with its own consent alert; this switch only controls automatic naming.
    @Published var speakerMemory: Bool {
        didSet { save() }
    }

    /// 会中改正听错的词: finished sentences carry the word list to the AI service, which points out
    /// misheard words (`Correction`). On by default; does nothing without an AI service.
    @Published var fixMisheard: Bool {
        didSet { save() }
    }

    /// 没见过的名字先问我: a new name is asked about once instead of left as heard.
    @Published var askNames: Bool {
        didSet { save() }
    }

    /// Record per-sentence timings (never text) and show the 诊断 tab. On by default in dev builds.
    /// 听哪里: "system" (what the Mac plays), "room" (a real microphone, for a meeting in the room) or
    /// "both" (电脑和会议室: people online and in the room, each heard on its own).
    @Published var listenSource: String {
        didSet { save() }
    }
    /// The microphone chosen beside 打开麦克风, by UID; empty is 自动. Never the system default's.
    @Published var roomMicUID: String {
        didSet { save() }
    }
    /// Only the room: nothing is in a call on this Mac (the translation is read out of the speakers).
    var listensToRoom: Bool { listenSource == "room" }
    /// The room mic is open: 会议室 or 电脑和会议室.
    var hearsRoom: Bool { listenSource != "system" }
    var hearsBoth: Bool { listenSource == "both" }

    @Published var diagnostics: Bool {
        didSet { save() }
    }

    var debug: Bool { defaults.bool(forKey: "debug") }

    init() {
        if let s = defaults.string(forKey: "sourceMode"), s != "auto",
           let lang = sourceLanguages.first(where: { $0.locale == s }) {
            sourceMode = .fixed(lang)
        } else {
            sourceMode = .auto
        }
        target = defaults.string(forKey: "target") ?? "system"
        subtitles = defaults.string(forKey: "subtitles") ?? "both"
        notesLanguage = defaults.string(forKey: "notesLanguage") ?? "mine"
        speakEnabled = defaults.bool(forKey: "speakEnabled")
        // Anyone who had it on before this question existed already knows.
        speakConfirmed = defaults.object(forKey: "speakConfirmed") as? Bool ?? defaults.bool(forKey: "speakEnabled")
        speakFrom = defaults.string(forKey: "speakFrom")
            ?? speakLocale(forLanguage: Cicada.myLanguage(systemLanguages: Locale.preferredLanguages))
        speakHandsFree = defaults.bool(forKey: "speakHandsFree")
        speakTo = defaults.string(forKey: "speakTo") ?? "room"
        speakOutput = defaults.string(forKey: "speakOutput") ?? ""
        autoSystemMic = defaults.object(forKey: "autoSystemMic") as? Bool ?? true
        speakMic = defaults.string(forKey: "speakMic") ?? ""
        savedSystemInput = defaults.string(forKey: "savedSystemInput") ?? ""
        recordAudio = defaults.object(forKey: "recordAudio") as? Bool ?? true
        exportOn = defaults.bool(forKey: "exportOn")
        exportFolder = defaults.string(forKey: "exportFolder") ?? ""
        importLanguage = defaults.string(forKey: "importLanguage") ?? "auto"
        importNotes = defaults.object(forKey: "importNotes") as? Bool ?? true
        overlayAuto = defaults.object(forKey: "overlayAuto") as? Bool ?? true
        overlayHideAfter = defaults.object(forKey: "overlayHideAfter") as? Double ?? 4
        talkKey = Shortcut(stored: defaults.string(forKey: "talkKey")) ?? .defaultTalk
        toggleKey = Shortcut(stored: defaults.string(forKey: "toggleKey")) ?? .defaultToggle
        aiModel = defaults.string(forKey: "aiModel") ?? "Ling-3.1-flash"
        aiProvider = defaults.string(forKey: "aiProvider") ?? "ling"
        aiModels = defaults.dictionary(forKey: "aiModels") as? [String: String] ?? [:]
        aiVoiceModels = defaults.dictionary(forKey: "aiVoiceModels") as? [String: String] ?? [:]
        aiCustomBase = defaults.string(forKey: "aiCustomBase") ?? ""
        aiCustomVoiceBase = defaults.string(forKey: "aiCustomVoiceBase") ?? ""
        aiCustomVoice = defaults.string(forKey: "aiCustomVoice") ?? ""
        aiCustomHearModel = defaults.string(forKey: "aiCustomHearModel") ?? ""
        aiCustomHearBase = defaults.string(forKey: "aiCustomHearBase") ?? ""
        aiCustomRecognize = defaults.bool(forKey: "aiCustomRecognize")
        aiCustomOnly = defaults.bool(forKey: "aiCustomOnly")
        aiCustomNotesOwn = defaults.bool(forKey: "aiCustomNotesOwn")
        aiCustomNotesBase = defaults.string(forKey: "aiCustomNotesBase") ?? ""
        displayMode = defaults.string(forKey: "displayMode") ?? "notes"
        speakVoices = defaults.dictionary(forKey: "speakVoices") as? [String: String] ?? [:]
        endWithApp = defaults.object(forKey: "endWithApp") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        silenceEnd = defaults.string(forKey: "silenceEnd") ?? "prompt"
        silenceMinutes = defaults.object(forKey: "silenceMinutes") as? Double ?? 10
        listenSource = ["room", "both"].contains(defaults.string(forKey: "listenSource")) ? defaults.string(forKey: "listenSource")! : "system"
        roomMicUID = defaults.string(forKey: "roomMicUID") ?? ""
        diagnostics = defaults.object(forKey: "diagnostics") as? Bool ?? DevBuild.isDev
        notesCapturable = defaults.bool(forKey: "notesCapturable")
        fixMisheard = defaults.object(forKey: "fixMisheard") as? Bool ?? true
        askNames = defaults.object(forKey: "askNames") as? Bool ?? true
        // Off by default while it was an experiment, and save() stores every key, so a stored false
        // mostly means "never touched": turn it on once for everyone when it became a regular feature.
        if defaults.bool(forKey: "speakerVoicesRegular") {
            speakerVoices = defaults.bool(forKey: "speakerVoices")
        } else {
            speakerVoices = true
            defaults.set(true, forKey: "speakerVoices")
            defaults.set(true, forKey: "speakerVoicesRegular")
        }
        speakerMemory = defaults.object(forKey: "speakerMemory") as? Bool ?? true
    }

    private func save() {
        switch sourceMode {
        case .auto: defaults.set("auto", forKey: "sourceMode")
        case .fixed(let lang): defaults.set(lang.locale, forKey: "sourceMode")
        }
        defaults.set(target, forKey: "target")
        defaults.set(subtitles, forKey: "subtitles")
        defaults.set(notesLanguage, forKey: "notesLanguage")
        defaults.set(speakEnabled, forKey: "speakEnabled")
        defaults.set(speakConfirmed, forKey: "speakConfirmed")
        defaults.set(speakFrom, forKey: "speakFrom")
        defaults.set(speakHandsFree, forKey: "speakHandsFree")
        defaults.set(speakTo, forKey: "speakTo")
        defaults.set(speakOutput, forKey: "speakOutput")
        defaults.set(autoSystemMic, forKey: "autoSystemMic")
        defaults.set(speakMic, forKey: "speakMic")
        defaults.set(savedSystemInput, forKey: "savedSystemInput")
        defaults.set(recordAudio, forKey: "recordAudio")
        defaults.set(exportOn, forKey: "exportOn")
        defaults.set(exportFolder, forKey: "exportFolder")
        defaults.set(importLanguage, forKey: "importLanguage")
        defaults.set(importNotes, forKey: "importNotes")
        defaults.set(overlayAuto, forKey: "overlayAuto")
        defaults.set(overlayHideAfter, forKey: "overlayHideAfter")
        defaults.set(talkKey.stored, forKey: "talkKey")
        defaults.set(toggleKey.stored, forKey: "toggleKey")
        defaults.set(aiModel, forKey: "aiModel")
        defaults.set(aiProvider, forKey: "aiProvider")
        defaults.set(aiModels, forKey: "aiModels")
        defaults.set(aiVoiceModels, forKey: "aiVoiceModels")
        defaults.set(aiCustomBase, forKey: "aiCustomBase")
        defaults.set(aiCustomVoiceBase, forKey: "aiCustomVoiceBase")
        defaults.set(aiCustomVoice, forKey: "aiCustomVoice")
        defaults.set(aiCustomHearModel, forKey: "aiCustomHearModel")
        defaults.set(aiCustomHearBase, forKey: "aiCustomHearBase")
        defaults.set(aiCustomRecognize, forKey: "aiCustomRecognize")
        defaults.set(aiCustomOnly, forKey: "aiCustomOnly")
        defaults.set(aiCustomNotesOwn, forKey: "aiCustomNotesOwn")
        defaults.set(aiCustomNotesBase, forKey: "aiCustomNotesBase")
        defaults.set(displayMode, forKey: "displayMode")
        defaults.set(speakVoices, forKey: "speakVoices")
        defaults.set(endWithApp, forKey: "endWithApp")
        defaults.set(showInDock, forKey: "showInDock")
        defaults.set(silenceEnd, forKey: "silenceEnd")
        defaults.set(silenceMinutes, forKey: "silenceMinutes")
        defaults.set(listenSource, forKey: "listenSource")
        defaults.set(roomMicUID, forKey: "roomMicUID")
        defaults.set(diagnostics, forKey: "diagnostics")
        defaults.set(notesCapturable, forKey: "notesCapturable")
        defaults.set(speakerVoices, forKey: "speakerVoices")
        defaults.set(speakerMemory, forKey: "speakerMemory")
        defaults.set(fixMisheard, forKey: "fixMisheard")
        defaults.set(askNames, forKey: "askNames")
    }

    /// Target language. "Follow system" translates into my language, or into the next system
    /// language when they speak mine.
    func resolvedTarget(source: String?) -> String {
        target == "system" ? followSystemTarget(source: source, systemLanguages: Locale.preferredLanguages) : target
    }

    /// The reader's own language: the translate-to choice, or with "follow system" the one
    /// `myLanguage(systemLanguages:)` picks. Notes in 我的语言 use it too.
    var myLanguage: String {
        target == "system" ? Cicada.myLanguage(systemLanguages: Locale.preferredLanguages) : target
    }

    /// "简体中文 / English": my language, then what it translates into when they speak mine.
    func systemTargetDescription() -> String {
        let prefs = Locale.preferredLanguages
        let mine = Cicada.myLanguage(systemLanguages: prefs)
        return [mine, followSystemTarget(source: mine, systemLanguages: prefs)].map(targetName).joined(separator: " / ")
    }

    var speakFromLang: Lang {
        sourceLanguages.first(where: { $0.locale == speakFrom }) ?? sourceLanguages[0]
    }
}

func debugLog(_ message: String) {
    if Thread.isMainThread, debugLogCapture != nil { debugLogCapture?.append(message) }
    let line = "\(Date()) \(message)\n"
    let path = DevBuild.logPath
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Transcript content is only logged when `defaults write com.wquguru.cicada debug -bool true`.
func contentLog(_ message: @autoclosure () -> String) {
    if UserDefaults.standard.bool(forKey: "debug") { debugLog(message()) }
}

extension AppSettings: FixSwitches {}
