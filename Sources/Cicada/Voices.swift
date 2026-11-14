import AVFoundation
import Foundation

// MARK: - Catalog

/// A voice the room can hear: one of Ming's (through the Ling key), one of another service's speech
/// model, a voice installed on this Mac, or the user's own voice cloned from a recording.
struct VoiceOption: Identifiable, Equatable {
    enum Kind: Equatable {
        case ming(String)
        case cloud(String)
        case system(String)
        case clone
    }
    /// Stored in settings: "ming:US_Emma", "cloud:Kore", "system:<AVSpeechSynthesisVoice identifier>", "clone".
    let id: String
    let name: String
    let tags: [String]
    let kind: Kind

    var needsKey: Bool { if case .system = kind { return false } else { return true } }
}

/// Which voices to offer for each language the room may hear. Ming's are hand-picked natural ones
/// (two women, two men where it has them); for languages it has no native voice for, Emma and
/// George speak it with `language_id`. The Mac's own best female and male voices follow, so there is
/// always something without a key.
enum VoiceCatalog {
    /// The cloud voices of the AI service in use. Set by the app when the service changes.
    enum Service: Equatable {
        case ming
        /// `label`: where they come from, shown next to each ("Gemini").
        case cloud(label: String, voices: [CloudVoice])
        case none
    }
    nonisolated(unsafe) static var service: Service = .ming

