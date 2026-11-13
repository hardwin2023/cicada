import AppKit
import AVFoundation
import CoreMedia
import Network

struct Segment {
    let id: Int
    var text: String
    let sourceCode: String
    var translation: String?
    /// The sentence's audio, 16 kHz mono, when telling voices apart is on.
    var voiceSamples: [Float]? = nil
    /// Where it sits in the recognizer's audio (seconds; `clock` changes with each new recognizer),
    /// and whether Cicada ended it at a pause: what deciding a join needs (`HeardText.continues`).
    var start = 0.0, end = 0.0, clock = 0
    var cut = false
    /// Cicada ended it where a sentence or clause ends, on purpose: the next line doesn't join it.
    var split = false
    /// The record's own recognizer heard it too and will settle its words (`onRefined`).
    var refining = false
}

/// System audio → language detection → on-device transcription → translation.
/// UI-free: it reports through the callbacks below.
/// 电脑和会议室 runs two: the main one on the Mac's audio, a `.room` one on the microphone, each
/// with its own language, pauses and model, as Feishu keeps online and room streams apart.
@MainActor
final class ListenEngine {
    enum Role { case main, room }
    /// Segment ids from here up are the room engine's.
    static let roomIDs = 1_000_000
    /// `.room`: the microphone side of 电脑和会议室 (no prompts, offers or remembered language).
    let role: Role
    /// A language picked by hand is the meeting's: the people at the table may speak another
    /// (yours, from 同声传译's 我说), so the room side always detects, starting with yours.
    private var sourceMode: SourceMode { role == .room ? .auto : settings.sourceMode }
    // Outputs
    var onSubtitle: ((_ source: String, _ translation: String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onStateChange: (() -> Void)?
    /// A finished sentence; `secondsAgo` ≈ how long ago it started.
    var onFinal: ((Segment, _ secondsAgo: Double) -> Void)?
    var onTranslated: ((_ segmentID: Int, _ translation: String) -> Void)?
    /// The record's own recognizer settled segment `id` (`RecordRefiner`): its text for the meeting
    /// record, "" when it heard nothing there.
    var onRefined: ((_ segmentID: Int, _ text: String) -> Void)?
    /// Diagnostics: how long a sentence took from its last new words to its translation on screen.
    var onTiming: ((SentenceTiming) -> Void)?
    /// The recognizer heard words (a draft or a line), whether or not they are shown.
    var onWords: (() -> Void)?
    /// The room mic stayed digital silence even after it was opened again (`RoomMic.onSilent`).
    private(set) var roomMicSilent = false

    let settings: AppSettings
    let router = AudioRouter()

    private(set) var isRunning = false
    private(set) var statusText = L("准备就绪")
    private(set) var activeLang: Lang?
    /// Where "auto" stands on the language, and when to check it next.
    private var detection = LanguageDetection()
    var languageConfirmed: Bool { detection.confirmed }
    var detecting: Bool { detection.checking }
    private(set) var candidates: [Lang] = []
    private(set) var installedLocales: Set<String> = []
    /// The speech model fetched in the background so "auto" has two to compare.
    private(set) var fetchingModel: (lang: Lang, progress: Progress)?
    private var fetchFailed: Set<String> = []
    /// Debug (`models:`): treat only these as installed, plus what is fetched meanwhile, and these as the Mac's languages.
    var simulatedModels: Set<String>?
    var simulatedSystemLanguages: [String]?
    /// Debug (`models:…@<s>`): a background download takes at least this long, like a slow network.
    var simulatedFetchDelay: Double = 0
    /// Debug (`modelFail:`): every model download fails this way (offline, disk, limit, other).
    var simulatedModelFailure: String?
    /// Debug (`network:`): pretend to be on or offline; nil follows the real network.
    var simulatedOnline: Bool? { didSet { networkChanged() } }
    /// A model that couldn't be had while it was needed, shown in 听不出 with what to do.
    private(set) var modelProblem: ModelProblem?
    /// Speech models downloading (locale → which and since when), the background fetch and the one
    /// listening waits for alike: the card says how long it has taken.
    private var downloads: [String: (lang: Lang, since: Date)] = [:]
    /// The download the card shows: the one listening waits for, else the background one.
    var downloading: (lang: Lang, since: Date, background: Bool)? {
        if let lang = activeLang, recognizer == nil || cloudListening, let d = downloads[lang.locale] {
            return (d.lang, d.since, fetchingModel?.lang == lang)
        }
        guard let d = downloads.values.min(by: { $0.since < $1.since }) else { return nil }
        return (d.lang, d.since, fetchingModel?.lang == d.lang)
    }

    /// A service hearing the meeting (`CloudStream`): 先用○○听 while the model it needs downloads,
    /// or the user's own recognition server.
    private struct CloudSession {
        /// What listening was before, restored by 换回等待.
        var replaced: (lang: Lang?, confirmed: Bool)
        /// The model being waited for: once it is on the Mac, listening goes back to it.
        let awaiting: Lang?
        /// Who was hearing the meeting when it went to a service, and whether it was the user's own
        /// recognition server (rather than 先用○○听): a change in settings must not move the audio elsewhere.
        let via: (provider: AIProvider.Kind?, server: Bool)
        /// The language the service says is spoken.
        var lang: Lang?
        var failures = 0
    }
    /// nil while this Mac listens.
    private var cloud: CloudSession?
    var cloudListening: Bool { cloud != nil }
    /// The user's own service stopped answering in this meeting: listening went back to this Mac.
    private var serverFellBack = false
    /// The meeting is recognized by the user's own service (`Recognition.serverPreferred`).
    var serverHears: Bool {
        Recognition.serverPreferred && !serverFellBack && translator?.ling.transcribes == true
    }
    /// Back on this Mac after the service listened (its name), shown for a few seconds.
    private(set) var cloudBack: (name: String, at: Date)?
    /// The service that can hear audio (Ling's Ming, or a custom service's speech model); nil when
    /// there is none.
    var cloudService: String? {
        guard let ling = translator?.ling, ling.hearsAudio || ling.transcribes else { return nil }
        return ling.config().provider.name
    }
    /// 先用○○听 is offered: a model listening needs has been downloading a while, or couldn't be had.
    var offersCloud: Bool {
        guard isRunning, !cloudListening, cloudService != nil else { return false }
        // Something already shows the meeting in its language: the download only adds a comparison.
        guard recognizer == nil || !recordable else { return false }
        if modelProblem != nil { return true }
        guard let d = downloading else { return false }
        return Date().timeIntervalSince(d.since) >= Self.cloudOfferAfter
    }
    /// The 132 MB English model took 97 s on a fast link: most downloads end before the offer shows.
    static let cloudOfferAfter = 90.0
    private let pathMonitor = NWPathMonitor()
    private var realOnline = true
    private var online: Bool { simulatedOnline ?? realOnline }
    private var systemLanguages: [String] { simulatedSystemLanguages ?? Locale.preferredLanguages }
    /// When words were first heard this run: 听不出 is offered once the language stays unknown long after.
    private var firstHeardAt: Date?
    private var askShown = false

    private var audioTap: AudioSource?
    /// 会议室: the microphone Cicada listens to the room with; nil leaves the input on its default.
    var roomDevice: (() -> OutputDevice?)?
    /// The Mac reading a translation aloud, or the talk key held: the room mic hears silence then.
    private var roomMuted = false
    private var startedAt = Date()
    private var recognizer: RecognitionStream?
    private var resultsTask: Task<Void, Never>?
    /// The record's recognizer for the current transcriber (`Recognition.recordTrack`). Its lines
    /// keep settling after `stop()`, so it has a generation of its own.
    private var refiner: RecordRefiner?
    private var refinerGen = 0
    private var recordTask: Task<Void, Never>?
    /// The room engine's clocks and segment ids start far above the main one's, so lines from the two
    /// never look like one recognizer's (joins, translations).
    private var generation: Int
    private var lastForeignCheck = Date.distantPast
    /// When the recognizer last wrote anything: speech, even where the loudness gate heard none.
    private var lastWordsAt = Date.distantPast
    /// Sentences finished before detection settled the language: recorded once it confirms the
    /// language they were heard in, dropped on a switch (the replay into the new model redoes them).
    private var unconfirmed: [(seg: Segment, at: Date, duration: Double)] = []
    private var recordable: Bool {
        sourceMode != .auto || detection.settledEnough
            || legacySingleLanguage || cloudListening
            // The room side's 听不出 never reaches the panel (it reads the main engine): held lines would
            // stay held all meeting. Measured: a show from a phone across the table scored 0.56–0.71 for
            // Chinese, never confirmed, and not one room line was written in 40 s.
            || role == .room
    }
    /// macOS 14/15 with one Dictation language: nothing to compare it with and none Cicada could
    /// fetch, and every check takes the recognizer from the meeting. It is taken as heard.
    private var legacySingleLanguage: Bool { Recognition.legacy && candidates.count < 2 }
    /// The only model there is checked the audio and it isn't its language (`LanguageDetection.Verdict.notThis`).
    var mismatch: Bool { detection.mismatch }
    /// The model for the language it starts with couldn't be had, and there is none to fall back
    /// on: nothing is listening, so the problem shows without waiting for 听不出.
    var blockedByModel: Bool { isRunning && modelProblem?.picked == true && recognizer == nil && modelProblem?.lang == activeLang }
    var hidesSource: Bool { mismatch && !recordable }
    /// Someone has spoken and the language isn't settled yet: what 此刻 says instead of 等有人开口.
    var identifyingLanguage: Bool {
        isRunning && sourceMode == .auto && !recordable && firstHeardAt != nil
    }
    /// How much audio a switch can replay: all of it since the start while the language is unknown.
    /// Three minutes (≈6 MB): a model download seen taking 106 s fits with room to spare.
    private static let holdUnknown = 180.0
    private func updateHold() {
        router.holdAudio(sourceMode == .auto && !languageConfirmed ? Self.holdUnknown : 10)
    }
    private var failureStreak = 0

    private var segments: [Segment] = []
    private var nextSegmentID: Int
    /// Segments joined onto the line before: a retry of theirs would translate half a sentence.
    private var joinedAway: Set<Int> = []
    private var volatileText = ""
    private var volatileTranslation = ""
    private var lastVolatileSent = ""
    private var volatileInFlight = false
    private var volatileEpoch = 0
    private var tickTimer: Timer?
    private var ticks = 0
    /// When the line in progress started and last grew, for cutting long ones at a pause.
    private var volatileStartedAt = Date()
    private var volatileStartClock = 0.0
    private var volatileChangedAt = Date()
    private var cutting = false
    private var lastCut = ""
    private var lastCutThrough = 0.0
    /// A cut was asked for: the next final line ends at Cicada's pause, not the speaker's.
    private var cutAsked = false
    /// The last draft that ended a sentence and its audio time (`HeardText.endsSentence`), and the
    /// head of one a cut was asked to end at: the final is checked against that, not the whole draft.
    private var volatileSentence: (head: String, end: Double)?
    private var sentenceCutHead: String?
    /// Where the line in progress could end short of a sentence (`HeardText.boundaries`, offsets in
    /// `shownDraft`), each with the audio time of the draft it first showed in.
    private var seenBoundaries: [(at: Int, kind: HeardText.Boundary, end: Double)] = []
    /// The cut asked for ends there: the final is split at it.
    private var pendingSplit: (near: Int, kind: HeardText.Boundary)?
    /// When the last cut was asked for: the next waits for its line (a moment at most), or it
    /// would take the place the first one is to be split at.
    private var cutAskedAt = Date.distantPast
    /// What a line ended at a sentence ran on into the next one: it starts the next line, and the
    /// draft shows it in front (`HeardText.splitAtSentenceEnd`).
    private var carry: (text: String, start: Double)?
    /// The line in progress as shown: what was carried over, then the draft.
    private var shownDraft: String {
        guard let carry else { return volatileText }
        return [carry.text, volatileText].filter { !$0.isEmpty }.joined(separator: joiner(for: activeLang?.code ?? ""))
    }
    /// Final transcript time and how long after the last word it came, per segment, until its translation lands.
    private var finalTiming: [Int: (at: Date, recognize: Double?)] = [:]

    init(settings: AppSettings, role: Role = .main) {
        self.settings = settings
        self.role = role
        generation = role == .room ? Self.roomIDs : 0
        nextSegmentID = role == .room ? Self.roomIDs : 0
        // A download that failed for want of a network resumes when there is one again.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.realOnline != up else { return }
                    self.realOnline = up
                    self.networkChanged()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "cicada.network"))
    }

