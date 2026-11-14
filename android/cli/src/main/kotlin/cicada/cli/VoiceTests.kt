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
    )

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
