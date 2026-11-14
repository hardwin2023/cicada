// 读出来的声音 (Voices.kt): the Mac's catalog, default and fallback rules, and what goes to Ling.
// No network: LingClient runs against a fake transport.
package cicada.cli

import cicada.*
import java.io.ByteArrayInputStream

object VoiceTests {
    val tests: List<Pair<String, () -> Unit>> = listOf(
        "voiceCatalogIsTheMacs" to ::catalog,
        "voiceDefaultIsTheServicesFirstElseThePhones" to ::defaults,
        "voiceAChoiceTheServiceCantSpeakFallsBack" to ::fallback,
        "voiceChoicesSurviveARestart" to ::settingsRoundTrip,
        "voiceLingIsAskedForTheChosenVoice" to ::lingBody,
        "cloneOnlyWithLingAndARecording" to ::cloneFallback,
        "cloneSendsTheRecordingAsAReference" to ::cloneBody,
        "cloneIsRefusedByOtherServices" to ::cloneElsewhere,
        "cloneRecordingIsKeptPrivatelyAndRemoved" to ::storage,
        "clonePaceIsTheMacs" to ::pace,
        "cloneRecordingIsCheckedLikeTheMac" to ::checkRecording,
    )

    private class Fake(val reply: String = "{}") : Transport {
        val streamed = mutableListOf<Pair<String, Int>>()
        val sent = mutableListOf<String>()
        override fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int): Transport.Response {
            sent.add(body ?: ""); return Transport.Response(200, reply)
        }
        override fun stream(url: String, body: String, headers: Map<String, String>, timeoutMs: Int): Transport.Stream {
            streamed.add(body to timeoutMs)
            val chunk = java.util.Base64.getEncoder().encodeToString(byteArrayOf(1, 0))
            return Transport.Stream(200, "text/event-stream", ByteArrayInputStream("data: {\"audio\": \"$chunk\"}\ndata: {\"type\": \"speech.audio.done\"}".toByteArray()))
        }
    }

    private fun client(fake: Transport, s: AppSettings): LingClient {
        val k = AIKey(PlainProtector, service = { s.aiProvider })
        k.remove(); k.save("sk-test-0000000000")
        return LingClient(k, fake, config = s::aiConfig)
    }

    /// A tone at 16 kHz: `seconds` long, silence before and after.
    private fun tone(seconds: Double, pad: Double = 0.5): ShortArray {
        val rate = Segmenter.RATE
        val out = ShortArray(((seconds + 2 * pad) * rate).toInt())
        val from = (pad * rate).toInt()
        for (i in 0 until (seconds * rate).toInt()) out[from + i] = (8000 * kotlin.math.sin(2 * Math.PI * 220 * i / rate)).toInt().toShort()
        return out
    }

    fun cloneFallback() {
        val chosen = mapOf("en" to "clone")
        equal("clone", VoiceCatalog.chosen(chosen, "en", ling, speaks = true, canClone = true), "kept")
        equal("ming:US_Emma", VoiceCatalog.chosen(chosen, "en", ling, speaks = true, canClone = false), "no recording")
        equal("cloud:Kore", VoiceCatalog.chosen(chosen, "en", openrouter, speaks = true, canClone = false), "OpenRouter can't clone")
        equal("phone", VoiceCatalog.chosen(chosen, "en", ling, speaks = false, canClone = false), "no key")
        equal("我自己的声音", VoiceCatalog.option("clone", "en", ling)?.name, "its name")
        check(Providers.LING.clones && !Providers.OPENROUTER.clones, "only Ling clones")
    }

    fun cloneBody() {
        val fake = Fake()
        val c = client(fake, AppSettings())
        check(c.clones, "Ling with a key clones")
        val got = java.io.ByteArrayOutputStream()
        c.speech("Bonjour", language = "fr", reference = "data:audio/wav;base64,UklGRg==" to "大家好") { got.write(it) }
        val (body, timeout) = fake.streamed[0]
        val b = Json.parse(body).obj()!!
        equal(listOf(mapOf("audio" to "data:audio/wav;base64,UklGRg==", "text" to "大家好")), b["references"], "references")
        check("voice" !in b, "no built-in voice with a reference")
        equal("fr", b["language_id"], "language_id")
        check(timeout >= 30_000, "30 s for a clone, got $timeout")
        equal(2, got.size(), "audio came")
    }

    fun cloneElsewhere() {
        val fake = Fake()
        val c = client(fake, AppSettings(aiProvider = "openrouter"))
        check(!c.clones, "OpenRouter doesn't clone")
        try { c.speech("Hi", reference = "data:audio/wav;base64,AA==" to "hi") {}; throw AssertionError("spoke") } catch (_: LingException) {}
        equal(0, fake.streamed.size, "nothing sent")
    }

    fun storage() {
        VoiceReference.remove()
        check(!VoiceReference.exists && VoiceReference.reference() == null, "none yet")
        val pcm = tone(12.0, pad = 0.0)
        VoiceReference.save(pcm, "大家好，我是主持人。")
        check(VoiceReference.exists, "saved")
        equal(12L, Math.round(VoiceReference.duration), "duration")
        val (audio, text) = VoiceReference.reference()!!
        check(audio.startsWith("data:audio/wav;base64,UklGR"), "a WAV data URI")
        equal("大家好，我是主持人。", text, "its text")
        equal(pcm.toList(), Wav.read(VoiceReference.audio.inputStream()).toList(), "16 kHz as recorded")
        val perms = java.nio.file.Files.getPosixFilePermissions(VoiceReference.audio.toPath()).map { it.name }.toSet()
        equal(setOf("OWNER_READ", "OWNER_WRITE"), perms, "owner only")
        equal(VoiceReference.folder, VoiceReference.audio.parentFile, "in voice/")
        VoiceReference.remove()
        check(!VoiceReference.exists && !VoiceReference.folder.exists(), "removed")
    }

    fun pace() {
        equal(listOf("大", "家", "hello", "it's", "2026"), VoiceReference.tokens("大家 Hello, it’s 2026!"), "tokens")
        val span = VoiceReference.speechSpan(tone(4.0))!!
        check(kotlin.math.abs(span - 4.0) < 0.05, "speech span $span")
        equal(null, VoiceReference.speechSpan(ShortArray(16000)), "silence")
        check(VoiceReference.isSlow("大家好我是主持人", 2.0), "2 characters a second is slow")
        check(!VoiceReference.isSlow("大家好我是主持人", 4.0), "4 is not")
        check(VoiceReference.isSlow("hello everyone thanks for joining", 1.2), "1.2 words a second is slow")
        check(!VoiceReference.isSlow("hello everyone thanks for joining", 2.5), "2.5 is not")
    }

    fun checkRecording() {
        fun heard(original: String) = Fake(Json.write(mapOf("choices" to listOf(mapOf(
            "message" to mapOf("content" to "LANG: zh-CN\nORIGINAL: $original\nTRANSLATION: Hello everyone."), "finish_reason" to "stop"))), pretty = false))
        val short = VoiceReference.check(Translator(client(heard("大家好"), AppSettings())), tone(8.0, pad = 0.0), "zh-CN")
        equal(VoiceReference.Check.Again("录音太短了，请至少朗读 %lld 秒", listOf(10)), short, "under 10 s")
        // 12 s read as 12 characters: one a second, too slow for a meeting.
        val slow = VoiceReference.check(Translator(client(heard("大家好我是这次会议的主持人"), AppSettings())), tone(12.0), "zh-CN")
        equal(VoiceReference.Check.Again("读得有点慢，克隆的声音也会这么慢。请用平时说话的语速再录一次"), slow, "slow")
        val passage = "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。"
        val ok = VoiceReference.check(Translator(client(heard(passage), AppSettings())), tone(11.0), "zh-CN")
        equal(VoiceReference.Check.Ok(passage), ok, "heard at an ordinary pace")
        val none = VoiceReference.check(Translator(client(heard("嗯"), AppSettings())), tone(11.0), "zh-CN")
        equal(VoiceReference.Check.Again("没听清录音内容，请换个安静的地方再录一次"), none, "nothing heard")
    }

    private fun check(ok: Boolean, what: String) { if (!ok) throw AssertionError(what) }
    private fun <T> equal(expected: T, actual: T, what: String) { if (expected != actual) throw AssertionError("$what: expected «$expected», got «$actual»") }

    private val ling = AppSettings().aiConfig()
    private val openrouter = AppSettings(aiProvider = "openrouter").aiConfig()

    fun catalog() {
        equal(listOf("ming:US_Emma", "ming:UK_George", "ming:UK_Charlotte", "phone"), VoiceCatalog.options("en", ling).map { it.id }, "English")
        equal(listOf("ming:灵小雅", "ming:灵小棠", "ming:灵小锋", "ming:灵卓然", "phone"), VoiceCatalog.options("zh-CN", ling).map { it.id }, "Chinese")
        equal(VoiceCatalog.options("zh-CN", ling), VoiceCatalog.options("zh-TW", ling), "one Chinese key")
        equal(listOf("ming:US_Emma", "ming:UK_George", "phone"), VoiceCatalog.options("ja", ling).map { it.id }, "Japanese")
        equal(listOf("phone"), VoiceCatalog.options("pt", ling).map { it.id }, "Portuguese: no Ming voice")
        equal("ja", VoiceCatalog.mingLanguage("ja"), "language_id")
        equal(null, VoiceCatalog.mingLanguage("zh-CN"), "Chinese needs none")
        equal(listOf("cloud:Kore", "cloud:Aoede", "cloud:Charon", "cloud:Puck", "phone"), VoiceCatalog.options("zh-CN", openrouter).map { it.id }, "Gemini's")
        val noVoice = AppSettings(aiProvider = "custom", aiCustomBase = "https://x.example/v1", aiModels = mutableMapOf("custom" to "m")).aiConfig()
        equal(listOf("phone"), VoiceCatalog.options("en", noVoice).map { it.id }, "no speech model")
        equal(listOf("女", "美式", "自然对话"), VoiceCatalog.ming("en")[0].tags, "tags are the Mac's keys")
    }

    fun defaults() {
        equal("ming:US_Emma", VoiceCatalog.defaultId("en", ling, speaks = true), "English")
        equal("ming:灵小雅", VoiceCatalog.defaultId("zh-CN", ling, speaks = true), "Chinese")
        equal("phone", VoiceCatalog.defaultId("en", ling, speaks = false), "no key")
        equal("phone", VoiceCatalog.defaultId("pt", ling, speaks = true), "no Ming voice")
        equal("cloud:Kore", VoiceCatalog.defaultId("en", openrouter, speaks = true), "OpenRouter")
    }

    fun fallback() {
        val chosen = mapOf("en" to "ming:UK_George", "zh" to "phone", "ja" to "ming:灵小雅")
        equal("ming:UK_George", VoiceCatalog.chosen(chosen, "en", ling, speaks = true), "kept")
        equal("phone", VoiceCatalog.chosen(chosen, "zh-CN", ling, speaks = true), "the phone's, chosen")
        equal("ming:US_Emma", VoiceCatalog.chosen(chosen, "ja", ling, speaks = true), "not one of Japanese's")
        equal("cloud:Kore", VoiceCatalog.chosen(chosen, "en", openrouter, speaks = true), "Ming after switching to OpenRouter")
        equal("ming:UK_George", VoiceCatalog.chosen(chosen, "en", ling, speaks = true), "and back with Ling")
        equal("phone", VoiceCatalog.chosen(chosen, "en", ling, speaks = false), "no key: the phone's")
        equal("ming:US_Emma", VoiceCatalog.chosen(emptyMap(), "en-US", ling, speaks = true), "never chosen")
    }

    fun settingsRoundTrip() {
        val s = AppSettings()
        s.speakVoices["en"] = "ming:UK_George"
        s.speakVoices["zh"] = "phone"
        s.save()
        equal(mapOf("en" to "ming:UK_George", "zh" to "phone"), AppSettings.load().speakVoices.toMap(), "speakVoices")
        check(Json.write(s.toJson()).contains("\"speakVoices\""), "the Mac's key")
    }

    fun lingBody() {
        val streamed = mutableListOf<String>()
        val fake = object : Transport {
            override fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int) = Transport.Response(200, "{}")
            override fun stream(url: String, body: String, headers: Map<String, String>, timeoutMs: Int): Transport.Stream {
                streamed.add(body)
                return Transport.Stream(200, "text/event-stream", ByteArrayInputStream("data: {\"type\": \"speech.audio.done\"}".toByteArray()))
            }
        }
        val s = AppSettings()
        val k = AIKey(PlainProtector, service = { s.aiProvider })
        k.remove(); k.save("sk-test-0000000000")
        val client = LingClient(k, fake, config = s::aiConfig)
        client.speech("こんにちは", voice = "UK_George", language = "ja") {}
        val b = Json.parse(streamed[0]).obj()!!
        equal(Triple("Ming-3.0-tts-0.5B", "UK_George", "ja"), Triple(b["model"], b["voice"], b["language_id"]), "Ming's voice and language")
        check("references" !in b, "no reference for a built-in voice")
    }
}