    var resolvedTarget: String { settings.resolvedTarget(source: activeLang?.code) }

    func languageSummary() -> String {
        let target = targetName(resolvedTarget)
        if cloudListening, let service = cloudService {
            return "\(activeLang?.name ?? "…") → \(target) · \(service)"
        }
        switch sourceMode {
        case .fixed(let lang):
            return "\(lang.name) → \(target)"
        case .auto:
            guard let lang = activeLang else { return L("自动识别 → \(target)") }
            if detecting || !languageConfirmed { return L("\(lang.name)（识别中…）→ \(target)") }
            return "\(lang.name) → \(target)"
        }
    }

    private func setStatus(_ text: String) {
        statusText = text
        onStatus?(text)
        onStateChange?()
    }

    // MARK: Models

    /// The room side never lists the models itself: without the main engine's list it starts in
    /// the last online meeting's language instead of yours.
    func shareModels(from main: ListenEngine) {
        installedLocales = main.installedLocales
        candidates = main.candidates
    }

    func refreshInstalledLocales() async {
        installedLocales = await Recognition.installedLocales()
        if let simulatedModels { installedLocales.formIntersection(simulatedModels) }
        candidates = sourceLanguages.filter { installedLocales.contains($0.locale) }
        debugLog("installed speech models: \(installedLocales.sorted()) candidates=\(candidates.map(\.locale))")
        if cloudListening { cloudModelArrived() }
        onStateChange?()
        // Also when not listening: at launch the Mac's language and English come in quietly, so
        // the first meeting already has two models to compare.
        fetchSecondModel()
    }

    /// Detection needs two models: a Mac with fewer fetches the likeliest missing ones in the
    /// background, one at a time (each one's end refreshes the list and asks for the next).
    private func fetchSecondModel(besides starting: Lang? = nil) {
        // The service hears every language (`cloudOnly`): a "download" would only restart it.
        guard !Recognition.cloudOnly, sourceMode == .auto, fetchingModel == nil, candidates.count < 2 else { return }
        let last = UserDefaults.standard.string(forKey: "lastDetected")
        // The model being started is fetched by `ensureModel` already. At a start that is `starting`:
        // `activeLang` is still the last run's then, and may be a model since taken away.
        let busy = starting ?? (isRunning ? activeLang : nil)
        guard let lang = likelySourceLanguages(last: last, systemLanguages: systemLanguages).first(where: {
            !installedLocales.contains($0.locale) && !fetchFailed.contains($0.locale) && $0 != busy
        }) else { return }
        fetchingModel = (lang, Progress())
        downloads[lang.locale] = (lang, Date())
        Task { [weak self] in
            var ok = false
            do {
                if await Recognition.status(lang.locale) == .unsupported {
                    debugLog("model fetch: \(lang.locale) unsupported")
                } else {
                    try await Recognition.install(lang.locale) { progress in
                        self?.fetchingModel = (lang, progress)
                        self?.onStateChange?()
                        debugLog("model fetch: downloading \(lang.locale)")
                    }
                    if let delay = self?.simulatedFetchDelay, delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                    if let fail = self?.simulatedModelFailure { throw ModelProblem.simulated(fail) }
                    ok = true
                }
            } catch {
                debugLog("model fetch \(lang.locale) failed: \(error)")
                if let self, await self.modelFailed(lang, error, picked: false) {
                    // A slot was given back: try again straight away.
                    self.fetchingModel = nil
                    self.downloads[lang.locale] = nil
                    self.fetchSecondModel()
                    return
                }
            }
            guard let self else { return }
            debugLog("model fetch: \(lang.locale) \(ok ? "ready" : "gave up")")
            self.fetchingModel = nil
            self.downloads[lang.locale] = nil
            // The new model gets its 20 s to settle the language before 听不出 is offered.
            if self.firstHeardAt != nil { self.firstHeardAt = Date() }
            self.detection.modelFetched(ok: ok)
            if ok {
                self.simulatedModels?.insert(lang.locale)
                if self.modelProblem?.lang == lang { self.modelProblem = nil }
            } else {
                self.fetchFailed.insert(lang.locale)
            }
            await self.refreshInstalledLocales()
            if ok { self.detectHeld() }
        }
    }

    // MARK: Start / stop

