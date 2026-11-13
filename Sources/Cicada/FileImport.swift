import AVFoundation
import CoreMedia
import Foundation
import Speech
import UniformTypeIdentifiers

/// Recordings and videos the user brings in: each becomes a meeting record, transcribed on device
/// faster than real time, one file at a time. It never touches the live pipeline, so a meeting can
/// be listened to meanwhile; its translations wait behind the live ones (`TranslationService.Kind.file`).
/// UI-free: AppModel shows the state and writes the notes when a file is done.
@MainActor
final class FileImporter: ObservableObject {
    struct Job: Equatable {
        let id: String
        let url: URL
        /// The language the user said it is in; nil detects it.
        var lang: Lang? = nil
    }

    enum Phase: Equatable {
        case preparing, detecting, downloading(String), transcribing, translating
    }

    /// Files waiting, in order; the one being transcribed is `current`.
    @Published private(set) var queue: [Job] = []
    @Published private(set) var current: Job?
    @Published private(set) var phase: Phase = .preparing
    /// Seconds of the current file transcribed so far, and its length.
    @Published private(set) var heard = 0.0
    @Published private(set) var duration = 0.0
    /// Lines of the current file sent for translation, and those still waiting for it.
    @Published private(set) var toTranslate = 0
    @Published private(set) var untranslated = 0

    /// `cloudOnly`: stretches of the current file the service couldn't hear (set by the app).
    var hearFailures = 0

    /// A file was transcribed and translated to the end.
    var onFinished: ((_ sessionID: String) -> Void)?

    let store: SessionStore
    let settings: AppSettings
    let translator: TranslationService
    let profiles: SpeakerProfileStore
    private var task: Task<Void, Never>?
    /// The running `SpeechAnalyzer` (macOS 26) or `RecognitionStream`, for 停止转写.
    private var analyzer: AnyObject?

    init(store: SessionStore, settings: AppSettings, translator: TranslationService, profiles: SpeakerProfileStore) {
        self.store = store
        self.settings = settings
        self.translator = translator
        self.profiles = profiles
    }

    var busy: Bool { current != nil }

    /// 0…1 of the current step: how much of the file is transcribed, then how many lines are translated.
    var progress: Double {
        if phase == .translating { return toTranslate > 0 ? Double(toTranslate - untranslated) / Double(toTranslate) : 1 }
        guard duration > 0 else { return 0 }
        return min(1, heard / duration)
    }

    /// Only things AVFoundation can play: audio, or video with a sound track.
    nonisolated static func importable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    /// Adds the files to the queue as records right away (so they show in the list); returns their ids.
    @discardableResult
    func add(_ urls: [URL]) async -> [String] {
        var ids: [String] = []
        for url in urls where Self.importable(url) {
            let (date, length) = await Self.facts(url)
            let s = store.beginImport(file: url, recordedAt: date, duration: length)
            queue.append(Job(id: s.id, url: url))
            ids.append(s.id)
            debugLog("import: queued \(s.id) (\(Int(length)) s)")
        }
        next()
        return ids
    }

    /// Transcribe a record again from the start (one that stopped halfway, or by request), in
    /// `lang` when the user picked it.
    func retry(_ id: String, lang: Lang? = nil) {
        guard let path = store.session(id)?.sourcePath, current?.id != id, !queue.contains(where: { $0.id == id }) else { return }
        store.restartImport(id)
        queue.append(Job(id: id, url: URL(fileURLWithPath: path), lang: lang))
        next()
    }

    enum Status: Equatable {
        /// Waiting, with this many files to go before it.
        case queued(ahead: Int)
        case running
        /// Stopped before the end (quit, 停止转写, or the file couldn't be read).
        case unfinished
    }

    /// Where a record stands; nil once it is transcribed (or not imported at all).
    func status(of s: Session) -> Status? {
        if current?.id == s.id { return .running }
        if let i = queue.firstIndex(where: { $0.id == s.id }) { return .queued(ahead: i + (current == nil ? 0 : 1)) }
        return s.importing == true ? .unfinished : nil
    }

