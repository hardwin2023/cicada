import Foundation

// MARK: - Model

/// Meeting notes kept with the session (`session.json` › `notes`). Written by Ling while the
/// meeting runs ("速记版") and rewritten once over the whole transcript when it ends ("完整版").
struct MeetingNotes: Codable, Equatable {
    /// A short name for the meeting in the notes' language (absent in older notes).
    var title: String?
    var summary = ""
    var topics: [NoteTopic] = []
    var conclusions: [NoteItem] = []
    var todos: [NoteItem] = []
    var terms: [NoteTerm] = []
    /// How many transcript lines these notes cover.
    var covered = 0
    var updatedAt: Date?
    var final = false

    var isEmpty: Bool { summary.isEmpty && topics.isEmpty }
}

struct NoteTopic: Codable, Equatable, Identifiable {
    var start: Double
    var title: String
    var summary: String
    var points: [String]
    var fishbone: Fishbone?
    /// When each point was said (its first evidence line), parallel to `points`; older notes have none.
    var pointTimes: [Double?]?
    var id: String { "\(Int(start))-\(title)" }

    func pointTime(_ i: Int) -> Double? { pointTimes.flatMap { i < $0.count ? $0[i] : nil } }
}

/// A cause-and-effect diagram for a topic that discusses why something happened.
struct Fishbone: Codable, Equatable {
    var question: String
    var branches: [FishboneBranch]
}

struct FishboneBranch: Codable, Equatable, Identifiable {
    var label: String
    var detail: String
    var t: Double?
    /// How many transcript lines back this branch; 0 is shown as weak.
    var support: Int
    var id: String { label + detail }
}

struct NoteItem: Codable, Equatable, Identifiable {
    var text: String
    var owner: String?
    var support: Int
    /// When it was said (first evidence line).
    var t: Double?
    var id: String { text }

    /// The owner as stored ("你", "对方", "说话人2" or a name) in the UI language.
    var ownerShown: String? {
        guard let owner else { return nil }
        switch owner {
        case "你": return L("你")
        case "对方": return L("对方")
        case "未识别": return L("未识别")
        default: break
        }
        if owner.hasPrefix("说话人"), let n = Int(owner.dropFirst(3).trimmingCharacters(in: .whitespaces)) { return L("说话人 \(n)") }
        return owner
    }

    /// The to-do with its owner after it: "（对方）" in Chinese, " (Them)" in English.
    var withOwner: String { text + (ownerShown.map { L("待办的负责人 \($0)") } ?? "") }
}

/// A name or term as the notes settled on it, and how speech recognition heard it.
struct NoteTerm: Codable, Equatable, Identifiable {
    var name: String
    var note: String
    var heard: [String]
    var id: String { name }

    /// Corrected spellings first: what a reader can't work out alone.
    static func ordered(_ terms: [NoteTerm]) -> [NoteTerm] {
        terms.filter { !$0.heard.isEmpty } + terms.filter { $0.heard.isEmpty }
    }