    func start() {
        guard !isRunning else { return }
        guard Recognition.isAvailable else {
            setStatus(L("此 Mac 不支持本机语音识别"))
            return
        }
        guard !Recognition.authorizationDenied else {
            setStatus(Recognition.notAllowed.localizedDescription)
            return
        }
        // An Intel Mac hears only through the service: without its key there is nothing to listen with.
        guard !Recognition.cloudOnly || cloudService != nil else {
            setStatus(L("请先在设置 › AI 服务里填入 Ling key"))
            return
        }
        detection.start()
        unconfirmed = []
        lastWordsAt = .distantPast
        firstHeardAt = nil
        askShown = false
        fetchFailed = []
        modelProblem = nil
        cloud = nil
        cloudBack = nil
        serverFellBack = false
        startedAt = Date()
        updateHold()
        debugLog("listen start mode=\(sourceMode) target=\(resolvedTarget)")

        // Debug (`silentListen:<locale>`): a meeting with no audio at all, its lines given by
        // `heard:` — to try what follows a finished sentence while another app is recording.
        if let locale = Self.silentLocale {
            activeLang = sourceLanguages.first { $0.locale == locale } ?? sourceLanguages[0]
            detection.setConfirmed(true)
            isRunning = true
            debugLog("listen start: silent (debug), no audio, \(activeLang!.code)")
            return
        }

        guard startTap() else { return }
        router.setVoiceCapture(settings.speakerVoices)
        isRunning = true
        startTickTimer()

        let initial: Lang
        switch sourceMode {
        case .fixed(let lang):
            initial = lang
        case .auto:
            let last = UserDefaults.standard.string(forKey: "lastDetected")
            // The people at the table most likely speak yours (同声传译's 我说), not the last online meeting's.
            let mine = role == .room || settings.listensToRoom
                ? candidates.first(where: { $0.locale == settings.speakFromLang.locale }) : nil
            initial = initialSourceLanguage(candidates: candidates, last: last,
                                            systemLanguages: systemLanguages, mine: mine)
        }
        // 会议室 the first time: nothing is heard until macOS's microphone question is answered.
        setStatus(audioTap == nil ? L("等你允许使用麦克风") : L("正在听"))
        Task { await switchTranscriber(to: initial) }
        fetchSecondModel(besides: initial)
    }

    /// The last run heard speech (a few seconds of it), read when its meeting ends.
    private(set) var heardSpeech = false

    func stop() {
        // Lines still waiting for the language are recorded rather than dropped: the meeting
        // ended before detection settled it. Not when the only model said the audio isn't its
        // language: those lines are noise, and the recording keeps what was said.
        flushCarry()
        if sourceMode == .auto, !recordable, !mismatch { flushUnconfirmed() }
        unconfirmed = []
        heardSpeech = isRunning && (router.stats().voicedTotal >= 3 || firstHeardAt != nil)
        isRunning = false
        generation += 1
        cloud = nil
        cloudBack = nil
        tickTimer?.invalidate()
        tickTimer = nil
        audioTap?.stop()
        audioTap = nil
        router.reset()
        resultsTask?.cancel()
        resultsTask = nil
        if let tee = recognizer as? TeeStream {
            // The record's recognizer hears out what it has, and its last lines settle.
            Task {
                await tee.live.cancel()
                await tee.record.finish()
            }
        } else if let recognizer {
            Task { await recognizer.cancel() }
        }
        recognizer = nil
        segments.removeAll()
        volatileText = ""
        volatileSentence = nil
        carry = nil
        seenBoundaries = []
        pendingSplit = nil
        volatileTranslation = ""
        lastVolatileSent = ""
        volatileInFlight = false
        detection.checkEnded()
        setStatus(L("已暂停"))
    }

