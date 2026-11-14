package cicada

import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/// Listening end to end: audio → segments → the AI service's hear model (Ming on Ling: language,
/// original, translation in one call) → lines in the record, plus live notes. UI-free; the app shows the record and listens to
/// `onChange` (called on worker threads: post to the main thread).
///
/// Ming takes ~2.2 s whatever the segment's length, so segments overlap in flight: request starts
/// still go through LingClient's gate, and lines are delivered in segment order.
class ListenEngine(
    private val ling: LingClient,
    private val translator: Translator,
    private val store: SessionStore,
    private val notes: NotesEngine,
    private val settings: AppSettings,
) {
    private val gate = Any()
    private val pool = Executors.newCachedThreadPool { r -> Thread(r, "Listen").apply { isDaemon = true } }
    private var source: AudioSource? = null
    private var audio: LinkedBlockingQueue<ShortArray>? = null
    private var worker: Thread? = null
    private val done = HashMap<Int, Heard?>()
    private val segments = HashMap<Int, Segment>()
    private val inFlight = mutableListOf<Future<*>>()
    private var nextToDeliver = 1
    private var lineCount = 0
    private var last: TranscriptLine? = null
    private var lastEnd = 0.0
    private var hint: String? = null
    private var candidate: String? = null
    private var candidateVotes = 0
    private val listeners = mutableListOf<() -> Unit>()
    /// One thread records delivered lines, so lines (and their voices) go in strictly in segment order.
    private val deliverLock = Any()

    /// 说话人识别 (Speakers.kt), set by the app; null or unavailable leaves every line 对方.
    @Volatile var speakers: SpeakerTagger? = null
    /// 改正听错的词, set by the app: the word list's forms fixed as lines arrive, and the service's
    /// proposals with each finished line's translation (null: no fixing at all).
    @Volatile var fixes: LiveFixes? = null
    /// A line got a voice (the meeting's id): the app asks Ling for names.
    @Volatile var onVoice: ((String) -> Unit)? = null
    /// Voiceprints one at a time beside Ming (each already uses up to four cores).
    private val voicePool = Executors.newSingleThreadExecutor { r -> Thread(r, "Voiceprints").apply { isDaemon = true } }
    private val voiceprints = HashMap<Int, Future<FloatArray?>>()
    private var voicesWaiting = 0
    private val voicesOn: Boolean get() = settings.speakerVoices && speakers?.available == true

    @Volatile var listening = false; private set
    @Volatile var sessionId: String? = null; private set
    /// What this meeting is heard from ("playback", "mic", "file").
    @Volatile var sourceKind: String? = null; private set
    /// The meeting's language so far (null until Ming has heard something).
    val spoken: String? get() = synchronized(gate) { hint }
    /// Segments sent and not yet back: the UI shows "…" while this is above zero.
    val pending: Int get() = synchronized(gate) { segments.size }
    /// The last error worth showing ("Ling key 无效", "连不上 ZenMux"), cleared by the next good reply.
    @Volatile var problem: String? = null; private set
    /// What kind it is ("key", "busy", "network"), for the screens to pick an icon by.
    @Volatile var problemKind: String? = null; private set
    /// Stretches in a row the service answered with a 5xx (under `gate`).
    private var serverErrors = 0
    @Volatile var level = 0.0; private set
    /// Seconds of audio heard this meeting (the capture is alive while this grows).
    @Volatile var heardSeconds = 0.0; private set
    /// The loudest recent level: 0 for a while means the source is silent (e.g. an app that blocks capture).
    @Volatile var peak = 0.0; private set

    /// Compresses a segment before upload (the app sets AAC: WAV is ~10x larger, ~146 MB an hour
    /// of speech on mobile data). Null or a throw falls back to WAV, which Ming always takes. Only
    /// for Ling: the other services' `input_audio` is WAV (Qwen, Gemini and Doubao were tested
    /// with WAV only), so they cost the bigger upload.
    @Volatile var encoder: (ShortArray) -> Clip? = { null }

    // The notes' language is read from 设置 when they're written, from launch on: notes generated
    // for an old meeting before anything was listened to used to fall back to Simplified Chinese.
    init {
        translator.glossary = { notes.glossary() }
        notes.language = { Languages.englishName(settings.notesCode) }
    }

    fun onChange(listener: () -> Unit) { synchronized(listeners) { listeners.add(listener) } }
    private fun changed() { synchronized(listeners) { listeners.toList() }.forEach { it() } }

    val target: String get() = settings.targetCode

    private val END = ShortArray(0)
    // Hold and release go through the audio queue, so buffers recorded before the press stay the
    // other side's and those recorded before the release are still mine.
    private val HOLD = ShortArray(0)
    private val RELEASE = ShortArray(0)

    // MARK: 我说 (面对面 only): hold, say something, release → Ming → spoken in their language.

    /// Words were recognised, theirs or mine (a line arrived or grew): what MeetingEndWatch counts.
    var onWords: (() -> Unit)? = null

    /// Speaks my words to the person in front of me: `text` is always a translation (see `speakable`).
    var onSaid: ((text: String, lang: String) -> Unit)? = null
    /// The button is down.
    @Volatile var holding = false; private set
    /// My words are at Ming.
    @Volatile var saying = false; private set
    /// Set while the phone speaks: the mic would hear the translation as the other side, so the
    /// segmenter gets silence instead.
    @Volatile var muted = false
    /// Why the last press said nothing ("没听清，再说一次"); cleared by the next press.
    @Volatile var sayProblem: String? = null; private set
    private val mine = ArrayList<ShortArray>()
    private var holdStart = 0.0
    private var saidCount = 0

    val canSay: Boolean get() = listening && sourceKind == "mic"

    /// Who I'm talking to speaks the meeting's language; before they have said anything (or when
    /// it is mine), English, or Chinese for an English speaker (the Mac always falls back to English).
    val theirLanguage: String get() {
        val me = target
        val heard = spoken
        if (heard != null && !Languages.same(heard, me)) return heard
        return if (me.startsWith("en")) "zh-CN" else "en"
    }

    fun hold() {
        if (!canSay || holding) return
        holding = true
        sayProblem = null
        audio?.offer(HOLD)
        changed()
    }

    /// The app couldn't speak a translation ("手机没有这个语言的语音").
    fun sayFailed(why: String) { sayProblem = why; changed() }

    /// Debug: audio as if the source had just delivered it (the emulator's microphone is silent).
    fun inject(pcm: ShortArray) {
        var i = 0
        while (i < pcm.size) { audio?.offer(pcm.copyOfRange(i, minOf(pcm.size, i + 1600))); i += 1600 }
    }

    /// Debug (the Mac's `heard:`): a finished sentence as if the hear model gave it untranslated, in
    /// a meeting listening to SilentAudioSource. The record, its translation and fixes, and the
    /// screens all follow, as for a heard line.
    fun debugHeard(text: String, lang: String? = null) {
        val id = sessionId ?: return
        if (!listening) return
        val at = store.get(id)?.let { (System.currentTimeMillis() - it.startedAt.toEpochMilli()) / 1000.0 } ?: 0.0
        val seg = Segment(0, Math.round(at * 10) / 10.0, ShortArray(0))
        pool.execute { synchronized(deliverLock) { record(seg, Heard(lang ?: spoken ?: "zh-CN", text, null), null) }; changed() }
    }

    fun release() {
        if (!holding) return
        holding = false
        audio?.offer(RELEASE)
        changed()
    }

    /// Sees every buffer as heard, on the audio thread (保存会议录音, an import's progress): it
    /// must only hand the buffer on.
    @Volatile var tap: ((ShortArray) -> Unit)? = null

    fun start(from: AudioSource, kind: String) {
        if (listening) return
        val session = store.begin()
        sessionId = session.id
        sourceKind = kind
        synchronized(gate) {
            done.clear(); segments.clear(); inFlight.clear(); voiceprints.clear()
            nextToDeliver = 1; lineCount = 0; last = null; lastEnd = 0.0
            hint = null; candidate = null; candidateVotes = 0; problem = null; problemKind = null; serverErrors = 0
        }
        holding = false; saying = false; muted = false; sayProblem = null; saidCount = 0
        heardSeconds = 0.0; peak = 0.0
        notes.begin(session.id)
        speakers?.reset()
        fixes?.meetingStarted()
        // 面对面: the line follows the room, as the Mac's and Windows' room mic do.
        val segmenter = Segmenter(if (kind == "mic") VoiceGate() else null)
        segmenter.onSegment = ::send
        val queue = LinkedBlockingQueue<ShortArray>()
        audio = queue
        // One worker owns the segmenter: audio callbacks only queue buffers.
        worker = Thread({
            var mineOpen = false
            while (true) {
                val buf = queue.take()
                if (buf === END) break
                if (buf === HOLD) { mineOpen = true; synchronized(mine) { mine.clear() }; holdStart = heardSeconds; continue }
                if (buf === RELEASE) { if (mineOpen) { mineOpen = false; finishSaying() }; continue }
                if (mineOpen) synchronized(mine) { mine.add(buf) }
                // Silence, not nothing, so the segmenter's clock keeps step with the meeting's.
                segmenter.feed(if (mineOpen || muted) ShortArray(buf.size) else buf)
                level = Wav.rms(buf)
                peak = maxOf(peak * 0.995, level)
                heardSeconds += buf.size / Segmenter.RATE.toDouble()
            }
            segmenter.flush()
        }, "ListenWorker").apply { isDaemon = true; start() }
        source = from
        from.onSamples = { tap?.invoke(it); queue.offer(it) }
        // Listening before the source starts: a source that fails at once calls onEnded → stop(),
        // which must see this meeting as running to end it.
        listening = true
        from.start()
        Log.d("listen: started ${session.id} source=$kind target=$target")
        changed()
    }

    /// Stops listening, waits (briefly) for segments still at Ming, ends the record and starts the
    /// final notes. Blocks until the record is saved: call off the main thread.
    fun stop(endedAt: java.time.Instant? = null) {
        if (!listening) return
        // This meeting's id now: a new one may start while this waits for Ming below.
        val id = sessionId ?: return
        listening = false
        source?.let { it.onSamples = null; it.stop() }
        audio?.offer(END)
        worker?.join(5000)
        val deadline = System.currentTimeMillis() + 15_000
        // Again until none is left: a stretch Ming answers may start its line's fixing request.
        while (System.currentTimeMillis() < deadline) {
            val waiting = synchronized(gate) { inFlight.filter { !it.isDone } }
            if (waiting.isEmpty()) break
            for (f in waiting) {
                try { f.get(maxOf(1, deadline - System.currentTimeMillis()), TimeUnit.MILLISECONDS) } catch (_: Exception) {}
            }
        }
        store.end(id, endedAt)
        Log.d("listen: stopped $id, $lineCount lines")
        changed()
        pool.execute { notes.finish() }
    }

    private fun finishSaying() {
        val pcm = synchronized(mine) {
            val all = ShortArray(mine.sumOf { it.size }); var at = 0
            for (b in mine) { b.copyInto(all, at); at += b.size }
            mine.clear(); all
        }
        // Spoken, not just loud enough: a silent press came back from the service as "嗯" and was said as "Hmm." (the Mac's PressSpeech).
        if (pcm.size < Segmenter.RATE / 2 || !PressSpeech.spoken(pcm)) {
            sayProblem = if (pcm.size < Segmenter.RATE / 2) Strings.L("按住说完再松开") else Strings.L("没听到声音，靠近手机再说")
            changed(); return
        }
        saying = true
        changed()
        val t = Math.round(holdStart * 1000) / 1000.0
        pool.execute { say(pcm, t) }
    }

    private fun say(pcm: ShortArray, t: Double) {
        val id = sessionId ?: run { saying = false; return }
        val their = theirLanguage
        val me = target
        try {
            val heard = translator.hear(encode(pcm), their, me, pcm.size / Segmenter.RATE.toDouble())
            if (heard == null) { sayProblem = Strings.L("没听清，再说一次"); return }
            if (PressSpeech.filler(heard.original)) { Log.d("listen: only a filler heard, not said"); return }
            var dst = heard.translation
            if (dst == null && !Languages.same(heard.lang, their)) dst = translator.translate(heard.original, heard.lang, their, Translator.Kind.Speak)
            val sameLanguage = Languages.same(heard.lang, their)
            val probe = TranscriptLine(speaker = "me", src = heard.original, dst = dst, srcLang = heard.lang, dstLang = their)
            val text = speakable(probe)
            Log.d("listen: said ${heard.lang} -> $their, ${if (text != null) "speaking" else "not spoken"}")
            // As on the Mac: a sentence that didn't translate is neither sent nor recorded. One
            // already in their language was heard as it is, so it is kept.
            if (text == null && !sameLanguage) { sayProblem = Strings.L("这句没翻译成 · 没有说出去"); return }
            val n = synchronized(gate) { ++saidCount }
            val line = TranscriptLine(id = "m$n", t = t, speaker = "me", src = heard.original, dst = dst,
                                      srcLang = heard.lang, dstLang = their)
            // The other side's next words start their own line, never joined onto mine.
            synchronized(gate) { last = null }
            store.append(id, line.copy())
            onWords?.invoke()
            if (text != null) onSaid?.invoke(text, their) else sayProblem = Strings.L("这句已经是对方的语言")
        } catch (e: LingException) {
            val name = ling.hearName
            sayProblem = when {
                e.kind == LingException.Kind.Http && e.status in listOf(400, 404) && name != "Ling" -> Strings.L("这个模型听不了声音，换一个支持音频输入的")
                e.kind == LingException.Kind.NoKey || e.kind == LingException.Kind.InvalidKey ->
                    if (name == "Ling") Strings.L("Ling key 无效") else Strings.LF("%@ 的 key 无效", Strings.L(name))
                // One held sentence: say it didn't go out and why; the meeting's own line covers the rest.
                e.kind == LingException.Kind.Network || e.kind == LingException.Kind.Timeout ->
                    Strings.LF("这句没说出去 · 连不上 %@", Strings.L(name))
                else -> Strings.L("没听清，再说一次")
            }
            Log.d("listen: saying failed ${e.message}")
        } catch (e: Exception) {
            sayProblem = Strings.L("没听清，再说一次")
            Log.d("listen: saying failed ${e.javaClass.simpleName}")
        } finally {
            saying = false
            changed()
        }
    }

    private fun encode(pcm: ShortArray): Clip {
        if (!ling.config().isLing) return Clip.wav(pcm)
        val clip = try { encoder(pcm) } catch (e: Exception) { Log.d("listen: encode failed ${e.message}"); null }
        if (clip == null || clip.bytes.isEmpty()) return Clip.wav(pcm)
        return clip
    }

    private fun send(seg: Segment) {
        if (voicesOn) {
            // Subtitles wait for a line's voice, so on a phone too slow to keep up a line goes
            // unlabelled (对方) rather than every subtitle falling further behind.
            val behind = synchronized(gate) { (voicesWaiting >= 2).also { if (!it) voicesWaiting++ } }
            if (behind) Log.d("speakers: voiceprints behind, segment ${seg.index} left unlabelled")
            else {
                val f = voicePool.submit<FloatArray?> {
                    val started = System.currentTimeMillis()
                    try {
                        speakers?.embed(seg.samples).also {
                            Log.d("speakers: segment ${seg.index} ${"%.1f".format(seg.seconds)}s voiceprint in ${System.currentTimeMillis() - started} ms")
                        }
                    } finally { synchronized(gate) { voicesWaiting-- } }
                }
                synchronized(gate) { voiceprints[seg.index] = f }
            }
        }
        val lang = synchronized(gate) { segments[seg.index] = seg; hint }
        // Timing only (never text): where the segment sits in the audio, to measure delay.
        Log.d("listen: segment ${seg.index} sent at ${"%.2f".format(seg.start)}+${"%.2f".format(seg.seconds)}")
        changed()
        val future = pool.submit {
            var heard: Heard? = null
            val started = System.currentTimeMillis()
            try {
                val clip = encode(seg.samples)
                // Into what the meeting's language translates to; a segment that turns out to be
                // in my own language under "follow system" is translated again (record).
                val asked = settings.targetFor(lang)
                heard = translator.hear(clip, asked, lang, seg.seconds)?.let { h ->
                    if (settings.targetFor(h.lang) == asked) h else h.copy(translation = null)
                }
                synchronized(gate) { serverErrors = 0 }
                problem = null; problemKind = null
            } catch (e: LingException) {
                // A server error (a gateway's 502) is said from the third in a row, as on the Mac: one
                // isn't worth a banner, but a meeting with no subtitles and no reason is worse.
                val shown = synchronized(gate) {
                    serverErrors = if (serverError(e)) serverErrors + 1 else 0
                    !serverError(e) || serverErrors >= SERVER_ERRORS_SHOWN
                }
                if (shown) {
                    val (kind, text) = problem(e, ling.hearName)
                    problemKind = kind; problem = text
                }
                Log.d("listen: segment ${seg.index} failed ${e.message}")
            } catch (e: Exception) {
                Log.d("listen: segment ${seg.index} failed ${e.javaClass.simpleName}")
            }
            Log.d("listen: segment ${seg.index} ${"%.1f".format(seg.seconds)}s -> ${heard?.lang ?: "nothing"} in ${System.currentTimeMillis() - started} ms")
            synchronized(gate) { done[seg.index] = heard }
            deliver()
        }
        synchronized(gate) { inFlight.add(future); inFlight.removeAll { it.isDone } }
    }

    /// Hands finished segments on in order: one slow reply holds back those after it.
    private fun deliver() {
        val ready = mutableListOf<Pair<Segment, Heard?>>()
        synchronized(deliverLock) {
            synchronized(gate) {
                while (done.containsKey(nextToDeliver)) {
                    val heard = done.remove(nextToDeliver)
                    ready.add(segments.remove(nextToDeliver)!! to heard)
                    nextToDeliver++
                }
            }
            for ((seg, heard) in ready) {
                val print = synchronized(gate) { voiceprints.remove(seg.index) }
                if (heard != null) record(seg, heard, voice(print, seg, heard))
            }
        }
        if (ready.isNotEmpty()) changed()
    }

    /// The segment's voice, or null when unsure. A line with hardly a letter ("." from a breath or
    /// a click) gets no voiceprint; like the Mac, every labelled segment counts towards its voice.
    private fun voice(print: Future<FloatArray?>?, seg: Segment, heard: Heard): Int? {
        if (print == null || heard.original.count { it.isLetter() } < 2) return null
        val vector = try { print.get(20, TimeUnit.SECONDS) } catch (e: Exception) {
            Log.d("speakers: voiceprint failed ${e.javaClass.simpleName}"); return null
        }
        return speakers?.label(vector, seg.seconds)
    }

    private fun record(seg: Segment, heard: Heard, voice: Int?) {
        val id = sessionId ?: return
        val target = settings.targetFor(heard.lang)
        // The meeting's language moves only after two segments agree, so one misheard stretch
        // doesn't flip the hint (the Mac waits for confidence the same way).
        synchronized(gate) {
            val h = hint
            if (h == null) hint = heard.lang
            else if (heard.lang != h) {
                if (candidate == heard.lang) candidateVotes++ else { candidate = heard.lang; candidateVotes = 1 }
                if (candidateVotes >= 2) { hint = candidate; candidate = null; candidateVotes = 0 }
            } else { candidate = null; candidateVotes = 0 }
        }

        val line: TranscriptLine
        var joined = false
        synchronized(gate) {
            val prev = last
            // Two voices never share a line: a half sentence joins only the same voice (or an unknown one).
            if (prev != null && continues(prev, seg.start - lastEnd, heard) && (voice == null || prev.voice == null || voice == prev.voice)) {
                prev.src = join(prev.src, heard.original, heard.lang)
                prev.dst = if (prev.dst == null || heard.translation == null) null else join(prev.dst!!, heard.translation, target)
                line = prev
                joined = true
            } else {
                line = TranscriptLine(id = "h${++lineCount}-${seg.index}", t = seg.start, speaker = "them",
                                      src = heard.original, dst = heard.translation, srcLang = heard.lang, dstLang = target, voice = voice)
                last = line
            }
            lastEnd = seg.start + seg.seconds
        }
        val copy = synchronized(gate) { line.copy() }
        // A line the hear model translated itself: finished sentences are being translated again.
        if (!joined && heard.translation != null) translator.sentencesUntranslated = false
        if (joined) store.replace(id, copy) else store.append(id, copy)
        fixes?.applyKnown(copy.id, id)
        if (voice != null) onVoice?.invoke(id)
        onWords?.invoke()

        // A line Ming translated itself: with 改正听错的词 on, the AI service translates it again with
        // the misheard words pointed out (Ming's stays when that fails).
        if (!joined && line.dst != null && line.srcLang != target && fixes != null) {
            val src = line.src
            // Waited for like a stretch at Ming: the meeting's last line gets its fixes before it ends.
            val f = pool.submit {
                val dst = translator.fixLine(src, line.srcLang, target) ?: return@submit
                val updated = synchronized(gate) {
                    if (line.src != src) return@submit
                    line.dst = dst
                    line.copy()
                }
                store.replace(id, updated)
                changed()
            }
            synchronized(gate) { inFlight.add(f) }
        }
        // A joined sentence is translated again as a whole; a line Ming didn't translate gets text translation.
        if ((joined || line.dst == null) && line.srcLang != target) {
            val src = line.src
            pool.execute {
                val dst = translator.translate(src, line.srcLang, target, Translator.Kind.Sentence)
                // Untranslated: the live screens may now say why (translator.sentencesUntranslated).
                if (dst == null) { changed(); return@execute }
                val updated = synchronized(gate) {
                    if (dst == null || line.src != src) return@execute
                    line.dst = dst
                    line.copy()
                }
                store.replace(id, updated)
                changed()
            }
        }
    }

    companion object {
        /// Server errors in a row before listening says so (ListenEngine.swift's cloudFailures).
        const val SERVER_ERRORS_SHOWN = 3

        fun serverError(e: LingException) = e.kind == LingException.Kind.Http && e.status >= 500

        /// (kind, what to say) for a stretch that couldn't be heard. Ling keeps its own words; another
        /// service is named. A hear model that refuses audio (400 / 404) is a key-like problem: 设置 fixes it.
        fun problem(e: LingException, service: String): Pair<String?, String?> {
            val ling = service == "Ling"
            if (e.kind == LingException.Kind.Http && (e.status == 400 || e.status == 404) && !ling)
                return "key" to Strings.L("这个模型听不了声音，换一个支持音频输入的")
            // It answered, with an error: like busy, it passes by itself (AICheck's serverError words).
            if (serverError(e)) return "busy" to Strings.LF("%@ 暂时出错（HTTP %lld），稍后再试。", Strings.L(service), e.status)
            val kind = when (e.kind) {
                LingException.Kind.NoKey, LingException.Kind.InvalidKey -> "key"
                LingException.Kind.RateLimited -> "busy"
                LingException.Kind.Network, LingException.Kind.Timeout -> "network"
                else -> null
            }
            val name = Strings.L(service)
            val text = when (e.kind) {
                LingException.Kind.NoKey -> if (ling) Strings.L("需要 Ling key 才能听") else Strings.LF("需要 %@ 的 key 才能听", name)
                LingException.Kind.InvalidKey -> if (ling) Strings.L("Ling key 无效") else Strings.LF("%@ 的 key 无效", name)
                LingException.Kind.RateLimited -> if (ling) Strings.L("Ling 太忙，稍后再试") else Strings.LF("%@ 太忙，稍后再试", name)
                // Hearing goes through the service: the subtitles wait with the notes, then go on by themselves.
                LingException.Kind.Network, LingException.Kind.Timeout -> Strings.LF("字幕和纪要等 %@ 恢复 · 连上后自动继续", name)
                else -> null
            }
            return kind to text
        }

        /// What may be spoken into the room for a line: my words' translation, never my own words.
        fun speakable(line: TranscriptLine): String? {
            val dst = line.dst?.trim() ?: return null
            if (line.speaker != "me" || dst.isEmpty() || Languages.same(line.srcLang, line.dstLang) || dst == line.src.trim()) return null
            return dst
        }

        /// A segment continues the last line when the cut came mid-sentence: no sentence end on the
        /// last line, a short gap, the same language, and the joined line not too long to read.
        fun continues(last: TranscriptLine, gap: Double, next: Heard): Boolean {
            if (gap > 0.8 || last.srcLang != next.lang) return false
            val text = last.src.trimEnd()
            if (text.isEmpty() || ".!?。！？…".contains(text.last())) return false
            val cjk = Languages.isCjkLanguage(next.lang)
            val size = if (cjk) text.length + next.original.length else "$text ${next.original}".split(' ').count { it.isNotEmpty() }
            return size <= if (cjk) 80 else 45
        }

        fun join(a: String, b: String, lang: String): String {
            val cjk = lang.startsWith("zh") || lang.startsWith("ja")
            return if (cjk) a.trimEnd() + b.trimStart() else a.trimEnd() + " " + b.trimStart()
        }
    }
}

