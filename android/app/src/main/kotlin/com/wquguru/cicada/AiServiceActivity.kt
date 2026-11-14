package com.wquguru.cicada

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import cicada.AICheck
import cicada.AIConfig
import cicada.AIKey
import cicada.Model
import cicada.Provider
import cicada.Providers
import cicada.Strings
import cicada.Strings.L
import cicada.Strings.LF

/// 设置 › AI 服务 (AISettings.swift, the design's Android page): which service, its key and how
/// the check went, what works with it (现在能用的, with 听对方 first: on the ports the service
/// hears), and the models, each a row that opens its choices. The recommended ones are already
/// chosen, so most people never open those.
class AiServiceActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private var unobserve: (() -> Unit)? = null
    private var shown: String? = null
    /// A custom service's rows that are open (翻译和纪要, 听对方, 同传声音); null until the page first decides.
    private var open: MutableSet<String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        page = ui.stack(0).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(24)) }
        setContentView(ui.screen(this, L("AI 服务"), back = true, ground = Palette.ground, body = page))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::build); shown = null; build() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private fun value(text: String) = ui.text(text, 15f, Palette.secondary, lines = 1)

    private fun build() {
        val app = cicada
        val ling = app.ling
        val c = ling.config()
        val p = c.provider
        val key = listOf(ling.keyState, ling.currentKey()?.takeLast(4), ling.aiCheck.summary, ling.aiCheck.at?.let { it / 60_000 }, ling.lastVoice?.first,
                         ling.textCatalog.size, ling.hearCatalog.size, ling.notesCatalog.size, ling.notesHasOwnKey,
                         app.settings.toJson(), Strings.language, open).joinToString("|")
        if (key == shown) return
        shown = key
        page.removeAllViews()
        val name = name(p)
        if (p.id == "custom") { customPage(app, c); return }

        // The service, its key (and a custom service's address).
        page.addView(ui.sectionLabel(L("服务")))
        val rows = mutableListOf<View>(choiceRow(L("服务"), Providers.ALL.map { it.id to label(it) }, p.id) { app.setAiProvider(it) })
        val k = ling.currentKey()
        val title = when {
            k == null -> if (p.id == "custom") L("还没填好") else L("还没填 API key")
            else -> AIKey.masked(k)
        }
        val trailing = if (!k.isNullOrEmpty()) ui.text(L("更换"), 15f, Palette.link, bold = true, lines = 1) else null
        rows.add(ui.listRow(title, status(app), leading = ui.icon(R.drawable.i_lock, 22, Palette.body), trailing = trailing, chevron = k == null) {
            editKey(this, ui)
        })
        if (k == null && p.site != null) rows.add(ui.listRow(LF("打开 %@", name), null, trailing = ui.icon(R.drawable.i_external, 18, Palette.link), chevron = false) {
            try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(p.site))) } catch (_: Exception) {}
        })
        // Where it broke and the one thing that fixes it; all passed folds into the key's line.
        val check = ling.aiCheck
        if (k != null && AiCheckViews.showSteps(check)) rows.add(AiCheckViews.steps(this, ui, recheck = false) { editKey(this, ui) })
        check.balanceLine(name)?.let { low ->
            // Wraps: English runs two lines.
            rows.add(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui.dp(56)
                setPadding(ui.dp(16), ui.dp(8), ui.dp(8), ui.dp(8))
                setBackgroundColor(AiCheckViews.warnPale)
                addView(ui.text(low, 15f, AiCheckViews.warn), ui.weight())
                addView(ui.textButton(L("去充值")) { AiCheckViews.open(this@AiServiceActivity, AiCheckViews.topUp(p)) })
            })
        }
        if (k != null) rows.add(ui.listRow(if (check.running) L("正在检查…") else L("重新检查"), null,
            leading = ui.icon(R.drawable.i_restore, 22, if (check.running) Palette.tertiary else Palette.body), chevron = false,
            onClick = if (check.running) null else ({ app.recheck() })))
        page.addView(ui.group(rows))
        val host = c.base?.let { Uri.parse(it).host } ?: L("你填的地址")
        page.addView(ui.helper(LF("加密存在这台手机上，只发给 %@（%@）", name, host)).apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), 0) })

        page.addView(ui.sectionLabel(L("现在能用的")))
        page.addView(ui.group(usesRows(app, c, name)))

        page.addView(ui.sectionLabel(L("自己选模型")))
        page.addView(ui.group(modelRows(app, c)))
        val foot = (if (c.isLing) "" else L("按所选模型计费。")) + LF("听的时候，声音会发给 %@。", name)
        page.addView(ui.helper(foot).apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), 0) })
    }

    /// 现在能用的 (AISettings.swift › usage): what each part of the app uses with this service.
    private fun usesRows(app: CicadaApp, c: AIConfig, name: String): List<View> {
        val ling = app.ling
        // Only what the last result supports: when the service can't be reached (or the key
        // fails) nothing says "用 ZenMux"; a deaf hear model greys only what hears.
        val reason = ling.aiCheck.failure?.reason
        val down = ling.hasKey && reason in listOf(AICheck.Reason.Unreachable, AICheck.Reason.BadAddress, AICheck.Reason.InvalidKey,
                                                   AICheck.Reason.MgmtKey, AICheck.Reason.NoCredit)
        val on = ling.usable && !down
        val uses = LF("用 %@", name)
        val needKey = Triple(L("需要 key"), 0, L("填好 key 后可用"))
        val off = Triple(L("暂不可用"), 0, if (reason == AICheck.Reason.Unreachable) LF("连上 %@ 后可用", name) else L("换好 key 后可用"))
        val notReady = if (down) off else needKey
        val deaf = Triple(L("还不能用"), 0, LF("%@ 听不了声音。", short(c.hearModel)))
        val hear = when {
            !on -> notReady
            ling.hears == false -> deaf
            c.isLing -> Triple(uses, 1, L("Ming 一次识别并翻译"))
            else -> Triple(uses, 1, short(c.hearModel) + " · " + L("比 Ling 晚 1–2 秒出字"))
        }
        val notes = when {
            !on -> notReady
            reason == AICheck.Reason.NoModel -> Triple(L("暂不可用"), 0, L("换一个模型后可用"))
            reason == AICheck.Reason.NoJSON -> Triple(L("暂不可用"), 0, L("这个服务不支持 JSON"))
            ling.aiCheck.busy -> Triple(L("很忙"), 2, L("会自动重试，纪要可能晚一点"))
            else -> Triple(uses, 1, L("会中每 45 秒更新"))
        }
        val voice = cloudVoice(app)
        val say = when {
            !on -> notReady
            ling.hears == false -> deaf
            voice != null && ling.lastVoice?.first == false -> Triple(uses, 1, L("上次同传没出声，用了手机的声音"))
            voice != null && ling.lastVoice?.first == true -> Triple(uses, 1, LF("%@ 的声音读给对方", voice) + " · " + L("上次同传时正常"))
            else -> Triple(uses, 1, if (voice != null) LF("%@ 的声音读给对方", voice) else L("手机的声音读给对方"))
        }
        // 改正听错的词 (AISettings.swift's row): a text request per finished line, switched in 词表.
        val fix = when {
            !on -> notReady
            !app.settings.fixMisheard -> Triple(L("已关"), 0, L("在“词表”里打开"))
            else -> Triple(uses, 1, L("随翻译一起发，几乎不多花"))
        }
        val rows = mutableListOf(L("听对方") to hear, L("实时纪要") to notes, L("改正听错的词") to fix, L("我说 · 面对面") to say)
        if (!c.isLing) rows.add(L("你自己的声音") to Triple(L("只有 Ling"), 0, L("换用 Ling 才有")))
        return rows.map { (title, u) ->
            val (tag, style, note) = u
            val (fg, bg) = when (style) { 1 -> Palette.ink to Palette.selected; 2 -> AiCheckViews.warn to AiCheckViews.warnPale; else -> Palette.secondary to Palette.ground }
            ui.listRow(title, note, trailing = ui.badge(tag, fg = fg, bg = bg), chevron = false)
        }
    }

    /// 自己选模型: the hear, text and voice models; Ling's hear model is Ming, always.
    private fun modelRows(app: CicadaApp, c: AIConfig): List<View> {
        val p = c.provider
        val s = app.settings
        if (p.id == "ling") return listOf(
            choiceRow(L("文字模型"), p.textModels.map { it.id to it.id }, c.textModel, helper = L("3.1 更准；3.0 更快、更省")) { app.setAiModel("text", it) },
            ui.listRow(L("听的模型"), L("Ming 一次识别并翻译"), trailing = value(c.hearModel), chevron = false))
        val rows = mutableListOf(
            modelRow(L("听的模型"), L("听对方和“我说”都用它"), p.hearModels, app.ling.hearCatalog, c.hearModel) { app.setAiModel("hear", it) },
            modelRow(L("文字模型"), L("纪要和整句翻译"), p.textModels, app.ling.textCatalog, c.textModel) { app.setAiModel("text", it) })
        if (p.hasVoices) rows.add(modelRow(L("声音模型"), L("面对面时读给对方"), p.voiceModels, emptyList(), c.voiceModel ?: "") { app.setAiModel("voice", it) })
        return rows
    }

    // MARK: Own service

    /// 其他（兼容 OpenAI）(AISettings.swift › customPage): one row per use, each at its own address if
    /// need be (a text model, an audio model and a speech model often run as separate servers),
    /// each opening to its fields and saying whether it works and how fast. On a phone the hear
    /// model is what listens: there is no on-device recognition to fall back to.
    private fun customPage(app: CicadaApp, c: AIConfig) {
        val ling = app.ling
        val check = ling.aiCheck
        // A service that isn't set up yet, or doesn't work, opens where it needs filling in.
        val opened = open ?: mutableSetOf<String>().also {
            if (check.failure?.step == AICheck.StepID.Hear) it.add("hear") else if (!check.passed || check.slow) it.add("text")
            open = it
        }
        page.addView(ui.sectionLabel(L("服务")))
        page.addView(ui.group(listOf(choiceRow(L("服务"), Providers.ALL.map { it.id to label(it) }, c.provider.id) { app.setAiProvider(it) })))
        page.addView(ui.helper(L("每样可以接不同的机器；这台手机和局域网里的服务可以用 http。")).apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), 0) })
        page.addView(ui.sectionLabel(L("按功能指定")))
        val rows = mutableListOf<View>()
        textSection(app, c, opened, rows)
        hearSection(app, c, opened, rows)
        voiceSection(app, c, opened, rows)
        page.addView(ui.group(rows))
        page.addView(ui.group(listOf(onlyRow(app))).apply {
            layoutParams = LinearLayout.LayoutParams(-1, -2).apply { topMargin = ui.dp(16) }
        })
        val host = c.base?.let { Uri.parse(it).host } ?: L("你填的地址")
        page.addView(ui.helper(LF("加密存在这台手机上，只发给 %@", keyHosts(app, c))).apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), 0) })
        // Never "按所选模型计费" here: the user runs it, or their provider bills it its own way.
        val nearby = c.base?.let(Providers::isNearby) ?: false
        val foot = (if (nearby) L("跑在你自己的机器上，不按量计费。") else L("费用以这个服务为准。")) +
            if (app.settings.aiCustomOnly) LF("会议的语音和文字只发给 %@，不经过 Google 等外部服务。", customHosts(c))
            else LF("听的时候，声音会发给 %@。", ling.hearHost.ifEmpty { host })
        page.addView(ui.helper(foot).apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), 0) })
    }

    /// 语音和文字只发给你的服务 (AISettings.swift › onlyRow): Google is never asked. The grey line says
    /// what it costs, and while the service can't be reached, that new subtitles are the original
    /// only (a phone has no on-device translation to stand in).
    private fun onlyRow(app: CicadaApp): View {
        val on = app.settings.aiCustomOnly
        val check = app.ling.aiCheck
        val failure = check.failure
        val down = on && app.ling.hasKey && !check.running && failure != null && failure.reason != AICheck.Reason.Busy
        val detail = if (down) L("现在连不上：新字幕暂时只有原文") else L("不用 Google 翻译；说话时要等整句说完才出译文")
        return ui.switchRow(L("语音和文字只发给你的服务"), detail, on) { app.setCustomOnly(it) }
    }

    /// Where the custom service's audio and text go: one host when every use shares it. On a phone
    /// the hear model always listens, so its address always counts.
    private fun customHosts(c: AIConfig): String =
        hostsLine(listOfNotNull(c.base, c.forNotes.base?.takeIf { c.notesApart }, c.hearBase, c.voiceBase?.takeIf { c.hasVoices }))

    /// Where the custom service's key is sent: every use's address, the notes' only while they share it.
    private fun keyHosts(app: CicadaApp, c: AIConfig): String =
        hostsLine(listOfNotNull(c.base, c.forNotes.base?.takeIf { c.notesApart && !app.ling.notesHasOwnKey }, c.hearBase,
                                c.voiceBase?.takeIf { c.hasVoices }))

    /// One host, "a 和 b", or 你填的地址 for more.
    private fun hostsLine(bases: List<String>): String {
        val hosts = bases.mapNotNull { Uri.parse(it).host }.distinct()
        return when (hosts.size) {
            1 -> hosts[0]
            2 -> LF("%@ 和 %@", hosts[0], hosts[1])
            else -> L("你填的地址")
        }
    }

    /// A row that opens to its fields: a state dot, the use, what it runs on, and how it's doing.
    private fun useRow(id: String, open: MutableSet<String>, title: String, detail: String, dot: Int, trailing: String?,
                       trailingColor: Int = Palette.tertiary): View {
        val row = ui.listRow(title, detail, leading = ui.dot(dot), trailing = trailing?.let { ui.text(it, 13f, trailingColor, lines = 1).apply { fontFeatureSettings = "tnum" } }) {
            if (!open.remove(id)) open.add(id)
            build()
        }
        row.getChildAt(row.childCount - 1).rotation = if (id in open) 90f else 0f
        return row
    }

    /// The fields under an open row, indented under its title.
    private fun panel(vararg views: View?) = ui.stack(0).apply {
        setPadding(ui.dp(18), 0, 0, ui.dp(8))
        views.filterNotNull().forEach { addView(it) }
    }

    private fun note(text: String, color: Int) = ui.text(text, 13f, color).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(8)) }

    private fun badAddress(raw: String) =
        if (raw.isNotBlank() && Providers.customBase(raw) == null) note(L("地址要用 https；这台手机和局域网里的服务可以用 http。"), Palette.link) else null

    /// An address as the row shows it: host and port ("192.168.1.20:8000").
    private fun where(raw: String): String {
        val u = Uri.parse(Providers.customBase(raw) ?: return raw)
        return (u.host ?: raw) + if (u.port > 0) ":${u.port}" else ""
    }

    private val grey = android.graphics.Color.parseColor("#C4C7CE")

    /// "192.168.1.20 · qwen-mt-turbo", then the notes' model, or their own server after a bar.
    private fun textDetail(c: AIConfig, host: String): String {
        if (host.isEmpty() || c.textModel.isEmpty()) return L("填上地址和模型")
        val line = "$host · ${short(c.textModel)}"
        if (!c.notesApart) return line
        val n = c.forNotes
        val notesHost = n.base?.let { Uri.parse(it).host }
        if (notesHost != null && n.base != c.base) return line + " ｜ $notesHost · ${short(n.textModel)}"
        return if (n.textModel == c.textModel) line else line + " · ${short(n.textModel)}"
    }

    /// 翻译和纪要 (AISettings.swift › textSection): 翻译's address, key and model, then 纪要 on the
    /// same service (another model at most) or another one with its own address and key.
    private fun textSection(app: CicadaApp, c: AIConfig, open: MutableSet<String>, rows: MutableList<View>) {
        val ling = app.ling
        val s = app.settings
        val check = ling.aiCheck
        val host = c.base?.let { Uri.parse(it).host }.orEmpty()
        val secs = check.translate?.let { "%.1f".format(Strings.locale, it.seconds) }
        // The hear model's own failure shows on its row: the text model may be fine.
        val failed = check.textFailure != null
        // Translation works but the notes' own model or server doesn't.
        val notesDown = !failed && check.notesFailed
        val trailing = when {
            check.running -> L("正在检查…")
            failed && ling.hasKey -> status(app)
            notesDown -> L("纪要写不了")
            else -> secs?.let { LF("翻一句 %@ 秒", it) }
        }
        val dot = when {
            !ling.hasKey -> grey
            check.running -> Palette.accent
            failed -> Palette.link
            check.slow || check.busy || check.notesFailed -> AiCheckViews.warn
            check.at != null && check[AICheck.StepID.Text] is AICheck.State.Ok -> AiCheckViews.ok
            else -> grey
        }
        rows.add(useRow("text", open, L("翻译和纪要"), textDetail(c, host), dot, trailing,
            if (failed || notesDown) Palette.link else if (check.slow) AiCheckViews.warn else Palette.tertiary))
        if ("text" !in open) return
        val k = ling.currentKey()
        val keyLine = when {
            k == null -> L("还没填 API key")
            k.isEmpty() -> L("本机和局域网服务可不填")
            else -> AIKey.masked(k)
        }
        val model = modelPicker(L("模型"), s.aiModels["custom"].orEmpty(), L("例如 qwen3:14b"), null, host,
                                { ling.textCatalog }, { ling.fetchCatalog() }) { app.setAiModel("text", it) }
        val steps = k != null && (check.running || failed || (check.at != null && check.failure == null && !check.passed))
        val apart = c.notesApart && check.passed && check.translate != null
        val facts = if (!steps && !apart && check.at != null && check[AICheck.StepID.Text] is AICheck.State.Ok)
            listOfNotNull(L("能写纪要"), check.translate?.let { if (it.thinks) L("会先思考") else L("不思考") }).joinToString(" · ") else null
        val views = mutableListOf<View?>(
            groupTitle(L("翻译")),
            fieldRow(L("地址"), s.aiCustomBase, "http://192.168.1.20:8000/v1", null, shown = ::where) { s.aiCustomBase = it; s.save(); app.aiChanged() },
            badAddress(s.aiCustomBase),
            ui.listRow("key", keyLine, trailing = if (!k.isNullOrEmpty()) ui.text(L("更换"), 15f, Palette.link, bold = true, lines = 1) else null) { editKey(this, ui) },
            model,
            ui.divider().apply { layoutParams = LinearLayout.LayoutParams(-1, 1).apply { topMargin = ui.dp(4); bottomMargin = ui.dp(4); leftMargin = ui.dp(16) } },
        )
        views.addAll(notesGroup(app, c, host))
        views.addAll(listOf(
            ui.listRow(if (check.running) L("正在检查…") else L("重新检查"), null,
                leading = ui.icon(R.drawable.i_restore, 22, if (check.running) Palette.tertiary else Palette.body), chevron = false,
                onClick = if (check.running || k == null) null else ({ app.recheck() })),
            check.slowLine(app.translator.googleOff)?.let { note(it, AiCheckViews.warn) },
            if (steps) AiCheckViews.steps(this, ui, recheck = false) { editKey(this, ui) } else null,
            facts?.let { note(it, Palette.tertiary) },
            if (apart && !steps) checkRows(c, check) else null,
        ))
        rows.add(panel(*views.toTypedArray()))
    }

    private fun groupTitle(text: String) = ui.text(text, 13f, Palette.ink, bold = true, lines = 1).apply {
        setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(2))
        isAccessibilityHeading = true
    }

    /// 纪要: the same service as translation (another model at most), or another one with its own
    /// address and key. Switching back keeps what was typed.
    private fun notesGroup(app: CicadaApp, c: AIConfig, host: String): List<View?> {
        val ling = app.ling
        val s = app.settings
        val own = s.aiCustomNotesOwn
        val n = c.forNotes
        val notesHost = n.base?.let { Uri.parse(it).host } ?: host
        val shared = !ling.notesHasOwnKey
        val elsewhere = n.base != c.base
        val views = mutableListOf<View?>(
            groupTitle(L("纪要")),
            ui.segmented(listOf("same" to L("同一个服务"), "own" to L("另一个服务")), if (own) "own" else "same") { app.setNotesOwn(it == "own") }
                .apply { layoutParams = LinearLayout.LayoutParams(-1, -2).apply { leftMargin = ui.dp(16); rightMargin = ui.dp(16); topMargin = ui.dp(4); bottomMargin = ui.dp(4) } },
        )
        if (own) {
            val nk = if (shared) null else ling.notesKey()
            views.add(fieldRow(L("地址"), s.aiCustomNotesBase, L("跟上面一样"), null, L("跟上面一样"), ::where) { app.setNotesBase(it) })
            views.add(badAddress(s.aiCustomNotesBase))
            views.add(ui.listRow("key", if (nk.isNullOrEmpty()) L("不填就用上面的 key") else AIKey.masked(nk),
                trailing = if (!nk.isNullOrEmpty()) ui.text(L("更换"), 15f, Palette.link, bold = true, lines = 1) else null) { editNotesKey(app, notesHost) })
        }
        views.add(modelPicker(L("模型"), s.aiModels[Providers.NOTES_MODEL].orEmpty(), L("和翻译模型一样"), L("和翻译模型一样"), notesHost,
            { if (elsewhere) ling.notesCatalog else ling.textCatalog }, { if (elsewhere) ling.fetchNotesCatalog() else ling.fetchCatalog() }) {
            app.setAiModel("notes", it)
        })
        val problem = ling.aiCheck.notesLine(notesHost, n.textModel, sharedKey = shared)
        views.add(if (problem != null) note(problem, Palette.link) else note(L("用来写实时纪要、识别说话人，默认和翻译用同一个"), Palette.tertiary))
        return views
    }

    /// After a check with notes apart: one row each, what it runs and how it did.
    private fun checkRows(c: AIConfig, check: AICheck): View {
        val t = check.translate!!
        val notes = check.notes
        val notesText = when (notes) {
            is AICheck.Notes.Ok -> LF("能写纪要 · %@ 秒", "%.1f".format(Strings.locale, notes.seconds))
            is AICheck.Notes.Fail -> if (notes.why == AICheck.Reason.InvalidKey || notes.why == AICheck.Reason.MgmtKey) L("key 不对") else L("纪要写不了")
            AICheck.Notes.Running -> L("正在检查…")
            null -> ""
        }
        fun row(use: String, model: String, ok: Boolean, result: String) =
            ui.listRow(use, short(model), leading = ui.dot(if (ok) AiCheckViews.ok else Palette.link),
                       trailing = ui.text(result, 13f, if (ok) AiCheckViews.ok else Palette.link, lines = 1).apply { fontFeatureSettings = "tnum" }, chevron = false)
        val translate = LF("翻一句 %@ 秒", "%.1f".format(Strings.locale, t.seconds)) + " · " + (if (t.thinks) L("会先思考") else L("不思考"))
        return ui.stack(0,
            row(L("翻译"), c.textModel, true, translate),
            row(L("纪要"), c.forNotes.textModel, notes?.ok ?: true, notesText))
    }

    /// The notes' own key (另一个服务): paste, save, or remove it (back to the key above). It goes
    /// only to the notes' address.
    private fun editNotesKey(app: CicadaApp, host: String) {
        lateinit var dialog: android.app.Dialog
        lateinit var submit: () -> Unit
        val status = ui.helper("")
        val box = ui.keyField { submit() }.apply { hint = L("不填就用上面的 key") }
        val field = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = ui.rounded(Palette.ground, 16)
            setPadding(ui.dp(16), ui.dp(4), ui.dp(4), ui.dp(4))
            addView(box, ui.weight())
            addView(ui.button(L("粘贴"), "white", R.drawable.i_clipboard, height = 44) { SettingsActivity.paste(box) })
        }
        submit = submit@{
            val text = box.text.toString().trim()
            if (text.isEmpty()) { dialog.dismiss(); return@submit }
            if (!app.setNotesKey(text)) { status.text = L("保存失败"); return@submit }
            dialog.dismiss()
        }
        val body = ui.stack(10, field, status,
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(ui.button(L("取消"), "quiet") { dialog.dismiss() }, ui.weight())
                addView(ui.button(L("保存"), "primary") { submit() }, ui.weight().apply { leftMargin = ui.dp(10) })
            })
        if (app.ling.notesHasOwnKey) body.addView(ui.textButton(L("移除"), Palette.link) { app.setNotesKey(null); dialog.dismiss() })
        dialog = ui.sheet(this, LF("粘贴 %@ 的 key", host), body)
        dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        dialog.show()
        box.requestFocus()
    }

    /// A custom service's model (AISettings.swift › ModelPicker): the row shows it; tapping opens
    /// the names its `/models` lists, searchable, and takes a name it doesn't list (an alias, a
    /// model it hides). Without a list the sheet is a plain field. `sameLabel`: a first choice
    /// that clears the value (和翻译模型一样).
    private fun modelPicker(label: String, current: String, placeholder: String, sameLabel: String?, host: String,
                            catalog: () -> List<String>, refetch: () -> Unit, pick: (String) -> Unit) =
        ui.listRow(label, null, trailing = value(if (current.isEmpty()) sameLabel ?: L("未填") else short(current))) {
            pickModel(label, current, placeholder, sameLabel, host, catalog, refetch, pick)
        }

    private fun pickModel(title: String, current: String, placeholder: String, sameLabel: String?, host: String,
                          catalog: () -> List<String>, refetch: () -> Unit, pick: (String) -> Unit) {
        lateinit var d: android.app.Dialog
        fun choose(id: String) { d.dismiss(); if (id != current) pick(id) }
        val search = android.widget.EditText(this).apply {
            setSingleLine()
            // Model ids: ASCII, no autocorrect, the URL keyboard.
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            imeHintLocales = android.os.LocaleList(java.util.Locale.US)
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE or android.view.inputmethod.EditorInfo.IME_FLAG_FORCE_ASCII
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16f)
            background = ui.rounded(Palette.ground, 16)
            setPadding(ui.dp(16), 0, ui.dp(16), 0)
            minHeight = ui.dp(52)
        }
        val list = ui.stack(0)
        val scroll = android.widget.ScrollView(this).apply { addView(list) }
        val foot = ui.helper("")
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(ui.button(L("取消"), "quiet") { d.dismiss() }, ui.weight())
            addView(ui.button(L("保存"), "primary") { choose(search.text.toString().trim()) }, ui.weight().apply { leftMargin = ui.dp(10) })
        }
        fun row(text: String, on: Boolean, action: () -> Unit) = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = ui.dp(48)
            setPadding(ui.dp(16), ui.dp(4), ui.dp(12), ui.dp(4))
            addView(ui.text(text, 15f, Palette.ink, bold = on, lines = 2), ui.weight())
            if (on) addView(ui.icon(R.drawable.i_check, 20, Palette.ink), LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)))
            contentDescription = text
            isSelected = on
            ui.tappable(this, 16, if (on) ui.rounded(Palette.ground, 16) else null) { action() }
        }
        var shape: Boolean? = null
        var listed = false
        fun render() {
            val all = catalog()
            val q = search.text.toString().trim()
            listed = all.isNotEmpty()
            if (shape != listed) {
                // No list: a plain field, saved with 保存; a list: search it, or use what was typed.
                shape = listed
                search.hint = if (listed) L("搜索或输入模型") else placeholder
                scroll.visibility = if (listed) View.VISIBLE else View.GONE
                buttons.visibility = if (listed) View.GONE else View.VISIBLE
            }
            foot.text = if (listed) LF("%@ 列出 %lld 个模型", host, all.size) else L("这个地址没列出模型，直接填名字")
            list.removeAllViews()
            if (!listed) return
            val matches = if (q.isEmpty()) all else all.filter { it.contains(q, ignoreCase = true) }
            if (q.isNotEmpty() && q !in all) list.addView(row(LF("用 %@（列表里没有）", q), false) { choose(q) })
            if (sameLabel != null && q.isEmpty()) list.addView(row(sameLabel, current.isEmpty()) { choose("") })
            matches.take(300).forEach { id -> list.addView(row(id, id == current) { choose(id) }) }
        }
        search.setOnEditorActionListener { _, a, _ ->
            if (a != android.view.inputmethod.EditorInfo.IME_ACTION_DONE) return@setOnEditorActionListener false
            // Done: the only match, else exactly what was typed.
            val q = search.text.toString().trim()
            val matches = catalog().filter { it.contains(q, ignoreCase = true) }
            if (listed && q.isNotEmpty() && matches.size == 1) choose(matches[0]) else if (q.isNotEmpty() || !listed) choose(q)
            true
        }
        search.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(t: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(t: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(e: android.text.Editable?) { render() }
        })
        val again = ui.textButton(L("重新获取")) {
            val app = cicada
            app.background.execute { refetch(); app.main.post { if (d.isShowing) render() } }
        }
        val footer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(ui.dp(4), 0, ui.dp(4), 0)
            addView(foot, ui.weight())
            addView(again)
        }
        // Without a list the field holds the name to edit; with one it searches.
        if (catalog().isEmpty()) search.setText(current)
        render()
        val body = ui.stack(10, search, scroll, footer, buttons)
        (scroll.layoutParams as LinearLayout.LayoutParams).height = ui.dp(48 * 6)
        d = ui.sheet(this, title, body)
        d.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        d.show()
        search.requestFocus()
    }

    /// 听对方: the hear model, which may run on its own server; its state is the check's hear step.
    private fun hearSection(app: CicadaApp, c: AIConfig, open: MutableSet<String>, rows: MutableList<View>) {
        val ling = app.ling
        val s = app.settings
        val st = ling.aiCheck[AICheck.StepID.Hear]
        val detail = listOf(ling.hearHost, short(c.hearModel).ifEmpty { L("未填") }).filter { it.isNotEmpty() }.joinToString(" · ")
        val (dot, trailing) = when {
            !ling.hasKey -> grey to null
            st == AICheck.State.Running -> Palette.accent to L("正在检查…")
            st is AICheck.State.Ok -> AiCheckViews.ok to st.seconds?.let { LF("听 %@ 秒", "%.1f".format(Strings.locale, it)) }
            st == AICheck.State.Busy -> AiCheckViews.warn to LF("%@ 现在很忙", ling.serviceName)
            st is AICheck.State.Fail -> Palette.link to (if (st.reason == AICheck.Reason.Unreachable) L("暂时连不上") else L("模型用不了"))
            else -> grey to null
        }
        rows.add(useRow("hear", open, L("听对方"), detail, dot, trailing, if (st is AICheck.State.Fail) Palette.link else Palette.tertiary))
        if ("hear" !in open) return
        val problem = if (ling.aiCheck.failure?.step == AICheck.StepID.Hear) ling.checkMessage() else null
        rows.add(panel(
            fieldRow(L("模型"), s.aiHearModels["custom"].orEmpty(), L("例如 qwen3-omni"), L("要能输入音频：听对方和“我说”都用它")) { app.setAiModel("hear", it) },
            fieldRow(L("地址"), s.aiCustomHearBase, L("跟上面一样"), null, L("跟上面一样"), ::where) { s.aiCustomHearBase = it; s.save(); app.aiChanged() },
            badAddress(s.aiCustomHearBase),
            problem?.let { note(it, Palette.link) },
        ))
    }

    /// 同传声音: the speech model that reads 我说 to the other side; empty is the phone's voice.
    private fun voiceSection(app: CicadaApp, c: AIConfig, open: MutableSet<String>, rows: MutableList<View>) {
        val ling = app.ling
        val s = app.settings
        val voiceModel = s.aiVoiceModels["custom"].orEmpty()
        val host = c.voiceBase?.let { Uri.parse(it).host }.orEmpty()
        val detail = if (voiceModel.isEmpty()) L("没填，用手机的声音") else listOf(host, voiceModel, s.aiCustomVoice).filter { it.isNotEmpty() }.joinToString(" · ")
        val last = ling.lastVoice?.first
        val dot = if (voiceModel.isEmpty() || last == null) grey else if (last) AiCheckViews.ok else Palette.link
        val trailing = if (voiceModel.isEmpty()) null else last?.let { if (it) L("上次正常") else L("上次没出声") }
        rows.add(useRow("voice", open, L("同传声音"), detail, dot, trailing, if (last == false) Palette.link else Palette.tertiary))
        if ("voice" !in open) return
        rows.add(panel(
            fieldRow(L("模型"), voiceModel, L("例如 kokoro"), L("需支持 /audio/speech；不填就用手机的声音")) { app.setAiModel("voice", it) },
            fieldRow(L("声音"), s.aiCustomVoice, L("例如 af_heart"), null) { s.aiCustomVoice = it; s.save(); app.aiChanged(check = false) },
            fieldRow(L("地址"), s.aiCustomVoiceBase, L("跟上面一样"), null, L("跟上面一样"), ::where) { s.aiCustomVoiceBase = it; s.save(); app.aiChanged(check = false) },
            badAddress(s.aiCustomVoiceBase),
        ))
    }

    /// Recommended models first, with why, then everything else the service lists.
    private fun modelRow(label: String, helper: String?, recommended: List<Model>, listed: List<String>, current: String, pick: (String) -> Unit): View {
        val options = recommended.map { it.id to (it.id + if (it.note.isNotEmpty()) " · " + L(it.note) else "") }.toMutableList()
        for (id in listed) if (options.none { it.first == id }) options.add(id to id)
        if (current.isNotEmpty() && options.none { it.first == current }) options.add(current to current)
        return ui.listRow(label, helper, trailing = value(short(current))) {
            ui.choose(this, label, options, current) { pick(it) }
        }
    }

    private fun choiceRow(label: String, options: List<Pair<String, String>>, selected: String, helper: String? = null, changed: (String) -> Unit) =
        ui.listRow(label, helper, trailing = value(options.firstOrNull { it.first == selected }?.second ?: selected)) {
            ui.choose(this, label, options, selected) { changed(it) }
        }

    /// A typed value (a custom service's address and models): the row shows it, tapping edits it.
    private fun fieldRow(label: String, current: String, hint: String, helper: String?, empty: String = L("未填"),
                         shown: (String) -> String = ::short, save: (String) -> Unit) =
        ui.listRow(label, helper, trailing = value(if (current.isEmpty()) empty else shown(current))) {
            // Addresses, model ids and voice names: ASCII, no autocorrect, the URL keyboard.
            ui.input(this, label, current, helper = helper, hint = hint,
                     type = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI) { if (it != current) save(it) }
        }

    companion object {
        fun name(p: Provider) = if (p.id == "custom") L(p.name) else p.name
        fun label(p: Provider) = if (p.id == "ling") "Ling" + L("（推荐）") else name(p)

        /// A model id without its vendor ("qwen3.8-omni-flash"): the rows are narrow.
        fun short(id: String) = id.substringAfterLast('/')

        /// The service's own voice for 我说 (Ming on Ling, Gemini on OpenRouter and ZenMux), or null:
        /// the phone's. Which of its voices is 读出来的声音's choice.
        fun cloudVoice(app: CicadaApp): String? {
            val c = app.ling.config()
            if (!app.ling.speaks) return null
            if (c.isLing) return "Ming"
            val m = c.voiceModel ?: return null
            return if ("gemini" in m.lowercase()) "Gemini" else short(m)
        }

        /// How the service is doing, under its key; null when there's nothing to say.
        fun status(app: CicadaApp): String? {
            val ling = app.ling
            val check = ling.aiCheck
            if (!ling.hasKey) return null
            if (check.running) return L("正在检查…")
            // Named after the step that failed: a missing model is not a connection problem.
            check.failure?.takeIf { it.reason != AICheck.Reason.Busy }?.let {
                return when (it.step) {
                    AICheck.StepID.Reach -> L("暂时连不上")
                    AICheck.StepID.Key -> L("这个 key 用不了")
                    AICheck.StepID.Text, AICheck.StepID.Hear -> L("模型用不了")
                }
            }
            if (check.busy) return LF("%@ 现在很忙", ling.serviceName)
            return AiCheckViews.summary(check)
        }

        /// The 设置 row's line: connected (and what that costs in delay), or what's wrong.
        fun summary(app: CicadaApp): String {
            val ling = app.ling
            val k = ling.currentKey() ?: return L("还没填 API key")
            val check = ling.aiCheck
            if (check.failure != null || check.busy) return ling.checkMessage() ?: status(app) ?: AIKey.masked(k)
            if (ling.config().isLing) return AIKey.masked(k) + " · " + L("正常")
            return status(app) ?: L("已连接")
        }

        /// The prefix says whose key it is: a management key can't call models, and another
        /// service's key goes there with one tap (改用 %@ into `into`), never a silent switch.
        /// True when the key isn't for `service`: don't save it here.
        fun keyHint(ui: Ui, key: String, service: String, status: android.widget.TextView, into: LinearLayout, switched: () -> Unit): Boolean {
            val (owner, management) = AICheck.owner(key) ?: return false
            if (management) {
                status.text = L("这是 ZenMux 的管理 key，不能用来调用模型。请粘贴 sk-payg 开头的 key。")
            } else if (owner != service) {
                val name = Providers.named(owner).name
                status.text = LF("这是 %@ 的 key。", name)
                into.addView(ui.button(LF("改用 %@", name), "primary", height = 44) {
                    into.removeAllViews()
                    ui.context.cicada.switchService(owner, key)
                    switched()
                })
            } else return false
            status.setTextColor(Palette.link)
            status.setCompoundDrawablesRelative(null, null, null, null)
            status.announceForAccessibility(status.text)
            return true
        }

        /// Change or remove the key of the service in use: a sheet with the field, 粘贴, and 删除.
        fun editKey(activity: Activity, ui: Ui) {
            val app = activity.cicada
            val p = app.ling.provider
            val isLing = p.id == "ling"
            val status = ui.helper("")
            lateinit var dialog: android.app.Dialog
            lateinit var submit: () -> Unit
            val box = ui.keyField { submit() }
            // A service on this phone or the local network may need none (the key is optional there).
            val base = app.ling.config().base
            if (p.id == "custom" && base != null && Providers.isNearby(base)) box.hint = L("本机和局域网服务可不填")
            val field = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = ui.rounded(Palette.ground, 16)
                setPadding(ui.dp(16), ui.dp(4), ui.dp(4), ui.dp(4))
                addView(box, ui.weight())
                addView(ui.button(L("粘贴"), "white", R.drawable.i_clipboard, height = 44) { SettingsActivity.paste(box) })
            }
            val other = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_HORIZONTAL }
            submit = submit@{
                val text = box.text.toString().trim()
                other.removeAllViews()
                if (keyHint(ui, text, p.id, status, other) { dialog.dismiss() }) return@submit
                if (isLing && !text.startsWith("sk-")) { status.text = L("要粘贴 sk- 开头的 Ling key"); status.setTextColor(Palette.link); return@submit }
                if (text.isEmpty()) return@submit
                if (!app.key.save(text)) { status.text = L("保存失败"); return@submit }
                app.aiChanged()
                dialog.dismiss()
            }
            val body = ui.stack(10, field, status, other,
                LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(ui.button(L("取消"), "quiet") { dialog.dismiss() }, ui.weight())
                    addView(ui.button(L("保存"), "primary") { submit() }, ui.weight().apply { leftMargin = ui.dp(10) })
                })
            if (app.key.read() != null)
                body.addView(ui.textButton(if (isLing) L("删除 Ling key") else L("删除"), Palette.link) { app.key.remove(); app.aiChanged(); dialog.dismiss() })
            dialog = ui.sheet(activity, if (isLing) L("更换 Ling key") else LF("粘贴 %@ 的 key", name(p)), body)
            dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            dialog.show()
            box.requestFocus()
        }
    }
}