    func reconnectAudio() {
        guard isRunning else { return }
        audioTap?.stop()
        audioTap = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                if self.startTap() { self.setStatus(L("正在听")) }
            }
        }
    }

    @discardableResult
    private func startTap() -> Bool {
        // Two restarts close together (the echo-cancelling unit made, then let go of) must not leave two sources.
        audioTap?.stop()
        audioTap = nil
        let room = role == .room || settings.listensToRoom
        router.setRoomGate(room)
        if room { return startRoomMic() }
        if SystemAudioPermission.status() == .denied {
            debugLog("audio tap: system audio recording was refused")
            isRunning = false
            setStatus(L("请在系统设置里允许“系统音频录制”，再重新打开知了"))
            return false
        }
        let tap = SystemAudioTap()
        let router = self.router
        tap.onAudio = { pcm in router.push(pcm) }
        tap.onRateChange = { [weak self] in MainActor.assumeIsolated { self?.reconnectAudio() } }
        do {
            try tap.start()
            audioTap = tap
            debugLog("audio tap started, permission \(SystemAudioPermission.status().map { "\($0)" } ?? "unreadable")")
            return true
        } catch {
            debugLog("audio tap start failed: \(error)")
            isRunning = false
            setStatus(L("无法读取系统音频，请在系统设置里允许“系统音频录制”"))
            return false
        }
    }

    /// 会议室. The first time, macOS asks for the microphone; listening starts once it is allowed.
    private func startRoomMic() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            debugLog("room mic: asking for the microphone")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.isRunning, self.role == .room || self.settings.listensToRoom, self.audioTap == nil else { return }
                        if granted { if self.startRoomMic() { self.setStatus(L("正在听")) } } else { self.roomMicDenied() }
                    }
                }
            }
            return true
        default:
            roomMicDenied()
            return false
        }
        // 电脑和会议室: the remote voices from the speakers are taken out of the mic (`VoiceMic`).
        if role == .room, echoCancelled, let voiceMic, let device = roomDevice?() {
            let mic = EchoCancelledRoomMic(mic: voiceMic, device: device, processing: !echoBypassed)
            if echoBypassed { mic.echoGate = echoGate }
            mic.muted = roomMuted
            let router = self.router
            mic.onAudio = { pcm in router.push(pcm) }
            mic.onFailed = { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.echoCancellationFailed(mic) }
                }
            }
            try? mic.start()
            audioTap = mic
            return true
        }
        // A unit left over from echo cancellation would starve the plain mic (one unit or none).
        if let voiceMic, !voiceMic.inUse { voiceMic.release() }
        let mic = RoomMic(device: roomDevice?())
        mic.muted = roomMuted
        if role == .room { mic.echoGate = echoGate }
        roomMicSilent = false
        mic.onSilent = { [weak self, weak mic] in
            MainActor.assumeIsolated {
                guard let self, let mic, self.audioTap === mic else { return }
                self.roomMicSilent = true
                self.onStateChange?()
            }
        }
        let router = self.router
        mic.onAudio = { pcm in router.push(pcm) }
        do {
            try mic.start()
            audioTap = mic
            debugLog("room mic started: \(mic.deviceName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.audioTap === mic else { return }
                    debugLog("room mic speech threshold \(String(format: "%.4f", self.router.gateThreshold()))")
                }
            }
            return true
        } catch {
            debugLog("room mic start failed: \(error)")
            isRunning = false
            setStatus(L("麦克风无法启动，请在系统设置里允许\(appDisplayName)使用麦克风"))
            return false
        }
    }

    /// 电脑和会议室: take the online voices out of the room mic with the echo-cancelling unit. Off,
    /// or when the unit can't be had, the plain mic is gated while the Mac plays speech (`gateEcho`).
    var echoCancelled = true
    /// With `echoCancelled`: the room through the unit with processing off (the plain mic's sound,
    /// gated as `RoomMic` is), so a talk-key press can turn it on (`VoiceMic.attach(processing:)`).
    var echoBypassed = false
    var voiceMic: VoiceMic?
    /// Whether the plain room mic is open: the echo-cancelling unit would starve it, so it lets the
    /// unit go each time it starts (`startRoomMic`).
    var holdsPlainMic: Bool { isRunning && audioTap is RoomMic }
    /// Whether the room is heard through the echo-cancelling unit right now.
    var hearsEchoCancelled: Bool { audioTap is EchoCancelledRoomMic }
    /// The microphone hearing the room right now, to notice it going away (nil: the default input).
    var roomMicUID: String? { (audioTap as? RoomMic)?.deviceUID ?? (audioTap as? EchoCancelledRoomMic)?.deviceUID }

    private func echoCancellationFailed(_ mic: EchoCancelledRoomMic) {
        guard isRunning, audioTap === mic else { return }
        mic.stop()
        audioTap = nil
        // Nobody else may hold the unit while the plain mic is used: it would starve it.
        if voiceMic?.inUse == false { voiceMic?.release() }
        echoCancelled = false
        if !startRoomMic() { debugLog("room mic: plain mic failed too") }
    }

    /// Closed by the main engine while the Mac plays speech: the plain room mic then hears silence,
    /// since what it hears is the speakers (unused through the echo-cancelling unit).
    let echoGate = EchoGate()

    private func roomMicDenied() {
        debugLog("room mic: microphone not allowed")
        if isRunning { stop() }
        setStatus(L("麦克风无法启动，请在系统设置里允许\(appDisplayName)使用麦克风"))
    }

    /// While the Mac speaks into the room (or you hold the talk key) the room mic hears silence.
    func setRoomMuted(_ on: Bool) {
        guard on != roomMuted else { return }
        roomMuted = on
        (audioTap as? RoomMic)?.muted = on
        (audioTap as? EchoCancelledRoomMic)?.muted = on
        if role == .room || settings.listensToRoom { debugLog("room mic \(on ? "muted" : "open")") }
    }

    /// 听哪里 changed: while listening, the new source takes over in the same meeting.
    func listenSourceChanged() {
        debugLog("listen source=\(settings.listenSource)")
        reconnectAudio()
        onStateChange?()
    }

    // MARK: Settings changes

    func sourceModeChanged() {
        detection.modeChanged()
        updateHold()
        if isRunning, case .fixed(let lang) = sourceMode {
            // Chosen by hand: what was held back in that language is now confirmed.
            if lang == activeLang { flushUnconfirmed() }
            Task { await switchTranscriber(to: lang) }
        }
        fetchSecondModel()
        onStateChange?()
    }

    func targetChanged() {
        retranslateVisible()
        onStateChange?()
    }

    func redetect() {
        guard isRunning, sourceMode == .auto else { return }
        detection.redetect()
        updateHold()
        onStateChange?()
    }

    // MARK: Transcriber

    private func ensureModel(for lang: Lang) async throws {
        // Already coming in the background (fetched at launch): wait for it rather than ask twice.
        while fetchingModel?.lang == lang {
            setStatus(L("正在下载 \(lang.name) 语音模型…"))
            try await Task.sleep(for: .milliseconds(300))
        }
        let status = await Recognition.status(lang.locale)
        if status == .installed {
            if simulatedModels?.insert(lang.locale).inserted == true { await refreshInstalledLocales() }
            return
        }
        debugLog("model status for \(lang.locale): \(status)")
        guard status != .unsupported else { throw Recognition.unsupported(lang.locale) }
        if let fail = simulatedModelFailure { throw ModelProblem.simulated(fail) }
        if downloads[lang.locale] == nil { downloads[lang.locale] = (lang, Date()) }
        defer { if fetchingModel?.lang != lang { downloads[lang.locale] = nil } }
        try await Recognition.install(lang.locale) { _ in self.setStatus(L("正在下载 \(lang.name) 语音模型…")) }
        simulatedModels?.insert(lang.locale)
        await refreshInstalledLocales()
    }

    private func switchTranscriber(to lang: Lang, replaySeconds: Double = 0) async {
        // No models to switch between: the service hears every language, and a language picked in
        // settings only becomes its hint (`cloudHint`).
        if Recognition.cloudOnly || serverHears {
            guard isRunning else { return }
            if case .fixed = sourceMode { activeLang = lang } else if activeLang == nil { activeLang = lang }
            if !cloudListening { startCloud() }
            return
        }
        if cloudListening { debugLog("cloud: off, \(lang.locale) on this Mac") }
        cloud = nil
        generation += 1
        let gen = generation
        router.detach()
        resultsTask?.cancel()
        resultsTask = nil
        if let old = recognizer {
            recognizer = nil
            await old.cancel()
        }
        guard isRunning, gen == generation else { return }

        let previous = activeLang
        if activeLang != lang {
            segments.removeAll()
            unconfirmed = []
            detection.clearMismatch()
        }
        activeLang = lang
        volatileText = ""
        carry = nil
        seenBoundaries = []
        pendingSplit = nil
        volatileTranslation = ""
        lastVolatileSent = ""
        volatileEpoch += 1
        cutAsked = false
        volatileSentence = nil
        sentenceCutHead = nil
        // The new transcriber's audio clock starts again at zero.
        lastCutThrough = 0
        onStateChange?()

        do {
            do {
                try await ensureModel(for: lang)
            } catch where sourceMode == .auto && previous != nil && previous != lang {
                // A model that can't be had (no network, or the Mac's five reserved languages taken):
                // retrying would fail the same way every 30 s. Go back to the one that works, unsure again.
                debugLog("model for \(lang.locale) unavailable, back to \(previous!.locale): \(error)")
                if await modelFailed(lang, error, picked: true) {
                    guard isRunning, gen == generation else { return }
                    Task { await switchTranscriber(to: lang, replaySeconds: replaySeconds) }
                    return
                }
                fetchFailed.insert(lang.locale)
                detection.unconfirm()
                // macOS 14/15: a language is added in Dictation settings, which only the user can do.
                setStatus(Recognition.needsUser(error) ? error.localizedDescription : L("没能下载 \(lang.name) 语音模型"))
                guard isRunning, gen == generation else { return }
                Task { await switchTranscriber(to: previous!) }
                return
            } catch {
                // Nothing to fall back on (a language chosen in settings, or the first model on this
                // Mac): say why instead of retrying every 30 s; the network back or 再试一次 resumes.
                debugLog("model for \(lang.locale) unavailable, nothing to fall back on: \(error)")
                if await modelFailed(lang, error, picked: true) {
                    guard isRunning, gen == generation else { return }
                    Task { await switchTranscriber(to: lang, replaySeconds: replaySeconds) }
                    return
                }
                setStatus(Recognition.needsUser(error) ? error.localizedDescription : L("没能下载 \(lang.name) 语音模型"))
                return
            }
            guard isRunning, gen == generation else { return }
            let stream = try await Recognition.start(lang.locale, drafts: true, confidence: true)
            guard isRunning, gen == generation else {
                await stream.cancel()
                return
            }
            var listening: RecognitionStream = stream
            if let record = try? await Recognition.startRecord(lang.locale, format: stream.format) {
                guard isRunning, gen == generation else {
                    await stream.cancel()
                    await record.cancel()
                    return
                }
                listening = TeeStream(live: stream, record: record)
                startRefining(record)
            } else {
                refiner = nil
            }
            router.attach(listening, replaySeconds: replaySeconds)
            updateHold()
            self.recognizer = listening
            resultsTask = Task { [weak self] in
                do {
                    for try await piece in stream.results {
                        self?.handle(piece, generation: gen)
                    }
                } catch {
                    self?.recognitionFailed(error, generation: gen)
                }
            }
            debugLog("transcriber started recognizer=\(Recognition.name) locale=\(lang.locale) format=\(stream.format)")
            setStatus(L("正在听"))
        } catch {
            debugLog("transcriber start failed locale=\(lang.locale): \(error)")
            recognitionFailed(error, generation: gen)
        }
    }

    private func recognitionFailed(_ error: Error, generation gen: Int) {
        guard gen == generation, isRunning else { return }
        debugLog("recognition error: \(error)")
        failureStreak += 1
        var delay = min(30.0, 2.0 * pow(2.0, Double(failureStreak - 1)))
        if Recognition.needsUser(error) {
            // Fixed in System Settings, not by waiting: say what to do, and try again soon after.
            delay = 3
            setStatus(error.localizedDescription)
        } else {
            setStatus(L("识别出错，\(Int(delay)) 秒后重试"))
        }
        guard let lang = activeLang else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, gen == self.generation else { return }
                Task { await self.switchTranscriber(to: lang) }
            }
        }
    }

    private func handle(_ result: Recognition.Piece, generation gen: Int) {
        guard gen == generation, isRunning else { return }
        failureStreak = 0
        var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Before any holding for the language: words at all is what tells speech from music.
        if !text.isEmpty { lastWordsAt = Date(); onWords?() }
        if result.isFinal {
            text = HeardText.clean(text)
            let fuller = HeardText.fuller(final: text, draft: sentenceCutHead ?? volatileText)
            let splitAt = pendingSplit
            pendingSplit = nil
            sentenceCutHead = nil
            volatileSentence = nil
            seenBoundaries = []
            if fuller != text {
                debugLog("final dropped words the draft had: kept the draft")
                contentLog("FINAL was: \(text)")
                text = fuller
            }
            var start = result.start, end = result.end
            if let c = carry {
                carry = nil
                text = HeardText.clean(c.text + joiner(for: activeLang?.code ?? "") + text)
                start = c.start
            }
            let code = activeLang?.code ?? ""
            if let at = splitAt, let split = at.kind == .sentence ? HeardText.splitAtSentenceEnd(text)
                : HeardText.split(text, near: at.near, kind: at.kind, language: code) {
                // Times shared out by length: the tail is a second or so of the next sentence.
                let at = start + (end - start) * Double(split.head.count) / Double(max(1, text.count))
                carry = (split.tail, at)
                (text, end) = (split.head, at)
            }
            volatileText = ""
            volatileEpoch += 1
            // A "." or "…" from a breath or a click is no sentence: Ling would answer it with a note that
            // there was nothing to translate, and it would sit in the record as a line.
            guard text.contains(where: \.isLetter) else { renderSubtitles(); return }
            if cloudListening, let code = result.language { cloudHeard(code) }
            let conf = result.confidence ?? 1
            // Heard by the service: its translation came with the line. Not when it was asked for the
            // language the line turned out to be in (the target follows it): that one is translated again.
            let given = translationOff() || result.translation == text && result.language != resolvedTarget ? nil : result.translation
            let provisional = given ?? (volatileTranslation.isEmpty ? nil : volatileTranslation)
            var seg = Segment(id: nextSegmentID, text: text, sourceCode: result.language ?? activeLang?.code ?? "auto",
                              translation: provisional)
            seg.start = start
            seg.end = end
            seg.clock = gen
            seg.cut = cutAsked
            seg.split = splitAt != nil
            cutAsked = false
            seg.refining = refiner != nil
            if refiner != nil { settled(refiner!.emitted(id: seg.id, start: seg.start, end: seg.end, text: seg.text)) }
            if settings.speakerVoices {
                seg.voiceSamples = router.voiceSamples(from: start, to: end)
            }
            nextSegmentID += 1
            // How long ago, in real time, the sentence's last word was spoken.
            let ago = router.fedSeconds() - end
            finalTiming[seg.id] = (Date(), ago.isFinite && ago >= 0 && ago < 30 ? ago : nil)
            if finalTiming.count > 40, let oldest = finalTiming.keys.min() { finalTiming[oldest] = nil }
            var shown = seg
            shown.voiceSamples = nil // the audio only travels to the meeting record
            segments.append(shown)
            // Only the last few are shown; in notes mode nothing clears them after a pause.
            if segments.count > 30 { segments.removeFirst(segments.count - 30) }
            if segments.count > 8 { segments.removeFirst(segments.count - 8) }
            volatileTranslation = ""
            lastVolatileSent = ""
            contentLog(String(format: "FINAL conf=%.2f [%@] %@", conf, activeLang?.locale ?? "?", text))
            let duration = max(0, end - start)
            // Only confirmed-language sentences go into the meeting record; earlier ones wait.
            let spoken = duration.isFinite ? duration : 0
            if recordable {
                // A replayed line was spoken longer ago than it lasted: the audio clock knows when.
                let since = router.fedSeconds() - seg.start
                onFinal?(seg, since.isFinite && since > spoken + 5 ? since : spoken)
            } else {
                unconfirmed.append((seg, Date(), spoken))
                // Held lines keep their audio only while recent: an undecided language must not pile up minutes of it.
                if unconfirmed.count > 20 { unconfirmed[unconfirmed.count - 21].seg.voiceSamples = nil }
            }
            if let given {
                finalTiming[seg.id] = nil
                contentLog("HEARD [\(seg.sourceCode)→\(resolvedTarget)] \(text) => \(given)")
                onTranslated?(seg.id, given)
            } else {
                translateSegment(id: seg.id)
            }
            if sourceMode == .auto, conf < 0.6, text.count >= 4, !cloudListening {
                detection.due = true
            }
            checkForeignLetters(text)
        } else {
            if firstHeardAt == nil, text.contains(where: \.isLetter) { firstHeardAt = Date() }
            if volatileText.isEmpty { volatileStartedAt = Date(); volatileStartClock = router.fedSeconds() }
            if text != volatileText { volatileChangedAt = Date() }
            // A sentence just ended: remember where, until words past it come to end the line there.
            if HeardText.endsSentence(text) { volatileSentence = (text, result.end) }
            volatileText = text
            noteBoundaries(at: result.end)
            checkForeignLetters(text)
        }
        renderSubtitles()
    }

    /// 改正听错的词: a finished line as shown once its fixes are in. Kept apart from the segment's own
    /// text, which deciding a join and the record's settling compare with what was heard.
    private var fixedText: [Int: String] = [:]

    /// The app fixed segment `id`'s words: the bar shows them if the line is still on it.
    func showFixed(_ id: Int, text: String) {
        guard let seg = segments.first(where: { $0.id == id }) else { return }
        fixedText[id] = text == seg.text ? nil : text
        if fixedText.count > 50, let oldest = fixedText.keys.min() { fixedText[oldest] = nil }
        if segments.last?.id == id { renderSubtitles() }
    }

    private func renderSubtitles() {
        let draft = shownDraft
        guard !(segments.isEmpty && draft.isEmpty) else { return }
        let srcJoin = joiner(for: activeLang?.code ?? "en")
        let last = segments.last.map { fixedText[$0.id] ?? $0.text } ?? ""
        let source = [last, draft].filter { !$0.isEmpty }
            .joined(separator: srcJoin.isEmpty ? " " : srcJoin)
        if sourceMode == .auto, !recordable {
            onSubtitle?(source, asksLanguage ? L("听不出是哪种语言，到菜单栏里选一下") : L("正在识别语言…"))
            return
        }
        let tgtJoin = joiner(for: resolvedTarget)
        var parts = segments.suffix(3).compactMap(\.translation)
        if !volatileTranslation.isEmpty { parts.append(volatileTranslation) }
        onSubtitle?(source, parts.joined(separator: tgtJoin.isEmpty ? "" : " "))
    }

    // MARK: Language detection

    /// A Chinese, Japanese or Korean model hearing English writes it out in Latin letters
    /// ("OKo where wen the lanch", "reigifridadeinali") with a confidence that looks fine; without
    /// this the switch waits for the next periodic check, 20 s of speech later. Only a line that
    /// ends in a run of Latin letters counts: English words mixed into Chinese ("还在做 onboarding
    /// 的 UI") would ask for checks that each risk a wrong switch.
    private func checkForeignLetters(_ text: String) {
        guard sourceMode == .auto, !detection.due, !cloudListening, let code = activeLang?.code,
              ["zh", "ja", "ko"].contains(where: { code.hasPrefix($0) }),
              Date().timeIntervalSince(lastForeignCheck) >= 8, HeardText.endsInLatin(text) else { return }
        lastForeignCheck = Date()
        debugLog("detect: Latin letters from the \(code) model, checking the language")
        detection.due = true
    }

    private func maybeDetectLanguage() {
        // One model can still tell whether the audio is its language, until the language is known.
        guard isRunning, sourceMode == .auto, !detecting, !legacySingleLanguage, !cloudListening,
              candidates.count >= 2 || (!languageConfirmed && candidates.first == activeLang && activeLang != nil) else { return }
        var stats = router.stats(window: 6)
        // Speech under the gate's line (a quiet remote voice, an app turned low: measured at RMS 0.008
        // against 0.01) is still written down, but never voiced 2.5 s, so nothing was checked and
        // 听不出 came at 20 s. The words say someone is talking: check what was just played.
        if stats.recentVoiced < 2.5, Date().timeIntervalSince(lastWordsAt) < 2 {
            if Date().timeIntervalSince(detection.lastCheckAt) >= 20 { detection.due = true }
            guard detection.due, let firstHeardAt, Date().timeIntervalSince(firstHeardAt) >= 4,
                  Date().timeIntervalSince(detection.lastCheckAt) >= 4 else { return }
            debugLog("detect: words under the loudness gate, checking the last 6 s")
            runDetection(router.snapshot(seconds: 6))
            return
        }
        if stats.silenceRun >= AudioRouter.gapSeconds { detection.due = true }
        if stats.voicedTotal >= detection.nextPeriodic { detection.due = true }
        guard detection.due, Date().timeIntervalSince(detection.lastCheckAt) >= 3 else { return }
        let clipSeconds = min(6, stats.sinceGap)
        guard clipSeconds >= 3 else { return }
        stats = router.stats(window: clipSeconds)
        guard stats.recentVoiced >= 2.5 else { return }

        detection.nextPeriodic = stats.voicedTotal + 20
        runDetection(router.snapshot(seconds: clipSeconds))
    }

    /// A model that just arrived checks the speech held back, without waiting for someone to talk again.
    private func detectHeld() {
        guard isRunning, sourceMode == .auto, !languageConfirmed, !detecting, candidates.count >= 2, !cloudListening else { return }
        let held = router.voicedSnapshot(seconds: 6)
        guard held.seconds >= 2.5 else { return }
        debugLog(String(format: "detect: new model, checking %.1f s of held speech", held.seconds))
        runDetection(held.buffers)
    }

    private func runDetection(_ clip: [AVAudioPCMBuffer]) {
        detection.checkStarted()
        onStateChange?()
        let candidates = self.candidates
        Task { [weak self] in
            let started = Date()
            let ranked = await LanguageDetector.rank(clip, candidates: candidates)
            guard let self else { return }
            self.detection.checkEnded()
            guard self.isRunning, self.sourceMode == .auto else { return }
            let summary = ranked.map { String(format: "%@ s=%.2f c=%.2f n=%d", $0.lang.locale, $0.score, $0.confidence, $0.chars) }
            debugLog("detect (\(String(format: "%.2f", Date().timeIntervalSince(started)))s): \(summary.joined(separator: " | "))")
            self.applyDetection(ranked)
            self.onStateChange?()
        }
    }

    private func applyDetection(_ ranked: [LanguageDetector.Candidate]) {
        switch detection.apply(ranked, active: activeLang) {
        case .none, .pending:
            return
        case .notThis(let lang, let firstTime):
            if firstTime { debugLog("detect: not \(lang.locale), holding lines for another model") }
            // Checked on speech: someone is talking even if the model wrote nothing down.
            if firstHeardAt == nil { firstHeardAt = Date() }
            renderSubtitles()
        case .noneOfThem(let now):
            if now {
                debugLog("detect: none of \(ranked.map(\.lang.locale).joined(separator: ",")), holding lines")
                if firstHeardAt == nil { firstHeardAt = Date() }
            }
            renderSubtitles()
        case .ambiguous:
            debugLog("detect: ambiguous, keeping \(activeLang?.locale ?? "-")")
            if recordable { flushUnconfirmed() }
            renderSubtitles()
        case .confirmed(let lang):
            updateHold()
            flushUnconfirmed()
            if role == .main { UserDefaults.standard.set(lang.locale, forKey: "lastDetected") }
            renderSubtitles()
        case .switchTo(let lang, let replayAll):
            debugLog("detect: switching \(activeLang?.locale ?? "-") → \(lang.locale)")
            unconfirmed = []
            if role == .main { UserDefaults.standard.set(lang.locale, forKey: "lastDetected") }
            Task { await switchTranscriber(to: lang, replaySeconds: replayAll ? Self.holdUnknown : 8) }
        }
    }

    /// Why a model couldn't be had. At the five-model limit a model Cicada isn't using is given
    /// back first: true means one was, and the caller tries again; otherwise the problem is kept
    /// for 听不出 to show.
    private func modelFailed(_ lang: Lang, _ error: Error, picked: Bool) async -> Bool {
        let cause = ModelProblem.cause(of: error, online: online, freeBytes: ModelProblem.freeBytes())
        debugLog("model problem \(lang.locale): \(cause)")
        if cause == .limit, simulatedModelFailure == nil, await freeModelSlot(for: lang) { return true }
        modelProblem = ModelProblem(lang: lang, cause: cause, picked: picked)
        onStateChange?()
        return false
    }

    /// Gives back a reserved model that isn't in use and isn't a likely language, oldest guess first.
    private func freeModelSlot(for wanted: Lang) async -> Bool {
        let keep = Set(likelySourceLanguages(last: UserDefaults.standard.string(forKey: "lastDetected"),
                                             systemLanguages: systemLanguages).map(\.locale)
                       + [wanted.locale, activeLang?.locale].compactMap { $0 })
        for locale in await Recognition.reservedLocales() where !keep.contains(locale) {
            if await Recognition.release(locale) {
                debugLog("model limit: gave back \(locale) for \(wanted.locale)")
                await refreshInstalledLocales()
                return true
            }
        }
        return false
    }

    /// 再试一次, or the network back for a download that needed it.
    func retryModel() {
        guard let p = modelProblem else { return }
        debugLog("model retry: \(p.lang.locale)")
        modelProblem = nil
        fetchFailed.remove(p.lang.locale)
        if p.picked, isRunning, p.lang == activeLang, recognizer == nil {
            // Nothing is listening: start the language again, with all the speech held since the start.
            Task { await switchTranscriber(to: p.lang, replaySeconds: languageConfirmed ? 0 : Self.holdUnknown) }
        } else if p.picked, isRunning {
            detection.unconfirm()
            pickLanguage(p.lang)
        } else {
            fetchSecondModel()
        }
        onStateChange?()
    }

    /// macOS 14/15: the language added in Dictation settings carries on by itself, as the network does.
    private func checkDictation() {
        guard isRunning, let p = modelProblem, case .dictation = p.cause, Recognition.dictationEnabled else { return }
        Task {
            guard await Recognition.status(p.lang.locale) == .installed, self.modelProblem == p else { return }
            self.retryModel()
        }
    }

    private func networkChanged() {
        debugLog("network \(online ? "up" : "down")")
        if online, modelProblem?.cause == .offline { retryModel() }
    }

    /// 听不出: the language is still unknown 20 s after the first words, with nothing under way that
    /// could settle it (no check running, no model coming). Too quiet for a check, two models that
    /// keep disagreeing, a model that couldn't be fetched: one click ends each.
    var asksLanguage: Bool {
        guard isRunning, sourceMode == .auto, !languageConfirmed, fetchingModel == nil, !cloudListening,
              !legacySingleLanguage, let firstHeardAt else { return false }
        // Once offered it stays until answered: a check running meanwhile doesn't make it blink.
        if askShown { return true }
        // The one model said no and no other is coming: nothing is shown or kept, so ask now.
        if mismatch { return true }
        return !detecting && Date().timeIntervalSince(firstHeardAt) >= 20
    }

    /// What 听不出 offers first; the rest sit under 更多.
    var askChoices: [Lang] {
        // None of the installed ones: offer what isn't installed; they are a 其实是 aside.
        if mismatch {
            let others = (likelySourceLanguages(last: nil, systemLanguages: systemLanguages) + sourceLanguages)
                .filter { !candidates.contains($0) && !fetchFailed.contains($0.locale) }
            var out: [Lang] = []
            for lang in others where !out.contains(lang) { out.append(lang) }
            if !out.isEmpty { return Array(out.prefix(3)) }
        }
        var out = likelySourceLanguages(last: activeLang?.locale, systemLanguages: systemLanguages)
        for lang in candidates + sourceLanguages where !out.contains(lang) { out.append(lang) }
        return Array(out.filter { !fetchFailed.contains($0.locale) }.prefix(3))
    }

    /// The language picked from 听不出: confirmed for this run (settings stay on auto). A model
    /// not on the Mac yet is downloaded as when it is detected.
    func pickLanguage(_ lang: Lang) {
        guard isRunning, sourceMode == .auto else { return }
        debugLog("language picked: \(lang.locale) (was \(activeLang?.locale ?? "-"))")
        let replay = languageConfirmed ? 8 : Self.holdUnknown
        detection.picked()
        askShown = false
        modelProblem = nil
        if role == .main { UserDefaults.standard.set(lang.locale, forKey: "lastDetected") }
        if lang == activeLang, recognizer != nil {
            updateHold()
            flushUnconfirmed()
            renderSubtitles()
            onStateChange?()
        } else {
            // The hold shrinks once the new model is attached, after it took the replay.
            unconfirmed = []
            Task { await switchTranscriber(to: lang, replaySeconds: replay) }
        }
    }

    /// Records the sentences held back before the language was confirmed, with the translation
    /// they got meanwhile and their time of speaking.
    private func flushUnconfirmed() {
        let held = unconfirmed
        unconfirmed = []
        for h in held {
            var seg = h.seg
            if let now = segments.first(where: { $0.id == seg.id }) { seg.translation = now.translation }
            onFinal?(seg, h.duration + Date().timeIntervalSince(h.at))
        }
    }

    // MARK: Listening through the service

    /// 先用○○听: the service hears the meeting until the model being downloaded is on the Mac.
    func startCloud() {
        guard isRunning, !cloudListening, cloudService != nil, let translator else { return }
        let awaiting = downloading?.lang ?? modelProblem?.lang
        debugLog("cloud: on (\(cloudService ?? "?")), replacing \(recognizer == nil ? "nothing" : activeLang?.locale ?? "?"), awaiting \(awaiting?.locale ?? "none")")
        // Held lines were a model's guesses at a language it may not know: the held audio goes to the service instead.
        let replay = languageConfirmed && recognizer != nil ? 0 : 30.0
        let replaced = (lang: activeLang, confirmed: languageConfirmed)
        // The analyzer's format keeps the audio held for it replayable.
        let format = recognizer?.format
        generation += 1
        let gen = generation
        router.detach()
        resultsTask?.cancel()
        resultsTask = nil
        if let old = recognizer {
            recognizer = nil
            Task { await old.cancel() }
        }
        cloud = CloudSession(replaced: replaced, awaiting: awaiting, via: (translator.ling.provider.id, serverHears))
        unconfirmed = []
        segments.removeAll()
        volatileText = ""
        volatileSentence = nil
        carry = nil
        seenBoundaries = []
        pendingSplit = nil
        volatileTranslation = ""
        lastVolatileSent = ""
        detection.clearMismatch()
        modelProblem = nil
        let stream = CloudStream(format: format) { [weak self] wav, seconds in
            guard let self, gen == self.generation else { return nil }
            do {
                let heard: CloudHeard?
                do {
                    heard = try await translator.hear(wav: wav, seconds: seconds, target: self.resolvedTarget, hint: self.cloudHint)
                } catch LingClient.Failure.rateLimited where translator.ling.transcribes {
                    // A chat to the audio model retries 429s itself (LingClient.retryWaits); a
                    // custom speech server's transcription doesn't: one more try.
                    try await Task.sleep(for: .seconds(1))
                    heard = try await translator.hear(wav: wav, seconds: seconds, target: self.resolvedTarget, hint: self.cloudHint)
                }
                if (self.cloud?.failures ?? 0) >= 3 { self.setStatus(L("\(self.cloudService ?? "AI") 在听")) }
                self.cloud?.failures = 0
                return heard
            } catch {
                guard gen == self.generation, self.cloud != nil, !(error is CancellationError) else { return nil }
                debugLog("cloud: hear failed: \(error)")
                self.cloud?.failures += 1
                // The service is down or the key stopped working: listening shouldn't go quiet with it.
                if (self.cloud?.failures ?? 0) >= 3 {
                    if self.serverHears, !Recognition.cloudOnly {
                        // The user's own service is down: this Mac recognizes the rest of the meeting.
                        debugLog("cloud: own service failed 3 times, back to this Mac for this meeting")
                        self.serverFellBack = true
                        if self.cloud?.replaced.lang == nil { self.cloud?.replaced = (self.activeLang, false) }
                        self.stopCloud()
                        self.setStatus(L("\(self.cloudService ?? "AI") 连不上 · 字幕改用本机识别"))
                    } else if !Recognition.cloudOnly { self.stopCloud() }
                    // Nothing to go back to on an Intel Mac: say why it's quiet, and keep trying.
                    else { self.setStatus(CloudHearing.trouble(error, service: self.cloudService ?? "AI")) }
                }
                return nil
            }
        }
        router.attach(stream, replaySeconds: replay)
        recognizer = stream
        resultsTask = Task { [weak self] in
            do {
                for try await piece in stream.results { self?.handle(piece, generation: gen) }
            } catch {
                debugLog("cloud: stream ended: \(error)")
            }
        }
        setStatus(L("\(cloudService ?? "AI") 在听"))
    }

    /// 换回等待 (or the service failing): back to what listened before, the download carrying on.
    func stopCloud() {
        guard let back = cloud?.replaced, !Recognition.cloudOnly else { return }
        let lang = back.lang ?? activeLang
        debugLog("cloud: off, back to \(lang?.locale ?? "nothing")")
        cloud = nil
        generation += 1
        detection.setConfirmed(back.confirmed)
        updateHold()
        onStateChange?()
        guard let lang else { return }
        Task { await switchTranscriber(to: lang) }
    }

    /// AI settings changed while a service hears the meeting. The audio stays only with the service
    /// it went to: another service (Ling chosen instead of a custom one), or 语音识别 set back to
    /// 本机, takes the meeting back to this Mac rather than sending its audio to a service nobody chose.
    func aiServiceChanged() {
        guard let via = cloud?.via else { return }
        let provider = translator?.ling.provider.id
        guard provider != via.provider || (via.server && !Recognition.serverPreferred) else { return }
        debugLog("cloud: the AI service changed (\(via.provider?.rawValue ?? "?") → \(provider?.rawValue ?? "?")), back to this Mac")
        stopCloud()
    }


    /// The language the meeting has been in, which keeps Ming from flipping on a short stretch.
    private var cloudHint: String? {
        if case .fixed(let lang) = sourceMode { return lang.code }
        guard let cloud else { return nil }
        return cloud.lang?.code ?? (cloud.replaced.confirmed ? cloud.replaced.lang?.code : nil)
    }

    /// The service said which language a line was in: it answers what detection would have.
    private func cloudHeard(_ code: String) {
        guard let lang = sourceLanguages.first(where: { $0.code == code })
                ?? sourceLanguages.first(where: { code.hasPrefix("zh") && $0.code.hasPrefix("zh") }) else { return }
        guard cloud != nil else { return }
        if cloud?.lang != lang { debugLog("cloud: heard \(lang.locale)") }
        cloud?.lang = lang
        if sourceMode == .auto, activeLang != lang {
            activeLang = lang
            if role == .main { UserDefaults.standard.set(lang.locale, forKey: "lastDetected") }
        }
    }

    /// A model came in while the service listened: the awaited one goes back to listening on the Mac.
    private func cloudModelArrived() {
        // The user chose their service: a model arriving is only the fallback getting ready.
        guard !serverHears else { return }
        guard let awaiting = cloud?.awaiting, installedLocales.contains(awaiting.locale) else { return }
        let want: Lang
        if case .fixed(let lang) = sourceMode {
            want = lang
        } else if let heard = cloud?.lang, installedLocales.contains(heard.locale) {
            want = heard
        } else {
            want = awaiting
        }
        guard installedLocales.contains(want.locale) else { return }
        debugLog("cloud: \(awaiting.locale) is on the Mac, back to \(want.locale) here")
        cloudBack = (cloudService ?? "AI", Date())
        // What the service heard settles the language; without a line from it, detection still decides.
        let confirmed = cloud?.lang == want
        cloud = nil
        generation += 1
        detection.setConfirmed(confirmed)
        updateHold()
        Task { await switchTranscriber(to: want) }
    }

    // MARK: Translation

    private func startTickTimer() {
        tickTimer?.invalidate()
        // Pauses are short: look for one four times a second; the rest runs once a second.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.maybeCutSentence()
                self.ticks += 1
                guard self.ticks % 4 == 0 else { return }
                self.translateVolatile()
                self.maybeDetectLanguage()
                if self.ticks % 20 == 0 { self.checkDictation() }
                // The fetch's progress, and 听不出 coming or going, redraw the windows.
                if let back = self.cloudBack, Date().timeIntervalSince(back.at) > 6 { self.cloudBack = nil }
                let ask = self.asksLanguage
                // The download's time, the offer and the service listening redraw every second too.
                if ask != self.askShown || !self.downloads.isEmpty || self.cloudListening || self.cloudBack != nil {
                    if ask != self.askShown { debugLog("language ask \(ask ? "shown" : "hidden")") }
                    let flipped = ask != self.askShown
                    self.askShown = ask
                    self.onStateChange?()
                    if flipped { self.renderSubtitles() }
                }
            }
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Set by the app: the shared translation chain.
    var translator: TranslationService?
    /// Subtitles set to the original only: nothing is translated.
    var translationOff: () -> Bool = { false }

    func translate(_ text: String, source: String, target: String? = nil,
                   kind: TranslationService.Kind = .sentence, trace: TranslateTrace? = nil) async -> String? {
        let target = target ?? resolvedTarget
        if source == target { return text }
        let out = await translator?.translate(text, source: source, target: target, kind: kind, trace: trace)
        // A partial without a translation is fine while the AI service will translate the sentence.
        let coming = kind == .draft && translator?.ling.usable == true
        if out == nil, !coming, segments.allSatisfy({ $0.translation == nil }) && volatileTranslation.isEmpty {
            onSubtitle?(shownDraft.isEmpty ? (segments.last?.text ?? "") : shownDraft, L("翻译暂不可用"))
        }
        return out
    }

    /// `retry` counts the earlier tries of a line every provider failed (Ling rate-limited while
    /// Google answers 429, and no on-device model): it is asked again a little later, as the copy
    /// `again`, since it may have scrolled off the bar meanwhile; the record still takes it.
    /// Debug: listen without any audio (`silentListen`), the locale its lines are in.
    static var silentLocale: String?

    /// Debug (`heard:<text>`): a finished sentence as if the recognizer gave it, in a silent meeting.
    /// The record, its translation and fixes, the bar and the notes window all follow.
    func debugHeard(_ text: String) {
        guard isRunning, Self.silentLocale != nil, let lang = activeLang else { return }
        let seg = Segment(id: nextSegmentID, text: text, sourceCode: lang.code, translation: nil)
        nextSegmentID += 1
        segments.append(seg)
        if segments.count > 8 { segments.removeFirst(segments.count - 8) }
        finalTiming[seg.id] = (Date(), 0.5)
        onFinal?(seg, 2)
        translateSegment(id: seg.id)
        renderSubtitles()
    }

    private func translateSegment(id: Int, retry: Int = 0, again: Segment? = nil) {
        guard !translationOff(), let seg = again ?? segments.first(where: { $0.id == id }) else { return }
        let trace = TranslateTrace()
        let asked = Date()
        // The target follows the detected language; log the one this call used, not the one after.
        let target = resolvedTarget
        Task { [weak self] in
            guard let self else { return }
            let result = await self.translate(seg.text, source: seg.sourceCode, target: target, trace: trace)
            if let timing = self.finalTiming.removeValue(forKey: id), !trace.attempts.isEmpty {
                self.onTiming?(SentenceTiming(at: timing.at, side: "them", chars: seg.text.count, recognize: timing.recognize,
                                              queue: trace.lingQueue, translate: Date().timeIntervalSince(asked), voice: nil,
                                              failed: trace.failedSeconds, via: result == nil ? "none" : trace.via,
                                              fallbacks: trace.fallbacks))
            }
            guard self.isRunning else { return }
            // The line was joined with the next one meanwhile: only the whole sentence's translation counts.
            if let now = self.segments.first(where: { $0.id == id }), now.text != seg.text { return }
            guard let out = result else {
                guard retry < 2 else { return }
                let delay = retry == 0 ? 10.0 : 20.0
                debugLog("translate: every provider failed, again in \(Int(delay)) s")
                // Segment ids are never reused, so a language switch in between does not matter.
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isRunning, !self.joinedAway.contains(id) else { return }
                        // Joined meanwhile: the joined sentence was asked for on its own.
                        if let now = self.segments.first(where: { $0.id == id }), now.text != seg.text { return }
                        self.translateSegment(id: id, retry: retry + 1, again: seg)
                    }
                }
                return
            }
            if let idx = self.segments.firstIndex(where: { $0.id == id }) {
                self.segments[idx].translation = out
            }
            contentLog("TRANSLATE [\(seg.sourceCode)→\(target)] \(seg.text) => \(out)")
            self.onTranslated?(id, out)
            self.renderSubtitles()
        }
    }

    /// The app joined segment `id` onto `into` (one sentence cut by a pause): the bar shows them as
    /// one, and the whole sentence is translated again. The old translation stays until then.
    func join(_ id: Int, into: Int, text: String) {
        let piece = segments.firstIndex(where: { $0.id == id }).map { segments.remove(at: $0) }
        joinedAway.insert(id)
        if joinedAway.count > 200, let oldest = joinedAway.min() { joinedAway.remove(oldest) }
        if let i = segments.firstIndex(where: { $0.id == into }) {
            segments[i].text = text
        } else {
            // The bar was cleared in between: show the joined sentence on its own.
            segments.append(Segment(id: into, text: text, sourceCode: piece?.sourceCode ?? activeLang?.code ?? "auto", translation: nil))
        }
        finalTiming[id] = nil
        translateSegment(id: into)
        renderSubtitles()
    }

    // MARK: The record's recognizer

    private func startRefining(_ record: RecordHearing) {
        recordTask?.cancel()
        refinerGen += 1
        let gen = refinerGen
        refiner = RecordRefiner()
        recordTask = Task { [weak self] in
            do {
                for try await sentence in record.sentences {
                    guard let self, gen == self.refinerGen, self.refiner != nil else { return }
                    contentLog("RECORD \(sentence.runs.map(\.text).joined())")
                    self.settled(self.refiner!.heard(sentence.runs, through: sentence.through))
                }
            } catch {
                debugLog("record track: \(error)")
            }
            guard let self, gen == self.refinerGen, self.refiner != nil else { return }
            self.settled(self.refiner!.finish())
            self.refiner = nil
        }
    }

    private func settled(_ lines: [(id: Int, text: String)]) {
        for l in lines { onRefined?(l.id, l.text) }
    }

    /// Stopping: what a sentence cut carried over is a line of its own, not lost with the draft.
    private func flushCarry() {
        guard let c = carry, isRunning else { carry = nil; return }
        carry = nil
        volatileText = ""
        volatileSentence = nil
        sentenceCutHead = nil
        handle(.init(text: c.text, isFinal: true, start: c.start, end: max(c.start, router.fedSeconds()), confidence: nil),
               generation: generation)
    }

    /// Each place the line could end, timed by the first draft that showed it: the words before it
    /// were heard by then. One that moves a character or so as the draft is revised keeps its time.
    private func noteBoundaries(at end: Double) {
        let text = shownDraft
        let carried = text.count - volatileText.count
        let now = HeardText.boundaries(text, language: activeLang?.code ?? "").filter { $0.at > carried }
        seenBoundaries = now.map { b in
            let old = seenBoundaries.first { $0.kind == b.kind && abs($0.at - b.at) <= 1 }
            return (b.at, b.kind, old?.end ?? end)
        }
    }

    /// A clause end for a long line (a Chinese line past 24 characters), or past `capped` any
    /// place between words: the latest one heard a moment ago, with enough before it to be a line.
    /// The notes window is read, not glanced at: there a Chinese line waits a little longer for a
    /// clause before it is cut between words ("不是很 | 大"); the subtitle bar keeps up with the
    /// speaker. Japanese has few clause marks besides 、: waiting there only made lines longer.
    private func boundaryCut(_ fed: Double, held: Double) -> (at: Int, kind: HeardText.Boundary, end: Double)? {
        let code = activeLang?.code ?? ""
        let line = HeardText.size(shownDraft)
        let patient = settings.displayMode != "bar" && code.hasPrefix("zh")
        let cap = HeardText.capped(code) + (patient ? HeardText.capped(code) / 3 : 0)
        let kind: HeardText.Boundary
        if line >= cap || held >= (patient ? 15 : 12) { kind = .word }
        else if line >= HeardText.clauseFrom(code) { kind = .clause }
        else { return nil }
        let text = shownDraft
        let fit = seenBoundaries.filter { b in
            b.kind >= kind && b.end > lastCutThrough && b.end > volatileStartClock + 0.5 && fed - b.end >= 0.4
                && HeardText.size(String(text.prefix(b.at))) >= (HeardText.isCJK(text) ? 12 : 5)
        }
        // Past the cap a clause end still beats a word gap, if it leaves at least half the line.
        if kind == .word, let clause = fit.filter({ $0.kind >= .clause && $0.at * 2 >= text.count }).max(by: { $0.at < $1.at }) {
            return clause
        }
        return fit.max { $0.at < $1.at }
    }

    /// SpeechTranscriber ends a sentence only at a clear pause; in a quick conversation that can
    /// take 15–20 s, and the subtitle stays a draft that long (the notes wait for it too). A long
    /// line in progress is ended where a sentence ends, at the next small pause (a dip in the
    /// sound), at a clause, past a cap between words, or when no new words come for a moment.
    private func maybeCutSentence() {
        guard isRunning, !cutting, let recognizer, !volatileText.isEmpty, volatileText != lastCut,
              (pendingSplit == nil && !cutAsked) || Date().timeIntervalSince(cutAskedAt) > 2 else { return }
        let cjk = joiner(for: activeLang?.code ?? "") == ""
        let long = cjk ? volatileText.count >= 24 : volatileText.split(separator: " ").count >= 10
        guard long else { return }
        // The longer the line has run, the smaller the pause that may end it.
        let held = Date().timeIntervalSince(volatileStartedAt)
        let needed = held >= 8 ? 0.15 : 0.3
        let c = router.clock()
        let mid = c.pause.end - c.pause.length / 2
        let through: Double, why: String
        var boundary: (at: Int, kind: HeardText.Boundary)?
        // The draft went on past the sentence, and still ends it about there (drafts get revised).
        if let s = volatileSentence, volatileText.count > s.head.count + 1,
           volatileText.prefix(s.head.count + 2).suffix(5).contains(where: { "。！？.!?".contains($0) }), s.end > lastCutThrough,
           s.end > volatileStartClock + 1, c.fed - s.end >= 0.5 {
            // The speaker finished a sentence and went straight on: end the line there. Its "." is
            // the speaker's, so the next piece doesn't join it back (`HeardText.continues`).
            (through, why) = (s.end, "sentence")
        } else if c.silence >= needed {
            (through, why) = (c.fed, "quiet")
        } else if c.pause.length >= needed, mid > volatileStartClock + 1.5, mid > lastCutThrough, c.pause.end <= c.fed {
            (through, why) = (mid, "pause")  // a pause already behind us: end the line there
        } else if let b = boundaryCut(c.fed, held: held) {
            (through, why) = (b.end, b.kind == .clause ? "clause" : "word")
            boundary = (b.at, b.kind)
        } else if Date().timeIntervalSince(volatileChangedAt) >= (held >= 8 ? 0.6 : 1.2) {
            (through, why) = (c.fed, "stalled")
        } else {
            return
        }
        cutting = true
        cutAskedAt = Date()
        cutAsked = why != "sentence" && boundary == nil
        let carried = shownDraft.count - volatileText.count
        if why == "sentence", let s = volatileSentence {
            sentenceCutHead = s.head
            pendingSplit = (carried + s.head.count, .sentence)
        } else if let b = boundary {
            sentenceCutHead = String(volatileText.prefix(max(0, b.at - carried)))
            pendingSplit = (b.at, b.kind)
        } else {
            sentenceCutHead = nil
            pendingSplit = nil
        }
        lastCut = volatileText
        lastCutThrough = through
        let chars = volatileText.count
        Task { [weak self] in
            do {
                try await recognizer.finalize(through: through)
                debugLog(String(format: "cut: line of %d chars ended after %.1f s (%@) at %.1f s of %.1f s",
                                chars, held, why, through, c.fed))
            } catch {
                debugLog("cut: finalize failed \(error)")
                self?.cutAsked = false
                self?.sentenceCutHead = nil
                self?.pendingSplit = nil
            }
            self?.cutting = false
        }
    }

    private func translateVolatile() {
        let text = shownDraft
        guard isRunning, !translationOff(), !volatileInFlight, text.count >= 2, text != lastVolatileSent else { return }
        let epoch = volatileEpoch
        let source = activeLang?.code ?? "auto"
        lastVolatileSent = text
        volatileInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let out = await self.translate(text, source: source, kind: .draft)
            self.volatileInFlight = false
            guard let out, self.isRunning, epoch == self.volatileEpoch else { return }
            self.volatileTranslation = out
            self.renderSubtitles()
        }
    }

    /// After a quiet spell the next sentence starts on a clean bar.
    func clearDisplay() {
        segments.removeAll()
        volatileTranslation = ""
        lastVolatileSent = ""
    }

    /// Translation switched back on: translate what is on screen now.
    func translationResumed() { if isRunning { retranslateVisible() } }

    private func retranslateVisible() {
        volatileTranslation = ""
        lastVolatileSent = ""
        for seg in segments.suffix(3) {
            if let idx = segments.firstIndex(where: { $0.id == seg.id }) { segments[idx].translation = nil }
            translateSegment(id: seg.id)
        }
        renderSubtitles()
    }
}
