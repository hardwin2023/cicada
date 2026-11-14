package cicada

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

// The meeting record, field for field the Mac app's `session.json` (SessionStore.swift, Notes.swift),
// so a record moves between the platforms unchanged. Each type maps to and from a JSON object;
// Json.write sorts the keys and leaves out nulls, as the Mac's encoder does.

/// Whole seconds, UTC, "Z": what Swift's `.iso8601` writes (and expects back).
object Iso8601 {
    private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(java.time.ZoneOffset.UTC)
    fun write(at: Instant): String = format.format(at.truncatedTo(ChronoUnit.SECONDS))
    fun read(text: String?): Instant? = try { text?.let { Instant.parse(it) } } catch (_: Exception) { null }
}

class TranscriptLine(
    /// "h<n>-<segment>" for heard lines, "m<n>" for the user's own.
    var id: String = "",
    /// Seconds from the start of the session.
    var t: Double = 0.0,
    /// "them" (what was heard) or "me" (the user's microphone, on the Mac).
    var speaker: String = "them",
    var src: String = "",
    var dst: String? = null,
    var srcLang: String = "",
    var dstLang: String = "",
    /// The other side's voice, as SpeakerTagger grouped it (null: not told apart).
    var voice: Int? = null,
    /// "room": heard by the Mac's room microphone in a 电脑和会议室 meeting; kept so a Mac record
    /// opened here keeps its 现场 / 线上.
    var via: String? = null,
    /// Words the AI service or the user fixed (Correction.kt); `src` stays what was heard. Absent
    /// when none, as the Mac writes it.
    var fixes: MutableList<LineFix>? = null,
) {
    fun copy() = TranscriptLine(id, t, speaker, src, dst, srcLang, dstLang, voice, via, fixes?.map { it.copy() }?.toMutableList())

    /// What the line says once its fixes are in: shown, searched, exported and read by the notes.
    val shown: String get() = fixes?.let { Correction.apply(it, src).text } ?: src

    fun toJson(): Map<String, Any?> = mapOf(
        "id" to id, "t" to t, "speaker" to speaker, "src" to src, "dst" to dst,
        "srcLang" to srcLang, "dstLang" to dstLang, "voice" to voice, "via" to via,
        "fixes" to fixes?.map { it.toJson() },
    )

    companion object {
        fun from(o: Map<String, Any?>) = TranscriptLine(
            id = o["id"].str() ?: "", t = o["t"].num() ?: 0.0, speaker = o["speaker"].str() ?: "them",
            src = o["src"].str() ?: "", dst = o["dst"].str(), srcLang = o["srcLang"].str() ?: "",
            dstLang = o["dstLang"].str() ?: "", voice = o["voice"].int(), via = o["via"].str(),
            fixes = (o["fixes"] as? List<*>)?.mapNotNull { it.obj()?.let(LineFix::from) }?.toMutableList(),
        )
    }
}

class VoiceGuess(var name: String = "", var evidence: String = "") {
    fun toJson(): Map<String, Any?> = mapOf("name" to name, "evidence" to evidence)
    companion object {
        fun from(o: Map<String, Any?>) = VoiceGuess(o["name"].str() ?: "", o["evidence"].str() ?: "")
    }
}