    /// Stops a file (deleted, or 停止转写); what was transcribed stays.
    func cancel(_ id: String) {
        queue.removeAll { $0.id == id }
        guard current?.id == id else { return }
        task?.cancel()
        if #available(macOS 26, *), let a = analyzer as? SpeechAnalyzer { Task { await a.cancelAndFinishNow() } }
        if let s = analyzer as? RecognitionStream { Task { await s.cancel() } }
    }

    func cancelAll() {
        let ids = queue.map(\.id) + [current?.id].compactMap { $0 }
        ids.forEach(cancel)
    }

    // MARK: Running

    private func next() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        current = job
        phase = .preparing
        heard = 0
        duration = 0
        untranslated = 0
        toTranslate = 0
        task = Task { [weak self] in
            await self?.run(job)
            guard let self else { return }
            self.current = nil
            self.analyzer = nil
            self.next()
        }
    }

    private func run(_ job: Job) async {
        let started = Date()
        // The file's sound as 16 kHz mono PCM: video containers and any codec AVFoundation reads.
        let pcm = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-import-\(job.id).caf")
        defer { try? FileManager.default.removeItem(at: pcm) }
        do {
            let gotAccess = job.url.startAccessingSecurityScopedResource()
            defer { if gotAccess { job.url.stopAccessingSecurityScopedResource() } }
            duration = try await Task.detached(priority: .userInitiated) { try await Self.extractAudio(job.url, to: pcm) }.value
        } catch {
            // Left unfinished: the record offers 重新转写.
            debugLog("import: \(job.id) can't read the file: \(error)")
            return
        }
        guard !Task.isCancelled, store.session(job.id) != nil else { return }

        var lang = job.lang ?? sourceLanguages[0]
        // The service names each line's language itself (`cloudOnly`): no models to compare.
        let named = job.lang ?? sourceLanguages.first { $0.locale == settings.importLanguage }
        if Recognition.cloudOnly { lang = named ?? lastLanguage } else if job.lang == nil { lang = await language(of: pcm) }
        guard !Task.isCancelled else { return }
        let target = settings.resolvedTarget(source: lang.code)
        debugLog("import: \(job.id) \(lang.locale) → \(target)")
        // Nothing hears it on an Intel Mac without a Ling key: left unfinished, it offers 重新转写 once there is one.
        if Recognition.cloudOnly, !translator.ling.hearsAudio {
            debugLog("import: \(job.id) needs a Ling key")
            return
        }
        hearFailures = 0
        // What the service heard was translated for this target with it (`Recognition.cloudHear`).
        let heardTarget = settings.resolvedTarget(source: named?.code)

        do {
            if await Recognition.status(lang.locale) != .installed {
                try await Recognition.install(lang.locale) { _ in self.phase = .downloading(lang.name) }
            }
            guard !Task.isCancelled else { return }
            phase = .transcribing
            var n = 0
            var translations: [Task<Void, Never>] = []
            // 说话人识别, as when listening: each line's stretch of the file gets a voiceprint.
            let voices = settings.speakerVoices ? ImportVoices(pcm: pcm, store: store, session: job.id, profiles: profiles) : nil
            defer { voices?.stop() }
            // `end`: when the recognized stretch ends, so its last line's sound ends there.
            let add = { (sentences: [(text: String, t: Double)], end: Double, heard: String?, translation: String?) in
                let src = heard.flatMap { code in sourceLanguages.first { $0.code == code }?.code } ?? lang.code
                let to = heard == nil ? target : self.settings.resolvedTarget(source: src)
                // The service's translation covers the whole stretch: kept when the stretch is one line.
                let given = sentences.count == 1 && to == heardTarget ? translation : nil
                for (k, sentence) in sentences.enumerated() {
                    let text = HeardText.clean(sentence.text)
                    guard text.contains(where: \.isLetter) else { continue }
                    n += 1
                    let line = TranscriptLine(id: "f\(n)", t: max(0, sentence.t), speaker: "them",
                                              src: text, dst: src == to ? text : given, srcLang: src, dstLang: to)
                    self.store.append(line, to: job.id)
                    if line.dst == nil { translations.append(self.translate(line, session: job.id)) }
                    voices?.tag(line.id, from: line.t, to: k + 1 < sentences.count ? sentences[k + 1].t : end)
                }
            }
            if !Recognition.legacy, !Recognition.cloudOnly, #available(macOS 26, *) {
                let transcriber = SpeechTranscriber(locale: Locale(identifier: lang.locale), transcriptionOptions: [],
                                                    reportingOptions: [], attributeOptions: [.audioTimeRange])
                let file = try AVAudioFile(forReading: pcm)
                let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
                self.analyzer = analyzer
                for try await result in transcriber.results {
                    guard !Task.isCancelled, store.session(job.id) != nil else { break }
                    heard = CMTimeGetSeconds(result.range.end)
                    let pieces = result.text.runs.map { run in
                        (String(result.text[run.range].characters), run.audioTimeRange.map { CMTimeGetSeconds($0.start) })
                    }
                    add(Self.sentences(pieces, start: CMTimeGetSeconds(result.range.start)), CMTimeGetSeconds(result.range.end), nil, nil)
                }
                _ = analyzer
            } else {
                let hint = Recognition.cloudOnly ? named?.locale : lang.locale
                try await transcribeLegacy(pcm, locale: hint, session: job.id) { piece in
                    add(Self.sentences(Self.words(piece), start: piece.start), piece.end, piece.language, piece.translation)
                }
            }
            guard !Task.isCancelled, store.session(job.id) != nil else { return }
            if Recognition.cloudOnly, hearFailures > 0 {
                debugLog("import: \(job.id) \(hearFailures) stretches not heard, left unfinished")
                return
            }
            heard = duration
            phase = .translating
            for t in translations { await t.value }
            await voices?.finish()
            store.finishImport(job.id)
            debugLog(String(format: "import: %@ done, %d lines from %.0f s of audio in %.0f s", job.id, n, duration, Date().timeIntervalSince(started)))
            onFinished?(job.id)
        } catch {
            debugLog("import: \(job.id) failed: \(error)")
        }
    }

    /// macOS 14.4–15: the file fed through the older recognizer, which ends a line at each pause.
    /// It is fed only a couple of lines ahead of what has come back, so a long file doesn't queue up in memory.
    private func transcribeLegacy(_ pcm: URL, locale: String?, session id: String,
                                  line: @escaping (Recognition.Piece) -> Void) async throws {
        // Heard by the service: `locale` is only its hint, nil when the file's language isn't known.
        let stream = Recognition.cloudOnly ? Recognition.cloudStream(locale)
            : try await Recognition.start(locale ?? sourceLanguages[0].locale, drafts: false, background: true)
        analyzer = stream
        let file = try AVAudioFile(forReading: pcm)
        let rate = file.processingFormat.sampleRate
        var fedSeconds = 0.0
        let reader = Task { @MainActor in
            do {
                for try await piece in stream.results where piece.isFinal {
                    line(piece)
                }
            } catch {
                debugLog("import: recognizer error \(error)")
            }
        }
        let conv = PCMConverter()
        let chunk = AVAudioFrameCount(rate / 10)
        while !Task.isCancelled, store.session(id) != nil {
            // One recognizer at a time on macOS 14/15: a meeting being listened to goes first. The
            // file's line in progress ends, and the file carries on in the meeting's pauses.
            if LegacyStream.Gate.meetingBusy {
                try? await stream.finalize(through: fedSeconds)
                while LegacyStream.Gate.meetingBusy, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            }
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  (try? file.read(into: buf, frameCount: chunk)) != nil, buf.frameLength > 0 else { break }
            if let c = conv.convert(buf, to: stream.format) { stream.append(c) }
            fedSeconds += Double(buf.frameLength) / rate
            heard = max(heard, fedSeconds - 10)
            // A couple of lines in the recognizer at a time.
            while ((stream as? LegacyStream)?.backlog ?? (stream as? CloudStream)?.backlog ?? 0) > 2, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
        }
        if Task.isCancelled { await stream.cancel() } else { await stream.finish() }
        await reader.value
    }

    /// The older recognizer times a line, not its words: the line cut after each sentence mark,
    /// each piece timed by where its characters fall in the line.
    nonisolated static func words(_ piece: Recognition.Piece) -> [(String, Double?)] {
        var out: [(String, Double?)] = []
        var current = "", offset = 0
        let total = max(1, piece.text.count)
        func flush() {
            guard !current.isEmpty else { return }
            out.append((current, piece.start + (piece.end - piece.start) * Double(offset) / Double(total)))
            offset += current.count
            current = ""
        }
        for ch in piece.text {
            current.append(ch)
            if "。！？!?.".contains(ch) { flush() }
        }
        flush()
        return out
    }

    /// At most a few translations in flight: Ling takes about two a second across the whole app.
    private var inFlight = 0
    private func translate(_ line: TranscriptLine, session id: String) -> Task<Void, Never> {
        untranslated += 1
        toTranslate += 1
        return Task { [weak self] in
            guard let self else { return }
            while self.inFlight >= 3 { try? await Task.sleep(for: .milliseconds(150)) }
            self.inFlight += 1
            defer { self.inFlight -= 1; self.untranslated -= 1 }
            guard !Task.isCancelled, self.store.session(id) != nil else { return }
            for attempt in 0..<3 {
                if let out = await self.translator.translate(line.src, source: line.srcLang, target: line.dstLang, kind: .file) {
                    self.store.setTranslation(in: id, lineID: line.id, out)
                    return
                }
                try? await Task.sleep(for: .seconds(attempt == 0 ? 5 : 15))
            }
        }
    }

    /// The file's language: the one chosen in settings, else the installed model that understands
    /// a few clips from across the file best.
    /// The language the last meeting was heard in, else the first.
    private var lastLanguage: Lang {
        let last = UserDefaults.standard.string(forKey: "lastDetected")
        return sourceLanguages.first { $0.locale == last } ?? sourceLanguages[0]
    }

    private func language(of pcm: URL) async -> Lang {
        if let fixed = sourceLanguages.first(where: { $0.locale == settings.importLanguage }) { return fixed }
        let langs = await Self.installed()
        guard langs.count > 1 else { return langs.first ?? sourceLanguages[0] }
        phase = .detecting
        guard let file = try? AVAudioFile(forReading: pcm) else { return langs[0] }
        let rate = file.processingFormat.sampleRate
        let clipFrames = AVAudioFrameCount(rate * 8)
        var scores: [String: Double] = [:]
        // Three clips from across the file (fewer in a short one): an intro may be music or silence.
        let starts = Set([0.15, 0.45, 0.75].map { min(AVAudioFramePosition(Double(file.length) * $0), max(0, file.length - AVAudioFramePosition(clipFrames))) })
        for start in starts.sorted() {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: clipFrames) else { continue }
            file.framePosition = start
            guard (try? file.read(into: buffer, frameCount: clipFrames)) != nil, buffer.frameLength > 0 else { continue }
            for c in await LanguageDetector.rank([buffer], candidates: langs) { scores[c.lang.locale, default: 0] += c.score }
        }
        debugLog("import: language scores \(scores.map { String(format: "%@=%.2f", $0.key, $0.value) }.sorted())")
        let best = scores.max { $0.value < $1.value }?.key
        return langs.first { $0.locale == best } ?? langs[0]
    }

    /// With no long pause the recognizer hands back minutes as one result (a speech, a fluent
    /// reader): split it after each sentence, each line timed at its first word. `pieces` are the
    /// result's runs with their start, when known; `start` is the result's own.
    nonisolated static func sentences(_ pieces: [(String, Double?)], start: Double) -> [(text: String, t: Double)] {
        var out: [(text: String, t: Double)] = []
        var text = "", t: Double?
        for (piece, at) in pieces {
            if t == nil, !piece.trimmingCharacters(in: .whitespaces).isEmpty { t = at }
            text += piece
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Short ones ("Mr.", "OK.") stay with what follows.
            if let last = trimmed.last, "。！？!?.".contains(last), trimmed.filter(\.isLetter).count >= 8 {
                out.append((trimmed, t ?? out.last?.t ?? start))
                text = ""
                t = nil
            }
        }
        let rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append((rest, t ?? out.last?.t ?? start)) }
        return out
    }

    /// The languages whose speech model is on this Mac, asked per model: the installed-locale list
    /// can come back short right after a model download.
    nonisolated static func installed() async -> [Lang] {
        var out: [Lang] = []
        for lang in sourceLanguages where await Recognition.status(lang.locale) == .installed {
            out.append(lang)
        }
        return out
    }

    // MARK: Files

    /// When it was recorded (the file's own creation date, else the file system's) and how long it is.
    nonisolated static func facts(_ url: URL) async -> (Date, Double) {
        let asset = AVURLAsset(url: url)
        let length = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        var date: Date?
        if let item = try? await asset.load(.creationDate) { date = (try? await item.load(.dateValue)) ?? nil }
        if date == nil { date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate }
        return (date ?? Date(), length.isFinite ? length : 0)
    }

    /// Decodes the first sound track to 16 kHz mono Float32 PCM; returns its length in seconds.
    nonisolated static func extractAudio(_ url: URL, to out: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "CicadaImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "no sound track"])
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "CicadaImport", code: 2) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        try? FileManager.default.removeItem(at: out)
        let file = try AVAudioFile(forWriting: out, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var frames: AVAudioFramePosition = 0
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            let n = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { continue }
            buffer.frameLength = n
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(n), into: buffer.mutableAudioBufferList)
            guard status == noErr else { continue }
            try file.write(from: buffer)
            frames += AVAudioFramePosition(n)
        }
        if reader.status == .failed { throw reader.error ?? NSError(domain: "CicadaImport", code: 3) }
        return Double(frames) / 16_000
    }
}

