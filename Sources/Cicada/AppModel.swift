import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import Network
import SwiftUI
import Speech
import UserNotifications

/// Wires the engines, the meeting store, the subtitle bar and the UI together.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let store = SessionStore()
    let overlay = OverlayController()
    let talkCombo = HotKey(id: 1, shortcut: .defaultTalk)
    let talkRight = RightOptionKey()
    let toggleKey = HotKey(id: 2, shortcut: .defaultToggle)
    lazy var listen = ListenEngine(settings: settings)
    /// The one echo-cancelling mic unit, shared by the talk key and 电脑和会议室's room.
    let voiceMic = VoiceMic()
    lazy var speak = SpeakEngine(settings: settings, voiceMic: voiceMic)
    /// 电脑和会议室: the microphone side, its own engine (language, pauses, model), as Feishu keeps the
    /// online and the room streams apart instead of mixing them into one track.
    lazy var roomListen = ListenEngine(settings: settings, role: .room)
    /// Debug (`roomEcho:on|off|bypass`, `roomGate:off`), next meeting. By default the room is heard
    /// through the echo-cancelling unit with its processing off (`bypass`): the plain mic's sound and
    /// the gate, as `RoomMic` (processing on let no echo through but lost most of what people at the
    /// table said), while the talk key turns processing on for a press. With the plain mic the press
    /// had no echo cancellation and was dropped whenever the other side was talking.
    var roomEchoCancel = true
    var roomEchoBypass = true
    var roomEchoGate = true
    /// The Mac's lines of late (wall clock), and room lines waiting to be told apart from their echo.
    private var recentOnline: [EchoMatch.Heard] = []
    /// The meeting's last 30 s, its lines and their translations, for 不用按键 to tell its echo.
    private var recentMeeting: [EchoMatch.Heard] = []
    private var recentMeetingSegs: [Int: (start: Double, end: Double)] = [:]
    private(set) var heldRoom: [(id: Int, seg: Segment, duration: Double, heard: EchoMatch.Heard)] = []
    /// What each engine shows as the line in progress, and when it last changed.
    private var liveMain = (src: "", dst: "", at: Date.distantPast)
    private var liveRoom = (src: "", dst: "", at: Date.distantPast)
    lazy var speakTester = SpeakTester(speak: speak, ling: ling, settings: settings)
    /// Key released → the room heard the first sound, from the latest real press or sound test.
    @Published var lastSpeakLatency: Double? = UserDefaults.standard.object(forKey: "lastSpeakLatency") as? Double {
        didSet { UserDefaults.standard.set(lastSpeakLatency, forKey: "lastSpeakLatency") }
    }
    /// The 试一句 sheet in settings.
    @Published var speakTestShown = false
    /// The panel is asking, the first time, what turning 同声传译 on changes.
    @Published var speakAsking = false
    /// Meeting apps and the microphone each reads; refreshed every second once the virtual mic exists.
    @Published var micUsers: [MicUser] = []
    lazy var systemMic = SystemMic(settings: settings)
    /// Whether the system default input is the virtual mic, and anything left to put back.
    @Published private(set) var systemMicState: SystemMic.State = .off
    /// The app whose "怎么改" sheet is open in Settings.
    @Published var micGuide: MicUser?
    /// Settings › 同声传译: the voice list under "对方听到" is open.
    @Published var voicePickerOpen = false
    /// Settings › AI 服务's 自己选模型 is unfolded.
    @Published var aiModelsOpen = false

    @Published private(set) var running = false
    /// The meeting is about to end by itself (a hang-up or a long silence) unless someone keeps it going.
    @Published private(set) var ending: MeetingEndWatch.Pending?
    /// The last meeting ended by itself: the menu says so, and the next call in a meeting app starts a new one.
    @Published private(set) var autoEnded = false
    /// The notes window is on screen: the menu bar panel's 显示 / 收起 follows it.
    @Published private(set) var notesShown = false
    private var endWatch: MeetingEndWatch?
    private var endTimer: Timer?
    /// Debug: meeting apps in a call instead of what Core Audio says, and shorter waits.
    private var fakeCalls: [String: String]?
    private var endTimesOverride: (silence: Double, countdown: Double, grace: Double)?
    @Published var status = L("准备就绪")
    @Published private(set) var summary = ""
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var candidates: [Lang] = []
    /// 听不出: the languages offered while "auto" can't tell (empty when it can).
    @Published private(set) var languageAsk: [Lang] = []
    /// The second speech model coming in the background: its name and how far along.
    @Published private(set) var modelFetch: ModelFetch?
    /// 先用○○听: offered, listening, or just handed back to this Mac.
    @Published private(set) var cloud = CloudState()
    /// 继续等 was chosen: the offer stays away until the next meeting.
    private var cloudDeclined = false
    @Published private(set) var identifyingLanguage = false
    /// 电脑和会议室 with the microphone not allowed (since when): the Mac's side goes on, the room's can't start.
    @Published private(set) var micDeniedSince: Date?
    var hybridMicDenied: Bool { micDeniedSince != nil }
    /// Debug (`micDeniedSim`): 电脑和会议室 acts as if the microphone were refused.
    private var fakeMicDenied = false
    /// Something only you can fix, said beyond the panel (shut while you meet): the menu bar's dot
    /// and its tooltip. The microphone also goes to the notes window, the subtitle bar and, once a
    /// meeting, a notification.
    @Published private(set) var problem: String?
    /// The notification went out: once a meeting, however often the microphone is refused again.
    private var micDeniedNotified = false
    /// 麦克风没声音: the room mic stayed digital silence after being opened again.
    @Published private(set) var roomMicSilent = false
    /// 外接麦克风断开了: what happened instead (RoomMicLoss), for a few seconds.
    @Published var roomMicLost: String?
    /// The debug command's pretend unplug: these inputs count as gone.
    private var fakeGoneMics: Set<String> = []
    /// Why the model 听不出 needed couldn't be had, when that is so.
    @Published private(set) var modelProblem: ModelProblem?
    /// That model was the one to start with and there is none to fall back on: nothing is listening.
    @Published private(set) var modelBlocked = false
    /// 听不出 because none of the installed models hear their language: it offers ones not installed.
    @Published private(set) var languageNotInstalled = false
    @Published var outputs: [OutputDevice] = []
    @Published var speakPhase: SpeakEngine.Phase = .idle
    @Published var settingsSection: SettingsSection =
        SettingsSection(rawValue: UserDefaults.standard.string(forKey: "settingsSection") ?? "") ?? .speak {
        didSet {
            UserDefaults.standard.set(settingsSection.rawValue, forKey: "settingsSection")
            // People pick a voice and move on: don't greet them with the list still open next time.
            if settingsSection != oldValue { voicePickerOpen = false }
        }
    }
    @Published private(set) var systemAudio = SystemAudioAccess.unknown
    var systemAudioOK: Bool { systemAudio == .granted }
    var systemAudioRefused: Bool { systemAudio == .refused }
    /// Quitting to reopen (`relaunch`): closing the guide now isn't finishing it.
    var relaunching = false
    /// Speech recognition can run: always on macOS 26; below it, Dictation on and 语音识别 allowed.
    @Published var speechOK = Recognition.ready
    /// Step 1 of the guide is done.
    var listenReady: Bool { systemAudioOK && speechOK }
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var liveSource = ""
    /// Lines whose words the record's own recognizer hasn't settled yet (the notes window says 校准中).
    @Published private(set) var settling: Set<String> = []
    /// Lines whose voiceprint is still being worked out: no voice yet is not "like no voice".
    @Published private(set) var voicePending: Set<String> = []
    @Published var liveTranslation = ""
    @Published var onboardingStep = 1
    /// Step 3 is showing what skipping the key leaves out (debug: `onboarding:3,skip`).
    @Published var onboardingKeySkip = false
    /// What step 4 shows (debug: `onboarding:4,ask` / `onboarding:4,setup`).
    enum SpeakStep { case followSetting, ask, checklist }
    /// Step 4's yes/no or checklist; until one is chosen, the checklist if speaking is already on.
    @Published var onboardingSpeakSetup = SpeakStep.followSetting
    /// Debug: which meeting and tab the main window shows ("<id>" or "<id>,transcript").
    @Published var mainShow: String?
    /// Hold right ⌥ is chosen but "输入监控" isn't allowed yet.
    @Published var talkNeedsPermission = false
    /// Google translation unreachable, and whether sentences go untranslated (`TranslationService.health`).
    @Published var translationHealth = TranslationHealth()
    @Published var toggleKeyTaken = false
    private var permissionPoll: Timer?
    private var shortcutsSuspended = false
    let installer = VirtualMicInstaller()
    let ling = LingClient()
    /// Network changes (a proxy app turned on, Wi-Fi back): the AI service is looked at again
    /// when it was unreachable. No timer: nothing is checked while the network stays the same.
    private let networkMonitor = NWPathMonitor()
    private var networkDebounce: DispatchWorkItem?
    lazy var translator = TranslationService(ling: ling)
    let diagnostics = Diagnostics()
    let updates = Updates()
    let loginItem = LoginItem()
    lazy var notes = NotesEngine(ling: ling, store: store)
    /// 存到文件夹 (settings › 通用).
    lazy var folderExport = FolderExporter(store: store, settings: settings)
    lazy var notesWindow = NotesWindowController(model: self)
    lazy var importer = FileImporter(store: store, settings: settings, translator: translator, profiles: profiles)
    let vocabulary = Vocabulary(url: Vocabulary.defaultURL)
    lazy var fixes = LiveFixes(store: store, vocabulary: vocabulary, settings: settings)
    let sample = SamplePlayer()
    let speakers = SpeakerTagger()
    /// The local voiceprint library; never sent anywhere. See SpeakerProfiles.swift.
    let profiles = SpeakerProfileStore()
    /// A UI copy of `profiles`, refreshed by its onChange callback.
    @Published private(set) var speakerProfiles: [SpeakerProfile] = []
    @Published var speakerLibraryShown = false
    @Published private(set) var speakerMemoryBusy = false
    lazy var speakerNamer = SpeakerNamer(ling: ling, store: store)
    /// The last speaker edit, offered as 撤销 at the bottom of both windows for a few seconds.
    @Published var speakerUndo: SpeakerUndo?
    private var speakerSetting: AnyCancellable?
    private var speakerMemorySetting: AnyCancellable?
    private var handsFreeSetting: AnyCancellable?
    /// 开始听时打开麦克风 already opened it for this meeting's call.
    private var micAutoOpened = false
    var openOnboarding: (() -> Void)?

    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    var showPanel: (() -> Void)?
    /// Opens the menu bar panel, leaving it open if it already is.
    var openPanel: (() -> Void)?

    private var lineForSegment: [Int: String] = [:]
    private var lineCounter = 0
    /// The other side's last recorded line, which the next one may carry on (`HeardText.continues`).
    private var lastHeard: (seg: Segment, line: String)?
    /// A line that may carry on `lastHeard`, waiting to hear whose voice it is; its translation if
    /// that comes first.
    private var heldJoin: (seg: Segment, t: Double, translation: String?)?
    /// Lines the record's own recognizer is still settling (`ListenEngine.onRefined`): each line's
    /// meeting and its segments in order (several after a join), each with the live recognizer's text.
    private var refining: [String: (session: String, segs: [(id: Int, text: String, settled: String?)])] = [:]
    private var refiningOrder: [String] = []
    private var lineOfSegment: [Int: String] = [:]
    /// Settled before its line was recorded (a line waiting for its voice, the language or an echo check).
    private var settledEarly: [Int: String] = [:]
    /// Lines with their record text: the live recognizer's translations no longer replace theirs.
    private var refinedLines: Set<String> = []

    init() {
        // A meeting or speaking holds the update notification until it ends (see stop()).
        updates.busy = { [weak self] in guard let self else { return false }; return self.running || self.speak.phase != .idle }
        // Words in the Mac's audio: speech, which the room mic is silenced for (music isn't, `EchoGate`).
        listen.onWords = { [gate = roomListen.echoGate] in gate.heardWords() }
        speak.micTaken = { [weak self] in
            guard let self else { return false }
            return self.roomListen.holdsPlainMic || self.listen.holdsPlainMic
        }
        speak.playedShare = { [gate = roomListen.echoGate] from, to in
            gate.playedShare(from: from.timeIntervalSinceReferenceDate, to: to.timeIntervalSinceReferenceDate)
        }
        roomListen.onStateChange = { [weak self] in self?.refresh() }
        listen.onSubtitle = { [weak self] src, dst in
            guard let self else { return }
            // Someone is speaking either way; only the wrong model's words aren't shown.
            self.liveMain = (self.listen.hidesSource ? "" : src, dst, Date())
            self.showLive(spoke: src)
        }
        roomListen.onSubtitle = { [weak self] src, dst in
            guard let self else { return }
            self.liveRoom = (self.roomListen.hidesSource ? "" : src, dst, Date())
            self.showLive(spoke: src)
        }
        listen.onStatus = { [weak self] text in
            self?.status = text
            self?.overlay.setStatus(text)
        }
        listen.onStateChange = { [weak self] in self?.refresh() }
        listen.onFinal = { [weak self] seg, duration in self?.heardOnline(seg, duration: duration) }
        roomListen.onFinal = { [weak self] seg, duration in self?.heardInRoom(seg, duration: duration) }
        roomListen.onStatus = { debugLog("room engine: \($0)") }
        speakers.onVoice = { [weak self] line, voice in
            guard let self else { return }
            self.store.setVoice(lineID: line, voice)
            if let id = self.store.liveID { self.speakerNamer.guess(id) }
        }
        speakerProfiles = profiles.all()
        profiles.onChange = { [weak self] all in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speakerProfiles = all } }
        }
        speakers.profiles = profiles
        speakers.onProfile = { [weak self] line, voice, match in
            guard let self, let id = self.store.liveID else { return }
            self.store.setVoice(lineID: line, voice)
            self.store.setVoiceProfile(id, voice: voice, ref: match.ref)
            self.profiles.markSeen(id: match.profile.id)
            self.speakerNamer.guess(id)
        }
        speakers.onSuggestion = { [weak self] line, voice, match in
            guard let self, let id = self.store.liveID else { return }
            self.store.setVoice(lineID: line, voice)
            self.store.setVoiceSuggestion(id, voice: voice, match.ref)
        }
        // 不用按键 runs only while a meeting is being listened to: its lines are what tells the meeting's
        // echo (`meetingSaid`), and the running unit mutes the built-in mic for other apps (#24), which
        // then hear the virtual mic anyway. It pauses while 打开麦克风 is on: the room shares the unit and
        // is heard unprocessed, and everyone at the table would be interpreted as me.
        handsFreeSetting = Publishers.CombineLatest4(settings.$speakHandsFree, settings.$listenSource, settings.$speakEnabled, $running)
            .sink { [weak self] on, _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.speak.handsFree = on && self.settings.speakEnabled && !self.settings.hearsRoom && self.running
                        self.speak.keepUnit = self.settings.speakEnabled && self.running
                        self.speak.refreshHandsFree()
                    }
                }
            }
        speakerSetting = settings.$speakerVoices.sink { [weak self] on in
            TranscriptExport.voices = on
            self?.listen.router.setVoiceCapture(on)
            self?.roomListen.router.setVoiceCapture(on)
        }
        speakers.profiles = settings.speakerMemory ? profiles : nil
        speakerMemorySetting = settings.$speakerMemory.sink { [weak self] on in
            self?.speakers.profiles = on ? self?.profiles : nil
        }
        listen.onTranslated = { [weak self] segID, text in self?.translated(segID, text) }
        roomListen.onTranslated = { [weak self] segID, text in self?.translated(segID, text) }
        listen.onRefined = { [weak self] segID, text in self?.refined(segID, text) }
        roomListen.onRefined = { [weak self] segID, text in self?.refined(segID, text) }

        diagnostics.enabled = { [weak self] in self?.settings.diagnostics ?? false }
        diagnostics.folder = { [weak self] in
            guard let self, let id = self.store.liveID else { return nil }
            return self.store.folder(id)
        }
        listen.onTiming = { [weak self] in self?.diagnostics.record($0) }
        roomListen.onTiming = { [weak self] in self?.diagnostics.record($0) }
        speak.onTiming = { [weak self] in self?.diagnostics.record($0) }
        speak.onLatency = { [weak self] in self?.lastSpeakLatency = $0 }
        speakTester.onLatency = { [weak self] in self?.lastSpeakLatency = $0 }
        speakTester.translate = { [weak self] text, from, to in
            await self?.listen.translate(text, source: from, target: to, kind: .speak, trace: TranslateTrace())
        }
        ling.onCall = { [weak self] in self?.diagnostics.record($0) }
        ling.proxyHint = { await ProxyProbe.hint() }
        ling.localNetworkProbe = { await LocalNetworkProbe.denied($0) }
        watchNetwork()
        translator.onDraft = { [weak self] in self?.diagnostics.recordDraft(seconds: $0, ok: $1) }
        translator.onHealth = { [weak self] in self?.translationHealth = $0 }
        translator.proxyHint = { await ProxyProbe.hint() }

        ling.config = { [weak self] in self?.settings.aiConfig ?? AIConfig(provider: .ling, base: AIProvider.ling.base, textModel: "Ling-3.1-flash") }
        listen.translator = translator
        roomListen.translator = translator
        roomListen.voiceMic = voiceMic
        listen.voiceMic = voiceMic   // 会议室 alone: lets go of a leftover unit before the plain mic
        // Making or letting go of the echo-cancelling unit silences, for good, audio already flowing in
        // this process: the voice output (the room would hear nothing) and the Mac's audio tap (the
        // meeting would go unheard; measured: no line after it). Each is started anew.
        voiceMic.onUnitChanged = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.speak.newOutputEngine()
                if self.listen.isRunning { self.listen.reconnectAudio() }
                if self.roomListen.isRunning, !self.roomListen.hearsEchoCancelled { self.roomListen.reconnectAudio() }
            }
        }
        translator.glossary = { [weak self] in self?.notes.glossary ?? [] }
        translator.fixContext = { [weak self] text in self?.fixes.context(for: text) }
        translator.onFixes = { [weak self] text, edits in self?.fixes.received(text, edits) }
        fixes.onLineFixed = { [weak self] id, line in self?.lineFixed(id, line) }
        fixes.onChange = { [weak self] in self?.objectWillChange.send() }
        // An Intel Mac's imports: heard at a lower priority than the live meeting.
        Recognition.cloudHear = { [weak self] wav, seconds, locale in
            guard let self else { return nil }
            let hint = sourceLanguages.first { $0.locale == locale }?.code
            do {
                return try await self.translator.hear(wav: wav, seconds: seconds, target: self.settings.resolvedTarget(source: hint),
                                                      hint: hint, priority: .notes)
            } catch {
                // A stretch not heard is not silence: the import stays unfinished and offers 重新转写.
                debugLog("import: hear failed: \(error)")
                self.importer.hearFailures += 1
                return nil
            }
        }
        importer.onFinished = { [weak self] id in self?.importFinished(id) }
        // 存到文件夹: written once a record is settled, rewritten when it changes.
        folderExport.settling = { [weak self] id in self?.notes.settling(id) ?? false }
        store.onSave = { [weak self] id in self?.folderExport.saved(id) }
        notes.finalDone = { [weak self] id in self?.folderExport.settled(id) }
        folderExport.retry()
        notes.language = { [weak self] id in
            TranslationService.englishName(self?.notesLanguageCode(id) ?? "zh-CN")
        }
        listen.translationOff = { [weak self] in self?.subtitles == "original" }
        roomListen.translationOff = { [weak self] in self?.subtitles == "original" }
        applyAIService()

        installer.speakThrough = { [weak self] text, lang, device in
            await self?.speak.speak(text, language: lang, device: device)
        }
        installer.onLoaded = { [weak self] in self?.virtualMicInstalled() }

        speak.translate = { [weak self] text, from, to, trace in
            await self?.listen.translate(text, source: from, target: to, kind: .speak, trace: trace)
        }
        speak.interpret = { [weak self] wav, from, to, trace in
            await self?.translator.interpret(wav: wav, source: from, target: to, trace: trace)
        }
        speak.roomLanguage = { [weak self] in self?.listen.activeLang?.code }
        speak.inputDevice = { [weak self] in self?.systemMic.recordingDevice }
        let roomMic = { [weak self] () -> OutputDevice? in
            MainActor.assumeIsolated { AudioDevices.roomMic(excluding: self?.fakeGoneMics ?? [], preferredUID: self?.settings.roomMicUID) }
        }
        listen.roomDevice = roomMic
        roomListen.roomDevice = roomMic
        applyVoice()
        speak.onStatus = { [weak self] text in self?.status = text }
        speak.onNotice = { [weak self] text in self?.speakNotice(text) }
        speak.onLive = { [weak self] phase, src, dst in
            guard let self else { return }
            self.muteRoomWhileSpeaking(phase)
            self.speakPhase = phase
            // A 试一句 rehearsal shows in its own sheet: no notes window, caption or subtitle bar.
            if self.speakTester.busy { return }
            if phase == .listening && !src.isEmpty { self.heardSpeech(); self.heardWords() }
            guard self.settings.displayMode == "bar" else {
                // The notes window's caption line shows what you are saying.
                if phase != .idle || !src.isEmpty {
                    self.liveSource = src.isEmpty ? L("你正在说…") : L("你：\(src)")
                    self.liveTranslation = dst
                }
                return
            }
            if !self.overlay.isShown { self.overlay.show() }
            if phase == .idle && src.isEmpty {
                self.overlay.setSpeaking(nil)
            } else {
                self.overlay.setSpeaking(.init(phase: phase, source: src, translation: dst))
            }
        }
        speak.meetingSaid = { [weak self] text, from, to in
            let heard = EchoMatch.Heard(text: text, start: from.timeIntervalSinceReferenceDate, end: to.timeIntervalSinceReferenceDate)
            guard let self else { return false }
            if EchoMatch.isEcho(heard, online: self.recentMeeting) { return true }
            // The meeting was playing: its line (and translation) may land a moment after Ming's answer.
            guard self.listen.router.stats().silenceRun < EchoMatch.window else { return false }
            try? await Task.sleep(nanoseconds: UInt64(EchoMatch.hold * 1_000_000_000))
            return EchoMatch.isEcho(heard, online: self.recentMeeting)
        }
        speak.onUtterance = { [weak self] src, dst, from, to, ago in
            self?.recordSaid(src, dst, from: from, to: to, secondsAgo: ago)
        }

        let began: () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressBegan() } }
        }
        let ended: () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressEnded() } }
        }
        talkCombo.onDown = began
        talkCombo.onUp = ended
        talkRight.onDown = began
        talkRight.onUp = ended
        talkRight.onCancel = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressCancelled() } }
        }
        overlay.onMic = { [weak self] in MainActor.assumeIsolated { guard let self else { return }; self.setMic(!self.micOn) } }
        overlay.onCollapsed = { [weak self] in
            self?.listen.clearDisplay()
            self?.overlay.setSubtitle(source: "", translation: "")
        }
        overlay.mode = { [weak self] in
            (self?.settings.overlayAuto ?? true, self?.settings.overlayHideAfter ?? 4)
        }
        toggleKey.onDown = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.cycleDisplay() } }
        }
        applyToggleKey()
        refreshOutputs()
        let watch = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.watchEnd()
                self?.watchRoomMic()
            }
        }
        endTimer = watch
        RunLoop.main.add(watch, forMode: .common)
    }

    /// The room's microphone unplugged: Core Audio moves the engine to the system default without a
    /// word, which may be a headset or the virtual mic. Pick again the way the meeting started, and say so.
    private func watchRoomMic() {
        let both = settings.hearsBoth && roomListen.isRunning
        guard let engine = both ? roomListen : settings.listensToRoom && listen.isRunning ? listen : nil,
              let uid = engine.roomMicUID,
              fakeGoneMics.contains(uid) || !AudioDevices.inputs().contains(where: { $0.uid == uid }) else { return }
        let next = AudioDevices.roomMic(excluding: fakeGoneMics, preferredUID: settings.roomMicUID)
        debugLog("room mic gone: \(uid) → \(next?.name ?? "none")")
        if next != nil { engine.reconnectAudio() } else if both { stopRoomSide() } else { stop() }
        let note = RoomMicLoss.detail(next: next?.name, builtIn: next.map { AudioDevices.transport($0.id) == kAudioDeviceTransportTypeBuiltIn } ?? false,
                                      both: both)
        roomMicLost = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.roomMicLost == note { self?.roomMicLost = nil }
        }
        refresh()
    }

    func pickLanguage(_ lang: Lang) { listen.pickLanguage(lang) }
    func retryModel() { listen.retryModel() }
    func startCloud() { listen.startCloud(); refresh() }
    func stopCloud() { listen.stopCloud(); refresh() }
    func declineCloud() {
        debugLog("cloud: offer declined")
        cloudDeclined = true
        refresh()
    }
    func openDictationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
    }

    func setOverlayAuto(_ on: Bool) {
        settings.overlayAuto = on
        overlay.modeChanged()
        objectWillChange.send()
    }

    func launch() async {
        await listen.refreshInstalledLocales()
        refresh()
        // Listening starts by itself at launch: never with the microphone open. 会议室 is chosen
        // for the meeting at hand, not kept for the next login.
        if settings.hearsRoom { settings.listenSource = "system" }
        start()
        if settings.speakEnabled { enableSpeaking(true) }
    }

    func refresh() {
        running = listen.isRunning
        // Once the tap has run, the permission is there: pausing doesn't take it away.
        if listen.isRunning && !settings.listensToRoom && systemAudio != .granted { systemAudio = .granted }
        summary = settings.listensToRoom ? L("麦克风 · \(listen.languageSummary())")
            : settings.hearsBoth ? L("电脑和麦克风 · \(listen.languageSummary())") : listen.languageSummary()
        candidates = listen.candidates
        installed = listen.installedLocales
        let ask = listen.asksLanguage ? listen.askChoices : []
        if ask != languageAsk { languageAsk = ask }
        let fetch = listen.downloading.map { ModelFetch(name: $0.lang.name, since: $0.since, background: $0.background) }
        if fetch != modelFetch { modelFetch = fetch }
        if !listen.isRunning { cloudDeclined = false }
        let cloudNow = CloudState(service: listen.cloudService, offered: listen.offersCloud && !cloudDeclined,
                                  listening: listen.cloudListening, back: listen.cloudBack?.name)
        if cloudNow != cloud { cloud = cloudNow }
        if listen.identifyingLanguage != identifyingLanguage { identifyingLanguage = listen.identifyingLanguage }
        checkProblem()
        let silent = micOn && (settings.hearsBoth ? roomListen : listen).roomMicSilent
        if silent != roomMicSilent { roomMicSilent = silent }
        overlay.setMic(micOn)
        if listen.modelProblem != modelProblem { modelProblem = listen.modelProblem }
        if listen.blockedByModel != modelBlocked { modelBlocked = listen.blockedByModel }
        let notInstalled = !ask.isEmpty && listen.mismatch && ask.allSatisfy { !listen.candidates.contains($0) }
        if notInstalled != languageNotInstalled { languageNotInstalled = notInstalled }
        if running { status = listen.statusText }
    }

    func refreshOutputs() {
        outputs = AudioDevices.outputs()
    }

    var virtualMic: OutputDevice? { outputs.first(where: \.isVirtualMic) }

    // MARK: Permissions (all from the UI, no Terminal)

    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic != micStatus { micStatus = mic }
        checkProblem()
        let devices = AudioDevices.outputs()
        if devices.map(\.uid) != outputs.map(\.uid) { outputs = devices }
        // Refused (in the prompt, or turned off in System Settings later): the tap would only hear silence.
        let access = systemAudio.next(status: SystemAudioPermission.status(),
                                      tapRan: listen.isRunning && !settings.listensToRoom)
        if access != systemAudio { systemAudio = access }
        let speech = Recognition.ready
        if speech != speechOK { speechOK = speech }
        refreshMicUsers()
        refreshSystemMic()
    }

    // MARK: System microphone

    /// Switching the system mic only helps when there is a call to speak into.
    var wantsSystemMic: Bool {
        // 只听会议室: no call, and the talk key only says it's for online meetings.
        settings.speakEnabled && settings.autoSystemMic && !settings.listensToRoom && virtualMic != nil
    }

    func refreshSystemMic() {
        let state = systemMic.refresh(wanted: wantsSystemMic)
        if state != systemMicState { systemMicState = state }
    }

    /// Switches or lets go to match the settings (同声传译, 自动切换, 声音输出到).
    func applySystemMic() {
        // Speaking off: turning it off already put the mic back; a crash leftover waits for 还原.
        if wantsSystemMic { systemMic.engage(wanted: true) } else if settings.speakEnabled { systemMic.release() }
        refreshSystemMic()
    }

    /// 还原: the real mic back now. While speaking it stays back until 换回 or the next time speaking starts.
    func restoreSystemMic() {
        systemMic.release()
        refreshSystemMic()
    }

    /// 换回 / 切换: the virtual mic as the system default again.
    func switchSystemMic() {
        systemMic.engage(wanted: true)
        refreshSystemMic()
    }

    func setAutoSystemMic(_ on: Bool) {
        settings.autoSystemMic = on
        applySystemMic()
    }

    func refreshMicUsers() {
        // Compare against where our voice actually goes: 高级 › 声音输出到 can point elsewhere.
        let target = outputs.first { !settings.speakOutput.isEmpty && $0.uid == settings.speakOutput } ?? virtualMic
        let users = virtualMic != nil ? target.map { MicUsers.current(virtualMic: $0.id) } ?? [] : []
        if users != micUsers { micUsers = users }
    }

    /// Opens the "怎么改" sheet for an app, from the panel or Settings.
    func showMicGuide(_ user: MicUser) {
        micGuide = user
        openSettings(.speak)
    }

    /// Brings a meeting app forward so the user can change its microphone.
    func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Starting the tap triggers the system prompt; if it still fails, open the pane.
    func requestSystemAudio() {
        if !listen.isRunning { start() }
        if !listen.isRunning {
            openSettingsPane("Privacy_ScreenCapture")
        }
        refreshPermissions()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.refreshPermissions() } }
        }
    }

    func openMicrophoneSettings() { openSettingsPane("Privacy_Microphone") }
    /// 换麦克风: the room is heard by the system's input (`RoomMicPlan`), picked in Sound.
    func openSoundInputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") {
            NSWorkspace.shared.open(url)
        }
    }

    /// On each change and every second: the menu bar's dot, the subtitle bar's notice and the
    /// notification. Never a dialog: it would take the focus from the meeting app, and show in a
    /// shared screen.
    func checkProblem() {
        let both = listen.isRunning && settings.hearsBoth && !Recognition.legacy
        let denied = both && (fakeMicDenied || [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio)))
        if denied != hybridMicDenied {
            micDeniedSince = denied ? Date() : nil
            overlay.setAlert(denied ? L("听不到会议室 · 麦克风没允许") : nil)
        }
        let p = denied ? L("听会议室要先允许麦克风") : AIServiceStrip.blocking(ling, textModel: settings.textModel)
        if p != problem { problem = p }
        // With the notes window up its banner says so; put away, a notification after 10 s
        // (long enough for a quick fix in the panel), once a meeting.
        if denied, !micDeniedNotified, !notesShown, let since = micDeniedSince, Date().timeIntervalSince(since) >= 10 {
            micDeniedNotified = true
            notifyMicDenied()
        }
    }

    private func notifyMicDenied() {
        let title = L("听不到会议室"), body = L("麦克风没允许，现在只在记电脑声音。点按去设置")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { debugLog("problem: notifications not allowed"); return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = ["problem": "mic"]
            let request = UNNotificationRequest(identifier: "problem-mic", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                debugLog(error.map { "problem: notification not shown: \($0)" } ?? "problem: notified mic denied")
            }
        }
    }

    /// Quits and opens Cicada again: a permission turned on after it was refused takes only then.
    func relaunch() {
        // Quitting closes the guide, which would count as finishing it: it carries on after the reopen.
        relaunching = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// macOS 14/15: asks for 语音识别, then opens Keyboard settings if Dictation is still off.
    func requestSpeech() {
        Task {
            if await Recognition.authorize() {
                if !Recognition.dictationEnabled,
                   let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                openSettingsPane("Privacy_SpeechRecognition")
            }
            refreshPermissions()
        }
    }

    func openLocalNetworkSettings() { openSettingsPane("Privacy_LocalNetwork") }

    private func openSettingsPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSettings(_ section: SettingsSection? = nil) {
        if let section { settingsSection = section }
        // The 诊断 tab only exists while its switch is on.
        if settingsSection == .diagnostics && !settings.diagnostics { settingsSection = .overlay }
        openSettingsWindow?()
    }

    func ensureListening() {
        if !listen.isRunning { start() }
    }

    func virtualMicInstalled() {
        refreshOutputs()
        // Core Audio restarted to load the driver: device IDs changed, reattach the
        // system-audio tap and rebuild the voice output.
        speak.resetOutput()
        listen.reconnectAudio()
        if settings.speakEnabled { applySystemMic() }
        objectWillChange.send()
    }

    // MARK: Start / stop

    /// `byUser`: started by a click or ⌘R, so the notes window shows at once as the sign that
    /// listening began. Starting by itself (launch, a meeting app's call) waits for the first words.
    func start(byUser: Bool = false) {
        guard !listen.isRunning else { return }
        // Starting by hand means the meeting is here now: open the room microphone too, when the
        // user turned on 开始听时打开麦克风 (设置 › 通用). Launch still stays silent.
        micAutoOpened = false
        if byUser, settings.autoMicOnStart, settings.listenSource == "system" {
            settings.listenSource = Recognition.legacy ? "room" : "both"
            micAutoOpened = true
            debugLog("mic auto-on: user started listening")
        }
        let session = store.begin()
        diagnostics.begin()
        speakers.reset()
        lineForSegment = [:]
        lastHeard = nil
        heldJoin = nil
        refining = [:]
        settling = []
        voicePending = []
        refiningOrder = []
        lineOfSegment = [:]
        settledEarly = [:]
        refinedLines = []
        fixes.meetingStarted()
        recentOnline = []
        heldRoom = []
        liveMain = ("", "", .distantPast)
        liveRoom = ("", "", .distantPast)
        // The caption under the notes would otherwise show the last meeting's line until someone speaks.
        liveSource = ""
        liveTranslation = ""
        speechHeard = false
        fakeGoneMics = []
        micDeniedNotified = false
        meetingSubtitles = nil
        autoEnded = false
        endWatch = MeetingEndWatch(config: endConfig, start: Date())
        setEnding(nil)
        if settings.recordAudio {
            listen.router.setRecording(store.systemAudioURL(session.id))
            speak.setRecording(store.micAudioURL(session.id))
            // Here, not when the mic opens: one clock with the Mac's audio, and opening the mic
            // again mid-meeting must not start the file over.
            roomListen.router.setRecording(store.roomAudioURL(session.id))
        }
        listen.start()
        if listen.isRunning, settings.hearsBoth { startRoomSide() }
        if settings.hearsRoom { store.markLiveInRoom() }
        notes.begin(session.id)
        if listen.isRunning {
            showDisplay(force: byUser)
        } else {
            store.end()
        }
        refresh()
    }

    /// `endedAt`: when a meeting that ends by itself really ended (see `autoEnd`).
    func stop(endedAt: Date? = nil) {
        autoEnded = false
        endWatch = nil
        setEnding(nil)
        diagnostics.end()
        stopRoomSide()
        listen.stop()
        listen.router.setRecording(nil)
        roomListen.router.setRecording(nil)
        speak.setRecording(nil)
        if let held = heldJoin {
            heldJoin = nil
            appendHeard(held.seg, t: held.t, translation: held.translation)
        }
        // Read the whole meeting for names once more (the id outlives store.end).
        let ended = store.liveID
        store.end(at: endedAt, heardSpeech: listen.heardSpeech)
        if settings.speakerVoices, let ended { speakerNamer.guess(ended, force: true) }
        notes.finish()
        if let ended { folderExport.ended(ended) }
        overlay.hide()
        refresh()
        updates.notifyIfDue()  // held while the meeting was on
    }

    func setRunning(_ on: Bool) { on ? start(byUser: true) : requestStop() }

    /// The menu (⌘R) and the panel switch: a meeting with lines is ended only after asking, with
    /// "继续记录" as the default so a stray Return keeps it going. An empty one just stops.
    func requestStop() {
        guard listen.isRunning, let id = store.liveID, let s = store.session(id), !s.lines.isEmpty else { stop(); return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("结束这场会议？")
        alert.informativeText = L("已记录 \(NotesEngine.clock(Date().timeIntervalSince(s.startedAt))) · \(s.lines.count) 句。结束后停止收听，并整理一份完整版纪要。")
        let end = alert.addButton(withTitle: L("结束会议"))
        let keep = alert.addButton(withTitle: L("继续记录"))
        end.hasDestructiveAction = true
        end.keyEquivalent = ""
        keep.keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn { stop() }
    }

    /// The bottom-left 诊断 switch in settings: shows or hides the 诊断 tab.
    func setDiagnostics(_ on: Bool) {
        settings.diagnostics = on
        if !on && settingsSection == .diagnostics { settingsSection = .overlay }
        objectWillChange.send()
    }

    // MARK: Languages

    /// This meeting's 字幕 choice from the notes window's language chip (nil: the settings').
    @Published var meetingSubtitles: String?
    /// Notes language chosen for one meeting (the chip during it, 重新整理 after it).
    @Published private(set) var notesLanguageFor: [String: String] = [:]

    var subtitles: String { meetingSubtitles ?? settings.subtitles }

    func notesChoice(_ id: String) -> String { notesLanguageFor[id] ?? settings.notesLanguage }

    /// The language the other side spoke most in a meeting (the detected one while nothing is recorded yet).
    func meetingLanguage(_ id: String?) -> String? {
        let heard = id.flatMap { store.session($0) }?.lines.filter { $0.speaker != "me" }.map(\.srcLang) ?? []
        let counts = Dictionary(heard.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key ?? (id == store.liveID ? listen.activeLang?.code : nil)
    }

    func notesLanguageCode(_ id: String) -> String {
        notesChoice(id) == "source" ? (meetingLanguage(id) ?? settings.myLanguage) : settings.myLanguage
    }

    /// The subtitle as the 字幕 choice shows it: both lines, the translation alone, or the
    /// original alone as the main line.
    func displayed(_ src: String, _ dst: String) -> (source: String, translation: String) {
        switch subtitles {
        case "original": return ("", src)
        case "translation": return dst.isEmpty ? (src, "") : ("", dst)
        default: return (src, dst)
        }
    }

    func setSubtitles(_ mode: String, meetingOnly: Bool = false) {
        let wasOff = subtitles == "original"
        if meetingOnly { meetingSubtitles = mode } else { settings.subtitles = mode; meetingSubtitles = nil }
        if wasOff && subtitles != "original" { listen.translationResumed() }
        debugLog("subtitles=\(subtitles) meetingOnly=\(meetingOnly)")
        objectWillChange.send()
    }

    /// A different notes language during a meeting rewrites the notes in it right away.
    func setNotesLanguage(_ choice: String, meetingOnly: Bool = false) {
        let live = store.liveID
        let before = live.map(notesLanguageCode)
        if meetingOnly, let live { notesLanguageFor[live] = choice } else { settings.notesLanguage = choice }
        if let live, notesLanguageCode(live) != before { notes.rewrite() }
        debugLog("notesLanguage=\(live.map(notesLanguageCode) ?? settings.notesLanguage) meetingOnly=\(meetingOnly)")
        objectWillChange.send()
    }

    /// After a meeting: write its notes again in the other language.
    func regenerateNotes(_ id: String, choice: String) {
        notesLanguageFor[id] = choice
        notes.generate(for: id)
    }

    /// A hand edit of summary/topics/names: stored with the meeting and shown at once.
    func saveEditedNotes(_ edited: MeetingNotes, session id: String) {
        var next = edited
        next.updatedAt = Date()
        store.setNotes(id, next)
        notes.applyEdited(next, id: id)
    }

    // MARK: Display (live notes / subtitle bar / nothing)

    /// 录屏时可见: every place that shows it (settings, menu bar panel, 显示 menu, the notes
    /// window's badge) flips this one setting.
    func setNotesCapturable(_ on: Bool) {
        settings.notesCapturable = on
        notesWindow.setCapturable(on)
        objectWillChange.send()
    }

    func setDisplayMode(_ mode: String) {
        settings.displayMode = mode
        objectWillChange.send()
        showDisplay(force: true)
    }

    /// ⌃⌥S: notes → subtitle bar → nothing → notes.
    func cycleDisplay() {
        let order = ["notes", "bar", "none"]
        let i = order.firstIndex(of: settings.displayMode) ?? 0
        setDisplayMode(order[(i + 1) % order.count])
    }

    /// Set at the first words of a meeting: until then listening stays out of sight.
    private var speechHeard = false

    private func heardSpeech() {
        guard !speechHeard, listen.isRunning else { return }
        speechHeard = true
        if settings.displayMode == "notes" { notesWindow.show() }
    }

    /// `force`: the user asked for this mode or started listening, show it even before anyone speaks.
    private func showDisplay(force: Bool = false) {
        switch settings.displayMode {
        case "bar":
            notesWindow.hide()
            if listen.isRunning { overlay.show() }
        case "none":
            notesWindow.hide()
            overlay.hide()
        default:
            overlay.hide()
            // The notes window waits for someone to speak, so launching or a silent tab
            // doesn't put an empty window on screen.
            if listen.isRunning && (speechHeard || force) { notesWindow.show() }
        }
    }

    /// The user closed the notes window: show the same meeting in the records window.
    func notesWindowClosed() {
        let id = store.liveID ?? notes.shownID
        openMainWindow?()
        if let id {
            mainShow = nil
            mainShow = "\(id),notes"
        }
    }

    /// Asked for by name (菜单栏面板 打开, 窗口 › 实时纪要): shown even before anyone speaks, and
    /// without touching 显示方式, so 不显示 or 字幕条 is back at the next meeting.
    func openNotesWindow() { notesWindow.show(asked: true) }

    /// The listening pill: bring back what shows this meeting, the subtitle bar in 字幕条 mode,
    /// else the notes window (in 不显示 just this once).
    func showLiveDisplay() {
        if settings.displayMode == "bar" { overlay.reveal() } else { openNotesWindow() }
    }

    /// 收起 in the menu bar panel: out of the way for now, still in 实时纪要 mode
    /// (unlike the close button, it doesn't open the records window).
    func hideNotesWindow() { notesWindow.hide() }

    func notesVisibilityChanged(_ shown: Bool) {
        if notesShown != shown { notesShown = shown }
    }

    // MARK: Settings actions

    /// 打开麦克风 / 关闭麦克风, in the panel, the notes window and the subtitle bar. The Mac's audio is
    /// always heard; the microphone adds the people in the room to the same meeting (macOS 14/15,
    /// where two recognizers interrupt each other: the microphone in place of the Mac's audio).
    /// Not kept for the next launch: listening starts by itself, never with the microphone open.
    var micOn: Bool { settings.hearsRoom }

    /// The menu beside 打开麦克风: which microphone hears the room ("" = 自动, as `RoomMicPlan` picks).
    /// Picking one while the microphone is off is asking to hear the room with it; while it is on,
    /// only the room side reconnects, and the meeting goes on.
    func setRoomMic(_ uid: String) {
        settings.roomMicUID = uid
        debugLog("room mic chosen: \(uid.isEmpty ? "auto" : uid)")
        guard micOn else { setMic(true); return }
        let engine = settings.hearsBoth ? roomListen : listen
        if engine.isRunning, engine.roomMicUID != AudioDevices.roomMic(excluding: fakeGoneMics, preferredUID: uid)?.uid {
            engine.reconnectAudio()
        }
        objectWillChange.send()
    }

    func setMic(_ on: Bool) {
        let value = !on ? "system" : Recognition.legacy ? "room" : "both"
        // Asking for the room is asking to listen, even with the switch already on.
        if value == settings.listenSource {
            if on, !listen.isRunning { start(byUser: true) }
            return
        }
        debugLog("mic \(on ? "on" : "off") (\(value))")
        let wasRoomOnly = settings.listensToRoom
        settings.listenSource = value
        if listen.isRunning && settings.hearsRoom { store.markLiveInRoom() }
        // The main engine changes only between the Mac and the room alone; "both" adds the room side.
        if wasRoomOnly != settings.listensToRoom { listen.listenSourceChanged() }
        if listen.isRunning {
            if settings.hearsBoth { startRoomSide() } else { stopRoomSide() }
        } else if on {
            // Asking for the room is asking to listen.
            start(byUser: true)
        }
        applySystemMic()
        refreshMicUsers()
        refresh()
        objectWillChange.send()
    }

    /// Why a press of the talk key went nowhere (no virtual mic, 只听会议室): shown where the eyes
    /// are while it is held, the subtitle bar or the notes window's caption, since nothing shows `status`.
    private func speakNotice(_ text: String) {
        status = text
        debugLog("speak: notice \(text)")
        if speakTester.busy { return }
        if settings.displayMode == "bar" {
            if !overlay.isShown { overlay.show() }
            overlay.setSpeaking(.init(phase: .idle, source: "", translation: text))
        } else if running {
            liveSource = ""
            liveTranslation = text
        }
    }

    /// The room mic hears silence while the talk key is down, and a moment after, so your voice
    /// doesn't come back as the room. The translation goes into the virtual mic, never the speakers,
    /// so the room is heard again while it is translated and read out.
    private func muteRoomWhileSpeaking(_ phase: SpeakEngine.Phase) {
        if phase == .listening {
            listen.setRoomMuted(true)
            roomListen.setRoomMuted(true)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.speak.phase != .listening else { return }
                self.listen.setRoomMuted(false)
                self.roomListen.setRoomMuted(false)
            }
        }
    }

    var sourceSelection: String {
        get {
            if case .fixed(let l) = settings.sourceMode { return l.locale }
            return "auto"
        }
        set {
            settings.sourceMode = newValue == "auto" ? .auto
                : .fixed(sourceLanguages.first(where: { $0.locale == newValue }) ?? sourceLanguages[0])
            listen.sourceModeChanged()
            refresh()
            objectWillChange.send()
        }
    }

    var targetSelection: String {
        get { settings.target }
        set {
            settings.target = newValue
            listen.targetChanged()
            refresh()
            objectWillChange.send()
        }
    }

    func enableSpeaking(_ on: Bool) {
        settings.speakEnabled = on
        if on { settings.speakConfirmed = true }
        objectWillChange.send()
        if on {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted { debugLog("microphone permission denied") }
            }
            if settings.talkKey.isRightOption && !RightOptionKey.allowed { RightOptionKey.requestAccess() }
            applyTalkKey()
            refreshOutputs()
            applySystemMic()
            Task { await speak.prepare() }
        } else {
            applyTalkKey()
            restoreSystemMic()
            Task { await speak.teardownAnalyzer() }
        }
    }

    // MARK: Shortcuts

    enum ShortcutRole { case talk, toggle }

    /// Arms the talk key for the current setting. Right ⌥ waits for "输入监控" and
    /// arms itself as soon as it's allowed (no relaunch).
    func applyTalkKey() {
        talkCombo.unregister()
        talkRight.stop()
        var needsPermission = false
        if settings.speakEnabled && !shortcutsSuspended {
            if settings.talkKey.isRightOption {
                needsPermission = !talkRight.start()
            } else {
                talkCombo.register(settings.talkKey)
            }
        }
        if talkNeedsPermission != needsPermission { talkNeedsPermission = needsPermission }
        if needsPermission, permissionPoll == nil {
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if RightOptionKey.allowed || !self.settings.speakEnabled || !self.settings.talkKey.isRightOption {
                        self.permissionPoll?.invalidate()
                        self.permissionPoll = nil
                        self.applyTalkKey()
                    }
                }
            }
        }
    }

    func applyToggleKey() {
        toggleKey.unregister()
        guard !shortcutsSuspended else { return }
        let ok = toggleKey.register(settings.toggleKey)
        if toggleKeyTaken == ok { toggleKeyTaken = !ok }
    }

    func allowTalkKey() {
        RightOptionKey.requestAccess()
        RightOptionKey.openSystemSettings()
    }

    /// While a shortcut field is recording, our own shortcuts must not swallow the keys.
    func suspendShortcuts(_ on: Bool) {
        shortcutsSuspended = on
        applyTalkKey()
        applyToggleKey()
    }

    /// Validates and saves a new shortcut. Returns why it was refused, or nil.
    func setShortcut(_ s: Shortcut, for role: ShortcutRole) -> String? {
        if role == .toggle && s.isRightOption { return L("右 ⌥ 只能用于“按住说话”") }
        if let p = s.typingProblem { return p }
        let other = role == .talk ? settings.toggleKey : settings.talkKey
        if s == other { return L("与另一个快捷键冲突") }
        if s.isSystemShortcut { return L("\(s.display) 是系统快捷键，换一个吧") }
        // The one already in use is registered by us: probing it would always fail.
        let current = role == .talk ? settings.talkKey : settings.toggleKey
        if !s.isRightOption && s != current {
            // Probe: Carbon refuses a combo another app already registered.
            let probe = HotKey(id: 9, shortcut: s)
            let free = probe.register()
            probe.unregister()
            if !free { return L("\(s.display) 已被其他应用占用，换一个吧") }
        }
        switch role {
        case .talk:
            settings.talkKey = s
            if s.isRightOption && settings.speakEnabled && !RightOptionKey.allowed { RightOptionKey.requestAccess() }
        case .toggle:
            settings.toggleKey = s
        }
        applyTalkKey()
        applyToggleKey()
        objectWillChange.send()
        return nil
    }

    /// The room hears the voice chosen for its language (looked up each time it speaks).
    func applyVoice() {
        speak.route = { [weak self] language in
            guard let self else { return .system(nil) }
            return self.voiceRoute(id: self.voiceID(for: language), language: language)
        }
    }

    /// The chosen voice for a language, or its default (the service's first with a key, else the
    /// Mac's). A choice the service in use cannot speak (Ming after switching to OpenRouter, the
    /// user's own voice without Ling) falls back to the default, and comes back with that service.
    func voiceID(for language: String) -> String? {
        let fallback = VoiceCatalog.defaultID(for: language, hasKey: ling.speaks)
        guard let id = settings.speakVoices[VoiceCatalog.key(for: language)] else { return fallback }
        if id.hasPrefix("system:") { return id }
        if id == "clone" { return VoiceReference.exists && ling.clones ? id : fallback }
        return VoiceCatalog.remote(for: language).contains { $0.id == id } ? id : fallback
    }

    /// Any change of route (an interface, a VPN or TUN from a proxy app) waits 3 s for the network
    /// to settle, then the AI client looks again if the service was unreachable.
    private func watchNetwork() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.networkDebounce?.cancel()
                    let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.ling.networkChanged(); self?.translator.networkChanged() } }
                    self.networkDebounce = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "cicada.ai-network"))
        // Turning the local network permission on doesn't change the path: look again on coming back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ling.recheckLocalNetwork()
                self?.folderExport.retry()  // a folder permission fixed in System Settings
            }
        }
    }

    /// One click on "换成推荐的": the service's first recommended text model, then a fresh check.
    func useRecommendedTextModel() {
        guard let first = settings.provider.textModels.first?.id else { return }
        if settings.provider.id == .ling { settings.aiModel = first } else { settings.aiModels[settings.aiProvider] = first }
        applyAIService()
    }

    /// A key pasted for one service that belongs to another ("改用 OpenRouter"): switch, save it there, check.
    func switchService(_ kind: AIProvider.Kind, key: String) {
        settings.aiProvider = kind.rawValue
        applyAIService()
        Task { await ling.setKey(key) }
    }

    /// "改用 Ling" where another service is out of reach: only when a Ling key is already saved,
    /// so the one click works without a trip to the settings.
    var canSwitchToLing: Bool { settings.provider.id != .ling && AIKey.read("ling") != nil }

    func switchToLing() {
        guard canSwitchToLing else { return }
        settings.aiProvider = AIProvider.Kind.ling.rawValue
        applyAIService()
    }

    /// Settings changed the AI service, its address or a model: voices follow, the key is checked again.
    func applyAIService() {
        let c = settings.aiConfig
        switch c.provider.id {
        case .ling: VoiceCatalog.service = .ming
        default:
            let label = c.provider.id == .custom ? (c.voiceModel ?? "") : c.voiceModel.map { $0.contains("gemini") ? "Gemini" : c.provider.name } ?? ""
            VoiceCatalog.service = c.hasVoices ? .cloud(label: label, voices: c.voices) : .none
        }
        speak.streamName = { [weak self] in
            guard let id = self?.settings.provider.id, id != .ling else { return "ming" }
            return id.rawValue
        }
        // Takes effect from the next meeting: one already running keeps how it listens, except that
        // its audio never goes on to a service other than the one hearing it (`aiServiceChanged`).
        Recognition.serverPreferred = c.transcribes
        translator.googleOff = c.provider.id == .custom && settings.aiCustomOnly
        ling.reconfigure()
        listen.aiServiceChanged()
        roomListen.aiServiceChanged()
        applyVoice()
    }

    func setVoice(_ id: String, for language: String) {
        settings.speakVoices[VoiceCatalog.key(for: language)] = id
    }

    /// Ming's voices need a working key; without one the Mac's voice speaks.
    func voiceRoute(id: String?, language: String) -> SpeakEngine.VoiceRoute {
        guard let id else { return .system(nil) }
        if id.hasPrefix("system:") { return .system(String(id.dropFirst("system:".count))) }
        guard ling.speaks else { return .system(nil) }
        if id.hasPrefix("cloud:") {
            let voice = String(id.dropFirst("cloud:".count))
            return .stream { [weak self] text in
                self?.ling.speech(text, voice: voice)
                    ?? AsyncThrowingStream { $0.finish(throwing: LingClient.Failure.noKey) }
            }
        }
        let lang = VoiceCatalog.mingLanguage(for: language)
        if id == "clone" {
            guard ling.clones else { return .system(nil) }
            guard let ref = VoiceReference.reference() else { return .system(nil) }
            return .stream { [weak self] text in
                self?.ling.speech(text, voice: nil, reference: ref, language: lang)
                    ?? AsyncThrowingStream { $0.finish(throwing: LingClient.Failure.noKey) }
            }
        }
        let voice = String(id.dropFirst("ming:".count))
        return .stream { [weak self] text in
            self?.ling.speech(text, voice: voice, language: lang)
                ?? AsyncThrowingStream { $0.finish(throwing: LingClient.Failure.noKey) }
        }
    }

    /// Plays a voice on the speakers (not into the room) with a line in that language.
    @Published var previewing: String?

    func previewVoice(_ id: String, language: String, text: String? = nil) {
        previewing = id
        let route = voiceRoute(id: id, language: language)
        Task {
            let started = Date()
            await speak.speak(text ?? VoiceCatalog.sample(for: language), language: language,
                              device: AudioDevices.defaultOutput, route: route)
            debugLog("voice preview \(id) \(language) took \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            if previewing == id { previewing = nil }
        }
    }

    func speakFromChanged() {
        objectWillChange.send()
        if settings.speakEnabled { Task { await speak.prepare() } }
    }

    // MARK: Meeting end

    private var endConfig: MeetingEndWatch.Config {
        var c = MeetingEndWatch.Config()
        c.followApps = settings.endWithApp
        c.silence = MeetingEndWatch.Silence(rawValue: settings.silenceEnd) ?? .prompt
        c.silenceAfter = settings.silenceMinutes * 60
        if let o = endTimesOverride { (c.silenceAfter, c.countdown, c.appGrace) = (o.silence, o.countdown, o.grace) }
        return c
    }

    private func heardWords() {
        endWatch?.heard(at: Date())
        setEnding(endWatch?.pending)
    }

    /// Every 2 s: while listening, whether the meeting is over; after one ended by itself, whether
    /// a meeting app started the next call.
    private func watchEnd() {
        if listen.isRunning, var w = endWatch {
            w.config = endConfig
            let said = store.liveID.flatMap { store.session($0) }.map { !$0.lines.isEmpty } ?? false
            let calls = w.config.followApps ? (fakeCalls ?? MicUsers.currentCalls()) : [:]
            // A meeting app call started while we were already listening to the Mac only: add the
            // room microphone, or the user's own voice is missing from the record (Tencent Meeting,
            // Zoom, …). 启动时 launch() still starts without the microphone; this is the call signal.
            // Once a meeting: closing the microphone by hand during the call must stay closed.
            if settings.autoMicOnStart, !micAutoOpened, settings.listenSource == "system", !calls.isEmpty {
                micAutoOpened = true
                debugLog("mic auto-on: a meeting app started a call")
                setMic(true)
            }
            let reason = w.tick(at: Date(), calls: calls, said: said)
            endWatch = w
            setEnding(w.pending)
            if let reason { autoEnd(reason, watch: w) }
        } else if !listen.isRunning, autoEnded, settings.endWithApp, !(fakeCalls ?? MicUsers.currentCalls()).isEmpty {
            debugLog("meeting end: a meeting app started a call, starting a new meeting")
            // A call is on the Mac, not in the room.
            if settings.listensToRoom { settings.listenSource = "system"; applySystemMic() }
            start()
        }
    }

    private func setEnding(_ p: MeetingEndWatch.Pending?) {
        guard p != ending else {
            if p != nil { showEndingOnBar() }
            return
        }
        if let p { debugLog("meeting end: pending \(p.reason), ends in \(Int(p.deadline.timeIntervalSinceNow)) s") }
        else if ending != nil { debugLog("meeting end: pending cleared"); overlay.clearStatus() }
        ending = p
        showEndingOnBar()
    }

    /// The subtitle bar has no buttons: it says what will happen, and speaking keeps a silent meeting going.
    private func showEndingOnBar() {
        guard settings.displayMode == "bar", let p = ending else { return }
        let left = max(0, Int(p.deadline.timeIntervalSinceNow.rounded()))
        overlay.notice(endingTitle(p) + " · " + L("\(left) 秒后结束"))
    }

    func endingTitle(_ p: MeetingEndWatch.Pending) -> String {
        switch p.reason {
        case .appLeft(let name): L("\(name) 已挂断")
        case .silence, .nobodySpoke: L("已经 \(max(1, Int((endConfig.silenceAfter / 60).rounded()))) 分钟没人说话")
        }
    }

    func endingDetail(_ p: MeetingEndWatch.Pending, now: Date = Date()) -> String {
        L("\(max(0, Int(p.deadline.timeIntervalSince(now).rounded()))) 秒后结束会议并整理纪要")
    }

    /// "继续记录" on the ending prompt.
    func keepRecording() {
        endWatch?.keepGoing(at: Date())
        setEnding(nil)
        debugLog("meeting end: kept going")
    }

    /// Ends where the meeting really ended: a little after the last words, or at the hang-up if
    /// that was later. Never before a line that was kept, or its audio would be cut.
    private func autoEnd(_ reason: MeetingEndWatch.Reason, watch w: MeetingEndWatch) {
        if reason == .nobodySpoke {
            // Nothing to keep or summarise: back to "开始听", not "会议已自动结束".
            debugLog("meeting end: nobody spoke for \(Int(w.config.silenceAfter)) s, stopped")
            stop()
            return
        }
        var at = w.lastSpeech.addingTimeInterval(5)
        if case .appLeft = reason { at = max(at, Date().addingTimeInterval(-w.config.appGrace)) }
        debugLog("meeting end: ended by itself (\(reason)), end time \(Int(Date().timeIntervalSince(at))) s ago")
        stop(endedAt: at)
        autoEnded = true
    }

    // MARK: Meeting record

    // MARK: Speakers

    /// Name a voice ("" keeps 说话人 N, nil goes back to Ling's guess).
    func renameSpeaker(session id: String, voice: Int, _ name: String?) {
        guard let s = store.session(id) else { return }
        let n = SpeakerLabels.voiceNumbers(s)[voice] ?? 0
        let before = SpeakerLabels.label(n, SpeakerLabels.names(s))
        speakerEdit(id) { store.setVoiceName(id, voice: voice, name) }
        let after = store.session(id).map { SpeakerLabels.label(n, SpeakerLabels.names($0)) } ?? before
        if after != before { speakerUndo?.text = L("\(before) 已改成 \(after)") } else { speakerUndo = nil }
    }

    /// A click on 对方 / 说话人 in the transcript: ask for a name without making the user find
    /// the speaker strip first. It only names this meeting's voice; remembering the voiceprint is
    /// still an explicit 记住这个声音 step with its own consent alert.
    func promptSpeakerName(session id: String, voice: Int) {
        guard let s = store.session(id) else { return }
        let n = SpeakerLabels.voiceNumbers(s)[voice] ?? 0
        let current = SpeakerLabels.names(s)[n] ?? ""
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = L("输入名字")
        let alert = NSAlert()
        alert.messageText = L("这个人是谁？")
        alert.informativeText = L("写上名字后，这场记录会按这个名字显示。要下次自动认出，再点“记住这个声音”。")
        alert.accessoryView = field
        alert.addButton(withTitle: L("保存"))
        alert.addButton(withTitle: L("取消"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { renameSpeaker(session: id, voice: voice, name) }
    }

    /// Two voices are one person. While listening the voiceprints merge too, which 撤销 can't take back.
    func mergeSpeaker(session id: String, _ from: Int, into: Int) {
        guard let s = store.session(id) else { return }
        let numbers = SpeakerLabels.voiceNumbers(s), names = SpeakerLabels.names(s)
        let a = SpeakerLabels.label(numbers[from] ?? 0, names), b = SpeakerLabels.label(numbers[into] ?? 0, names)
        speakerEdit(id) { store.mergeVoice(id, from, into: into) }
        if id == store.liveID { speakers.merge(from, into: into) }
        speakerUndo?.text = L("\(a) 已并入 \(b)")
    }

    /// These lines were someone else's.
    func assignLines(session id: String, _ lines: Set<String>, to voice: Int) {
        guard let s = store.session(id) else { return }
        let first = s.lines.first { lines.contains($0.id) }
        speakerEdit(id) { store.setLineVoices(id, lines: lines, voice) }
        guard let s2 = store.session(id) else { return }
        let who = SpeakerLabels.label(SpeakerLabels.voiceNumbers(s2)[voice] ?? 0, SpeakerLabels.names(s2))
        speakerUndo?.text = L("\(first.map { TranscriptExport.clock($0.t) } ?? "") 这句已改给 \(who)")
    }

    func undoSpeakerEdit() {
        guard let u = speakerUndo else { return }
        speakerUndo = nil
        store.restore(u.session, u.snapshot)
        debugLog("speakers: undo \(u.session)")
    }

    private func speakerEdit(_ id: String, _ change: () -> Void) {
        guard let snap = store.voiceSnapshot(id) else { return }
        change()
        let undo = SpeakerUndo(session: id, snapshot: snap, text: "")
        speakerUndo = undo
        debugLog("speakers: edit \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.speakerUndo?.id == undo.id { self?.speakerUndo = nil }
        }
    }

    // MARK: Voiceprint library

    /// The user accepted a close match: name this meeting's voice from the library and let the
    /// live clusterer use the profile for later lines.
    func acceptSpeakerSuggestion(session id: String, voice: Int) {
        guard let s = store.session(id), let ref = s.voiceSuggestions?[String(voice)],
              let profile = profiles.snapshot().first(where: { $0.id == ref.id }) else { return }
        speakerEdit(id) { store.setVoiceProfile(id, voice: voice, ref: ref) }
        profiles.markSeen(id: profile.id)
        if id == store.liveID { speakers.bind(voice: voice, profile: profile) }
        speakerUndo?.text = L("已认出 \(ref.name)")
    }

    func dismissSpeakerSuggestion(session id: String, voice: Int) {
        store.setVoiceSuggestion(id, voice: voice, nil)
    }

    /// "不是 TA": drop this meeting's binding; never touch the global profile.
    func forgetSpeaker(session id: String, voice: Int) {
        guard store.session(id)?.voiceProfiles?[String(voice)] != nil else { return }
        speakerEdit(id) { store.setVoiceProfile(id, voice: voice, ref: nil) }
        speakerUndo?.text = L("这次不再按声纹认人")
    }

    /// Explicit enrolment: the caller has already named the voice. The alert is the consent step;
    /// voiceprints are biometric data and are never saved from a background match alone.
    func rememberSpeaker(session id: String, voice: Int, name: String? = nil) {
        guard let s = store.session(id) else { return }
        let n = SpeakerLabels.voiceNumbers(s)[voice] ?? 0
        let chosen = (name ?? s.voiceNames?[String(voice)] ?? s.voiceProfiles?[String(voice)]?.name
                        ?? SpeakerLabels.names(s)[n] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty else {
            alert(L("先给这个人起个名字"), L("在“是谁”里输入名字后，再记住这个声音。"))
            return
        }
        guard let audio = audioURL(for: s) else {
            alert(L("没有可用的录音"), L("打开“保存会议录音”，或用导入的录音文件建立声纹。"))
            return
        }
        let alert = NSAlert()
        alert.messageText = L("记住“\(chosen)”的声音？")
        alert.informativeText = L("请先确认对方知道。声纹只保存在这台 Mac，用于以后会议认出这个人，可随时在人员库里删除。")
        alert.addButton(withTitle: L("记住"))
        alert.addButton(withTitle: L("不用"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        speakerMemoryBusy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.speakerMemoryBusy = false }
            do {
                let result = try await SpeakerEnrollment.build(session: s, voice: voice, audioURL: audio)
                let existing = s.voiceProfiles?[String(voice)]?.id
                let profile: SpeakerProfile?
                if let existing, self.profiles.updateEmbedding(id: existing, embedding: result.embedding) {
                    _ = self.profiles.rename(id: existing, to: chosen)
                    profile = self.profiles.snapshot().first { $0.id == existing }
                } else {
                    profile = self.profiles.remember(name: chosen, embedding: result.embedding)
                }
                guard let profile else {
                    self.alert(L("这个声音还不够清楚"), L("换一段更长、更安静的发言再试。"))
                    return
                }
                self.store.setVoiceProfile(id, voice: voice, ref: VoiceProfileRef(id: profile.id, name: profile.name, similarity: 1))
                self.profiles.markSeen(id: profile.id)
                if id == self.store.liveID, let full = self.profiles.snapshot().first(where: { $0.id == profile.id }) {
                    self.speakers.bind(voice: voice, profile: full)
                }
                self.speakerProfiles = self.profiles.all()
                debugLog("voice profiles: remembered \(chosen) from \(result.clips) clips / \(Int(result.seconds)) s")
            } catch {
                self.alert(L("没记住这个声音"), error.localizedDescription)
            }
        }
    }

    func renameSpeakerProfile(id: UUID, to name: String) {
        guard profiles.rename(id: id, to: name) else { return }
        speakerProfiles = profiles.all()
    }

    func saveSpeakerProfileNotes(id: UUID, notes: String) {
        guard profiles.setNotes(id: id, notes) else { return }
        speakerProfiles = profiles.all()
    }

    func deleteSpeakerProfile(id: UUID) {
        profiles.delete(id: id)
        speakerProfiles = profiles.all()
    }

    func deleteAllSpeakerProfiles() {
        profiles.deleteAll()
        speakerProfiles = profiles.all()
    }

    func speakerSuggestion(session id: String, voice: Int) -> VoiceProfileRef? {
        store.session(id)?.voiceSuggestions?[String(voice)]
    }

    private func audioURL(for s: Session) -> URL? {
        if let path = s.sourcePath, s.sourceFile != nil { return URL(fileURLWithPath: path) }
        let system = store.systemAudioURL(s.id)
        return FileManager.default.fileExists(atPath: system.path) ? system : nil
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: L("知道了"))
        a.runModal()
    }

    // MARK: 电脑和会议室

    private func startRoomSide() {
        // macOS 14/15: two live recognizers interrupt each other (docs/macos-legacy-plan.md 2, 10).
        guard !roomListen.isRunning, !Recognition.legacy else { return }
        roomListen.echoCancelled = roomEchoCancel
        roomListen.echoBypassed = roomEchoBypass
        roomListen.shareModels(from: listen)
        // Last meeting's measurement may be another room or another output: assume echo until measured.
        roomListen.echoGate.reset()
        // A, the gate: only the plain room mic heeds it (echo cancellation keeps talk over a remote speaker).
        listen.router.setOnLoud(roomEchoGate ? { [gate = roomListen.echoGate] in gate.hold() } : nil)
        roomListen.start()
        debugLog("hybrid: room side started (echo cancellation \(roomEchoBypass ? "bypassed" : roomEchoCancel ? "on" : "off"), gate \(roomEchoGate ? "on" : "off"))")
    }

    private func stopRoomSide() {
        listen.router.setOnLoud(nil)
        guard roomListen.isRunning else { return }
        roomListen.stop()
        // Room lines still waiting for their echo check are what was said: kept.
        let held = heldRoom
        heldRoom = []
        for h in held { recordRoom(h) }
        liveRoom = ("", "", .distantPast)
        debugLog("hybrid: room side stopped")
    }

    /// A sentence from the Mac's audio: recorded, and remembered to tell the room's copy of it.
    private func heardOnline(_ seg: Segment, duration: Double) {
        let at = CFAbsoluteTimeGetCurrent()
        recentMeeting.append(.init(text: seg.text, start: at - duration, end: at))
        recentMeeting.removeAll { $0.end < at - 30 }
        recentMeetingSegs[seg.id] = (at - duration, at)
        recentMeetingSegs = recentMeetingSegs.filter { $0.value.end >= at - 30 }
        if roomListen.isRunning {
            let now = CFAbsoluteTimeGetCurrent()
            recentOnline.append(.init(text: seg.text, start: now - duration, end: now))
            recentOnline.removeAll { $0.end < now - 20 }
            heldRoom.removeAll { h in
                guard EchoMatch.isEcho(h.heard, online: recentOnline) else { return false }
                debugLog("hybrid: room line dropped as an echo (\(h.seg.text.count) chars)")
                return true
            }
        }
        recordHeard(seg, duration: duration)
    }

    /// A sentence from the room mic: an echo of the Mac's audio is dropped; the rest waits a moment
    /// for the Mac's line it may echo (`EchoMatch.hold`), then is recorded where it was said.
    private func heardInRoom(_ seg: Segment, duration: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        let heard = EchoMatch.Heard(text: seg.text, start: now - duration, end: now)
        if EchoMatch.isEcho(heard, online: recentOnline) {
            debugLog("hybrid: room line dropped as an echo (\(seg.text.count) chars)")
            return
        }
        // The Mac has played nothing for a while: there is nothing for this to echo, no need to wait.
        if listen.router.stats().silenceRun >= EchoMatch.window {
            recordRoom((seg.id, seg, duration, heard))
            return
        }
        heldRoom.append((seg.id, seg, duration, heard))
        DispatchQueue.main.asyncAfter(deadline: .now() + EchoMatch.hold) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let i = self.heldRoom.firstIndex(where: { $0.id == seg.id }) else { return }
                let h = self.heldRoom.remove(at: i)
                self.recordRoom(h)
            }
        }
    }

    private func recordRoom(_ h: (id: Int, seg: Segment, duration: Double, heard: EchoMatch.Heard)) {
        let waited = CFAbsoluteTimeGetCurrent() - h.heard.end
        debugLog("hybrid: room line kept (\(h.seg.text.count) chars)")
        recordHeard(h.seg, duration: h.duration + waited)
    }

    /// A live line's words were fixed (or a fix undone): the subtitle bar follows if it still shows it.
    private func lineFixed(_ session: String, _ line: TranscriptLine) {
        guard session == store.liveID, let seg = lineForSegment.first(where: { $0.value == line.id })?.key else { return }
        let engine = line.via == "room" && roomListen.isRunning ? roomListen : listen
        engine.showFixed(seg, text: line.shown)
    }

    private func translated(_ segID: Int, _ text: String) {
        if let t = recentMeetingSegs[segID] { recentMeeting.append(.init(text: text, start: t.start, end: t.end)) }
        if heldJoin?.seg.id == segID { heldJoin?.translation = text }
        if let i = heldRoom.firstIndex(where: { $0.id == segID }) { heldRoom[i].seg.translation = text }
        guard let line = lineForSegment[segID], !refinedLines.contains(line) else { return }
        store.setTranslation(lineID: line, text)
    }

    /// A line starts settling with its first segment; a joined one adds its own.
    private func trackRefining(_ seg: Segment, line: String) {
        guard seg.refining, let session = store.liveID else { return }
        lineOfSegment[seg.id] = line
        if refining[line] == nil {
            refiningOrder.append(line)
            // Old lines no longer join or settle: keep the last few hundred.
            if refiningOrder.count > 300 {
                let old = refiningOrder.removeFirst()
                refining[old] = nil
                settling.remove(old)
            }
        }
        refining[line, default: (session, [])].segs.append((seg.id, seg.text, nil))
        settling.insert(line)
        if let early = settledEarly.removeValue(forKey: seg.id) { refined(seg.id, early) }
    }

    /// The record's recognizer settled segment `segID`. Once every segment of its line has, the line
    /// takes the record's words and is translated again; a segment it heard nothing in keeps its own.
    private func refined(_ segID: Int, _ text: String) {
        guard let line = lineOfSegment[segID], var entry = refining[line],
              let k = entry.segs.firstIndex(where: { $0.id == segID }) else {
            settledEarly[segID] = text
            if settledEarly.count > 60, let oldest = settledEarly.keys.min() { settledEarly[oldest] = nil }
            return
        }
        let heard = HeardText.clean(text)
        entry.segs[k].settled = heard.contains(where: \.isLetter) ? heard : entry.segs[k].text
        refining[line] = entry
        guard entry.segs.allSatisfy({ $0.settled != nil }) else { return }
        settling.remove(line)
        let parts = entry.segs.map { $0.settled! }
        let whole = parts.dropFirst().reduce(parts[0]) { HeardText.join($0, $1) }
        guard let rec = store.session(entry.session)?.lines.first(where: { $0.id == line }), whole != rec.src else { return }
        store.setSource(in: entry.session, lineID: line, whole)
        fixes.applyKnown(lineID: line, in: entry.session)
        refinedLines.insert(line)
        contentLog("REFINE \(line): \(rec.src) => \(whole)")
        guard rec.dst != nil else { return }
        Task { [weak self] in
            guard let self, let out = await self.listen.translate(whole, source: rec.srcLang, target: rec.dstLang) else { return }
            // Joined again meanwhile: that line's own settling translates it.
            guard self.store.session(entry.session)?.lines.first(where: { $0.id == line })?.src == whole else { return }
            self.store.setTranslation(in: entry.session, lineID: line, out)
        }
    }

    /// The line in progress: the engine that changed it last and still has words, so the room and the
    /// Mac take turns on the one caption.
    private func showLive(spoke src: String) {
        let room = !liveRoom.src.isEmpty && (liveMain.src.isEmpty || liveRoom.at > liveMain.at)
        let (visible, dst) = room ? (liveRoom.src, liveRoom.dst) : (liveMain.src, liveMain.dst)
        liveSource = visible
        liveTranslation = dst
        if !src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { heardSpeech(); heardWords() }
        guard settings.displayMode == "bar" else { return }
        overlay.clearStatus()
        let shown = displayed(visible, dst)
        overlay.setSubtitle(source: shown.source, translation: shown.translation)
    }

    private func recordHeard(_ seg: Segment, duration: Double) {
        guard let start = store.liveStart else { return }
        let t = max(0, Date().timeIntervalSince(start) - duration)
        // A line still waiting for its voice is overtaken: it stands on its own.
        if let held = heldJoin {
            heldJoin = nil
            appendHeard(held.seg, t: held.t, translation: held.translation)
            if let line = lineForSegment[held.seg.id] { voicePending.insert(line) }
        }
        guard let prev = lastHeard, store.session(store.liveID ?? "")?.lines.last?.id == prev.line,
              prev.seg.clock == seg.clock, prev.seg.sourceCode == seg.sourceCode,
              // macOS 14/15: the older recognizer ends a line only at a real pause and often drops
              // the full stop, so a missing one says nothing; only a line Cicada cut is a half sentence.
              !Recognition.legacy || prev.seg.cut, !prev.seg.split,
              HeardText.continues(prev.seg.text, seg.text, gap: seg.start - prev.seg.end, cut: prev.seg.cut) else {
            appendHeard(seg, t: t, tag: true)
            return
        }
        // Two voices never share a line: hear whose this is first (a few hundredths of a second).
        if settings.speakerVoices, let samples = seg.voiceSamples, seg.text.filter(\.isLetter).count >= 2 {
            heldJoin = (seg, t, nil)
            speakers.voice(of: samples) { [weak self] assignment in self?.heardVoice(seg, assignment) }
            return
        }
        join(seg, onto: prev)
    }

    private func heardVoice(_ seg: Segment, _ assignment: SpeakerAssignment) {
        let voice = assignment.voice
        guard let held = heldJoin, held.seg.id == seg.id else {
            // Already recorded on its own (another line came first).
            if let line = lineForSegment[seg.id] {
                apply(assignment, to: line)
                voicePending.remove(line)
            }
            return
        }
        heldJoin = nil
        let lines = store.session(store.liveID ?? "")?.lines ?? []
        if let prev = lastHeard, let last = lines.last, last.id == prev.line,
           voice == nil || last.voice == nil || voice == last.voice {
            join(seg, onto: prev)   // the earlier line's voice stays
        } else {
            appendHeard(seg, t: held.t, translation: held.translation)
            if let line = lineForSegment[seg.id] { apply(assignment, to: line) }
        }
    }

    /// Put a voice (and a library match, if any) on a recorded line. Used when a line was held
    /// back for its voice instead of going through `SpeakerTagger.tag`.
    private func apply(_ assignment: SpeakerAssignment, to line: String) {
        guard let voice = assignment.voice else { return }
        speakers.onVoice?(line, voice)
        guard let match = assignment.match, let id = store.liveID else { return }
        store.setVoice(lineID: line, voice)
        if match.kind == .auto {
            store.setVoiceProfile(id, voice: voice, ref: match.ref)
            profiles.markSeen(id: match.profile.id)
        } else {
            store.setVoiceSuggestion(id, voice: voice, match.ref)
        }
    }

    /// One sentence a pause cut in two: the earlier line takes the rest and is translated again whole.
    private func join(_ seg: Segment, onto prev: (seg: Segment, line: String)) {
        let text = HeardText.join(prev.seg.text, seg.text)
        var joined = prev.seg
        joined.text = text
        joined.end = seg.end
        joined.cut = seg.cut
        joined.split = seg.split
        lastHeard = (joined, prev.line)
        store.setSource(lineID: prev.line, text)
        if let id = store.liveID { fixes.applyKnown(lineID: prev.line, in: id) }
        trackRefining(seg, line: prev.line)
        listen.join(seg.id, into: prev.seg.id, text: text)
        contentLog("JOIN \(prev.line) += \(seg.text)")
        heardWords()
    }

    private func appendHeard(_ seg: Segment, t: Double, translation: String? = nil, tag: Bool = false) {
        lineCounter += 1
        let id = "h\(lineCounter)-\(seg.id)"
        lineForSegment[seg.id] = id
        store.append(TranscriptLine(id: id, t: t, speaker: "them", src: seg.text, dst: translation ?? seg.translation,
                                    srcLang: seg.sourceCode, dstLang: listen.resolvedTarget,
                                    // 会议室 alone too: a meeting switched to it from 电脑和会议室
                                    // would otherwise mark its later room lines 线上.
                                    via: seg.id >= ListenEngine.roomIDs || settings.listensToRoom ? "room" : nil))
        if let live = store.liveID { fixes.applyKnown(lineID: id, in: live) }
        trackRefining(seg, line: id)
        var kept = seg
        kept.voiceSamples = nil
        lastHeard = (kept, id)
        // A line with hardly a letter ("." from a breath or a click) gets no voiceprint.
        if tag, settings.speakerVoices, let samples = seg.voiceSamples, seg.text.filter(\.isLetter).count >= 2 {
            voicePending.insert(id)
            speakers.tag(lineID: id, samples: samples) { [weak self] in self?.voicePending.remove(id) }
        }
        heardWords()
    }

    private func recordSaid(_ src: String, _ dst: String, from: String, to: String, secondsAgo: Double) {
        guard let start = store.liveStart else { return }
        lineCounter += 1
        let t = max(0, Date().timeIntervalSince(start) - secondsAgo)
        store.append(TranscriptLine(id: "m\(lineCounter)", t: t, speaker: "me", src: src, dst: dst,
                                    srcLang: from, dstLang: to))
        heardWords()
    }

    // MARK: Imported files

    /// 导入录音或视频…: the open panel, then the files go into the queue.
    func chooseImportFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = L("导入")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    /// Dropped on the window or the Dock icon, opened with Cicada, or chosen: each file becomes a
    /// record, shown in the main window.
    func importFiles(_ urls: [URL]) {
        let files = urls.filter(FileImporter.importable)
        guard !files.isEmpty else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        Task {
            let ids = await importer.add(files)
            openMainWindow?()
            if let first = ids.first { mainShow = "\(first),transcript" }
        }
    }

    /// Deleting a record also stops transcribing it; the original file stays where it was.
    func deleteSession(_ id: String) {
        importer.cancel(id)
        store.delete(id)
        folderExport.deleted(id)
    }

    private func importFinished(_ id: String) {
        guard let s = store.session(id) else { return }
        // The voices are known now: Ling's guess at who 说话人 1, 2… are, as at the end of a meeting.
        if settings.speakerVoices { speakerNamer.guess(id, force: true) }
        let notesToo = settings.importNotes && ling.hasKey && !s.lines.isEmpty
        if notesToo { notes.generate(for: id) }
        folderExport.ended(id)
        let content = UNMutableNotificationContent()
        content.title = L("\(s.displayTitle) 转好了")
        content.body = L("\(RecordList.length(s)) · \(s.lines.count) 句") + (notesToo ? L("，正在整理纪要") : "")
        content.userInfo = ["session": id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "import-\(id)", content: content, trigger: nil)) { error in
            if let error { debugLog("import: notification not shown: \(error)") }
        }
    }

    // MARK: Export

    func export(_ session: Session, kind: String) {
        if kind == "copy" {
            RichCopy.session(session)
            return
        }
        let panel = NSSavePanel()
        let ext = kind == "word" ? "docx" : kind == "srt" ? "srt" : "md"
        panel.nameFieldStringValue = "\(session.displayTitle.replacingOccurrences(of: "/", with: "-")).\(ext)"
        panel.canCreateDirectories = true
        if let w = NSApp.keyWindow, !(w is NSPanel), w.isVisible {
            panel.beginSheetModal(for: w) { [weak self] r in
                guard r == .OK, let url = panel.url else { return }
                MainActor.assumeIsolated { _ = self?.writeExport(session, kind: kind, to: url) }
            }
            return
        }
        NSApp.activate()
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeExport(session, kind: kind, to: url)
    }

    @discardableResult
    func writeExport(_ session: Session, kind: String, to url: URL) -> Bool {
        do {
            switch kind {
            case "word": try TranscriptExport.docx(session).write(to: url)
            case "srt": try TranscriptExport.srt(session).write(to: url, atomically: true, encoding: .utf8)
            default: try TranscriptExport.markdown(session).write(to: url, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            debugLog("export failed: \(error)")
            return false
        }
    }

    // MARK: Debug control (only with `defaults write com.wquguru.cicada debug -bool true`)

    func installDebugControl() {
        guard settings.debug || DevBuild.isDev else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(DevBuild.debugChannel), object: nil, queue: .main
        ) { [weak self] note in
            let cmd = note.object as? String ?? ""
            let id = note.userInfo?["id"] as? String
            MainActor.assumeIsolated { self?.runDebugCommand(cmd, id: id) }
        }
        debugLog("debug control ready")
        MainThreadWatchdog.shared.start()
    }

    func debugCommand(_ cmd: String) {
        debugLog("debug command: \(cmd)")
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "ping":
            let snapshot = debugSnapshot(["build"])
            DebugRun.reply?.data = snapshot
        case "state":
            // Built first: a bad section fails the reply while the snapshot is made.
            let snapshot = debugSnapshot(arg.split(separator: ",").map(String.init))
            DebugRun.reply?.data = snapshot
        // start:user is a click on 开始听; plain start is listening starting by itself.
        case "start": start(byUser: arg == "user")
        case "models":
            // models:<installed,…>/<system languages,…> pretends the Mac has only these speech models
            // and languages, to test the fetch of a second model and 听不出; models:off ends it.
            // models:none/zh-Hans-CN is a Mac with no model at all.
            let parts = arg.split(separator: "@", maxSplits: 1).map(String.init)
            listen.simulatedFetchDelay = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
            let p = parts[0].split(separator: "/", omittingEmptySubsequences: false)
                .map { $0.split(separator: ",").map(String.init).filter { $0 != "none" } }
            listen.simulatedModels = arg == "off" ? nil : Set(p.first ?? [])
            listen.simulatedSystemLanguages = arg == "off" || p.count < 2 ? nil : p[1]
            Task { await listen.refreshInstalledLocales() }
        case "recordTrack":
            // recordTrack:off compares the meeting record without its own recognizer (next start).
            Recognition.recordTrackOff = arg == "off"
            debugLog("record track: \(Recognition.recordTrack ? "on" : "off")")
        case "share":
            // share:<record id>[,full][,pw] shares a meeting as the sheet would (point a dev build at a
            // local Worker with the shareServer default); unshare:<record id> turns it off.
            let p = arg.split(separator: ",").map(String.init)
            guard let s = p.first.flatMap({ store.session($0) }) else { debugFail("share: no such record"); break }
            var o = ShareClient.Options()
            o.scope = p.contains("full") || s.notes?.isEmpty ?? true ? .full : .notes
            o.password = p.contains("pw") ? SharePassword.make() : nil
            Task {
                switch await ShareClient.shared.share(s, o) {
                case .shared(let r): debugLog("share: \(r.url)\(r.password.map { " password \($0)" } ?? "")")
                case .blocked(let hits, let kept): debugLog("share: blocked lines \(ShareHit.recordLines(hits, kept: kept).sorted())")
                case .failed(let code, _): debugLog("share: failed \(code)")
                }
            }
        case "shareSheet":
            if !arg.isEmpty { openMainWindow?(); mainShow = arg }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .debugShareSheet, object: arg.isEmpty ? nil : arg)
            }
        case "unshare":
            guard let r = ShareStore.read(arg) else { debugFail("share: \(arg) not shared"); break }
            Task { debugLog("share: revoked \(await ShareClient.shared.revoke(r, sessionID: arg))") }
        case "recordState": debugLog("record track: \(Recognition.recordTrack ? "on" : "off") settling=\(settling.count) tracked=\(refining.count)")
        case "recognizer":
            // recognizer:legacy runs the macOS 14/15 recognizer (SFSpeechRecognizer) on 26; recognizer:cloud
            // hears as an Intel Mac does; recognizer:auto ends either. Takes effect from the next start.
            Recognition.forceLegacy = arg == "legacy"
            Recognition.forceCloud = arg == "cloud"
            debugLog("recognizer: \(Recognition.name)")
            Task { await listen.refreshInstalledLocales() }
        case "releaseModel":
            // releaseModel:<locale> gives back a speech model this app reserved (macOS keeps five per app).
            guard #available(macOS 26, *) else { break }
            guard #available(macOS 26, *) else { break }
            Task {
                let ok = await AssetInventory.release(reservedLocale: Locale(identifier: arg.replacingOccurrences(of: "-", with: "_")))
                debugLog("releaseModel \(arg): \(ok) reserved now=\(await AssetInventory.reservedLocales.map { $0.identifier })")
                await listen.refreshInstalledLocales()
            }
        case "modelFail":
            // modelFail:<offline|disk|limit|other> makes every model download fail that way; modelFail:off ends it.
            listen.simulatedModelFailure = arg == "off" || arg.isEmpty ? nil : arg
        case "network":
            // network:<on|off> pretends the network came or went; network:real follows the real one.
            listen.simulatedOnline = arg == "on" ? true : arg == "off" ? false : nil
        case "modelRetry": listen.retryModel()
        case "cloud":
            // cloud:on is a click on 先用○○听, cloud:off on 换回等待, cloud:decline on 继续等.
            switch arg {
            case "off": stopCloud()
            case "decline": declineCloud()
            case "state":
                debugLog("cloud state service=\(listen.cloudService ?? "none") offered=\(cloud.offered) listening=\(listen.cloudListening) "
                         + "downloading=\(listen.downloading.map { "\($0.lang.locale) \(Int(-$0.since.timeIntervalSinceNow)) s" } ?? "none")")
            default: startCloud()
            }
        case "pickLanguage":
            if let lang = sourceLanguages.first(where: { $0.locale == arg }) { listen.pickLanguage(lang) }
        case "stop": stop()
        case "source": sourceSelection = arg
        case "listenSource", "mic":
            // mic:<on|off> is the button; listenSource:<system|room|both> the old names for it.
            setMic(arg == "on" || arg == "room" || arg == "both")
        case "roomEchoSim":
            // roomEchoSim:<on|off|real>: pretend the speakers do (or don't) reach the room mic.
            roomListen.echoGate.forced = arg == "real" ? nil : arg != "off"
        case "roomMicSilent":
            // roomMicSilent:<on|off>: the room mic delivers nothing but zeros (from its next start).
            RoomMic.simulateSilence = arg != "off"
        case "roomMic":
            // roomMic:<uid|auto>: the menu beside 打开麦克风.
            setRoomMic(arg == "auto" ? "" : arg)
        case "roomMicGone":
            // roomMicGone[:none]: pretend the room's microphone (or every one) was unplugged.
            let uid = (settings.hearsBoth ? roomListen : listen).roomMicUID
            fakeGoneMics = arg == "none" ? Set(AudioDevices.inputs().map(\.uid)) : Set([uid].compactMap { $0 })
            watchRoomMic()
        case "open": openMainWindow?()
        case "panel": showPanel?()
        case "onboarding":
            // onboarding:<step>[,skip|setup]: the step, optionally in its second state.
            let p = arg.split(separator: ",").map(String.init)
            onboardingStep = min(max(Int(p.first ?? "") ?? 1, 1), OnboardingView.done)
            onboardingKeySkip = p.contains("skip")
            onboardingSpeakSetup = p.contains("setup") ? .checklist : p.contains("ask") ? .ask : .followSetting
            openOnboarding?()
        case "step": onboardingStep = Int(arg) ?? 1
        case "samplePlay": ensureListening(); sample.play()
        case "speakers": settings.speakerVoices = arg == "on"
        // 改正听错的词: switches, the word list, and the fixes of a meeting (live, or `<id>`).
        case "fixes": settings.fixMisheard = arg != "off"
        // A meeting without audio (no tap, no recognizer), fed lines by `heard:`.
        case "silentListen": ListenEngine.silentLocale = arg.isEmpty || arg == "off" ? nil : arg
        case "heard": listen.debugHeard(arg)
        case "askNames": settings.askNames = arg != "off"
        case "vocabAdd":   // vocabAdd:Morpho=莫拉、莫法 (several lines with "|")
            let r = vocabulary.importText(arg.replacingOccurrences(of: "|", with: "\n"))
            debugLog("vocab: added=\(r.added) updated=\(r.updated) skipped=\(r.skipped)")
        case "vocabRemove": vocabulary.remove(arg)
        case "vocabState":
            debugLog("vocab: \(vocabulary.terms.count) terms")
            for t in vocabulary.terms { contentLog("VOCAB \(t.word) heard=\(t.heard) source=\(t.source) fixes=\(t.fixes)") }
        case "fixState":
            let id = arg.isEmpty ? store.liveID ?? store.sessions.first?.id ?? "" : arg
            let lines = store.session(id)?.lines ?? []
            let all = lines.flatMap { $0.fixes ?? [] }
            debugLog("fix state \(id): lines=\(lines.filter { $0.fixes != nil }.count) applied=\(all.filter(\.applied).count) "
                     + "asked=\(all.filter { $0.ask == true }.count) off=\(all.filter { $0.off == true }.count) on=\(settings.fixMisheard)")
            contentLog("BAR \(liveMain.src) | \(liveMain.dst)")
            for l in lines where l.fixes != nil {
                contentLog("FIXED \(l.id) \(l.fixes!.map { "\($0.from)→\($0.to)\($0.ask == true ? "?" : $0.off == true ? "✗" : "")" }) | \(l.shown)")
            }
        case "fixAnswer":  // fixAnswer:yes|no[,<id>]
            let parts = arg.split(separator: ",", maxSplits: 1).map(String.init)
            let id = parts.count > 1 ? parts[1] : store.liveID ?? store.sessions.first?.id ?? ""
            if let first = fixes.asking(in: id) ?? fixes.pending(in: id).first.map({ ($0.line, $0.fix, 1, 1) }) {
                fixes.answer(first.fix, yes: parts.first == "yes", in: id)
            }
        // The recheck without audio: line `<id>` settles as `<text>` and is translated (and fixed) again,
        // with the lines after it in view, as the record's own recognizer would have it.
        case "resettle":   // resettle:<line id>=<text>
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2, let id = store.liveID, let rec = store.session(id)?.lines.first(where: { $0.id == p[0] }) else { break }
            store.setSource(in: id, lineID: rec.id, p[1])
            fixes.applyKnown(lineID: rec.id, in: id)
            Task { [weak self] in
                guard let self, let out = await self.listen.translate(p[1], source: rec.srcLang, target: rec.dstLang) else { return }
                self.store.setTranslation(in: id, lineID: rec.id, out)
            }
        case "fixLater":
            let id = arg.isEmpty ? store.liveID ?? "" : arg
            if let a = fixes.asking(in: id) { fixes.later(a.fix, in: id) }
        case "fixUndo": fixes.undo()
        case "fixEdit":   // fixEdit:<line id>=<new text>[|one|keep0][,<session id>]
            let (head, sid) = { () -> (String, String) in
                if let c = arg.lastIndex(of: ","), !arg[arg.index(after: c)...].contains("=") { return (String(arg[..<c]), String(arg[arg.index(after: c)...])) }
                return (arg, store.liveID ?? store.sessions.first?.id ?? "")
            }()
            let p = head.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2 else { break }
            let opts = p[1].split(separator: "|").map(String.init)
            let n = fixes.edit(lineID: p[0], in: sid, to: opts[0], everywhere: !opts.contains("one"), remember: !opts.contains("keep0"))
            debugLog("fix edit changed \(n) lines")
        case "fixRevert":  // fixRevert:<line id>[,<session id>]: the line's first applied fix
            let parts = arg.split(separator: ",", maxSplits: 1).map(String.init)
            let id = parts.count > 1 ? parts[1] : store.liveID ?? store.sessions.first?.id ?? ""
            if let l = store.session(id)?.lines.first(where: { $0.id == parts.first }), let f = l.fixes?.first(where: \.applied) {
                fixes.revert(f, lineID: l.id, in: id)
            }
        case "speakerGuess": speakerNamer.guess(arg, force: true)
        case "speakersRender":
            // speakersRender:<session id>=<png>[@width]: the people strip and the first lines with their labels.
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2, let s = store.session(p[0]) else { break }
            let out = p[1].split(separator: "@").map(String.init)
            let width = out.count > 1 ? CGFloat(Double(out[1]) ?? 360) : 360
            let r = ImageRenderer(content: SpeakerPreview(model: self, session: s).environment(\.speakerNames, SpeakerLabels.names(s)).frame(width: width).background(Color.white))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out[0]))
            }
        case "voiceprintFile":
            // voiceprintFile:<audio>=<json>: the app's voiceprint of a whole file, to compare with the reference model.
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2 else { break }
            DispatchQueue.global().async {
                let samples = Voiceprints.samples(of: URL(fileURLWithPath: p[0]))
                let v = samples.flatMap { s in (try? Voiceprints.load())?.embed(s) }
                let data = try? JSONSerialization.data(withJSONObject: ["seconds": Double(samples?.count ?? 0) / 16000, "v": v ?? []])
                try? data?.write(to: URL(fileURLWithPath: p[1]))
                debugLog("voiceprintFile: \(v == nil ? "failed" : "ok") \(p[0])")
            }
        case "micVerify": installer.install(verifyOnly: true)
        case "settings":
            settingsSection = SettingsSection(rawValue: arg) ?? settingsSection
            openSettings(settingsSection)
        case "diagnostics":
            setDiagnostics(arg != "off")
            debugLog("diagnostics \(settings.diagnostics ? "on" : "off")")
        case "diagReport":
            debugLog("diag report:\n" + diagnostics.report(version: "", service: settings.aiConfig))
        case "micTest": installer.runTest()
        case "micNext": installer.next()
        case "sysMic":
            refreshSystemMic()
            debugLog("system mic state=\(systemMicState) default=\(AudioDevices.defaultInput?.name ?? "-") saved=\(AudioDevices.inputs().first { $0.uid == settings.savedSystemInput }?.name ?? "-") recording=\(systemMic.recordingDevice?.name ?? "-") engine=\(speak.micDeviceName) auto=\(settings.autoSystemMic) wanted=\(wantsSystemMic)")
        case "sysMicSet":
            // Simulates another app or the user moving the system mic (part of a device name).
            if let d = AudioDevices.inputs().first(where: { $0.name.localizedCaseInsensitiveContains(arg) }) { AudioDevices.setDefaultInput(d) }
            refreshSystemMic()
        case "sysMicRestore": restoreSystemMic()
        case "sysMicSwitch": switchSystemMic()
        case "sysMicAuto": setAutoSystemMic(arg != "off")
        case "speakMic":
            settings.speakMic = arg.isEmpty ? "" : systemMic.realInputs.first { $0.name.localizedCaseInsensitiveContains(arg) }?.uid ?? ""
        case "micUsers":
            refreshMicUsers()
            debugLog("mic users virtual=\(virtualMic?.id ?? 0) readers=\(MicUsers.readers().map { "\($0.bundleID)\($0.inputs)" }) users=\(micUsers.map { "\($0.name)=\($0.state)" })")
        case "micGuide":
            refreshMicUsers()
            if let user = micUsers.first(where: { $0.bundleID == arg || $0.name == arg }) { showMicGuide(user) } else { micGuide = nil }
        case "talkKey", "toggleKey":
            let s = arg == "right" ? Shortcut.rightOption : Shortcut(stored: arg)
            let refusal = s.map { setShortcut($0, for: parts[0] == "talkKey" ? .talk : .toggle) } ?? "bad shortcut"
            debugLog("\(parts[0]) \(arg): \(refusal ?? "ok")")
        case "shortcuts":
            debugLog("shortcuts talk=\(settings.talkKey.display) armed=\(talkRight.isRunning || talkCombo.isRegistered) needsPermission=\(talkNeedsPermission) inputMonitoring=\(RightOptionKey.allowed) toggle=\(settings.toggleKey.display) taken=\(toggleKeyTaken)")
        case "aiKeyFile":
            // Dev testing: the key comes from a file so it never passes through the log.
            if let k = try? String(contentsOfFile: arg, encoding: .utf8) { Task { await ling.setKey(k) } }
        case "aiCheck": Task { await ling.check() }
        case "voice":
            // voice:<lang>=<id> chooses ("voice:en=ming:UK_George", "voice:zh=clone"); voice:<lang> logs the choice.
            let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { setVoice(kv[1], for: kv[0]) }
            debugLog("voice \(kv[0]) → \(voiceID(for: kv[0]) ?? "none") options=\(VoiceCatalog.options(for: kv[0]).map(\.id)) clone=\(VoiceReference.exists)")
        case "voiceCloneFile":
            // voiceCloneFile:<wav> uses a recording as "my voice", transcribing it like the sheet does.
            Task {
                let url = URL(fileURLWithPath: arg)
                guard let f = try? AVAudioFile(forReading: url),
                      let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
                      (try? f.read(into: buf)) != nil else { debugLog("voiceCloneFile: unreadable"); return }
                let text = await LoopbackTest.transcribe([buf], locale: settings.speakFromLang.locale)
                do { try VoiceReference.save(wav: url, text: text) } catch { debugLog("voiceCloneFile: \(error)") }
                let pace = VoiceReference.pace(of: url, text: text)
                debugLog("voiceCloneFile: saved, transcript \(text.count) chars, pace \(pace.map { String(format: "%.1f", $0) } ?? "-")/s slow=\(pace.map { VoiceReference.isSlow(text: text, pace: $0) } ?? false)")
            }
        case "voicePreview":
            // voicePreview:<lang>=<id>
            let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { previewVoice(kv[1], language: kv[0]) }
        case "notesNow": notes.updateNow()
        case "micDeniedSim":
            // micDeniedSim:on|off: 电脑和会议室 as if the microphone were refused (the dot, banner, notification).
            fakeMicDenied = arg != "off"
            checkProblem()
            debugLog("problem: mic denied sim \(fakeMicDenied) denied=\(hybridMicDenied) problem=\(problem ?? "-") notesShown=\(notesShown)")
        case "endSim":
            // endSim:<app name>[,<app name>] pretends those meeting apps are in a call; endSim: none; endSim:off real.
            fakeCalls = arg == "off" ? nil : Dictionary(arg.split(separator: ",").map { ("sim.\($0)", String($0)) }) { a, _ in a }
            debugLog("meeting end: simulated calls \(fakeCalls.map { $0.values.sorted().description } ?? "off")")
        case "endTimes":
            // endTimes:<silence>,<countdown>,<grace> in seconds; endTimes: back to the settings.
            let v = arg.split(separator: ",").compactMap { Double($0) }
            endTimesOverride = v.count == 3 ? (v[0], v[1], v[2]) : nil
        case "endKeep": keepRecording()
        case "endState":
            debugLog("meeting end: running=\(listen.isRunning) autoEnded=\(autoEnded) pending=\(ending.map { "\($0.reason) in \(Int($0.deadline.timeIntervalSinceNow)) s" } ?? "none") inCall=\(endWatch?.inCall.values.sorted() ?? []) silent=\(endWatch.map { Int(Date().timeIntervalSince($0.lastSpeech)) } ?? -1) s config=\(endConfig)")
        case "updateFeed":
            // updateFeed:<release json url>: check a fake release (file:// works), even in a dev build.
            if let url = URL(string: arg) { updates.checker.feed = url }
            updates.checkNow()
        case "updateCheck": updates.checkNow()
        case "updateInstall": updates.install(model: self)
        case "updateState": debugLog("update current=\(Updates.current) found=\(updates.update?.version ?? "-") check=\(updates.check) last=\(updates.lastChecked.map { "\($0)" } ?? "-") progress=\(updates.progress.map { String($0) } ?? "-") failure=\(updates.failure ?? "-")")
        case "loginItem":
            if !arg.isEmpty { loginItem.set(arg == "on") }
            loginItem.refresh()
            debugLog("login item enabled=\(loginItem.enabled) needsApproval=\(loginItem.needsApproval)")
        case "about": AboutPanel.show()
        case "display": setDisplayMode(arg)
        case "notesWindow":
            let v = arg.split(separator: ",").compactMap { Double($0) }
            openNotesWindow()
            if v.count == 4 { notesWindow.place(NSRect(x: v[0], y: v[1], width: v[2], height: v[3])) }
        case "notesFrame": debugLog("notes window frame=\(String(describing: notesWindow.frame)) visible=\(notesWindow.isVisible) policy=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")")
        case "notesReplay":  // <id>[,<lines per update>]
            let parts = arg.split(separator: ",").map(String.init)
            Task { await notes.replay(parts[0], step: parts.count > 1 ? Int(parts[1]) ?? 4 : 4) }
        case "notesShow": notes.show(arg)
        case "dock": settings.showInDock = arg != "off"  // 在 Dock 中显示
        case "dockRender":  // dockRender:<png>: the Dock tile as drawn now
            guard let v = NSApp.dockTile.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { debugFail("dock: no tile"); break }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
        case "notesCapturable": notesWindow.setCapturable(arg != "off")
        case "notesShare": setNotesCapturable(arg != "off")  // the setting itself, as its badge or switch does
        case "notesClose": notesWindow.performClose()
        case "notesMinimize": notesWindow.performMiniaturize()
        case "closeWindow":
            // closeWindow:<main|settings|onboarding>: what the window's close button does.
            let w = NSApp.windows.first { w in
                switch arg {
                case "main": w.contentView is NSHostingView<MainWindowView>
                case "settings": w.contentView is NSHostingView<SettingsView>
                default: w.contentView is NSHostingView<OnboardingView>
                }
            }
            w?.performClose(nil)
        case "transcriptRender":   // transcriptRender:<png>,<session id>,<first line>,<count>: the notes window's 原话
            let p = arg.split(separator: ",").map(String.init)
            guard p.count == 4, let s = store.session(p[1]), let first = Int(p[2]), let count = Int(p[3]) else { break }
            let ls = Array(s.lines.dropFirst(max(0, first - 1)).prefix(count))
            let waiting = fixes.pending(in: s.id)
            // The row's own parts (the list itself is lazy and draws nothing off screen).
            let view = VStack(alignment: .leading, spacing: 14) {
                ForEach(ls) { l in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TranscriptParagraphs.joinFixed([l])).font(.system(size: 14)).lineSpacing(2)
                        if let d = l.dst { Text(d).font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                        let fixed = (l.fixes ?? []).filter(\.applied).map { (l.id, $0) }
                        if !fixed.isEmpty { FixedWords(fixes: fixed) { _, _ in } }
                    }
                }
                Spacer(minLength: 0)
                if let w = waiting.first { FixConfirmCard(line: w.line, fix: w.fix, count: waiting.count) { _ in } }
            }
            .padding(16).frame(width: 460, height: 900).background(Color.white)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: p[0]))
            }
        case "notesRender":
            // The whole notes column as a PNG, for checking what is below the fold.
            let shownID = notes.shownID ?? store.liveID
            let fixTerms = shownID.flatMap { store.session($0) }.map { AnyView(FixTermsView(fixes: fixes, session: $0) { _ in }) }
            let view = NotesContentView(notes: notes.notes, fresh: notes.fresh, live: store.liveID != nil,
                                        updating: notes.state == .updating, fixTerms: fixTerms)
                .padding(24).frame(width: 460).background(Color.white)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: arg))
            }
        case "mainShow": mainShow = arg
        case "play":
            // The shown record plays from <seconds>, as a click on a line's time does.
            if let t = Double(arg) { NotificationCenter.default.post(name: .debugPlay, object: t) }
        case "mainWindow":
            // Place the records window, floating above other apps' panels while testing clicks (no arg: back to normal).
            guard let w = NSApp.windows.first(where: { $0.contentView is NSHostingView<MainWindowView> }) else { break }
            let v = arg.split(separator: ",").compactMap { Double($0) }
            if v.count == 4 { w.setFrame(NSRect(x: v[0], y: v[1], width: v[2], height: v[3]), display: true) }
            w.level = v.count == 4 ? .floating : .normal
            w.orderFrontRegardless()
        case "mainRender":
            // The main window as drawn, for checking it without Screen Recording permission.
            guard let view = NSApp.windows.first(where: { $0.contentView is NSHostingView<MainWindowView> })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { break }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
            // And the shown meeting's whole notes page beside it, for what is below the fold.
            if let id = mainShow?.split(separator: ",").first.map(String.init), let n = store.session(id)?.notes {
                let r = ImageRenderer(content: NotesContentView(notes: n, document: true).padding(32).frame(width: 744).background(Color.white))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let full = NSBitmapImageRep(data: tiff) {
                    try? full.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg + ".notes.png"))
                }
            }
        case "panelRender":
            // The menu bar panel drawn offscreen with real AppKit controls: the popover closes
            // as soon as another app is active, so it can't be caught by windowsRender.
            let host = NSHostingView(rootView: MenuPanelView(model: self, settings: settings))
            let size = host.fittingSize
            let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
                }
                w.orderOut(nil)
            }
        case "settingsRender":
            // settingsRender:<section>=<png>: one settings page in full, scroll view or not.
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2, let section = SettingsSection(rawValue: p[0]) else { break }
            settingsSection = section
            let r = ImageRenderer(content: SettingsView(model: self, settings: settings, installer: installer).page
                .frame(width: 530).background(Color(red: 0.965, green: 0.969, blue: 0.976)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: p[1]))
            }
        case "windowsRender":
            // Every visible window as drawn (<dir>/<n>-<class>.png), without Screen Recording permission.
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                guard let view = w.contentView, view.bounds.width > 40,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "\(i)-\(String(describing: type(of: w)).prefix(24)).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg).appendingPathComponent(name))
            }
        case "notesState": debugLog("notes state=\(notes.state) topics=\(notes.notes.topics.count) covered=\(notes.notes.covered) glossary=\(notes.glossary.count) timedPoints=\(notes.notes.topics.reduce(0) { $0 + ($1.pointTimes?.compactMap { $0 }.count ?? 0) })/\(notes.notes.topics.reduce(0) { $0 + $1.points.count }) fresh=\(notes.fresh.count)")
        case "lingSimulate":
            ling.simulate = ["429": .rateLimited, "hijack": .hijacked, "timeout": .timeout][arg]
            debugLog("ling simulate=\(String(describing: ling.simulate))")
        case "translateFail":
            // translateFail:<n>: the next n sentences fail on every provider (tests the retry).
            translator.failNext = Int(arg) ?? 0
            debugLog("translate fail next=\(translator.failNext)")
        case "googleDown":
            // googleDown:<on|off>: Google translation fails as if this Mac had no proxy.
            translator.simulateGoogleDown = arg != "off"
            debugLog("google down simulate=\(translator.simulateGoogleDown)")
        case "aiRemove": ling.removeKey()
        case "aiHide":
            // aiHide:<on|off>: the key file stays; the app behaves as if there were none (for screenshots).
            ling.hideKey = arg != "off"
            Task { await ling.check() }
        case "aiState":
            let c = settings.aiConfig
            debugLog("ai state=\(ling.keyState) provider=\(c.provider.id.rawValue) hasKey=\(ling.hasKey) model=\(c.textModel) "
                     + "voice=\(c.voiceModel ?? "-") speaks=\(ling.speaks) clones=\(ling.clones) catalog=\(ling.catalog.count)"
                     + " check=[\(ling.aiCheck.summary)]")
        case "aiCheckSim":
            // aiCheckSim:<reason|lowBalance|off>: every check ends this way (screenshots of each state).
            // localNetwork: can't reach it, and the local network permission is off.
            ling.simulateCheck = arg == "localNetwork" ? .unreachable : AICheck.Reason(rawValue: arg)
            ling.simulateBalance = arg == "lowBalance" ? 0.4 : nil
            ling.simulateLocalNetwork = arg == "localNetwork"
            Task { await ling.check() }
        case "localNetworkProbe":
            // localNetworkProbe:<url>: whether the local network permission holds back a connection to it (log).
            if let url = URL(string: arg) { Task { _ = await LocalNetworkProbe.denied(url) } }
        // AI service: aiProvider:<ling|openrouter|zenmux|openai|custom>, aiTextModel:<id>, aiVoiceModel:<id|"">,
        // aiCustomBase:<url>, aiCustomVoiceBase:<url|"">, aiCustomVoice:<name>, aiCustomHearModel:<name>,
        // aiCustomHearBase:<url|"">, aiCustomRecognize:on|off.
        case "aiProvider": settings.aiProvider = AIProvider.named(arg).id.rawValue; applyAIService()
        // switchToLing: the 改用 Ling on a status line (logs why when it isn't offered).
        case "switchToLing": debugLog("switchToLing offered=\(canSwitchToLing)"); switchToLing()
        case "aiTextModel":
            if settings.provider.id == .ling { settings.aiModel = arg } else { settings.aiModels[settings.aiProvider] = arg }
            applyAIService()
        case "aiVoiceModel": settings.aiVoiceModels[settings.aiProvider] = arg; applyAIService()
        case "aiCustomBase": settings.aiCustomBase = arg; applyAIService()
        case "aiCustomVoiceBase": settings.aiCustomVoiceBase = arg; applyAIService()
        case "aiCustomVoice": settings.aiCustomVoice = arg; applyAIService()
        case "aiCustomHearModel": settings.aiCustomHearModel = arg; applyAIService()
        case "aiCustomHearBase": settings.aiCustomHearBase = arg; applyAIService()
        case "aiCustomRecognize": settings.aiCustomRecognize = arg == "on"; applyAIService()
        case "aiCustomOnly": settings.aiCustomOnly = arg == "on"; applyAIService()
        case "subtitles": setSubtitles(arg)
        case "meetingSubtitles": setSubtitles(arg, meetingOnly: true)
        case "notesLang": setNotesLanguage(arg)
        case "meetingNotesLang": setNotesLanguage(arg, meetingOnly: true)
        case "notesRegenerate":
            let p = arg.split(separator: "=").map(String.init)
            if p.count == 2 { regenerateNotes(p[0], choice: p[1]) }
        case "speakAsk":
            // speakAsk[:off]: the panel's one-time question, as if the switch was flipped for the first time.
            speakAsking = arg != "off"
        case "speakConfirmed": settings.speakConfirmed = arg != "off"
        case "speakOn": enableSpeaking(true)
        case "speakOff": enableSpeaking(false)
        case "speakOut": speak.debugOutputURL = arg.isEmpty ? nil : URL(fileURLWithPath: arg)
        case "speakFile": speak.speakFile(URL(fileURLWithPath: arg))
        // talkDown / talkUp: the talk key held and let go, with the real microphone (audio tests).
        // handsFree:on|off: 不用按键, as the setting.
        case "handsFree": settings.speakHandsFree = arg != "off"
        case "handsFreeDump": speak.setHandsFreeDump(arg.isEmpty ? nil : arg)
        case "talkDown": speak.pressBegan()
        case "talkUp": speak.pressEnded()
        // stall:<seconds> blocks the main thread, to check the watchdog samples it.
        case "stall": Thread.sleep(forTimeInterval: Double(arg) ?? 3)
        case "speakVP": speak.echoCancel = arg != "off"
        case "voiceMicRun":
            // voiceMicRun:<on|off> runs the echo-cancelling unit with nobody listening (what it does to the rest).
            if arg == "off" { voiceMic.detach("debug") } else if let d = AudioDevices.roomMic {
                voiceMic.prepare(input: d.id) { [voiceMic] ok in
                    debugLog("voiceMicRun: \(ok && voiceMic.attach("debug", input: d.id) { _ in } ? "running" : "failed")")
                }
            }
        case "roomEcho":
            // roomEcho:<on|off|bypass>: bypass = through the unit with processing off, on only for a press.
            roomEchoCancel = arg != "off"
            roomEchoBypass = arg == "bypass"
        case "roomGate": roomEchoGate = arg != "off"
        case "hybridState":
            debugLog("hybrid state source=\(settings.listenSource) main=\(listen.isRunning) room=\(roomListen.isRunning) "
                     + "echoCancelled=\(roomListen.hearsEchoCancelled) roomLang=\(roomListen.activeLang?.locale ?? "-") "
                     + "mainLang=\(listen.activeLang?.locale ?? "-") held=\(heldRoom.count) voiceMic=\(voiceMic.inUse) "
                     + "echo=\(roomListen.echoGate.echo) [\(roomListen.echoGate.summary)] music=\(roomListen.echoGate.playingMusic()) micSilent=\(roomMicSilent) "
                     + String(format: "roomVoiced=%.1fs mainVoiced=%.1fs", roomListen.router.stats().voicedTotal, listen.router.stats().voicedTotal))
        case "speakTest":
            // speakTest:<sample|voice>: open settings › 同声传译 with the 试一句 sheet and run it.
            settingsSection = .speak
            openSettingsWindow?()
            speakTestShown = true
            speakTester.start(arg == "voice" ? .voice : .sample)
        case "speakOutput":
            // speakOutput:<part of a device name>, or empty for the virtual mic (automatic).
            settings.speakOutput = arg.isEmpty ? "" : AudioDevices.outputs().first { $0.name.localizedCaseInsensitiveContains(arg) }?.uid ?? ""
            applySystemMic()
            speak.resetOutput()
            debugLog("speak output=\(speak.outputDevice()?.name ?? "-")")
        case "voicePicker": voicePickerOpen = arg != "off"
        case "aiModels": aiModelsOpen = arg != "off"
        case "speakTestBegin": speakTester.beginTalking()
        case "speakTestEnd": speakTester.endTalking()
        case "speakTestClose": speakTester.cancel(); speakTestShown = false
        case "speakTestState":
            debugLog("speak test phase=\(speakTester.phase) reached=\(String(describing: speakTester.reached)) result=\(speakTester.result?.report.replacingOccurrences(of: "\n", with: " | ") ?? "-")")
        case "micGuideRender":
            // micGuideRender:<bundle id>=<png>: the 怎么改 sheet for an app in the list.
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2, let user = micUsers.first(where: { $0.bundleID == p[0] }) else { break }
            let r = ImageRenderer(content: MicGuideView(model: self, bundleID: user.bundleID, name: user.name, close: {}).background(Color.white))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: p[1]))
            }
        case "speakTestRender":
            let r = ImageRenderer(content: SpeakTestView(model: self, tester: speakTester, close: {}).background(Color.white))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
            }
        case "place":
            let n = arg.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 { overlay.place(x: n[0], y: n[1], width: n[2], fontSize: n[3]) }
        case "overlayState": debugLog("overlay \(overlay.stateDescription)")
        case "overlayToggle": overlay.toggleManual()
        case "pillClick": showLiveDisplay()
        case "overlayAuto": setOverlayAuto(arg != "off")
        case "hideAfter": settings.overlayHideAfter = Double(arg) ?? 4
        case "frame":
            debugLog("overlay frame=\(overlay.barFrame) font=\(overlay.currentFontSize)")
        case "import": importFiles(arg.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        // 存到文件夹: exportFolder:<path> picks a folder (as 存到这里 does), exportFolder:off turns it
        // off; exportAll is 也存一份; exportState replies with the index and the problem.
        case "exportFolder":
            if arg == "off" { folderExport.turnOff() } else { folderExport.choose(URL(fileURLWithPath: arg, isDirectory: true)) }
        case "exportAll": folderExport.writeAll()
        case "rename":
            // rename:<id>=<title> as if typed into the record's title (empty: the automatic one).
            let p = arg.split(separator: "=", maxSplits: 1).map(String.init)
            store.rename(p[0], to: p.count > 1 ? p[1] : "")
        case "exportState":
            let x = folderExport
            DebugRun.reply?.data = [
                "on": x.on, "folder": settings.exportFolder, "checking": x.checking,
                "problem": x.problem.map { "\($0)" } as Any, "files": x.index.files, "pending": x.index.pending,
                "unwritten": x.unwritten.count, "lastFile": x.index.lastFile as Any,
            ] as [String: Any]
        case "importCancel": importer.cancelAll()
        case "importRetry":
            // `<id>=<locale>`: as if that language was picked in 这场会议只留下了录音.
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            importer.retry(parts[0], lang: parts.count > 1 ? sourceLanguages.first { $0.locale == parts[1] } : nil)
        case "importNotify":
            UNUserNotificationCenter.current().getNotificationSettings { s in debugLog("import: notifications \(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue)") }
        case "importState":
            debugLog("import state: current=\(importer.current?.id ?? "-") phase=\(importer.phase) heard=\(Int(importer.heard))/\(Int(importer.duration)) untranslated=\(importer.untranslated) queue=\(importer.queue.map(\.id))")
        case "export":
            guard let s = store.sessions.first(where: { $0.id != store.liveID }) ?? store.sessions.first else { return }
            let dir = URL(fileURLWithPath: arg)
            for (kind, ext) in [("md", "md"), ("srt", "srt"), ("word", "docx")] {
                let ok = writeExport(s, kind: kind, to: dir.appendingPathComponent("export.\(ext)"))
                debugLog("export \(ext) ok=\(ok)")
            }
        default: debugFail("unknown debug command: \(parts.first ?? "")", code: "unknown_command")
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceWork: DispatchWorkItem?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var pollTimer: Timer?
    private var runningObserver: Any?
    private var dockObserver: Any?
    private var popoverClickMonitor: Any?
    private lazy var menu = AppMenu(model: model)
    /// Held here: a toolbar keeps only a weak reference to its delegate.
    private lazy var mainToolbar = MainToolbar(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The palette is light only: in Dark Mode unstyled text and checkboxes turn white on white cards.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(model.settings.showInDock ? .regular : .accessory)
        menu.showMainWindow = { [weak self] in self?.showMainWindow() }
        menu.showOnboarding = { [weak self] in self?.showOnboarding() }
        menu.install()
        setupStatusItem()
        model.openMainWindow = { [weak self] in self?.showMainWindow() }
        model.openSettingsWindow = { [weak self] in self?.showSettingsWindow() }
        model.showPanel = { [weak self] in self?.togglePopover() }
        model.openPanel = { [weak self] in if self?.popover.isShown == false { self?.togglePopover() } }
        model.openOnboarding = { [weak self] in self?.showOnboarding() }
        runningObserver = model.$running.combineLatest(model.updates.$update, model.$problem).sink { [weak self] live, update, problem in
            let badge: BrandImage.Badge = problem != nil ? .problem : update != nil ? .update : .none
            self?.statusItem.button?.image = BrandImage.menuBar(live: live, badge: badge)
            self?.statusItem.button?.toolTip = problem ?? update.map { L("有新版本 \($0.version)") }
            debugLog("menu bar: badge=\(badge) tooltip=\(problem ?? "-")")
            DockIcon.show(live: live)
        }
        dockObserver = model.settings.$showInDock.dropFirst().sink { [weak self] _ in
            // After the change lands: the observer fires before the property is set.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateActivationPolicy() } }
        }
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshPermissions() }
        }
        pollTimer = poll
        RunLoop.main.add(poll, forMode: .common)
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated { self?.showOnboarding() }
            }
        } else if !Self.launchedAsLoginItem {
            // Opened by hand (Finder, Launchpad, Spotlight): show something, like the Dock icon does.
            showMainWindow()
        }
        model.installDebugControl()
        UNUserNotificationCenter.current().delegate = self
        installDeviceListener()
        Task { await model.launch() }
        model.updates.start()
    }

    /// Files dropped on the Dock icon or opened with Cicada: imported as records.
    func application(_ application: NSApplication, open urls: [URL]) {
        model.importFiles(urls)
    }

    /// "转好了": shown even while Cicada is in front; a click opens that record.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let id = info["session"] as? String
        let update = info["update"] as? String
        let problem = info["problem"] as? String
        await MainActor.run {
            // "听不到会议室": straight to System Settings, without bringing Cicada forward.
            if problem == "mic" {
                model.openMicrophoneSettings()
                return
            }
            // "纪要没存到文件夹": settings › 通用, where the row says what to do.
            if problem == "folder" {
                model.openSettings(.records)
                return
            }
            // "有新版本": the panel shows the download, and install asks first if a meeting is on.
            if update != nil {
                if !popover.isShown { togglePopover() }
                model.updates.install(model: model)
                return
            }
            showMainWindow()
            if let id { model.mainShow = id }
        }
    }

    /// Started by the system at login: stay in the menu bar.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        // Other apps would be left on the virtual mic, hearing nothing.
        model.systemMic.release()
    }

    /// Dock icon or Finder: bring back what is open; the main window only when nothing is.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let open = [mainWindow, settingsWindow, onboardingWindow].compactMap { $0 }.filter { $0.isVisible || $0.isMiniaturized }
        if open.isEmpty { showMainWindow() } else { open.forEach { $0.deminiaturize(nil) }; NSApp.activate() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { menu.dockMenu() }

    /// Quitting ends the meeting being recorded: ask first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.updates.installing, model.running, let id = model.store.liveID, !(model.store.session(id)?.lines.isEmpty ?? true) else { return .terminateNow }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("正在记录会议")
        alert.informativeText = L("退出会结束这场记录，已记下的内容会保存。")
        alert.addButton(withTitle: L("退出"))
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandImage.menuBar(live: false)
            if DevBuild.isDev {
                button.imagePosition = .imageLeading
                button.attributedTitle = NSAttributedString(string: " DEV", attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                    .baselineOffset: 1,
                ])
                button.toolTip = "\(appDisplayName) · \(DevBuild.label ?? "")"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.animates = false
        let panel = NSHostingController(rootView: MenuPanelView(model: model, settings: model.settings))
        // The popover follows the panel's height as it changes (a status line, the virtual-mic
        // warning). Without this the hosting view resized the popover window from its bottom
        // edge, pushing the top of the panel above the screen.
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        // .transient closes on focus changes, but the notes panel and the subtitle bar never take
        // focus: a click on them would leave the popover open on top. Close it ourselves.
        popoverClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if let self, self.popover.isShown, let w = e.window, w !== self.popover.contentViewController?.view.window,
               w !== self.statusItem.button?.window {
                self.popover.performClose(nil)
            }
            return e
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshOutputs()
            model.refresh()
            model.updates.panelOpened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Main window

    func showMainWindow() {
        popover.performClose(nil)
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = appDisplayName
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 480)
            w.delegate = self
            w.contentView = NSHostingView(rootView: MainWindowView(model: model, store: model.store, settings: model.settings,
                                                                   importer: model.importer))
            w.toolbar = mainToolbar.make()
            w.toolbarStyle = .unified
            w.titlebarSeparatorStyle = .none
            w.center()
            w.setFrameAutosaveName("LiveSubsMain")
            mainWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func showSettingsWindow() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = L("设置")
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings, installer: model.installer))
            w.center()
            w.setFrameAutosaveName("LiveSubsSettings")
            settingsWindow = w
        }
        model.refreshOutputs()
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func showOnboarding() {
        popover.performClose(nil)
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = L("欢迎使用\(appDisplayName)")
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(
                model: model, settings: model.settings, installer: model.installer, sample: model.sample,
                onFinish: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    self?.onboardingWindow?.close()
                }))
            w.center()
            onboardingWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        // After it's on screen: a notes window already showing has to make way.
        model.notesWindow.avoid(onboardingWindow)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        updateActivationPolicy(closing: w)
        if w == onboardingWindow { model.notesWindow.avoid(nil) }
        if w == onboardingWindow, !model.relaunching {
            model.sample.stop()
            UserDefaults.standard.set(true, forKey: "onboarded")
            // Done (or 稍后): land on the records window rather than nothing but the menu bar icon.
            if mainWindow?.isVisible != true {
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.showMainWindow() } }
            }
        }
    }

    /// A regular app (name and menus top left, Dock icon, ⌘Tab) while 在 Dock 中显示 is on, or
    /// else while the main, settings or onboarding window is open; only the menu bar item otherwise.
    /// The notes window doesn't count: it floats beside the meeting app and never takes focus from
    /// it (a regular app doesn't change that: the panel is non-activating either way).
    func updateActivationPolicy(closing: NSWindow? = nil) {
        let open = [mainWindow, onboardingWindow, settingsWindow].contains { $0 != nil && $0 != closing && $0!.isVisible }
        let policy: NSApplication.ActivationPolicy = open || model.settings.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        debugLog("activation policy → \(policy == .regular ? "regular" : "accessory")")
        // Back from .accessory the Dock can show a blank icon until the tile is drawn again.
        DockIcon.show(live: model.running)
    }

    // MARK: Output device changes

    private func installDeviceListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    private func outputDeviceChanged() {
        deviceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                debugLog("default output device changed → reconnecting tap")
                self?.model.listen.reconnectAudio()
                // Headphones in or out: whether the speakers reach the room mic is measured again.
                self?.model.roomListen.echoGate.reset()
                self?.model.refreshOutputs()
            }
        }
        deviceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

@main
struct CicadaMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-dmg-background"), args.count > i + 1 {
            let scale = args.count > i + 2 ? Int(args[i + 2]) ?? 1 : 1
            do {
                try DMGBackground.render(to: URL(fileURLWithPath: args[i + 1]), scale: scale)
                exit(0)
            } catch {
                FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        // AppKit adds "进入全屏幕" to a menu titled 显示 (View) unless told before launch;
        // no Live Subs window goes full screen.
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

struct ModelFetch: Equatable {
    let name: String
    let since: Date
    /// Fetched so "auto" has a second language to compare (else listening waits for it).
    let background: Bool
}

struct CloudState: Equatable {
    /// The service that can hear the meeting (only Ling today), nil when there is none.
    var service: String?
    var offered = false
    var listening = false
    /// The service's name, for a few seconds after listening came back to this Mac.
    var back: String?
}
