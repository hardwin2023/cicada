#if os(macOS)
import AppKit
#endif
import Foundation

struct TranscriptLine: Codable, Identifiable, Equatable {
    var id: String
    /// Seconds from the start of the session.
    var t: Double
    /// "them" (system audio) or "me" (microphone).
    var speaker: String
    var src: String
    var dst: String?
    var srcLang: String
    var dstLang: String
    /// Which of the other side's voices said it (SpeakerID.swift); nil when unknown.
    var voice: Int? = nil
    /// 电脑和会议室: "room" when the room mic heard it; absent for the Mac's audio (or older records).
    var via: String? = nil
    /// Words the AI service fixed (`Correction`); `src` stays what was heard. Absent when none.
    var fixes: [LineFix]? = nil
}

/// A name Ling found for a voice, and the line it is based on ("00:06 “Sure, Emma…”").
struct VoiceGuess: Codable, Equatable {
    var name: String
    var evidence: String
}

struct Session: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var lines: [TranscriptLine]
    var hasAudio: Bool
    /// AI notes (absent in older sessions and without an API key).
    var notes: MeetingNotes?
    /// The user renamed it; nil in older sessions, where any title but the default counts as renamed.
    var renamed: Bool?
    /// 说话人识别: names the user gave voices, keyed by voice id. An empty name means
    /// "not Ling's guess": the voice shows as 说话人 N.
    var voiceNames: [String: String]? = nil
    /// Names Ling read from the conversation, keyed by voice id; shown until the user says otherwise.
    var voiceGuesses: [String: VoiceGuess]? = nil
    /// A voice this meeting matched to the local voiceprint library, keyed by voice id. The name
    /// is a snapshot: deleting the profile later must not make an old record unreadable.
    var voiceProfiles: [String: VoiceProfileRef]? = nil
    /// Similar matches waiting for the user to say yes. Suggestions are never shown as the name.
    var voiceSuggestions: [String: VoiceProfileRef]? = nil
    /// An imported recording or video: its file name, where it was (played from there; never
    /// copied or deleted), and true until transcribing it finished.
    var sourceFile: String? = nil
    var sourcePath: String? = nil
    var importing: Bool? = nil
    /// A meeting kept for its recording alone: transcribed like an imported file (its
    /// `sourcePath` is its own recording), in a language the user picks.
    var fromRecording: Bool { sourceFile == nil && sourcePath != nil }
    /// Heard through the microphone in the room (会议室) for some or all of it.
    var room: Bool? = nil

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    /// The user's own title, else the date and the name the notes gave the meeting
    /// ("11月1日 产品路线评审", in the notes' language), else "会议 11月1日 14:30".
    var displayTitle: String {
        if renamed ?? !title.hasPrefix("会议 ") { return title }
        // The stored default title is Chinese ("会议 11月1日 14:30"); shown in the UI language.
        guard let name = notes?.title, !name.isEmpty else {
            // An imported file is known by its name until the notes give it one.
            if let file = sourceFile { return (file as NSString).deletingPathExtension }
            return L("会议 \(dateText(startedAt, "MMMdHHmm"))")
        }
        let thisYear = Calendar.current.isDate(startedAt, equalTo: Date(), toGranularity: .year)
        return "\(dateText(startedAt, thisYear ? "MMMd" : "yMMMd")) \(name)"
    }

    static func defaultTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return "会议 \(f.string(from: date))"
    }
}