/// 说话人识别 for an imported file: each line's stretch of the decoded audio goes through a tagger
/// of the file's own, so a meeting listened to meanwhile keeps its voices apart from the file's.
@MainActor
final class ImportVoices {
    private let tagger = SpeakerTagger()
    private let file: AVAudioFile?
    /// Off once the file is stopped: a voiceprint still queued then must not land on the lines of
    /// a 重新转写 that reuses the line ids.
    private var on = true

    init(pcm: URL, store: SessionStore, session id: String, profiles: SpeakerProfileStore) {
        file = try? AVAudioFile(forReading: pcm)
        tagger.profiles = profiles
        tagger.onVoice = { [weak self, weak store] line, voice in
            guard self?.on == true else { return }
            store?.setVoice(in: id, lineID: line, voice)
        }
        tagger.onProfile = { [weak self, weak store] line, voice, match in
            guard self?.on == true else { return }
            store?.setVoice(in: id, lineID: line, voice)
            store?.setVoiceProfile(id, voice: voice, ref: match.ref)
        }
        tagger.onSuggestion = { [weak self, weak store] line, voice, match in
            guard self?.on == true else { return }
            store?.setVoice(in: id, lineID: line, voice)
            store?.setVoiceSuggestion(id, voice: voice, match.ref)
        }
    }