class Session(
    var id: String = "",
    var title: String = "",
    var startedAt: Instant = Instant.now(),
    var endedAt: Instant? = null,
    var lines: MutableList<TranscriptLine> = mutableListOf(),
    var hasAudio: Boolean = false,
    var notes: MeetingNotes? = null,
    var renamed: Boolean? = null,
    var voiceNames: Map<String, String>? = null,
    var voiceGuesses: Map<String, VoiceGuess>? = null,
    /// An imported recording or video on the Mac (its file name, where it was, true until
    /// transcribed); Android imports too (ImportActivity) and writes these as the Mac does.
    var sourceFile: String? = null,
    var sourcePath: String? = null,
    var importing: Boolean? = null,
    /// Heard through the microphone in the room (会议室) for some or all of it.
    var room: Boolean? = null,
    /// Keys this version doesn't know (the Mac's voiceProfiles / voiceSuggestions, newer
    /// fields), written back untouched so saving here never drops another platform's data.
    var extra: Map<String, Any?> = emptyMap(),
) {
    val durationSeconds: Double get() = ((endedAt ?: Instant.now()).toEpochMilli() - startedAt.toEpochMilli()) / 1000.0

    fun toJson(): Map<String, Any?> = extra + mapOf(
        "id" to id, "title" to title, "startedAt" to Iso8601.write(startedAt), "endedAt" to endedAt?.let(Iso8601::write),
        "lines" to lines.map { it.toJson() }, "hasAudio" to hasAudio, "notes" to notes?.toJson(), "renamed" to renamed,
        "voiceNames" to voiceNames, "voiceGuesses" to voiceGuesses?.mapValues { it.value.toJson() },
        "sourceFile" to sourceFile, "sourcePath" to sourcePath, "importing" to importing, "room" to room,
    )

    companion object {
        fun from(o: Map<String, Any?>) = Session(
            id = o["id"].str() ?: "", title = o["title"].str() ?: "",
            startedAt = Iso8601.read(o["startedAt"].str()) ?: Instant.EPOCH, endedAt = Iso8601.read(o["endedAt"].str()),
            lines = o["lines"].arr().mapNotNull { it.obj()?.let(TranscriptLine::from) }.toMutableList(),
            hasAudio = o["hasAudio"].bool() ?: false, notes = o["notes"].obj()?.let(MeetingNotes::from),
            renamed = o["renamed"].bool(),
            voiceNames = o["voiceNames"].obj()?.mapValues { it.value.str() ?: "" },
            voiceGuesses = o["voiceGuesses"].obj()?.mapValues { VoiceGuess.from(it.value.obj() ?: emptyMap()) },
            sourceFile = o["sourceFile"].str(), sourcePath = o["sourcePath"].str(),
            importing = o["importing"].bool(), room = o["room"].bool(),
            extra = o.filterKeys { it !in KEYS },
        )

        private val KEYS = setOf("id", "title", "startedAt", "endedAt", "lines", "hasAudio", "notes", "renamed",
            "voiceNames", "voiceGuesses", "sourceFile", "sourcePath", "importing", "room")

        fun read(text: String): Session? = Json.parseObject(text)?.let(::from)
    }
}

/// Written by Ling while the meeting runs, rewritten over the whole transcript when it ends.
class MeetingNotes(
    var title: String? = null,
    var summary: String = "",
    var topics: MutableList<NoteTopic> = mutableListOf(),
    var conclusions: MutableList<NoteItem> = mutableListOf(),
    var todos: MutableList<NoteItem> = mutableListOf(),
    var terms: MutableList<NoteTerm> = mutableListOf(),
    /// How many transcript lines these notes cover.
    var covered: Int = 0,
    var final: Boolean = false,
    var updatedAt: Instant? = null,
) {
    val isEmpty get() = summary.isEmpty() && topics.isEmpty()

    fun toJson(): Map<String, Any?> = mapOf(
        "title" to title, "summary" to summary, "topics" to topics.map { it.toJson() },
        "conclusions" to conclusions.map { it.toJson() }, "todos" to todos.map { it.toJson() },
        "terms" to terms.map { it.toJson() }, "covered" to covered, "final" to final,
        "updatedAt" to updatedAt?.let(Iso8601::write),
    )

    companion object {
        fun from(o: Map<String, Any?>) = MeetingNotes(
            title = o["title"].str(), summary = o["summary"].str() ?: "",
            topics = o["topics"].arr().mapNotNull { it.obj()?.let(NoteTopic::from) }.toMutableList(),
            conclusions = o["conclusions"].arr().mapNotNull { it.obj()?.let(NoteItem::from) }.toMutableList(),
            todos = o["todos"].arr().mapNotNull { it.obj()?.let(NoteItem::from) }.toMutableList(),
            terms = o["terms"].arr().mapNotNull { it.obj()?.let(NoteTerm::from) }.toMutableList(),
            covered = o["covered"].int() ?: 0, final = o["final"].bool() ?: false, updatedAt = Iso8601.read(o["updatedAt"].str()),
        )
    }
}