/// One folder per meeting under ~/Library/Application Support/LiveSubs/Sessions/<id>/:
/// session.json, system.m4a (what you heard, the room mic folded in) and mic.m4a (what you said).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var liveID: String?
    /// The last meeting whose recording became a playable .m4a (the rewrap runs after the meeting).
    @Published private(set) var audioFinished: String?

    let root: URL
    /// Per meeting: a file being imported saves alongside the live meeting without delaying it.
    private var saveWork: [String: DispatchWorkItem] = [:]
    /// A record was written to disk (存到文件夹 follows its changes).
    var onSave: ((String) -> Void)?

    /// `root`: tests keep their meetings in a folder of their own.
    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? base.appendingPathComponent("\(DevBuild.supportFolder)/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        load()
    }

    func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func systemAudioURL(_ id: String) -> URL { folder(id).appendingPathComponent("system.m4a") }
    func micAudioURL(_ id: String) -> URL { folder(id).appendingPathComponent("mic.m4a") }
    /// 电脑和会议室: the room mic, beside system.m4a on the meeting's clock until the meeting ends,
    /// then folded into it (`finishAudio`), so a record still has one recording.
    func roomAudioURL(_ id: String) -> URL { folder(id).appendingPathComponent("room.m4a") }
    private func audioURLs(_ id: String) -> [URL] { [systemAudioURL(id), micAudioURL(id), roomAudioURL(id)] }

    private func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [Session] = []
        for dir in dirs {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
               var s = try? decoder.decode(Session.self, from: data) {
                if s.endedAt == nil { s.endedAt = s.lines.last.map { s.startedAt.addingTimeInterval($0.t + 5) } ?? s.startedAt }
                // The app quit mid-meeting: its recording is still in the partial file.
                if s.id != liveID, hasPartialAudio(s.id) {
                    s.hasAudio = true
                    finishAudio(s.id)
                }
                out.append(s)
            }
        }
        sessions = out.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Live session

    @discardableResult
    func begin() -> Session {
        let now = Date()
        let fid = DateFormatter()
        fid.dateFormat = "yyyyMMdd-HHmmss"
        let s = Session(id: fid.string(from: now), title: Session.defaultTitle(now),
                        startedAt: now, endedAt: nil, lines: [], hasAudio: false)
        sessions.insert(s, at: 0)
        liveID = s.id
        try? FileManager.default.createDirectory(at: folder(s.id), withIntermediateDirectories: true)
        return s
    }

    /// `at`: when the meeting really ended, for one that ended by itself after a hang-up or a
    /// long silence; the recordings are cut there too. `heardSpeech`: the recording holds speech,
    /// so a meeting is kept for it even when no line made it into the record (the language was
    /// never settled, say): an hour of a meeting must not vanish with its audio.
    func end(at: Date? = nil, heardSpeech: Bool = false) {
        guard let id = liveID, let i = index(id) else { liveID = nil; return }
        let now = Date()
        sessions[i].endedAt = at.map { min(now, max(sessions[i].startedAt, $0)) } ?? now
        liveID = nil
        sessions[i].hasAudio = audioURLs(id).contains {
            FileManager.default.fileExists(atPath: $0.path) || FileManager.default.fileExists(atPath: AudioFileWriter.partial($0).path)
        }
        if sessions[i].lines.isEmpty {
            guard heardSpeech, sessions[i].hasAudio else {
                // Nothing was said: don't keep an empty meeting around.
                try? FileManager.default.removeItem(at: folder(id))
                sessions.remove(at: i)
                return
            }
            // Only the recording: it plays, and is transcribed again, like an imported file.
            let system = systemAudioURL(id), room = roomAudioURL(id)
            let heard = [system, AudioFileWriter.partial(system), room, AudioFileWriter.partial(room)]
                .contains { FileManager.default.fileExists(atPath: $0.path) }
            sessions[i].sourcePath = (heard ? system : micAudioURL(id)).path
        }
        saveNow(id)
        finishAudio(id, until: at == nil ? nil : sessions[i].duration)
    }

    private func hasPartialAudio(_ id: String) -> Bool {
        audioURLs(id).contains { FileManager.default.fileExists(atPath: AudioFileWriter.partial($0).path) }
    }

    /// Turns the meeting's recordings into .m4a files (call after the recorders are closed).
    func finishAudio(_ id: String, until: Double? = nil) {
        let urls = audioURLs(id), system = systemAudioURL(id), room = roomAudioURL(id)
        Task.detached(priority: .utility) {
            for u in urls { await AudioFileWriter.finish(u, until: until) }
            Self.foldRoom(room, into: system)
            await self.markAudioFinished(id)
        }
    }

    /// One recording per meeting, both sides in it: the room mic goes into system.m4a (or becomes
    /// it, when the Mac played nothing). Waits while system.aac is left over from a cut rewrap:
    /// the next launch finishes it and folds again.
    nonisolated private static func foldRoom(_ room: URL, into system: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: room.path), !fm.fileExists(atPath: AudioFileWriter.partial(system).path) else { return }
        if !fm.fileExists(atPath: system.path) {
            try? fm.moveItem(at: room, to: system)
        } else if AudioFileWriter.mix(room, into: system) {
            try? fm.removeItem(at: room)
        }
    }

    private func markAudioFinished(_ id: String) {
        audioFinished = id
    }

    var liveStart: Date? { liveID.flatMap { index($0) }.map { sessions[$0].startedAt } }

    /// The live meeting is (now) heard in the room: its record says 会议室.
    func markLiveInRoom() {
        guard let id = liveID, let i = index(id), sessions[i].room != true else { return }
        sessions[i].room = true
        scheduleSave(id)
    }

    func append(_ line: TranscriptLine) {
        guard let id = liveID, let i = index(id) else { return }
        sessions[i].lines.append(line)
        scheduleSave(id)
    }

    func setTranslation(lineID: String, _ text: String) {
        guard let id = liveID, let i = index(id),
              let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].dst = text
        scheduleSave(id)
    }

    /// A line joined with the one after it (`HeardText.join`).
    func setSource(lineID: String, _ text: String) {
        guard let id = liveID, let i = index(id),
              let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].src = text
        scheduleSave(id)
    }

    /// The record's own recognizer's words for a line (`RecordRefiner`), which may land after the
    /// meeting ended.
    func setSource(in id: String, lineID: String, _ text: String) {
        guard let i = index(id), let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].src = text
        scheduleSave(id)
    }

    func setVoice(lineID: String, _ voice: Int) {
        guard let id = liveID else { return }
        setVoice(in: id, lineID: lineID, voice)
    }

    /// An imported file's line got its voice (`ImportVoices`).
    func setVoice(in id: String, lineID: String, _ voice: Int) {
        guard let i = index(id),
              let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].voice = voice
        scheduleSave(id)
    }

    /// The user says a line (or a paragraph of them) was someone else's: those lines take that voice.
    func setLineVoices(_ id: String, lines ids: Set<String>, _ voice: Int) {
        guard let i = index(id) else { return }
        for j in sessions[i].lines.indices where ids.contains(sessions[i].lines[j].id) && sessions[i].lines[j].speaker == "them" {
            sessions[i].lines[j].voice = voice
        }
        saveNow(id)
    }

    /// Who said what in a meeting, taken before a speaker edit so 撤销 can put it back.
    struct VoiceSnapshot {
        /// Every line's voice then (nil included), by line id.
        let voices: [String: Int?]
        let names: [String: String]?
        let guesses: [String: VoiceGuess]?
        let profiles: [String: VoiceProfileRef]?
        let suggestions: [String: VoiceProfileRef]?
    }

    func voiceSnapshot(_ id: String) -> VoiceSnapshot? {
        guard let s = session(id) else { return nil }
        var voices: [String: Int?] = [:]
        for l in s.lines { voices[l.id] = .some(l.voice) }
        return VoiceSnapshot(voices: voices, names: s.voiceNames, guesses: s.voiceGuesses,
                             profiles: s.voiceProfiles, suggestions: s.voiceSuggestions)
    }

    func restore(_ id: String, _ snap: VoiceSnapshot) {
        guard let i = index(id) else { return }
        // Lines heard since keep the voice they were given.
        for j in sessions[i].lines.indices {
            if let v = snap.voices[sessions[i].lines[j].id] { sessions[i].lines[j].voice = v }
        }
        sessions[i].voiceNames = snap.names
        sessions[i].voiceGuesses = snap.guesses
        sessions[i].voiceProfiles = snap.profiles
        sessions[i].voiceSuggestions = snap.suggestions
        saveNow(id)
    }

    /// The user names a voice. nil drops their name (Ling's guess shows again); "" keeps 说话人 N.
    func setVoiceName(_ id: String, voice: Int, _ name: String?) {
        guard let i = index(id) else { return }
        var names = sessions[i].voiceNames ?? [:]
        names[String(voice)] = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[i].voiceNames = names.isEmpty ? nil : names
        saveNow(id)
    }

    /// A voice was recognised by the local voiceprint library. The suggestion, if any, is spent.
    func setVoiceProfile(_ id: String, voice: Int, ref: VoiceProfileRef?) {
        guard let i = index(id) else { return }
        var profiles = sessions[i].voiceProfiles ?? [:]
        profiles[String(voice)] = ref
        sessions[i].voiceProfiles = profiles.isEmpty ? nil : profiles
        if var suggestions = sessions[i].voiceSuggestions {
            suggestions[String(voice)] = nil
            sessions[i].voiceSuggestions = suggestions.isEmpty ? nil : suggestions
        }
        saveNow(id)
    }

    /// A close voiceprint match waiting for the user. Never used as the displayed name by itself.
    func setVoiceSuggestion(_ id: String, voice: Int, _ ref: VoiceProfileRef?) {
        guard let i = index(id) else { return }
        var suggestions = sessions[i].voiceSuggestions ?? [:]
        suggestions[String(voice)] = ref
        sessions[i].voiceSuggestions = suggestions.isEmpty ? nil : suggestions
        saveNow(id)
    }

    /// Ling's latest guesses; earlier ones stay for voices it no longer mentions, unless it now named
    /// them without evidence (`refuted`, voice → name): then that earlier name goes too.
    func setVoiceGuesses(_ id: String, _ guesses: [Int: VoiceGuess], refuted: [Int: String] = [:]) {
        guard let i = index(id), !guesses.isEmpty || !refuted.isEmpty else { return }
        var all = sessions[i].voiceGuesses ?? [:]
        for (v, name) in refuted where guesses[v] == nil && all[String(v)]?.name == name { all[String(v)] = nil }
        for (v, g) in guesses { all[String(v)] = g }
        guard all != sessions[i].voiceGuesses else { return }
        sessions[i].voiceGuesses = all.isEmpty ? nil : all
        saveNow(id)
    }

    /// The user said two voices are the same person: `from`'s lines become `into`'s.
    func mergeVoice(_ id: String, _ from: Int, into: Int) {
        guard let i = index(id), from != into else { return }
        for j in sessions[i].lines.indices where sessions[i].lines[j].voice == from { sessions[i].lines[j].voice = into }
        if var names = sessions[i].voiceNames, let moved = names.removeValue(forKey: String(from)) {
            // A turned-down guess ("") stays with the voice it was about; a real name moves over.
            if names[String(into)] == nil, !moved.isEmpty { names[String(into)] = moved }
            sessions[i].voiceNames = names.isEmpty ? nil : names
        }
        if var guesses = sessions[i].voiceGuesses, let moved = guesses.removeValue(forKey: String(from)) {
            if guesses[String(into)] == nil { guesses[String(into)] = moved }
            sessions[i].voiceGuesses = guesses.isEmpty ? nil : guesses
        }
        if var profiles = sessions[i].voiceProfiles, let moved = profiles.removeValue(forKey: String(from)) {
            if profiles[String(into)] == nil { profiles[String(into)] = moved }
            sessions[i].voiceProfiles = profiles.isEmpty ? nil : profiles
        }
        if var suggestions = sessions[i].voiceSuggestions {
            suggestions[String(from)] = nil
            sessions[i].voiceSuggestions = suggestions.isEmpty ? nil : suggestions
        }
        saveNow(id)
    }

    func setNotes(_ id: String, _ notes: MeetingNotes) {
        guard let i = index(id) else { return }
        sessions[i].notes = notes
        id == liveID ? scheduleSave(id) : saveNow(id)
    }

    // MARK: Imported files

    /// A record for a recording or video, dated when it was recorded; filled by `FileImporter`.
    func beginImport(file: URL, recordedAt: Date, duration: Double) -> Session {
        let fid = DateFormatter()
        fid.dateFormat = "yyyyMMdd-HHmmss"
        let id = "import-\(fid.string(from: Date()))-\(UUID().uuidString.prefix(4).lowercased())"
        var s = Session(id: id, title: Session.defaultTitle(recordedAt), startedAt: recordedAt,
                        endedAt: recordedAt.addingTimeInterval(max(1, duration)), lines: [], hasAudio: false)
        s.sourceFile = file.lastPathComponent
        s.sourcePath = file.path
        s.importing = true
        sessions.append(s)
        sessions.sort { $0.startedAt > $1.startedAt }
        saveNow(id)
        return s
    }

    /// Transcribing again from the start: the old lines and notes go.
    func restartImport(_ id: String) {
        guard let i = index(id) else { return }
        sessions[i].lines = []
        sessions[i].notes = nil
        // Voices are numbered afresh: names given to the old ones would land on other people.
        sessions[i].voiceNames = nil
        sessions[i].voiceGuesses = nil
        sessions[i].voiceProfiles = nil
        sessions[i].voiceSuggestions = nil
        sessions[i].importing = true
        saveNow(id)
    }

    func append(_ line: TranscriptLine, to id: String) {
        guard let i = index(id) else { return }
        sessions[i].lines.append(line)
        scheduleSave(id)
    }

    /// A line's fixes (`Correction`): what the AI service proposed and the user decided.
    func setFixes(in id: String, lineID: String, _ fixes: [LineFix]) {
        guard let i = index(id), let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard sessions[i].lines[j].fixes ?? [] != fixes else { return }
        sessions[i].lines[j].fixes = fixes.isEmpty ? nil : fixes
        scheduleSave(id)
    }

    /// The line a reply was for, by its text as heard: the newest such line in the live meeting,
    /// else in a file being imported. Older meetings never: "好的。" is in all of them.
    func lineHeard(as text: String) -> (session: String, line: TranscriptLine)? {
        let ids = ([liveID].compactMap { $0 }) + sessions.filter { $0.importing == true }.map(\.id)
        for id in ids {
            if let s = session(id), let l = s.lines.last(where: { $0.src == text }) { return (id, l) }
        }
        return nil
    }

    func setTranslation(in id: String, lineID: String, _ text: String) {
        guard let i = index(id), let j = sessions[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        sessions[i].lines[j].dst = text
        scheduleSave(id)
    }

    func finishImport(_ id: String) {
        guard let i = index(id) else { return }
        sessions[i].importing = nil
        saveWork.removeValue(forKey: id)?.cancel()
        saveNow(id)
    }

    // MARK: Editing

    /// An empty title, or the one shown already, goes back to the automatic one.
    func rename(_ id: String, to title: String) {
        guard let i = index(id) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != sessions[i].displayTitle else { return }
        if t.isEmpty {
            sessions[i].title = Session.defaultTitle(sessions[i].startedAt)
            sessions[i].renamed = false
        } else {
            sessions[i].title = t
            sessions[i].renamed = true
        }
        id == liveID ? scheduleSave(id) : saveNow(id)
    }

    func delete(_ id: String) {
        guard id != liveID, let i = index(id) else { return }
        saveWork.removeValue(forKey: id)?.cancel()
        try? FileManager.default.removeItem(at: folder(id))
        sessions.remove(at: i)
    }

    func session(_ id: String?) -> Session? { id.flatMap { index($0) }.map { sessions[$0] } }

    private func index(_ id: String) -> Int? { sessions.firstIndex(where: { $0.id == id }) }

    /// At most one save per meeting every 1.5 s. A save already waiting writes the latest state,
    /// so it is never pushed back: an imported file adds lines and translations many times a
    /// second and would otherwise not reach the disk until it went quiet.
    private func scheduleSave(_ id: String) {
        guard saveWork[id] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveWork[id] = nil; self?.saveNow(id) }
        }
        saveWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func saveNow(_ id: String) {
        guard let s = session(id) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(s) else { return }
        try? FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        try? data.write(to: folder(id).appendingPathComponent("session.json"), options: .atomic)
        onSave?(id)
    }
}