    func tag(_ lineID: String, from start: Double, to end: Double) {
        // The model looks at 20 s at most: no need to hold more of a long line in memory.
        guard let file, let samples = Self.read(file, from: start, to: min(end, start + Voiceprints.maxSeconds)) else { return }
        tagger.tag(lineID: lineID, samples: samples)
    }

    /// Returns once every line handed in so far has its voice, or is known to have none.
    func finish() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            tagger.voice(of: []) { _ in c.resume() }   // too short to embed: just a place in the queue
        }
    }

    func stop() { on = false }

    /// 16 kHz mono floats from `start` to `end` seconds of the file.
    nonisolated static func read(_ file: AVAudioFile, from start: Double, to end: Double) -> [Float]? {
        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition(max(0, start) * rate)
        let last = min(file.length, AVAudioFramePosition(max(0, end) * rate))
        guard last > first, let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(last - first)) else { return nil }
        file.framePosition = first
        // A read after a seek can stop short of what was asked (a packet boundary): read on to the end.
        var out: [Float] = []
        out.reserveCapacity(Int(last - first))
        while file.framePosition < last {
            guard (try? file.read(into: buf, frameCount: AVAudioFrameCount(last - file.framePosition))) != nil,
                  buf.frameLength > 0, let d = buf.floatChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: d[0], count: Int(buf.frameLength)))
        }
        return out.isEmpty ? nil : out
    }
}