    /// Tabs in settings: (key, title). The key is the translation code without region ("zh" for zh-CN / zh-TW).
    static let languages: [(key: String, title: String)] = [
        ("en", "English"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
        ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português"),
    ]

    static func key(for code: String) -> String {
        let base = String(code.prefix(while: { $0 != "-" }))
        return base.isEmpty ? "en" : base
    }

    /// Ming's `language_id` for languages that need it (zh and en work without).
    static func mingLanguage(for code: String) -> String? {
        let k = key(for: code)
        return ["ja", "ko", "de", "fr", "es"].contains(k) ? k : nil
    }

    static func ming(for language: String) -> [VoiceOption] {
        func v(_ voice: String, _ name: String, _ tags: [String]) -> VoiceOption {
            VoiceOption(id: "ming:\(voice)", name: name, tags: tags, kind: .ming(voice))
        }
        switch key(for: language) {
        case "en":
            return [v("US_Emma", "Emma", [L("女"), L("美式"), L("自然对话")]), v("UK_George", "George", [L("男"), L("英式"), L("稳重")]),
                    v("UK_Charlotte", "Charlotte", [L("女"), L("英式"), L("平稳")])]
        case "zh":
            return [v("灵小雅", "小雅", [L("女"), L("清亮"), L("播报")]), v("灵小棠", "小棠", [L("女"), L("温和"), L("沉稳")]),
                    v("灵小锋", "小锋", [L("男"), L("温暖"), L("亲切")]), v("灵卓然", "卓然", [L("男"), L("沉着"), L("清楚")])]
        case "ja", "ko", "de", "fr", "es":
            return [v("US_Emma", "Emma", [L("女"), "Ming"]), v("UK_George", "George", [L("男"), "Ming"])]
        default:
            return []
        }
    }

    /// The Mac's best installed female and male voice for the language (no novelty voices).
    static func system(for language: String) -> [VoiceOption] {
        let k = key(for: language)
        let prefix = language.hasPrefix("zh-TW") ? "zh-TW" : k == "zh" ? "zh-CN" : k
        let all = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        var out: [VoiceOption] = []
        for gender in [AVSpeechSynthesisVoiceGender.female, .male] {
            guard let best = all.filter({ $0.gender == gender }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) else { continue }
            let quality = best.quality == .premium ? L("高品质") : best.quality == .enhanced ? L("增强") : L("标准")
            out.append(VoiceOption(id: "system:\(best.identifier)", name: best.name,
                                   tags: [gender == .female ? L("女") : L("男"), L("本机"), quality], kind: .system(best.identifier)))
        }
        return out
    }

    /// The service's voices for a language: Ming's, a speech model's (the same in every language), or none.
    static func remote(for language: String) -> [VoiceOption] {
        switch service {
        case .ming: return ming(for: language)
        case .cloud(let label, let voices):
            return voices.map { VoiceOption(id: "cloud:\($0.id)", name: $0.id, tags: [$0.gender, label].filter { !$0.isEmpty },
                                            kind: .cloud($0.id)) }
        case .none: return []
        }
    }

    static func options(for language: String) -> [VoiceOption] { remote(for: language) + system(for: language) }

    /// What a language uses until the user picks: the service's first voice with a key, else the Mac's.
    static func defaultID(for language: String, hasKey: Bool) -> String? {
        (hasKey ? remote(for: language).first : nil)?.id ?? system(for: language).first?.id
    }

    static let cloneOption = VoiceOption(id: "clone", name: L("我自己的声音"), tags: [], kind: .clone)

    /// A short line to try a voice with, in the language it will speak.
    static func sample(for language: String) -> String {
        switch key(for: language) {
        case "zh": "谢谢大家。我们来看一下上线时间表，并确定谁负责麦克风测试。"
        case "ja": "皆さん、ありがとうございます。発売スケジュールを確認しましょう。"
        case "ko": "감사합니다. 출시 일정을 함께 확인해 보겠습니다."
        case "es": "Gracias a todos. Revisemos el calendario de lanzamiento."
        case "fr": "Merci à tous. Regardons ensemble le calendrier de lancement."
        case "de": "Danke an alle. Schauen wir uns den Zeitplan für den Start an."
        case "pt": "Obrigado a todos. Vamos ver o cronograma de lançamento."
        default: "Thanks everyone. Let's look at the launch timeline and decide who owns the microphone tests."
        }
    }
}

// MARK: - The user's own voice

/// The recording Ming clones the user's voice from: `voice/reference.wav` (16 kHz mono, ≤ 30 s) and
/// `voice/reference.txt` (what it says, as transcribed on this Mac) under Application Support. Never
/// leaves the Mac except inside a speech request to Ling.
enum VoiceReference {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder).appendingPathComponent("voice")
    }
    static var audioURL: URL { folder.appendingPathComponent("reference.wav") }
    static var textURL: URL { folder.appendingPathComponent("reference.txt") }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: audioURL.path) && !(text ?? "").isEmpty
    }
    static var text: String? { try? String(contentsOf: textURL, encoding: .utf8) }

    static var duration: Double {
        guard let f = try? AVAudioFile(forReading: audioURL) else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// What Ming needs: the clip as a data URI and its transcript.
    static func reference() -> (audio: String, text: String)? {
        #if !CICADA_IOS
        trimSaved()
        #endif
        guard let data = try? Data(contentsOf: audioURL), let text, !text.isEmpty else { return nil }
        return ("data:audio/wav;base64," + data.base64EncodedString(), text)
    }

    static func save(wav: URL, text: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if fm.fileExists(atPath: audioURL.path) { try fm.removeItem(at: audioURL) }
        try fm.copyItem(at: wav, to: audioURL)
        #if !CICADA_IOS
        trim(audioURL)
        #endif
        try Data(text.utf8).write(to: textURL)
        for url in [audioURL, textURL] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            var u = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? u.setResourceValues(values)
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Pace

    #if !CICADA_IOS
    // Mac app only, with the voice recorder below: it scores with the speak test's tokens (SpeakTest.swift).

    /// Ming copies the recording's pace into every sentence: a recital at 1.7 characters a second
    /// made each sentence about 4× as long as the built-in voice says it. Below these (characters
    /// for Chinese, Japanese and Korean, words otherwise, per second of speech) the clone is too
    /// slow for a meeting; reading the passage at an ordinary pace gives 3.5–5 and 2.3–3.
    static let slowCharacters = 2.5, slowWords = 1.6

    /// How many characters or words a second the recording is read at, silence at both ends left
    /// out; nil when there is no speech to measure.
    static func pace(text: String, samples: [Float], sampleRate: Double) -> Double? {
        let units = SpeakScore.tokens(text).count
        guard units > 0, let span = speechSpan(samples, sampleRate: sampleRate), span > 0.5 else { return nil }
        return Double(units) / span
    }

    static func isSlow(text: String, pace: Double) -> Bool {
        let tokens = SpeakScore.tokens(text)
        let characters = tokens.filter { $0.unicodeScalars.contains(where: SpeakScore.isCJK) }.count
        return pace < (characters * 2 >= tokens.count ? slowCharacters : slowWords)
    }

    /// Seconds from the first to the last 20 ms window within 35 dB of the loudest one.
    static func speechSpan(_ samples: [Float], sampleRate: Double) -> Double? {
        guard let w = speechWindows(samples, sampleRate: sampleRate) else { return nil }
        return Double(w.last - w.first + 1) * Double(w.size) / sampleRate
    }

    /// The samples from 0.2 s before the reading to 0.2 s after it. Ming copies the clip's ending:
    /// a second of silence after the last word (the pause before 读完了) made every cloned
    /// sentence come back as 0.4 s of nothing (measured against Ling, 2026-11).
    static func trimmed(_ samples: [Float], sampleRate: Double) -> ArraySlice<Float> {
        guard let w = speechWindows(samples, sampleRate: sampleRate) else { return samples[...] }
        let pad = Int(sampleRate * 0.2)
        return samples[max(0, w.first * w.size - pad)..<min(samples.count, (w.last + 1) * w.size + pad)]
    }

    /// Rewrites a WAV without the quiet around the reading; false when there was nothing to cut.
    @discardableResult
    static func trim(_ url: URL) -> Bool {
        guard let f = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil, let ch = buf.floatChannelData?[0] else { return false }
        let rate = f.processingFormat.sampleRate
        let all = Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
        let kept = trimmed(all, sampleRate: rate)
        guard all.count - kept.count > Int(rate * 0.05),
              let out = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(kept.count)),
              let dst = out.floatChannelData?[0] else { return false }
        kept.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: kept.count) }
        out.frameLength = AVAudioFrameCount(kept.count)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".trim-\(UUID().uuidString).wav")
        do {
            // Scoped so the file is closed (its header written) before it replaces the original.
            do {
                let w = try AVAudioFile(forWriting: tmp, settings: f.fileFormat.settings,
                                        commonFormat: f.processingFormat.commonFormat, interleaved: f.processingFormat.isInterleaved)
                try w.write(from: out)
            }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    /// The saved recording, trimmed once: recordings made before trimming existed end in the pause.
    private static var checkedTrim: Date?
    static func trimSaved() {
        let date = (try? audioURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date, date != checkedTrim else { return }
        if trim(audioURL) { debugLog("voice clone: trimmed the saved recording to \(String(format: "%.1f", duration)) s") }
        checkedTrim = (try? audioURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func speechWindows(_ samples: [Float], sampleRate: Double) -> (first: Int, last: Int, size: Int)? {
        let size = max(1, Int(sampleRate * 0.02))
        var levels: [Float] = []
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + size)
            var sum: Float = 0
            for k in i..<end { sum += samples[k] * samples[k] }
            levels.append((sum / Float(end - i)).squareRoot())
            i = end
        }
        guard let loudest = levels.max(), loudest > 0.003 else { return nil }
        let floor = loudest * 0.0178
        guard let first = levels.firstIndex(where: { $0 >= floor }),
              let last = levels.lastIndex(where: { $0 >= floor }) else { return nil }
        return (first, last, size)
    }

    /// The pace of a WAV and what it says.
    static func pace(of url: URL, text: String) -> Double? {
        guard let f = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil, let ch = buf.floatChannelData?[0] else { return nil }
        return pace(text: text, samples: Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))),
                    sampleRate: f.processingFormat.sampleRate)
    }

    private static var savedPace: (date: Date, slow: Bool)?

    /// The saved recording is read too slowly (worked out once per recording).
    static var savedIsSlow: Bool {
        guard let date = (try? audioURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              let text else { return false }
        if let c = savedPace, c.date == date { return c.slow }
        let slow = pace(of: audioURL, text: text).map { isSlow(text: text, pace: $0) } ?? false
        savedPace = (date, slow)
        return slow
    }
    #endif

    /// The passage to read, in the user's own language.
    static func passage(for locale: String) -> String {
        switch VoiceCatalog.key(for: locale) {
        case "zh": "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。请大家先看一下屏幕上的议程。"
        case "ja": "皆さん、こんにちは。今日の会議では、新製品の発売計画について話し合います。スケジュール、テストの範囲、そしてマーケティングについて順番に確認しましょう。"
        default: "Hello everyone, thanks for joining. Today we'll walk through the launch plan for the new product: the schedule, what we still need to test, and how we'll tell people about it. Let's start with the agenda on the screen."
        }
    }
}