    /// The reply's terms in the order they were shown before, new ones after: the model often
    /// returns the same names reshuffled, which would make the chips jump on every update.
    static func keepingOrder(_ old: [NoteTerm], _ new: [NoteTerm]) -> [NoteTerm] {
        let rank = Dictionary(old.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
        return new.enumerated().sorted { a, b in
            (rank[a.element.name] ?? old.count + a.offset, a.offset) < (rank[b.element.name] ?? old.count + b.offset, b.offset)
        }.map(\.element)
    }

    /// Roles that say a term is a person, for offering it as a speaker's name.
    private static let roles = ["首席", "执行官", "主席", "总裁", "董事", "经理", "创始人", "记者", "主持", "研究员",
                                "分析师", "教授", "老师", "教师", "官员", "部长", "议员", "候选人", "嘉宾", "发言人",
                                "CEO", "CFO", "CTO", "host", "analyst", "reporter", "founder"]

    /// Names of people the notes mention, by their note ("BGN 集团首席运营官").
    static func people(_ terms: [NoteTerm]) -> [String] {
        terms.filter { t in roles.contains { t.note.localizedCaseInsensitiveContains($0) } }.map(\.name)
    }
}

// MARK: - Engine

/// Keeps the live session's notes up to date: every ~45 s with new speech, one Ling call sends
/// the current notes plus the new lines and gets the whole updated notes back as JSON. A failed or
/// odd reply never replaces good notes. UI-free; the notes window observes it.
@MainActor
final class NotesEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case updating
        case noKey
        case invalidKey
        case rateLimited
        /// The notes' own request couldn't reach the service (network, proxy, timeout). Another
        /// request failing, such as naming speakers, never sets this.
        case unreachable
        case failed
    }

    @Published private(set) var notes = MeetingNotes()
    @Published private(set) var state: State = .idle
    /// Points and topics that appeared in the last update ("新").
    @Published private(set) var fresh: Set<String> = []
    @Published private(set) var summaryChangedAt: Date?
    /// A finished meeting whose full notes are being written (main window "生成纪要").
    @Published private(set) var generatingID: String?

    let ling: LingClient
    let store: SessionStore
    /// The language a meeting's notes are written in (English name), set by the app from the
    /// 纪要语言 choice.
    var language: (_ sessionID: String) -> String = { _ in "Simplified Chinese" }

    private var sessionID: String?
    /// The session whose notes `notes` shows (stays set after the meeting ends).
    private(set) var shownID: String?
    private var timer: Timer?
    private var inFlight = false
    /// Final passes asked for while another call was running, in order; each runs after it.
    /// Several can wait: an imported file can finish while the meeting's own pass is queued.
    private var pendingFinals: [String] = []
    /// A final pass is over, whether it wrote notes or not (存到文件夹 waits for it).
    var finalDone: ((String) -> Void)?
    /// The final pass for this meeting is running or waiting its turn.
    func settling(_ id: String) -> Bool { generatingID == id || pendingFinals.contains(id) }
    /// A language change that arrived while another update was running: rewrite after it.
    private var pendingRewrite: String?
    private var lastAttempt = Date.distantPast
    private var freshGeneration = 0
    static let interval: TimeInterval = 45
    /// The most topics the final notes have (the prompt says so too; the model doesn't always listen).
    static let maxTopics = 8
    /// The most topics live notes have. Live notes used to stop at `maxTopics` and pour everything
    /// after into the last topic, whose summary then grew into a wall of "最新…又…补充…"; past this,
    /// the two shortest neighbouring settled topics are joined instead, so the newest can start.
    static let liveMaxTopics = 12
    /// A topic summary longer than this is a log the model kept appending to, not one sentence.
    static let topicSummaryLimit = 160
    /// How many of the last topics a live update may rewrite; earlier ones stay as they are.
    static let editableTopics = 2

    init(ling: LingClient, store: SessionStore) {
        self.ling = ling
        self.store = store
    }

    /// Names for the translation glossary: "江充 (heard as 江松, 江冲)".
    var glossary: [String] {
        notes.terms.prefix(30).map { t in
            t.heard.isEmpty ? "\(t.name) (\(t.note))" : "\(t.name) (\(t.note); misheard as \(t.heard.joined(separator: ", ")))"
        }
    }

    func begin(_ id: String) {
        sessionID = id
        shownID = id
        notes = store.session(id)?.notes ?? MeetingNotes()
        fresh = []
        state = ling.hasKey ? .idle : .noKey
        lastAttempt = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// The meeting ended: one last pass over the whole transcript.
    func finish() {
        timer?.invalidate()
        timer = nil
        guard let id = sessionID else { return }
        sessionID = nil
        Task { await update(id, final: true) }
    }

    /// The notes language changed during the meeting: rewrite the whole notes in it now.
    func rewrite() {
        guard let id = sessionID else { return }
        Task { await update(id, final: false, fresh: true) }
    }

    func updateNow() {
        guard let id = sessionID else { return }
        Task { await update(id, final: false) }
    }

    /// Show a stored meeting's notes (the window shows the live meeting when there is one).
    func show(_ id: String) {
        shownID = id
        notes = store.session(id)?.notes ?? MeetingNotes()
        fresh = []
        // A round that failed belongs to the meeting it ran for, not to the record opened now.
        if sessionID == nil, [.failed, .unreachable, .rateLimited].contains(state) { state = .idle }
    }

    /// Notes for a finished meeting that has none (e.g. recorded before a key was set).
    func generate(for id: String) {
        Task { await update(id, final: true) }
    }

    /// Debug control: rebuild a stored meeting's notes the way a live meeting would, a few lines
    /// at a time, then the final pass.
    func replay(_ id: String, step: Int = 4) async {
        guard let count = store.session(id)?.lines.count else { return }
        shownID = id
        notes = MeetingNotes()
        for upto in stride(from: min(step, count), through: count, by: step) {
            await update(id, final: false, upto: upto)
        }
        if count % step != 0 { await update(id, final: false, upto: count) }
        await update(id, final: true)
    }

    private func tick() {
        // A key was added or replaced since the last failure.
        if (state == .noKey || state == .invalidKey), ling.usable, ling.keyState != .checking { state = .idle }
        if state == .idle, !ling.hasKey { state = .noKey }
        // A key that was just checked and refused says so, rather than asking for a key again.
        if state == .noKey || state == .idle, ling.hasKey, ling.keyState == .invalid { state = .invalidKey }
        // The service answers again (the check after a network change, or any other request): the
        // banner goes now, not after the next round, which runs on its usual 45 s.
        if state == .unreachable, ling.aiCheck.failure?.reason != .unreachable { state = .idle }
        guard let id = sessionID, !inFlight else { return }
        guard let s = store.session(id), s.lines.count > notes.covered else { return }
        // First notes as soon as there is something to say, then every 45 s.
        let due = notes.isEmpty ? (s.lines.count >= 3 || Date().timeIntervalSince(lastAttempt) > 20)
                                : Date().timeIntervalSince(lastAttempt) >= Self.interval
        if due { Task { await update(id, final: false) } }
    }

    /// `fresh`: start from nothing (a new notes language); the final pass always does.
    private func update(_ id: String, final: Bool, upto: Int? = nil, fresh: Bool = false) async {
        if inFlight {
            // Never drop the end-of-meeting pass or a "生成纪要" request: queue it.
            if final {
                if !pendingFinals.contains(id) { pendingFinals.append(id) }
                if generatingID == nil { generatingID = id }
            }
            if fresh { pendingRewrite = id }
            return
        }
        guard let session = store.session(id), !session.lines.isEmpty else { if final { finalDone?(id) }; return }
        guard ling.hasKey else { state = .noKey; if final { finalDone?(id) }; return }
        inFlight = true
        lastAttempt = Date()
        state = .updating
        if final { generatingID = id }
        defer {
            inFlight = false
            if final, generatingID == id { generatingID = nil }
            if final { finalDone?(id) }
            if !pendingFinals.isEmpty {
                let next = pendingFinals.removeFirst()
                if pendingRewrite == next { pendingRewrite = nil } // the final pass starts from nothing anyway
                Task { await update(next, final: true) }
            } else if let next = pendingRewrite {
                pendingRewrite = nil
                Task { await update(next, final: false, fresh: true) }
            }
        }

        let lines = Array(session.lines.prefix(upto ?? session.lines.count))
        let base = final || fresh ? MeetingNotes() : (id == shownID ? notes : session.notes ?? MeetingNotes())
        let from = final ? 0 : min(base.covered, lines.count)
        let lang = language(id)
        let names = TranscriptExport.voices ? SpeakerLabels.names(session) : [:]
        let known = SpeakerLabels.knownVoices(session)
        // A live update returns only the last topics: when it rewrote them all, its reply grew with
        // the meeting until, about an hour in, it was cut off at max_tokens or fell into a loop and
        // the notes stopped updating. The final pass still rewrites everything once.
        let frozen = final || fresh ? 0 : max(0, base.topics.count - Self.editableTopics)
        let prompt = Self.prompt(notes: base, lines: lines, from: from, language: lang, final: final, names: names, frozen: frozen, known: known)
        let started = Date()
        do {
            // The final pass sends only the transcript, with no notes in the reader's language to
            // follow: given a long English meeting the model drifts into English. Say the language
            // again where it is read last, and try once more if the reply still isn't in it.
            var next = final ? await longFinal(lines, names: names, known: known, language: lang, startedAt: session.lines.first?.t ?? 0) : nil
            for attempt in 1...(final || fresh ? 2 : 1) where next == nil {
                let raw = try await ling.chat(content: prompt, instruction: "Update the notes. Write them in \(lang).",
                                              priority: .notes, json: true, maxTokens: 6000, timeout: 90, patient: final)
                guard let parsed = Self.parse(raw, times: lines.map(\.t), startedAt: session.lines.first?.t ?? 0) else { break }
                if Self.written(parsed, in: lang) { next = parsed; break }
                debugLog("notes: \(final ? "final" : "live") reply not in \(lang) (attempt \(attempt)), dropped")
            }
            guard var next else {
                debugLog("notes: no usable reply, kept the previous notes")
                state = .failed
                return
            }
            // The notes language changed while this was running: the queued rewrite replaces it.
            guard language(id) == lang else {
                debugLog("notes: language changed during the update, reply dropped")
                state = .idle
                return
            }
            if !final, !fresh { next.topics = Self.merge(base.topics, frozen: frozen, returned: next.topics) }
            if !fresh { next.terms = NoteTerm.keepingOrder((id == shownID ? notes : session.notes)?.terms ?? [], next.terms) }
            next.terms = Self.heardAsSaid(next.terms, lines: lines)
            Self.carryTimes(from: base, into: &next)
            // A reply without a name keeps the last one (not after a language change).
            if next.title == nil, !fresh { next.title = (id == shownID ? notes : session.notes)?.title }
            next.covered = lines.count
            next.updatedAt = Date()
            next.final = final
            if id == shownID {
                markFresh(old: notes, new: next, final: final)
                if next.summary != notes.summary { summaryChangedAt = Date() }
                notes = next
            }
            store.setNotes(id, next)
            state = .idle
            debugLog("notes: \(final ? "final" : "live") update \(lines.count - from) new lines → \(next.topics.count) topics, \(next.terms.count) terms in \(Int(Date().timeIntervalSince(started))) s")
        } catch LingClient.Failure.invalidKey {
            state = .invalidKey
        } catch LingClient.Failure.rateLimited {
            state = .rateLimited
        } catch LingClient.Failure.noKey {
            state = .noKey
        } catch LingClient.Failure.network, LingClient.Failure.timeout {
            debugLog("notes: update can't reach the service")
            state = .unreachable
        } catch {
            debugLog("notes: update failed \(error)")
            state = .failed
        }
    }

    /// A long meeting's final pass: each part noted on its own, all at once, then merged into one.
    /// nil when a step fails: the caller then makes one pass over the whole transcript, as before.
    private func longFinal(_ lines: [TranscriptLine], names: [Int: String], known: Set<Int>, language lang: String,
                           startedAt: Double) async -> MeetingNotes? {
        let parts = Self.parts(lines)
        guard parts.count > 1 else { return nil }
        let started = Date()
        let times = lines.map(\.t)
        var replies = [String?](repeating: nil, count: parts.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, range) in parts.enumerated() {
                let prompt = Self.prompt(notes: MeetingNotes(), lines: Array(lines.prefix(range.upperBound)), from: range.lowerBound,
                                         language: lang, final: true, names: names, part: (i + 1, parts.count), known: known)
                group.addTask { [ling] in
                    let raw = try? await ling.chat(content: prompt, instruction: "Write the notes for this part. Write them in \(lang).",
                                                   priority: .notes, json: true, maxTokens: 6000, timeout: 90)
                    return (i, raw)
                }
            }
            for await (i, raw) in group { replies[i] = raw }
        }
        var notes: [String] = [], topics: [NoteTopic] = []
        for (i, raw) in replies.enumerated() {
            guard let raw, let parsed = Self.parse(raw, times: times, startedAt: startedAt), !parsed.topics.isEmpty,
                  let a = raw.firstIndex(of: "{"), let b = raw.lastIndex(of: "}") else {
                debugLog("notes: final part \(i + 1)/\(parts.count) failed, one pass instead")
                return nil
            }
            // Without its topics: given them, the merge wrote them all back out and was cut off.
            guard var part = try? JSONSerialization.jsonObject(with: Data(raw[a...b].utf8)) as? [String: Any] else { return nil }
            part["topics"] = nil
            guard let data = try? JSONSerialization.data(withJSONObject: part), let text = String(data: data, encoding: .utf8) else { return nil }
            notes.append(text)
            topics += Self.thinned(parsed.topics, to: Self.partTopics(parts.count), end: lines[parts[i].upperBound - 1].t)
        }
        let voices = TranscriptExport.voices && !SpeakerLabels.numbers(lines).isEmpty
        let prompt = Self.mergePrompt(parts: notes, lines: lines, language: lang, voices: voices)
        for attempt in 1...2 {
            guard let raw = try? await ling.chat(content: prompt, instruction: "Merge the notes. Write them in \(lang).",
                                                 priority: .notes, json: true, maxTokens: 6000, timeout: 90),
                  var merged = Self.parse(raw, times: times, startedAt: startedAt) else { break }
            merged.topics = topics
            if Self.written(merged, in: lang) {
                debugLog("notes: final in \(parts.count) parts → \(merged.topics.count) topics in \(Int(Date().timeIntervalSince(started))) s")
                return merged
            }
            debugLog("notes: merged reply not in \(lang) (attempt \(attempt)), dropped")
        }
        debugLog("notes: merging \(parts.count) parts failed, one pass instead")
        return nil
    }

    /// "新" marks what the last live update added, for a minute. The final pass rewrites
    /// everything, so it marks nothing.
    private func markFresh(old: MeetingNotes, new: MeetingNotes, final: Bool) {
        freshGeneration += 1
        guard !old.isEmpty, !final else { fresh = []; return }
        let before = Set(old.topics.flatMap { [$0.title] + $0.points })
        fresh = Set(new.topics.flatMap { [$0.title] + $0.points }).subtracting(before)
        let generation = freshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated {
                if self?.freshGeneration == generation { self?.fresh = [] }
            }
        }
    }

    /// A live reply's topics after the `frozen` ones it was told to leave alone: with some frozen, at
    /// most the editable ones plus one new, from the end (the model sometimes echoes the whole list),
    /// never a copy of a frozen one, each summary kept to one sentence; and no more than
    /// `liveMaxTopics` in all (past that, settled neighbours are joined). A reply with no topics of
    /// its own keeps the ones it had.
    static func merge(_ old: [NoteTopic], frozen: Int, returned: [NoteTopic]) -> [NoteTopic] {
        var kept = Array(old.prefix(frozen))
        let fixed = Set(kept.map(\.title))
        let own = returned.filter { !fixed.contains($0.title) }
        var tail = kept.isEmpty ? own : Array(own.suffix(old.count - kept.count + 1))
        guard !tail.isEmpty else { return old }
        for i in tail.indices { tail[i].summary = shortened(tail[i].summary) }
        tail = capped(tail, to: liveMaxTopics - min(kept.count, 1))
        while kept.count + tail.count > liveMaxTopics, kept.count >= 2 {
            // The pair spanning the least time, its end being the next topic's start.
            let ends = kept.dropFirst().map(\.start) + [tail[0].start]
            let i = (0..<kept.count - 1).min { ends[$0 + 1] - kept[$0].start < ends[$1 + 1] - kept[$1].start }!
            kept[i] = joined(kept[i], kept[i + 1])
            kept.remove(at: i + 1)
        }
        return capped(kept + tail, to: liveMaxTopics)
    }

    /// Two neighbouring topics as one: both titles and summaries, and up to the 4 points the prompt
    /// allows, taken evenly from each.
    static func joined(_ a: NoteTopic, _ b: NoteTopic) -> NoteTopic {
        let fromA = min(a.points.count, max(2, 4 - b.points.count))
        let fromB = min(b.points.count, 4 - fromA)
        let times = (0..<fromA).map(a.pointTime) + (0..<fromB).map(b.pointTime)
        let gap = a.summary.last.map { "。！？；".contains($0) } ?? true ? "" : " "
        return NoteTopic(start: a.start, title: "\(a.title) / \(b.title)", summary: a.summary + gap + b.summary,
                         points: Array(a.points.prefix(fromA) + b.points.prefix(fromB)), fishbone: a.fishbone ?? b.fishbone,
                         pointTimes: times.contains { $0 != nil } ? times : nil)
    }

    /// Terms keep only the heard forms the recognizer really wrote (`src`). The notes read lines
    /// with fixes in, so a wrong fix came back as a heard form ("X平台 heard as platform"), went to
    /// the translator and the next fix's request as a known mishearing, and was proposed again.
    static func heardAsSaid(_ terms: [NoteTerm], lines: [TranscriptLine]) -> [NoteTerm] {
        terms.map { t in
            var t = t
            t.heard = t.heard.filter { h in lines.contains { $0.src.localizedCaseInsensitiveContains(h) } }
            return t
        }
    }

    /// A runaway topic summary cut back to its first sentence (or to the limit, with "…").
    static func shortened(_ summary: String) -> String {
        guard summary.count > topicSummaryLimit else { return summary }
        let head = summary.prefix(topicSummaryLimit)
        if let end = head.dropFirst(10).firstIndex(where: { "。！？；.!?;".contains($0) }) { return String(head[...end]) }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// At most `count` topics (at least one): the points of any after that go into the last kept.
    static func capped(_ topics: [NoteTopic], to count: Int) -> [NoteTopic] {
        var topics = topics
        while topics.count > max(1, count) {
            let extra = topics.removeLast()
            var last = topics.removeLast()
            let times = (0..<last.points.count).map(last.pointTime) + (0..<extra.points.count).map(extra.pointTime)
            last.points += extra.points
            last.pointTimes = times.contains { $0 != nil } ? times : nil
            topics.append(last)
        }
        return topics
    }

    /// The model echoes points it already had without evidence: keep the times they had.
    static func carryTimes(from old: MeetingNotes, into new: inout MeetingNotes) {
        var known: [String: Double] = [:]
        for t in old.topics { for (i, p) in t.points.enumerated() { if let x = t.pointTime(i) { known[p] = x } } }
        for (ti, t) in new.topics.enumerated() {
            // A point keeps the time it was first heard: a later mention never moves it later.
            let times = t.points.enumerated().map { i, p in [t.pointTime(i), known[p]].compactMap { $0 }.min() }
            new.topics[ti].pointTimes = times.contains { $0 != nil } ? times : nil
            // The reply dates a topic from the lines it cites now, often only the latest: it starts no
            // later than its first point, or its range runs minutes past what was said in it.
            if let first = times.compactMap({ $0 }).min(), first < t.start { new.topics[ti].start = first }
        }
        let items = Dictionary((old.conclusions + old.todos).compactMap { i in i.t.map { (i.text, $0) } }, uniquingKeysWith: { a, _ in a })
        func earliest(_ a: Double?, _ b: Double?) -> Double? { [a, b].compactMap { $0 }.min() }
        for i in new.conclusions.indices { new.conclusions[i].t = earliest(new.conclusions[i].t, items[new.conclusions[i].text]) }
        for i in new.todos.indices { new.todos[i].t = earliest(new.todos[i].t, items[new.todos[i].text]) }
    }

    // MARK: Prompt

    static func clock(_ t: Double) -> String { TranscriptExport.clock(t) }

    /// `part`: in a long meeting's final pass, which part `from..<lines.count` is (1-based, of `of`).
    static func prompt(notes: MeetingNotes, lines: [TranscriptLine], from: Int, language: String, final: Bool,
                       names: [Int: String] = [:], frozen: Int = 0, part: (index: Int, of: Int)? = nil,
                       known: Set<Int> = []) -> String {
        let numbers = TranscriptExport.voices ? SpeakerLabels.numbers(lines, known: known) : [:]
        func line(_ i: Int) -> String {
            let l = lines[i]
            // A named voice goes as its name: notes then say "George" rather than "说话人2".
            let who = l.speaker == "me" ? "你" : numbers[l.id].map { names[$0] ?? "说话人\($0)" } ?? (numbers.isEmpty ? "对方" : "未识别")
            return "[L\(i + 1) \(clock(l.t)) \(who)] \(l.shown)"
        }
        var current = "{}"
        if !notes.isEmpty, let data = try? JSONEncoder().encode(Compact(notes, from: frozen)), let s = String(data: data, encoding: .utf8) {
            current = s
        }
        let context = max(0, from - 2)
        let task = part.map { "that has just ended. It was long, so it is noted in parts: write the notes for part \($0.index) of \($0.of) only, from the lines below" }
            ?? (final ? "that has just ended. Rewrite them from the whole transcript" : "that is still going on. Update them with the new lines")
        var p = """
        You keep notes for a meeting \(task).
        Write the notes in \(language). Return JSON only.

        """
        if !final {
            if frozen > 0 {
                p += "Earlier topics (settled: kept as they are, do not return them):\n"
                    + notes.topics.prefix(frozen).map { "- \(clock($0.start)) \($0.title): \($0.summary)" }.joined(separator: "\n") + "\n\n"
            }
            p += "Current notes (JSON\(frozen > 0 ? ", latest topics only" : "")):\n\(current)\n\n"
        }
        if context < from {
            p += "Already covered (context only):\n" + (context..<from).map(line).joined(separator: "\n") + "\n\n"
        }
        p += "\(final ? "Transcript" : "New lines") (id, mm:ss, speaker 对方=the other side / 你=me / a name or 说话人N=one person on the other side, told apart by voice and possibly wrong / 未识别=someone on the other side not identified, text). Speech recognition makes mistakes, often in names: correct them from context, and write a public figure's name as the news spells it.\n"
        p += (from..<lines.count).map(line).joined(separator: "\n")
        // The model splits too eagerly when only told how long a topic should be: say plainly
        // whether this update may start one.
        if final, from < lines.count, let last = lines.last?.t {
            let first = lines[from].t
            let most = max(1, min(part.map { partTopics($0.of) } ?? maxTopics, Int((last - first) / 180) + 1))
            p += "\n\nThis \(part == nil ? "meeting" : "part") ran \(clock(last - first)): use at most \(most) topic\(most == 1 ? "" : "s")."
        } else if !final, let current = notes.topics.last, let newest = lines.last?.t, newest - current.start < 120 {
            p += "\n\nThe current topic \"\(current.title)\" started at \(clock(current.start)), under 2 minutes ago: do not start a new topic in this update; add the new lines to it."
        } else if !final, notes.topics.isEmpty {
            p += "\n\nThese are the first lines: make one topic."
        }
        p += "\n\n" + format(language: language, voices: !numbers.isEmpty, final: final, frozen: frozen)
        return p
    }

    /// The reply's JSON shape and the rules for its contents.
    private static func format(language: String, voices: Bool, final: Bool, frozen: Int) -> String {
        """
        Return the full notes as one JSON object with exactly these keys:
        {"title": "the meeting's name: what it is about, a few words",
         "summary": "2-3 sentences on the whole meeting so far",
         "topics": [{"start": seconds, "title": "short title", "summary": "one sentence on the whole topic", "points": [{"text": "key point", "evidence": ["L4"]}], "evidence": ["L3"],
                     "fishbone": null or {"question": "the problem or question", "branches": [{"label": "2-6 words", "detail": "one short line", "t": seconds, "evidence": ["L5"]}]}}],
         "conclusions": [{"text": "...", "evidence": ["L7", "L8"]}],
         "todos": [{"text": "...", "owner": \(!voices ? "\"对方\" or \"你\" or null" : "the person's label from the transcript (a name like \"George\", or \"说话人2\"), \"你\", or null when unclear"), "evidence": ["L9"]}],
         "terms": [{"name": "correct spelling", "note": "who or what, a few words", "heard": ["how it was misrecognised"]}]}
        Rules (be brief: these notes are read at a glance during the meeting):
        - title: a name for the whole meeting, like a calendar entry (at most 12 Chinese characters or 6 words; no date, no quotes, not "会议" alone). Keep the current title unless the meeting's subject has clearly changed.
        - summary: at most 3 short sentences.
        - Topics in time order, \(frozen > 0 ? "returning only the topics in the current notes and at most one new one after them" : "at most \(maxTopics) in total"). A topic is a stretch of the meeting, usually 3-10 minutes, not a single remark: start a new one only when the subject clearly changes and the current topic started at least 2 minutes before the newest line\(final ? "" : "; add at most one new topic per update"). Otherwise add to the current one, and merge small neighbouring topics. Keep earlier topics as they are unless new lines correct them. The last topic is the one being discussed now.
        - A topic's summary is one sentence on the whole topic, at most 40 Chinese characters or 25 words: as the topic grows, rewrite it; never append to it or narrate what came next ("最新", "又", "补充", "then", "later").
        - At most 4 points per topic, each one short phrase. Merge rather than repeat.
        - At most 5 conclusions and only real to-dos (often none).
        - Add a fishbone only to a topic that discusses causes, reasons or factors (3-5 branches); otherwise null.
        - Every topic, point, branch, conclusion and to-do needs evidence: the ids of the lines that say it. Never state anything the transcript does not say.
        - terms: at most 10 in total, replacing less useful ones rather than adding: first names the transcript misspells (heard), then the people, places and jargon a reader would not know. Leave out what everyone knows (a famous company, index or politician) unless it was misheard. name is the correct spelling in the transcript's language (no translation in brackets); heard lists only the wrong forms the transcript used, and only of that same thing: a name said again and again in one spelling that context doesn't tie to a known one ("我们 twoty", "our platform") is a thing of its own, its own term with that spelling, not a mishearing of a similar name; note is a few words.
        - Write the meeting title and every summary, title, point, branch, conclusion and to-do in \(language), even when the transcript is in another language. Only term names keep the transcript's spelling.
        - Write about what was said, never about the transcript or recognition quality.
        - Use empty arrays when there is nothing. No markdown, no text outside the JSON.
        """
    }

    // MARK: Long meetings

    /// How a long meeting's final pass is split: over `splitMinutes`, into equal parts by time of at
    /// most `partMinutes`. One pass covered a 91-minute meeting but only the first hour of a 4-hour one.
    static let splitMinutes = 100.0
    static let partMinutes = 60.0
    static func parts(_ lines: [TranscriptLine]) -> [Range<Int>] {
        guard let first = lines.first?.t, let last = lines.last?.t else { return [] }
        let minutes = (last - first) / 60
        guard minutes > splitMinutes else { return [0..<lines.count] }
        let count = Int((minutes / partMinutes).rounded(.up))
        let length = (last - first) / Double(count)
        var bounds = [0]
        for k in 1..<count {
            let at = first + length * Double(k)
            if let i = lines.firstIndex(where: { $0.t >= at }), i > bounds.last! { bounds.append(i) }
        }
        bounds.append(lines.count)
        return zip(bounds, bounds.dropFirst()).map { $0..<$1 }
    }

    /// Each part's share of the topics: the merge keeps them as they are, so every part has some.
    static func partTopics(_ parts: Int) -> Int { max(2, maxTopics / max(1, parts)) }

    /// At most `count` of a part's `topics`, neighbours joined: a part's reply often has more topics
    /// than asked. Keeping the first ones lost the end of the part, and keeping some spread from first
    /// to last kept a topic's "（续）" stub at the part's end and dropped the topic itself. The same
    /// subject twice is joined first, under the first one's title; then the pair spanning the least
    /// time (to the next topic's start, or `end` for the last), as live notes do.
    static func thinned(_ topics: [NoteTopic], to count: Int, end: Double) -> [NoteTopic] {
        var topics = topics
        while topics.count > max(1, count) {
            let pairs = 0..<topics.count - 1
            func span(_ i: Int) -> Double { (i + 2 < topics.count ? topics[i + 2].start : end) - topics[i].start }
            let same = pairs.first { subject(topics[$0].title) == subject(topics[$0 + 1].title) }
            let i = same ?? pairs.min { span($0) < span($1) }!
            var one = joined(topics[i], topics[i + 1])
            if same != nil { (one.title, one.summary) = (topics[i].title, topics[i].summary) }
            topics[i] = one
            topics.remove(at: i + 1)
        }
        return topics
    }

    /// A topic title without a trailing bracket ("预算评审（续）", "Budget (cont.)"): what it is about.
    static func subject(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard let close = t.last, "）)".contains(close), let open = t.lastIndex(where: { "（(".contains($0) }),
              open > t.startIndex else { return t }
        return t[..<open].trimmingCharacters(in: .whitespaces)
    }

    /// The whole meeting's title, summary, conclusions, to-dos and terms from its parts' notes (the
    /// replies as they came, with their evidence line ids). Asked to merge topics too, the model
    /// kept the first parts' and dropped the rest, so topics are joined in code.
    static func mergePrompt(parts: [String], lines: [TranscriptLine], language: String, voices: Bool) -> String {
        var p = """
        You keep notes for a meeting that has just ended. It was long, so each part was noted on its own; below are those notes, in time order (JSON; evidence ids are transcript lines, L1 the first). Merge them into the notes for the whole meeting.
        Write the notes in \(language). Return JSON only.


        """
        for (i, part) in parts.enumerated() { p += "Part \(i + 1) of \(parts.count):\n\(part)\n\n" }
        if let first = lines.first?.t, let last = lines.last?.t {
            p += "This meeting ran \(clock(last - first)). Return \"topics\": []: the parts' topics are kept as they are. Name and summarise the whole meeting, every part of it; keep each conclusion, to-do and term once, with the evidence ids it had (joined when you merge two).\n\n"
        }
        return p + format(language: language, voices: voices, final: true, frozen: 0)
    }

    /// Whether the notes' own words (summary, titles) are in `language`: Chinese, Japanese and
    /// Korean need a fair share of CJK (names and numbers stay Latin), other languages must not be mostly CJK.
    static func written(_ notes: MeetingNotes, in language: String) -> Bool {
        let text = ([notes.summary] + notes.topics.map(\.title)).joined()
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return true }
        let cjk = letters.filter { (0x3040...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }.count
        let wantsCJK = ["Chinese", "Japanese", "Korean"].contains { language.contains($0) }
        return wantsCJK ? cjk * 5 >= letters.count : cjk * 2 < letters.count
    }

    /// The current notes as sent back to the model (no bookkeeping fields).
    private struct Compact: Encodable {
        let title: String?
        let summary: String
        let topics: [Topic]
        let conclusions: [String]
        let todos: [String]
        let terms: [NoteTerm]
        struct Topic: Encodable {
            let start: Double
            let title: String
            let summary: String
            let points: [String]
            let fishbone: Fishbone?
        }
        /// `from`: the first topic sent (earlier ones go as a list of titles).
        init(_ n: MeetingNotes, from: Int = 0) {
            title = n.title
            summary = n.summary
            topics = n.topics.dropFirst(from).map { Topic(start: $0.start, title: $0.title, summary: $0.summary, points: $0.points, fishbone: $0.fishbone) }
            conclusions = n.conclusions.map(\.text)
            todos = n.todos.map(\.text)
            terms = n.terms
        }
    }

    // MARK: Parse

    /// Lenient: missing keys become empty, evidence ids are checked against the transcript.
    static func parse(_ raw: String, times: [Double], startedAt: Double) -> MeetingNotes? {
        let lineCount = times.count
        var text = raw
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}") { text = String(text[a...b]) }
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ v: Any?) -> String { (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
        func lineNumbers(_ v: Any?) -> Set<Int> {
            let ids = (v as? [Any])?.compactMap { $0 as? String } ?? []
            return Set(ids.compactMap { id -> Int? in
                guard let n = Int(id.drop(while: { !$0.isNumber })), n >= 1, n <= lineCount else { return nil }
                return n
            })
        }
        func support(_ v: Any?) -> Int { lineNumbers(v).count }
        /// When it was first said: the earliest evidence line.
        func time(_ v: Any?) -> Double? { lineNumbers(v).min().map { times[$0 - 1] } }
        var n = MeetingNotes()
        n.summary = str(root["summary"])
        let title = str(root["title"]).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”「」《》"))
        n.title = title.isEmpty ? nil : title
        n.topics = (root["topics"] as? [[String: Any]] ?? []).compactMap { t in
            let title = str(t["title"])
            guard !title.isEmpty else { return nil }
            var fish: Fishbone?
            if let f = t["fishbone"] as? [String: Any] {
                let branches = (f["branches"] as? [[String: Any]] ?? []).compactMap { b -> FishboneBranch? in
                    let label = str(b["label"])
                    // From its lines, as a point's: the model's own "t" came back past the meeting's end.
                    return label.isEmpty ? nil : FishboneBranch(label: label, detail: str(b["detail"]), t: time(b["evidence"]) ?? num(b["t"]),
                                                                support: support(b["evidence"]))
                }
                if branches.count >= 2 { fish = Fishbone(question: str(f["question"]), branches: branches) }
            }
            // Points come as {"text", "evidence"} (or plain strings from older replies).
            var points: [String] = [], pointTimes: [Double?] = []
            for p in t["points"] as? [Any] ?? [] {
                let text = (p as? [String: Any]).map { str($0["text"]) } ?? str(p)
                guard !text.isEmpty else { continue }
                points.append(text)
                pointTimes.append((p as? [String: Any]).flatMap { time($0["evidence"]) })
            }
            // When it was first said, from its lines: the model's own `start` drifts by tens of
            // minutes in a long meeting (a topic said at 51-85 min came back as starting at 23).
            let said = ([time(t["evidence"])] + pointTimes).compactMap { $0 }.min()
            return NoteTopic(start: said ?? num(t["start"]) ?? startedAt, title: title, summary: str(t["summary"]),
                             points: points, fishbone: fish,
                             pointTimes: pointTimes.contains { $0 != nil } ? pointTimes : nil)
        }
        func items(_ key: String) -> [NoteItem] {
            (root[key] as? [[String: Any]] ?? []).compactMap { i in
                let text = str(i["text"])
                let owner = str(i["owner"])
                return text.isEmpty ? nil : NoteItem(text: text, owner: owner.isEmpty ? nil : owner, support: support(i["evidence"]),
                                                     t: time(i["evidence"]))
            }
        }
        n.conclusions = items("conclusions")
        n.todos = items("todos")
        n.terms = (root["terms"] as? [[String: Any]] ?? []).compactMap { t in
            let name = str(t["name"])
            let heard = (t["heard"] as? [Any] ?? []).map(str).filter { !$0.isEmpty && $0 != name }
            return name.isEmpty ? nil : NoteTerm(name: name, note: str(t["note"]), heard: heard)
        }
        // The model keeps every term it ever had: bound the glossary, keeping the misheard ones.
        if n.terms.count > 20 { n.terms = Array(NoteTerm.ordered(n.terms).prefix(20)) }
        return n.isEmpty ? nil : n
    }
}