// MARK: - Export

enum TranscriptExport {
    static func clock(_ t: Double) -> String {
        let s = Int(max(0, t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Speaker numbers on (设置 › 通用 › 说话人识别); kept in step by AppModel.
    nonisolated(unsafe) static var voices = false

    static func speakerName(_ line: TranscriptLine, _ numbers: [String: Int] = [:], _ names: [Int: String] = [:]) -> String {
        if line.speaker == "me" { return L("你 · 同传") }
        if let n = numbers[line.id] { return SpeakerLabels.label(n, names) }
        return numbers.isEmpty ? L("对方") : L("未识别")
    }

    static func speakerNumbers(_ s: Session) -> [String: Int] { voices ? SpeakerLabels.numbers(s) : [:] }

    /// Whether lines say who spoke. An imported file has no "other side" to call 对方: its lines
    /// are named only once its voices are told apart.
    static func saysWho(_ s: Session, _ numbers: [String: Int]) -> Bool { s.sourceFile == nil || !numbers.isEmpty }

    static func header(_ s: Session) -> String {
        let mins = Int(s.duration / 60)
        return "\(dateText(s.startedAt, "yMMMdHHmm")) · " + (mins < 1 ? L("不到 1 分钟") : L("\(mins) 分钟"))
    }

    /// The notes as Markdown (empty when there are none).
    static func notesMarkdown(_ n: MeetingNotes?) -> String {
        guard let n, !n.isEmpty else { return "" }
        var out = "## \(L("纪要"))\n\n\(n.summary)\n\n"
        for t in n.topics {
            out += "### \(clock(t.start)) \(t.title)\n\n"
            if !t.summary.isEmpty { out += "\(t.summary)\n\n" }
            for p in t.points { out += "- \(p)\n" }
            if let f = t.fishbone {
                out += "\n**\(f.question)**\n\n"
                for b in f.branches { out += "- \(b.label)：\(b.detail)\n" }
            }
            out += "\n"
        }
        if !n.conclusions.isEmpty { out += "### \(L("结论"))\n\n" + n.conclusions.map { "- \($0.text)\n" }.joined() + "\n" }
        if !n.todos.isEmpty {
            out += "### \(L("待办"))\n\n" + n.todos.map { "- [ ] \($0.withOwner)\n" }.joined() + "\n"
        }
        if !n.terms.isEmpty {
            out += "### \(L("人名和术语"))\n\n" + n.terms.map { "- **\($0.name)** \($0.note)\n" }.joined() + "\n"
        }
        return out
    }

    static func markdown(_ s: Session) -> String {
        var out = "# \(s.displayTitle)\n\n\(header(s))\n\n"
        let notes = notesMarkdown(s.notes)
        if !notes.isEmpty { out += notes + "## \(L("文字记录"))\n\n" }
        let numbers = speakerNumbers(s), names = SpeakerLabels.names(s)
        for l in s.lines {
            let who = saysWho(s, numbers) ? " \(speakerName(l, numbers, names))" : ""
            out += "**[\(clock(l.t))]\(who)**  \n\(l.shown)\n"
            if let d = l.dst, d != l.shown { out += "> \(d)\n" }
            out += "\n"
        }
        return out
    }

    static func srt(_ s: Session) -> String {
        func ts(_ t: Double) -> String {
            let ms = Int((max(0, t) * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        var out = ""
        for (i, l) in s.lines.enumerated() {
            let next = i + 1 < s.lines.count ? s.lines[i + 1].t : l.t + 4
            let end = max(l.t + 1, min(next, l.t + 8))
            // Your own lines (the talk key) say so, as the record does.
            let tag = l.speaker == "me" ? "[\(L("同传"))] " : ""
            out += "\(i + 1)\n\(ts(l.t)) --> \(ts(end))\n\(tag)\(l.shown)\n"
            if let d = l.dst, d != l.shown { out += "\(d)\n" }
            out += "\n"
        }
        return out
    }

    #if os(macOS)
    // `.officeOpenXML` is macOS-only; iOS needs its own writer (docs/ios-plan.md).
    static func docx(_ s: Session) throws -> Data {
        let doc = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = after
            doc.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: p,
            ]))
        }
        add(s.displayTitle, size: 20, weight: .bold, after: 6)
        add(header(s), size: 10, color: .darkGray, after: 14)
        if let n = s.notes, !n.isEmpty {
            add(L("纪要"), size: 15, weight: .bold, after: 6)
            add(n.summary, size: 11, after: 10)
            for t in n.topics {
                add("\(clock(t.start))  \(t.title)", size: 12, weight: .semibold, after: 3)
                if !t.summary.isEmpty { add(t.summary, size: 11, color: .darkGray, after: 3) }
                for p in t.points { add("• \(p)", size: 11, after: 2) }
                if let f = t.fishbone {
                    add(f.question, size: 11, weight: .semibold, after: 2)
                    for b in f.branches { add("  – \(b.label)：\(b.detail)", size: 11, after: 2) }
                }
                add("", size: 6, after: 4)
            }
            if !n.conclusions.isEmpty {
                add(L("结论"), size: 12, weight: .semibold, after: 3)
                for c in n.conclusions { add("• \(c.text)", size: 11, after: 2) }
            }
            if !n.todos.isEmpty {
                add(L("待办"), size: 12, weight: .semibold, after: 3)
                for t in n.todos { add("☐ \(t.withOwner)", size: 11, after: 2) }
            }
            add(L("文字记录"), size: 15, weight: .bold, after: 6)
        }
        let numbers = speakerNumbers(s), names = SpeakerLabels.names(s)
        for l in s.lines {
            add("[\(clock(l.t))]" + (saysWho(s, numbers) ? " \(speakerName(l, numbers, names))" : ""), size: 9, weight: .semibold, color: .darkGray, after: 2)
            add(l.shown, size: 11, after: 2)
            if let d = l.dst, d != l.shown { add(d, size: 11, color: NSColor(calibratedWhite: 0.3, alpha: 1), after: 10) }
        }
        return try doc.data(from: NSRange(location: 0, length: doc.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }
    #endif
}
