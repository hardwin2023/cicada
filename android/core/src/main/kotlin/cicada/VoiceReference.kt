package cicada

import java.io.File
import java.util.Base64
import kotlin.math.sqrt

/// The recording Ming clones the user's voice from (VoiceReference in Voices.swift): `voice/reference.wav`
/// (16 kHz mono) and `voice/reference.txt` (what it says, as Ming heard it) in the app's private
/// folder, kept out of backups and device transfer. Never leaves the phone except inside a speech
/// request to Ling; never in records, exports or the log.
object VoiceReference {
    /// The phones' limits (#32): every sentence sends the clip again, so a long one makes the voice
    /// late. The Mac allows 8–30 s.
    const val MIN_SECONDS = 10.0
    const val MAX_SECONDS = 15.0

    val folder get() = File(Paths.root, "voice")
    val audio get() = File(folder, "reference.wav")
    val textFile get() = File(folder, "reference.txt")

    val text: String? get() = try { textFile.readText().takeIf { it.isNotBlank() } } catch (_: Exception) { null }
    val exists: Boolean get() = audio.isFile && text != null

    val duration: Double get() = try { (audio.length() - 44).coerceAtLeast(0) / 2.0 / Segmenter.RATE } catch (_: Exception) { 0.0 }

    /// What Ming needs: the clip as a data URI and its transcript.
    fun reference(): Pair<String, String>? {
        val t = text ?: return null
        val bytes = try { audio.readBytes() } catch (_: Exception) { return null }
        return "data:audio/wav;base64," + Base64.getEncoder().encodeToString(bytes) to t
    }

    fun save(pcm: ShortArray, text: String) {
        folder.mkdirs()
        folder.setReadable(false, false); folder.setReadable(true, true)
        folder.setExecutable(false, false); folder.setExecutable(true, true)
        val tmp = File(folder, "reference.wav.tmp")
        tmp.writeBytes(Wav.bytes(pcm))
        if (!tmp.renameTo(audio)) { audio.delete(); tmp.renameTo(audio) }
        textFile.writeText(text)
        for (f in listOf(audio, textFile)) { f.setReadable(false, false); f.setReadable(true, true); f.setWritable(false, false); f.setWritable(true, true) }
        cachedSlow = null
    }

    fun remove() { folder.deleteRecursively(); cachedSlow = null }

    // MARK: Pace (the Mac's)

    /// Ming copies the recording's pace into every sentence. Below these (characters for Chinese,
    /// Japanese and Korean, words otherwise, per second of speech) the clone is too slow for a
    /// meeting; reading the passage at an ordinary pace gives 3.5–5 and 2.3–3.
    const val SLOW_CHARACTERS = 2.5
    const val SLOW_WORDS = 1.6

