package com.wquguru.cicada

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import cicada.Strings
import cicada.Strings.L
import cicada.VoiceCatalog
import cicada.VoiceOption
import cicada.VoiceReference

/// 读出来的声音 (Settings › 我说 · 面对面): the Mac's voice picker (VoicePicker.swift) as a page.
/// Each language remembers its own voice (`speakVoices`); the list is the service's voices for the
/// language (Ming's on Ling), then the phone's, each with 试听. Opened on the language they speak
/// now (the `id` extra); the pill switches language.
class VoicesActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private var unobserve: (() -> Unit)? = null
    private var shown: String? = null
    private lateinit var language: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        language = intent.getStringExtra("id") ?: cicada.listen.theirLanguage
        page = ui.stack(0).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(24)) }
        setContentView(ui.screen(this, L("读出来的声音"), back = true, ground = Palette.ground, body = page))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::build); shown = null; build() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private val now get() = cicada.listen.theirLanguage

    private fun build() {
        val app = cicada
        val ling = app.ling
        val chosen = app.voiceId(language)
        val key = listOf(language, chosen, app.previewing, ling.keyState, ling.provider.id, ling.speaks, app.settings.speakVoices, Strings.language,
                         VoiceReference.exists, VoiceReference.audio.lastModified()).joinToString("|")
        if (key == shown) return
        shown = key
        page.removeAllViews()

        // "每种语言各记一个声音" for the language they speak now, "对方说…时用" for another, and the pill.
        val current = VoiceCatalog.key(language) == VoiceCatalog.key(now)
        val head = ui.row(10,
            ui.helper(if (current) L("每种语言各记一个声音") else Strings.LF("对方说%@时用", VoiceCatalog.title(language))).apply { layoutParams = ui.weight() },
            pill(VoiceCatalog.title(language) + if (current) L("（当前）") else ""))
        head.setPadding(ui.dp(4), ui.dp(4), 0, ui.dp(10))
        page.addView(head)

        val rows = VoiceCatalog.options(language, ling.config()).map { voiceRow(it, chosen) } + cloneRow(chosen)
        page.addView(ui.group(rows))
        page.addView(ui.helper(footnote(), Palette.tertiary).apply { setPadding(ui.dp(4), ui.dp(10), ui.dp(4), 0) })
    }

    /// The language menu: the Mac's tabs, the one they speak now marked.
    private fun pill(label: String) = ui.row(6,
        ui.text(label, 14f, Palette.ink, medium = true, lines = 1),
        ui.icon(R.drawable.i_chevron_down, 16, Palette.tertiary)).apply {
        setPadding(ui.dp(14), ui.dp(8), ui.dp(12), ui.dp(8))
        minimumHeight = ui.dp(40)
        contentDescription = label
        ui.tappable(this, 20, ui.rounded(Palette.card, 20, stroke = Palette.line)) {
            val nowKey = VoiceCatalog.key(now)
            ui.choose(this@VoicesActivity, L("读出来的声音"),
                      VoiceCatalog.languages.map { (k, t) -> k to t + if (k == nowKey) L("（当前）") else "" },
                      VoiceCatalog.key(language)) { language = if (it == "zh") "zh-CN" else it; shown = null; build() }
        }
    }

    private fun voiceRow(v: VoiceOption, chosen: String): View {
        val app = cicada
        val selected = v.id == chosen
        val usable = v.id == VoiceCatalog.PHONE || app.ling.speaks
        val row = ui.listRow(name(v), if (usable) VoicesActivity.summary(v) else L("需要 key"),
                             leading = playButton(v.id, selected, usable), trailing = radio(selected), chevron = false) {
            if (!usable) return@listRow
            app.settings.speakVoices[VoiceCatalog.key(language)] = v.id
            app.saveSettings()
            shown = null; build()
        }
        if (selected) row.background = ui.ripple(GradientDrawable().apply { setColor(Palette.accentPale) })
        if (!usable) row.alpha = 0.5f
        row.isSelected = selected
        return row
    }

    /// 我自己的声音, last (the Mac's cloneRow): only Ling clones, so another service offers 去换成 Ling;
    /// without a recording, 录制; with one, 试听, how it was recorded, 重录 · 删除, and the radio.
    private fun cloneRow(chosen: String): View {
        val app = cicada
        val ling = app.ling
        if (!ling.provider.clones) {
            return ui.listRow(L("我自己的声音"), L("只有 Ling 能用你自己的声音"),
                              trailing = smallButton(L("去换成 Ling"), primary = false) { startActivity(Intent(this, AiServiceActivity::class.java)) },
                              chevron = false, titleView = ui.text(L("我自己的声音"), 16f, Palette.secondary, lines = 1))
        }
        fun record() = startActivity(Intent(this, VoiceRecordActivity::class.java).putExtra("id", language))
        if (!VoiceReference.exists) {
            val mic = FrameLayout(this).apply {
                background = ui.rounded(Palette.accentPale, 18)
                addView(ui.icon(R.drawable.i_mic, 18, Palette.link), FrameLayout.LayoutParams(ui.dp(18), ui.dp(18), Gravity.CENTER))
                layoutParams = LinearLayout.LayoutParams(ui.dp(36), ui.dp(36))
            }
            return ui.listRow(L("我自己的声音"), L("录 15 秒原声，对方听到你的音色，晚约 3 秒"), leading = mic,
                              trailing = smallButton(L("录制"), primary = true, enabled = ling.clones) { if (ling.clones) record() },
                              chevron = false, titleView = ui.text(L("我自己的声音"), 16f, Palette.ink, bold = true, lines = 1)) { if (ling.clones) record() }
        }
        val selected = chosen == VoiceCatalog.CLONE
        val own = VoiceCatalog.key(app.settings.targetCode) == VoiceCatalog.key(language)
        val note = if (VoiceReference.savedIsSlow) L("读得偏慢") else if (own) L("最像你") else L("会带你的口音")
        // The Mac's one line, as two: 重录 · 删除 don't fit beside it on a phone in English.
        val links = ui.row(0,
            link(L("重录")) { record() },
            ui.text(" · ", 13f, Palette.secondary),
            link(L("删除")) {
                // A small link on a phone: asked first, unlike the Mac.
                ui.confirm(this, L("删除"), L("我自己的声音"), L("删除"), destructive = true) { app.removeVoiceReference(); shown = null; build() }
            })
        val texts = ui.stack(2, ui.text(L("我自己的声音"), 16f, Palette.ink, bold = true, lines = 1),
            ui.text(Strings.LF("已录 %lld 秒 · %@", Math.round(VoiceReference.duration).toInt(), note), 13f, Palette.secondary), links)
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = ui.dp(56)
            setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(12))
            addView(playButton(VoiceCatalog.CLONE, selected, ling.clones), LinearLayout.LayoutParams(ui.dp(36), ui.dp(36)).apply { rightMargin = ui.dp(14) })
            addView(texts, ui.weight())
            addView(radio(selected), LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)).apply { leftMargin = ui.dp(10) })
            contentDescription = L("用我自己的声音")
            isSelected = selected
            ui.tappable(this, 0, if (selected) GradientDrawable().apply { setColor(Palette.accentPale) } else null) {
                if (!ling.clones) return@tappable
                app.settings.speakVoices[VoiceCatalog.key(language)] = VoiceCatalog.CLONE
                app.saveSettings()
                shown = null; build()
            }
        }
        if (!ling.clones) row.alpha = 0.5f
        return row
    }

    private fun link(label: String, onClick: () -> Unit) = ui.text(label, 13f, Palette.link, bold = true, lines = 1).apply {
        paintFlags = paintFlags or android.graphics.Paint.UNDERLINE_TEXT_FLAG
        setPadding(0, ui.dp(6), 0, ui.dp(6))
        contentDescription = label
        ui.tappable(this, 6) { onClick() }
    }

    private fun smallButton(label: String, primary: Boolean, enabled: Boolean = true, onClick: () -> Unit) =
        ui.text(label, 14f, if (primary) Color.WHITE else Palette.ink, bold = true, lines = 1).apply {
            gravity = Gravity.CENTER
            minHeight = ui.dp(36)
            setPadding(ui.dp(14), 0, ui.dp(14), 0)
            contentDescription = label
            if (!enabled) alpha = 0.5f
            ui.tappable(this, 18, ui.rounded(if (primary) Palette.ink else Palette.card, 18, stroke = if (primary) null else Palette.line), dark = primary) { onClick() }
        }

    /// 试听: a round play button (accent when the voice is the chosen one), a spinner while it plays.
    private fun playButton(id: String, highlighted: Boolean, enabled: Boolean): View {
        val app = cicada
        val playing = app.previewing == id
        return FrameLayout(this).apply {
            contentDescription = L("试听")
            background = ui.rounded(if (highlighted) Palette.accent else Palette.ground, 18)
            if (playing) addView(ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
                indeterminateTintList = ColorStateList.valueOf(if (highlighted) Color.WHITE else Palette.accent)
            }, FrameLayout.LayoutParams(ui.dp(18), ui.dp(18), Gravity.CENTER))
            else addView(ui.icon(R.drawable.i_play, 16, if (highlighted) Color.WHITE else Palette.ink), FrameLayout.LayoutParams(ui.dp(16), ui.dp(16), Gravity.CENTER))
            layoutParams = LinearLayout.LayoutParams(ui.dp(36), ui.dp(36))
            if (enabled && !playing) ui.tappable(this, 18, background) {
                app.previewVoice(id, language) { android.widget.Toast.makeText(this@VoicesActivity, it, android.widget.Toast.LENGTH_SHORT).show() }
            }
        }
    }

    private fun radio(on: Boolean) = FrameLayout(this).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(ui.dp(2), if (on) Palette.accent else Palette.outline) }
        if (on) addView(ui.dot(Palette.accent, 10), FrameLayout.LayoutParams(ui.dp(10), ui.dp(10), Gravity.CENTER))
        // listRow sizes its trailing view by content: an empty ring needs its own size.
        minimumWidth = ui.dp(20); minimumHeight = ui.dp(20)
        layoutParams = LinearLayout.LayoutParams(ui.dp(20), ui.dp(20))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private fun footnote(): String {
        val ling = cicada.ling
        if (ling.provider.id != "ling") return if (ling.speaks) Strings.LF("%@ 用不了时，自动换手机的声音", ling.provider.name) else L("这个服务不出声音，用手机的声音")
        return if (ling.usable) L("Ling 不可用时自动换成手机的声音") else L("填入 Ling key 后可用 Ming 声音和你自己的声音")
    }

    companion object {
        /// The name a voice shows by (the phone's and the user's own are UI text).
        fun name(v: VoiceOption): String = if (v.id == VoiceCatalog.PHONE || v.id == VoiceCatalog.CLONE) L(v.name) else v.name

        /// "女 · 美式 · Ming" / "本机 · 最快": who it is and where it comes from.
        fun summary(v: VoiceOption): String = when {
            v.id == VoiceCatalog.PHONE -> listOf(L("本机"), L("最快")).joinToString(" · ")
            v.id.startsWith(VoiceCatalog.MING) -> (v.tags.take(2).map { L(it) } + "Ming").joinToString(" · ")
            else -> v.tags.map { L(it) }.joinToString(" · ")
        }
    }
}