#if !CICADA_IOS
// Mac app only (the iOS build sets CICADA_IOS): pinned to a Mac input device and checked with the
// Mac recognizer. iOS records its own (docs/ios-plan.md, M3).
/// Records the microphone for the voice clone: 16 kHz mono into a temporary WAV, with a level for
/// the meter. Stops by itself at 30 s.
@MainActor
final class VoiceRecorder: ObservableObject {
    enum Phase: Equatable { case idle, recording, checking, ready, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var seconds: Double = 0
    @Published private(set) var level: Float = 0
    /// What the recording says (transcribed on this Mac), used as the clone's reference text.
    @Published private(set) var transcript = ""

    static let maxSeconds = 30.0
    static let minSeconds = 8.0

    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var file: AVAudioFile?
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private var timer: Timer?
    private var started = Date()
    private(set) var url = FileManager.default.temporaryDirectory.appendingPathComponent("livesubs-voice-\(UUID().uuidString).wav")
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var locale = "zh-CN"

    /// `device`: the real mic; the system default may be the virtual mic while speaking is on.
    func start(locale: String, device: OutputDevice?) {
        stopEngine()
        self.locale = locale
        transcript = ""
        try? FileManager.default.removeItem(at: url)
        let input = engine.inputNode
        AudioDevices.pinInput(engine, to: device)
        // The hardware format, as in `RoomMic.start`: the client one can still be the system mic's.
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let f = try? AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true),
              let conv = AVAudioConverter(from: inFormat, to: format) else {
            phase = .failed(L("麦克风没收到声音，请检查麦克风权限"))
            return
        }
        file = f
        converter = conv
        let outFormat = format
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let conv = self.converter, let file = self.file else { return }
            let ratio = outFormat.sampleRate / buffer.format.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            try? file.write(from: out)
            var peak: Float = 0
            if let ch = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ch[i])) }
            }
            Task { @MainActor in self.level = min(1, peak * 2.5) }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            phase = .failed(L("无法打开麦克风：\(error.localizedDescription)"))
            return
        }
        started = Date()
        seconds = 0
        phase = .recording
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seconds = Date().timeIntervalSince(self.started)
                if self.seconds >= Self.maxSeconds { self.finish() }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// Stops recording and transcribes it; `ready` when it is long enough and recognisable.
    func finish() {
        guard phase == .recording else { return }
        stopEngine()
        guard seconds >= Self.minSeconds else {
            phase = .failed(L("录音太短了，请至少朗读 \(Int(Self.minSeconds)) 秒"))
            return
        }
        phase = .checking
        let url = url, locale = locale
        Task {
            let text = await Self.transcribe(url, locale: locale)
            self.transcript = text
            guard text.count >= 6 else { self.phase = .failed(L("没听清录音内容，请换个安静的地方再录一次")); return }
            let pace = VoiceReference.pace(of: url, text: text)
            debugLog("voice clone: \(text.count) chars, pace \(pace.map { String(format: "%.1f", $0) } ?? "-")/s")
            if let pace, VoiceReference.isSlow(text: text, pace: pace) {
                self.phase = .failed(L("读得有点慢，克隆的声音也会这么慢。请用平时说话的语速再录一次"))
                return
            }
            self.phase = .ready
        }
    }

    func cancel() {
        stopEngine()
        phase = .idle
        try? FileManager.default.removeItem(at: url)
    }

    private func stopEngine() {
        timer?.invalidate()
        timer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        file = nil
        converter = nil
        level = 0
    }

    private static func transcribe(_ url: URL, locale: String) async -> String {
        guard let f = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil else { return "" }
        return await LoopbackTest.transcribe([buf], locale: locale)
    }
}
#endif