class NoteTopic(
    var start: Double = 0.0,
    var title: String = "",
    var summary: String = "",
    var points: MutableList<String> = mutableListOf(),
    /// When each point was said (its first evidence line), parallel to points.
    var pointTimes: MutableList<Double?>? = null,
    var fishbone: Fishbone? = null,
) {
    fun pointTime(i: Int): Double? = pointTimes?.getOrNull(i)

    // pointTimes keeps its nulls: Swift writes [12.4, null].
    fun toJson(): Map<String, Any?> = mapOf(
        "start" to start, "title" to title, "summary" to summary, "points" to points,
        "pointTimes" to pointTimes, "fishbone" to fishbone?.toJson(),
    )

    companion object {
        fun from(o: Map<String, Any?>) = NoteTopic(
            start = o["start"].num() ?: 0.0, title = o["title"].str() ?: "", summary = o["summary"].str() ?: "",
            points = o["points"].arr().mapNotNull { it.str() }.toMutableList(),
            pointTimes = (o["pointTimes"] as? List<*>)?.map { it.num() }?.toMutableList(),
            fishbone = o["fishbone"].obj()?.let(Fishbone::from),
        )
    }
}

class Fishbone(var question: String = "", var branches: MutableList<FishboneBranch> = mutableListOf()) {
    fun toJson(): Map<String, Any?> = mapOf("question" to question, "branches" to branches.map { it.toJson() })
    companion object {
        fun from(o: Map<String, Any?>) = Fishbone(o["question"].str() ?: "", o["branches"].arr().mapNotNull { it.obj()?.let(FishboneBranch::from) }.toMutableList())
    }
}

class FishboneBranch(
    var label: String = "",
    var detail: String = "",
    var t: Double? = null,
    /// How many transcript lines back this branch; 0 is shown as weak.
    var support: Int = 0,
) {
    fun toJson(): Map<String, Any?> = mapOf("label" to label, "detail" to detail, "t" to t, "support" to support)
    companion object {
        fun from(o: Map<String, Any?>) = FishboneBranch(o["label"].str() ?: "", o["detail"].str() ?: "", o["t"].num(), o["support"].int() ?: 0)
    }
}

class NoteItem(
    var text: String = "",
    var owner: String? = null,
    var support: Int = 0,
    /// When it was said (first evidence line).
    var t: Double? = null,
) {
    fun toJson(): Map<String, Any?> = mapOf("text" to text, "owner" to owner, "support" to support, "t" to t)

    /// The owner as stored ("你", "对方", "说话人2" or a name) in the UI language.
    val ownerShown: String? get() {
        val o = owner ?: return null
        when (o) { "你", "对方", "未识别" -> return Strings.L(o) }
        if (o.startsWith("说话人")) o.substring(3).trim().toIntOrNull()?.let { return Strings.LF("说话人 %lld", it) }
        return o
    }

    /// The to-do with its owner after it: "（对方）" in Chinese, " (Them)" in English.
    val withOwner: String get() = text + (ownerShown?.let { Strings.LF("待办的负责人 %@", it) } ?: "")

    companion object {
        fun from(o: Map<String, Any?>) = NoteItem(o["text"].str() ?: "", o["owner"].str(), o["support"].int() ?: 0, o["t"].num())
    }
}

/// A name or term as the notes settled on it, and how speech recognition heard it.
class NoteTerm(var name: String = "", var note: String = "", var heard: MutableList<String> = mutableListOf()) {
    fun toJson(): Map<String, Any?> = mapOf("name" to name, "note" to note, "heard" to heard)

    companion object {
        fun from(o: Map<String, Any?>) = NoteTerm(o["name"].str() ?: "", o["note"].str() ?: "", o["heard"].arr().mapNotNull { it.str() }.toMutableList())

        /// Corrected spellings first: what a reader can't work out alone.
        fun ordered(terms: List<NoteTerm>) = terms.filter { it.heard.isNotEmpty() } + terms.filter { it.heard.isEmpty() }

        /// The reply's terms in the order they were shown before, new ones after: the model often
        /// returns the same names reshuffled, which would make the chips jump on every update.
        fun keepingOrder(old: List<NoteTerm>, new: List<NoteTerm>): List<NoteTerm> {
            val rank = HashMap<String, Int>()
            old.forEachIndexed { i, t -> rank.putIfAbsent(t.name, i) }
            return new.withIndex().sortedWith(compareBy({ rank[it.value.name] ?: (old.size + it.index) }, { it.index })).map { it.value }
        }
    }
}