    /// SpeakScore.tokens: each CJK character, and each run of letters, digits and apostrophes.
    fun tokens(text: String): List<String> {
        val out = mutableListOf<String>()
        val word = StringBuilder()
        fun flush() { if (word.isNotEmpty()) { out.add(word.toString().lowercase()); word.clear() } }
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            when {
                isCJK(cp) -> { flush(); out.add(String(Character.toChars(cp))) }
                Character.isLetterOrDigit(cp) || cp == '\''.code || cp == '’'.code -> word.appendCodePoint(if (cp == '’'.code) '\''.code else cp)
                else -> flush()
            }
            i += Character.charCount(cp)
        }
        flush()
        return out
    }

    fun isCJK(cp: Int) = cp in 0x3040..0x30FF || cp in 0x3400..0x4DBF || cp in 0x4E00..0x9FFF || cp in 0xAC00..0xD7AF || cp in 0xF900..0xFAFF

    /// Seconds from the first to the last 20 ms window within 35 dB of the loudest one.
    fun speechSpan(samples: ShortArray, rate: Int = Segmenter.RATE): Double? {
        val (first, last, size) = speechWindows(samples, rate) ?: return null
        return (last - first + 1) * size.toDouble() / rate
    }

    /// Quiet kept before and after the reading by `trim`.
    const val TRIM_PAD = 0.2

    /// The recording without the quiet before and after the reading, 0.2 s kept each side (the
    /// Linux port's trim). Ming copies the clip's ending: a second of silence after the last word
    /// (the pause before 读完了) cut every cloned sentence short (measured 2026-11 against Ling:
    /// 1.9 s of speech instead of 3.6 s for the same line).
    fun trim(samples: ShortArray, rate: Int = Segmenter.RATE): ShortArray {
        val (first, last, size) = speechWindows(samples, rate) ?: return samples
        val pad = (TRIM_PAD * rate).toInt()
        return samples.copyOfRange(maxOf(0, first * size - pad), minOf(samples.size, (last + 1) * size + pad))
    }

    /// The first and last 20 ms window within 35 dB of the loudest one, and the window's length.
    private fun speechWindows(samples: ShortArray, rate: Int): Triple<Int, Int, Int>? {
        val size = maxOf(1, (rate * 0.02).toInt())
        val levels = ArrayList<Double>()
        var i = 0
        while (i < samples.size) {
            val end = minOf(samples.size, i + size)
            var sum = 0.0
            for (k in i until end) { val s = samples[k] / 32768.0; sum += s * s }
            levels.add(sqrt(sum / (end - i)))
            i = end
        }
        val loudest = levels.maxOrNull() ?: return null
        if (loudest <= 0.003) return null
        val floor = loudest * 0.0178
        val first = levels.indexOfFirst { it >= floor }
        val last = levels.indexOfLast { it >= floor }
        if (first < 0) return null
        return Triple(first, last, size)
    }

    /// Characters or words a second, silence at both ends left out; null when there is no speech.
    fun pace(text: String, samples: ShortArray, rate: Int = Segmenter.RATE): Double? {
        val units = tokens(text).size
        val span = speechSpan(samples, rate) ?: return null
        if (units == 0 || span <= 0.5) return null
        return units / span
    }

    fun isSlow(text: String, pace: Double): Boolean {
        val t = tokens(text)
        val characters = t.count { w -> w.codePoints().anyMatch(::isCJK) }
        return pace < (if (characters * 2 >= t.size) SLOW_CHARACTERS else SLOW_WORDS)
    }

    @Volatile private var cachedSlow: Pair<Long, Boolean>? = null

    /// The saved recording is read too slowly (worked out once per recording).
    val savedIsSlow: Boolean get() {
        val t = text ?: return false
        val stamp = audio.lastModified()
        cachedSlow?.let { if (it.first == stamp) return it.second }
        val slow = try { pace(t, Wav.read(audio.inputStream()))?.let { isSlow(t, it) } ?: false } catch (_: Exception) { false }
        cachedSlow = stamp to slow
        return slow
    }

    /// The passage to read, in the user's own language.
    fun passage(language: String): String = when (VoiceCatalog.key(language)) {
        "zh" -> "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。请大家先看一下屏幕上的议程。"
        "ja" -> "皆さん、こんにちは。今日の会議では、新製品の発売計画について話し合います。スケジュール、テストの範囲、そしてマーケティングについて順番に確認しましょう。"
        else -> "Hello everyone, thanks for joining. Today we'll walk through the launch plan for the new product: the schedule, what we still need to test, and how we'll tell people about it. Let's start with the agenda on the screen."
    }

    /// What the recording says, as the service hears it (the Mac transcribes on the device; the
    /// phone has Ming), then checked as the Mac checks it. Returns the text and the trimmed clip
    /// to keep, or the reason to record again (a Chinese UI key). The 10 s are the reading's,
    /// silence at the ends left out.
    sealed class Check {
        class Ok(val text: String, val pcm: ShortArray) : Check() {
            override fun equals(other: Any?) = other is Ok && other.text == text && other.pcm.contentEquals(pcm)
            override fun hashCode() = text.hashCode()
            override fun toString() = "Ok($text, ${pcm.size} samples)"
        }
        data class Again(val reason: String, val args: List<Any> = emptyList()) : Check()
    }

    fun check(translator: Translator, recorded: ShortArray, own: String): Check {
        val pcm = trim(recorded)
        val seconds = pcm.size / Segmenter.RATE.toDouble()
        if (seconds < MIN_SECONDS) return Check.Again("录音太短了，请至少朗读 %lld 秒", listOf(MIN_SECONDS.toInt()))
        val other = if (VoiceCatalog.key(own) == "en") "zh-CN" else "en"
        val heard = try { translator.hear(Clip.wav(pcm), other, own, seconds) } catch (e: Exception) { Log.d("voice clone: hear failed ${e.javaClass.simpleName}"); null }
        val text = heard?.original?.trim().orEmpty()
        if (text.length < 6) return Check.Again("没听清录音内容，请换个安静的地方再录一次")
        val pace = pace(text, pcm)
        Log.d("voice clone: ${text.length} chars, pace ${pace?.let { "%.1f".format(it) } ?: "-"}/s")
        if (pace != null && isSlow(text, pace)) return Check.Again("读得有点慢，克隆的声音也会这么慢。请用平时说话的语速再录一次")
        return Check.Ok(text, pcm)
    }
}