/** Whether anyone spoke during a hold (PressSpeech in the Mac's SpeakEngine.swift, same numbers):
 *  0.3 s of 30 ms frames over three times the hold's own quiet (its quietest tenth), between
 *  -44 and -36 dBFS. A silent hold came back from Ming as "嗯。" and went out as "Hmm."; a result
 *  that is only fillers isn't said either. */
object PressSpeech {
    private const val FRAME = 480
    private const val NEEDED = 0.3
    private val fillers = setOf("嗯", "啊", "呃", "哦", "唔", "额", "噢", "哎", "um", "uh", "hmm", "hm", "mm", "mhm", "ah", "oh", "er", "えー", "あの", "음", "어")

    fun spoken(pcm: ShortArray): Boolean {
        if (pcm.size < FRAME) return false
        val levels = ArrayList<Double>()
        var i = 0
        while (i + FRAME <= pcm.size) {
            var sum = 0.0
            for (k in i until i + FRAME) { val v = pcm[k] / 32768.0; sum += v * v }
            levels.add(Math.sqrt(sum / FRAME))
            i += FRAME
        }
        val floor = levels.sorted()[levels.size / 10]
        val line = minOf(0.016, maxOf(0.0063, floor * 3))
        return levels.count { it >= line } * FRAME / 16000.0 >= NEEDED
    }

    /** Nothing but fillers (嗯, 啊, um, hmm…), whatever the punctuation. */
    fun filler(text: String): Boolean {
        // A heading with nothing after it ("翻译结果：", "Translation:"): the model's answer to noise, not a sentence.
        val trimmed = text.trim()
        if (trimmed.length in 1..12 && trimmed.last() in ":：") return true
        val words = text.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        return words.isEmpty() || words.all { w -> w in fillers || (w.length > 1 && w.toSet().size == 1 && w.substring(0, 1) in fillers) }
    }
}

