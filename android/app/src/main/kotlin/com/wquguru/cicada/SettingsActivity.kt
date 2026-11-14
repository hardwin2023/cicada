package com.wquguru.cicada

import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import cicada.AIKey
import cicada.Languages
import cicada.Log
import cicada.Strings
import cicada.Strings.L
import cicada.VoiceCatalog

/// 设置, a top-level screen beside 会议记录 (the floating navigation): grouped rows as the Mac
/// groups them (AI 服务, 语言, 听对方, 我说 · 面对面, …), each a value that opens its choices in a
/// sheet, or a switch whose effect is said under it.
class SettingsActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private var unobserve: (() -> Unit)? = null
    private var shown: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        page = ui.stack(0).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(24)) }
        builtTitle = L("设置")
        setContentView(ui.screen(this, builtTitle, back = false, ground = Palette.ground, body = page, bottom = ui.nav(this, "settings")))
    }

    private var builtTitle = ""

    // Brought back to the front by the nav, so rebuild if the language changed meanwhile.
    override fun onResume() { super.onResume(); if (L("设置") != builtTitle) { recreate(); return }; unobserve = cicada.observe(::build); shown = null; build()
        if (pickFolder) { pickFolder = false; FolderExportViews.pick(this) }
    }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private fun value(text: String) = ui.text(text, 15f, Palette.secondary, lines = 1)

    private fun build() {
        val app = cicada
        val s = app.settings
        val key = listOf(app.ling.keyState, app.ling.currentKey()?.takeLast(4), app.ling.aiCheck.summary, s.toJson(), app.canOverlay, Strings.language, app.updates.available?.version, app.updates.manual, app.vocabulary.terms.size, app.folderExport.stateKey()).joinToString("|")
        if (key == shown) return
        shown = key
        page.removeAllViews()

        // AI 服务: the service and how it is doing; its key, what works with it and its models are
        // on their own page (AiServiceActivity).
        page.addView(ui.sectionLabel(L("AI 服务")))
        page.addView(ui.group(listOf(ui.listRow(L("服务"), AiServiceActivity.summary(app), leading = ui.icon(R.drawable.i_lock, 22, Palette.body),
                                                trailing = value(AiServiceActivity.name(app.ling.provider))) {
            startActivity(Intent(this, AiServiceActivity::class.java))
        })))

        page.addView(ui.sectionLabel(L("语言")))
        val targets = listOf("system" to L("跟随系统")) + Languages.targets.map { it.code to it.name }
        page.addView(ui.group(listOf(
            choiceRow(L("翻译成"), targets, s.target) { s.target = it; app.saveSettings() },
            choiceRow(L("纪要语言"), listOf("system" to L("和字幕一样")) + Languages.targets.map { it.code to it.name }, s.notesLanguage) { s.notesLanguage = it; app.saveSettings() },
            choiceRow(L("界面语言"), listOf("system" to L("跟随系统"), "zh-Hans" to "简体中文", "en" to "English", "ja" to "日本語", "ko" to "한국어"), s.uiLanguage) {
                s.uiLanguage = it; app.saveSettings(); app.loadStrings(); shown = null; recreate()
            })))

        // 听对方: the Mac's listening switches. 说话人识别 tells voices apart on the phone
        // (NativeVoiceprints); should the library not load, it still numbers the voices of
        // records made elsewhere, and the helper says so.
        page.addView(ui.sectionLabel(L("听对方")))
        val voicesHere = app.listen.speakers?.available == true
        page.addView(ui.group(listOf(
            ui.switchRow(L("说话人识别"), if (voicesHere) L("按声音标出说话人 1、2…，只在这台手机上处理") else L("显示 Mac 和 Windows 上分出的说话人；这台手机还不能按声音分人"),
                      s.speakerVoices) { s.speakerVoices = it; app.saveSettings() },
            ui.switchRow(L("保存会议录音"), L("只存在这台手机上，会议记录里能回放原声"), s.recordAudio) { s.recordAudio = it; app.saveSettings() },
            // 改正听错的词: its switches and the word list (the Mac's 设置 › 词表).
            ui.listRow(L("词表"), if (s.fixMisheard && app.ling.usable) L("会中改正听错的词") else L("已关"),
                       trailing = value(if (app.vocabulary.terms.isEmpty()) "" else "${app.vocabulary.terms.size}")) {
                startActivity(Intent(this, WordListActivity::class.java))
            })))

        // 读出来的声音: the voice for the language they speak now, chosen per language on its own
        // page (VoicesActivity, the Mac's VoiceSection). 试一句 reads English in English's voice.
        page.addView(ui.sectionLabel(L("我说 · 面对面")))
        val their = app.listen.theirLanguage
        val theirVoice = VoiceCatalog.option(app.voiceId(their), their, app.ling.config())
        val english = VoiceCatalog.option(app.voiceId("en"), "en", app.ling.config())
        page.addView(ui.group(listOf(
            ui.switchRow(L("把我说的翻译给对方"), L("按住说话，松开后用对方的语言读出来"), s.speakBack) { s.speakBack = it; app.saveSettings() },
            ui.listRow(L("读出来的声音"), if (app.ling.usable) L("每种语言各记一个声音")
                       else if (app.ling.provider.id == "ling") L("填入 Ling key：声音更自然，还能用你自己的声音") else L("填好 AI 服务的 key，声音更自然"),
                       trailing = value(theirVoice?.let { VoicesActivity.name(it) } ?: L("手机的声音"))) {
                startActivity(Intent(this, VoicesActivity::class.java).putExtra("id", their))
            },
            ui.listRow(L("试一句"), when (english?.id) {
                           null, VoiceCatalog.PHONE -> L("用手机的声音读一句英语")
                           VoiceCatalog.CLONE -> L("用你的声音读一句英语")
                           else -> Strings.LF("用 %@ 的声音读一句英语", english.name)
                       },
                       trailing = ui.icon(R.drawable.i_play, 20, Palette.ink), chevron = false) { tryVoice() })))

        page.addView(ui.sectionLabel(L("在其他应用上")))
        val rows = mutableListOf<View>(
            ui.switchRow(L("悬浮窗"), L("切到其他应用时，在上面显示字幕或纪要"), s.overlay) { s.overlay = it; app.saveSettings(); if (!it) app.overlay.hide() },
            choiceRow(L("样式"), listOf("notes" to L("实时纪要"), "subtitles" to L("字幕条")), s.view) { app.setView(it) },
            ui.switchRow(L("共享屏幕时让对方看到"), L("关闭时，截图和录屏里看不到悬浮窗"), s.showInCapture) { s.showInCapture = it; app.saveSettings(); app.overlay.rebuild() })
        if (!app.canOverlay) rows.add(0, ui.listRow(L("开启“显示在其他应用上层”"), null, leading = ui.icon(R.drawable.i_pip, 22, Palette.link)) {
            OverlayGuideActivity.open(this, direct = true)
        })
        page.addView(ui.group(rows))

        // As on the Mac, minus 会议应用挂断后结束: Android can't see another app's microphone.
        page.addView(ui.sectionLabel(L("结束会议")))
        val endRows = mutableListOf<View>(
            choiceRow(L("没人说话时"), listOf("prompt" to L("提醒后结束"), "end" to L("直接结束"), "off" to L("一直记录")), s.silenceEnd,
                      helper = L("按识别出的话算，背景音乐不算")) { s.silenceEnd = it; app.saveSettings() })
        if (s.silenceEnd != "off") endRows.add(choiceRow(L("多久算没人说话"), listOf(5, 10, 15, 30).map { "$it" to Strings.LF("%lld 分钟", it) },
                                                       "${s.silenceMinutes.toInt()}") { s.silenceMinutes = it.toDouble(); app.saveSettings() })
        page.addView(ui.group(endRows))

        // 会后存一份: 存到文件夹 (FolderExportViews), as the Mac's 设置 › 通用.
        FolderExportViews.section(this, ui, page)

        page.addView(ui.sectionLabel(L("其他")))
        page.addView(ui.group(listOf(
            ui.listRow(L("导入录音或视频"), L("转成一场会议记录")) { startActivity(Intent(this, ImportActivity::class.java)) },
            ui.listRow(L("重看新手引导")) { startActivity(Intent(this, OnboardingActivity::class.java)) }) +
            // Android 13+ can add the tile from here; older versions edit Quick Settings by hand.
            (if (android.os.Build.VERSION.SDK_INT >= 33) listOf(ui.listRow(L("添加到快捷设置"), L("下拉通知栏，一键开始或结束听")) { addTile() }) else emptyList()) +
            listOf(updateRow())))
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        page.addView(ui.helper("${L("知了")} $version · Android").apply { gravity = Gravity.CENTER; setPadding(0, ui.dp(20), 0, 0) })
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FolderExportViews.PICK) { shown = null; FolderExportViews.picked(this, resultCode, data) }
    }

    /// 检查更新: its answer on the right; with a new version found, tapping it downloads that.
    private fun updateRow(): View {
        val u = cicada.updates
        val found = u.available
        val trailing = when {
            found != null -> ui.text(Strings.LF("有新版本 %@", found.version), 15f, Palette.link, bold = true, lines = 1)
            u.manual != null -> value(u.manual!!)
            else -> null
        }
        return ui.listRow(L("检查更新"), trailing = trailing, chevron = false) { if (found != null) u.download() else u.checkNow() }
    }

    private fun addTile() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        getSystemService(android.app.StatusBarManager::class.java).requestAddTileService(
            android.content.ComponentName(this, ListenTile::class.java), L("知了"),
            android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_notification), mainExecutor) { result ->
            Log.d("tile: add request result $result")
        }
    }

    /// A row showing its current value; tapping lists the choices.
    private fun choiceRow(label: String, options: List<Pair<String, String>>, selected: String, helper: String? = null, changed: (String) -> Unit) =
        ui.listRow(label, helper, trailing = value(options.firstOrNull { it.first == selected }?.second ?: selected)) {
            ui.choose(this, label, options, selected) { changed(it); shown = null; build() }
        }

    /// A sample of how my words will sound to them (the Mac's 试一句), in English's voice.
    private fun tryVoice() {
        val app = cicada
        app.previewVoice(app.voiceId("en"), "en", SAMPLE) { android.widget.Toast.makeText(this, it, android.widget.Toast.LENGTH_SHORT).show() }
    }

    companion object {
        const val SAMPLE = "Could you send the revised quote by Friday? We can sign next week."

        /// Debug (`export pick`): open the folder picker once settings is in front.
        var pickFolder = false

        fun paste(box: android.widget.EditText) {
            val clip = box.context.getSystemService(ClipboardManager::class.java).primaryClip
            val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(box.context)?.toString()?.trim()
            if (!text.isNullOrEmpty()) {
                box.setText(text); box.setSelection(text.length)
                // A secret: don't leave it on the clipboard for the next app (or the keyboard's history).
                if (text.startsWith("sk-")) try { box.context.getSystemService(ClipboardManager::class.java).clearPrimaryClip() } catch (_: Exception) {}
            }
        }
    }
}
