package cicada

/// A voice 我说 can read with (Voices.swift's VoiceOption): one of Ming's (through the Ling key), one
/// of another service's speech model, or the phone's text-to-speech. `id` is what settings keep:
/// "ming:US_Emma", "cloud:Kore", "phone".
data class VoiceOption(val id: String, val name: String, /** Chinese UI keys, localized where shown. */ val tags: List<String>)

/// Which voices to offer for each language the other side may hear (VoiceCatalog in Voices.swift).
/// Ming's are hand-picked natural ones; for languages it has no native voice for, Emma and George
/// speak it with `language_id`. The phone's own voice follows, so there is always one without a key.
object VoiceCatalog {
    const val PHONE = "phone"
    const val MING = "ming:"
    const val CLOUD = "cloud:"

    /// The picker's languages (key, title), as on the Mac. The key is the code without region.
    val languages = listOf("en" to "English", "zh" to "中文", "ja" to "日本語", "ko" to "한국어",
                           "es" to "Español", "fr" to "Français", "de" to "Deutsch", "pt" to "Português")

    fun key(code: String): String = code.substringBefore('-').ifEmpty { "en" }

    fun title(code: String): String = languages.firstOrNull { it.first == key(code) }?.second ?: code

    /// Ming's `language_id` for languages that need it (zh and en work without).
    fun mingLanguage(code: String): String? = key(code).takeIf { it in listOf("ja", "ko", "de", "fr", "es") }

    fun ming(language: String): List<VoiceOption> {
        fun v(voice: String, name: String, vararg tags: String) = VoiceOption(MING + voice, name, tags.toList())
        return when (key(language)) {
            "en" -> listOf(v("US_Emma", "Emma", "女", "美式", "自然对话"), v("UK_George", "George", "男", "英式", "稳重"),
                           v("UK_Charlotte", "Charlotte", "女", "英式", "平稳"))
            "zh" -> listOf(v("灵小雅", "小雅", "女", "清亮", "播报"), v("灵小棠", "小棠", "女", "温和", "沉稳"),
                           v("灵小锋", "小锋", "男", "温暖", "亲切"), v("灵卓然", "卓然", "男", "沉着", "清楚"))
            "ja", "ko", "de", "fr", "es" -> listOf(v("US_Emma", "Emma", "女"), v("UK_George", "George", "男"))
            else -> emptyList()
        }
    }

    /// The service's own voices for a language: Ming's on Ling, a speech model's (the same in every
    /// language) elsewhere, none when it has no speech model.
    fun remote(language: String, config: AIConfig): List<VoiceOption> = when {
        !config.hasVoices -> emptyList()
        config.isLing -> ming(language)
        else -> config.voices.map { VoiceOption(CLOUD + it.id, it.id, listOf(it.gender).filter { g -> g.isNotEmpty() }) }
    }

    val phone = VoiceOption(PHONE, "手机的声音", listOf("本机"))

    fun options(language: String, config: AIConfig): List<VoiceOption> = remote(language, config) + phone

    /// What a language uses until the user picks: the service's first voice once it can speak,
    /// else the phone's (the Mac's defaultID).
    fun defaultId(language: String, config: AIConfig, speaks: Boolean): String =
        (if (speaks) remote(language, config).firstOrNull()?.id else null) ?: PHONE

    /// The chosen voice for a language, or its default (AppModel.voiceID): a choice the service in
    /// use can't speak (Ming after switching to OpenRouter, any after the key is gone) falls back
    /// to the default, and comes back with that service.
    fun chosen(voices: Map<String, String>, language: String, config: AIConfig, speaks: Boolean): String {
        val fallback = defaultId(language, config, speaks)
        val id = voices[key(language)] ?: return fallback
        return when {
            id == PHONE -> id
            speaks && remote(language, config).any { it.id == id } -> id
            else -> fallback
        }
    }

    fun option(id: String, language: String, config: AIConfig): VoiceOption? =
        options(language, config).firstOrNull { it.id == id }

    /// A short line to try a voice with, in the language it will speak.
    fun sample(language: String): String = when (key(language)) {
        "zh" -> "谢谢大家。我们来看一下上线时间表，并确定谁负责麦克风测试。"
        "ja" -> "皆さん、ありがとうございます。発売スケジュールを確認しましょう。"
        "ko" -> "감사합니다. 출시 일정을 함께 확인해 보겠습니다."
        "es" -> "Gracias a todos. Revisemos el calendario de lanzamiento."
        "fr" -> "Merci à tous. Regardons ensemble le calendrier de lancement."
        "de" -> "Danke an alle. Schauen wir uns den Zeitplan für den Start an."
        "pt" -> "Obrigado a todos. Vamos ver o cronograma de lançamento."
        else -> "Thanks everyone. Let's look at the launch timeline and decide who owns the microphone tests."
    }
}
