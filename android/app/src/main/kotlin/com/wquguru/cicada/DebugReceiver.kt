package com.wquguru.cicada

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import cicada.Json
import cicada.SilentAudioSource
import cicada.Strings
import cicada.Log
import cicada.Session
import cicada.VoiceCatalog
import cicada.Wav
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/// Debug commands for dev builds over `adb shell am broadcast` (scripts/cicadactl.sh): the
/// Android counterpart of the Mac's tools/lsctl and the Windows pipe. One command per broadcast,
/// one JSON line back as the broadcast's result (never meeting text or the key).
///   state | start [playback|mic] | stop | feed <wav in files/> | sample | view notes|subtitles
///   capture on|off | overlay show|hide | show main|live|records|settings|words|onboarding|record [id] | overlay collapse|expand | key reload
///   hear|say <wav in files/> (面对面: the other side / me holding 我说) | tts <lang> <text>
///   import <session.json in files/> | importfile <audio or video in files/> | face | onboarded on|off | target <code> | ui <lang> | clip <text>
///   provider ling|openrouter|zenmux|custom | ai-model hear|text|voice|notes <id> ("" back to the recommended) | show ai
///   ai-base <url> (the custom service's address) · ai-notes same|own · ai-notes-base <url> · notes-key import <file in files/>|remove (the custom service's 纪要)
///   key import <file in files/> (sealed as the current service's key, the plain file deleted) | voice-try (设置's 试一句)
///   voice <lang>[=<id>] (读出来的声音: choose, or say it and the options) · voice-preview <lang> [<id>] (试听) · show voices [lang]
///   ai-check (重新检查) | ai-check-sim <reason|lowBalance|off> (every check ends that way; the state's ai.check has the steps)
///   改正听错的词: fixes on|off · asknames on|off · silent (a meeting with no audio) · heard <text> · vocab add|remove|state
///   fixstate · fixanswer yes|no · fixrevert <line> · fixlater · fixundo · fixedit <line>=<text>[|one][|keep0] · pinyin <text>
///   分享…: share <id>[,full][,pw] · unshare <id> · shares · shareSheet <id> (no id: closes it) · delete <id>
///   shareserver [url] (a local Worker; none: cicada.indaloop.app) · clipboard
///   存到文件夹: export state · export folder <tree uri> (one already granted; else the problem shows) · export pick
///   (the system picker) · export all (也存一份) · export retry · export off
class DebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        val app = context.cicada
        val line = intent.getStringExtra("cmd") ?: "state"
        val pending = goAsync()
        // UI work on the main thread; the reply waits for it, then for state to settle.
        app.background.execute {
            val done = CountDownLatch(1)
            var reply: Map<String, Any?> = emptyMap()
            app.main.post { reply = try { run(app, line) } catch (e: Exception) { mapOf("error" to "${e.javaClass.simpleName}: ${e.message}") }; done.countDown() }
            done.await(5, TimeUnit.SECONDS)
            if (reply.isEmpty()) {
                val again = CountDownLatch(1)
                Thread.sleep(300)
                app.main.post { reply = state(app); again.countDown() }
                again.await(5, TimeUnit.SECONDS)
            }
            pending.resultCode = 0
            pending.resultData = Json.write(reply, pretty = false)
            pending.finish()
        }
    }

    /// Empty: "reply with the state once the command has had a moment".
    private fun run(app: CicadaApp, line: String): Map<String, Any?> {
        val parts = line.trim().split(Regex("\\s+"), 2)
        val arg = parts.getOrElse(1) { "" }
        if (parts[0] != "state") Log.d("debug: ${parts[0]}")
        fun open(cls: Class<*>, extra: String? = null) =
            app.startActivity(Intent(app, cls).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).apply { extra?.let { putExtra("id", it) } })
        when (parts[0]) {
            "state" -> return state(app)
            "start" -> app.startListening(app, arg.ifEmpty { app.settings.source })
            "stop" -> app.stopListening()
            "feed" -> app.listenToFile(File(app.filesDir, arg), play = false)
            "sample" -> app.listenToFile(null, play = true)
            // 导入录音或视频 without the file picker: any audio or video in files/.
            "importfile" -> app.importFile(app, android.net.Uri.fromFile(File(app.filesDir, arg)))
            "face" -> app.startActivity(Intent(app, FaceActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "view" -> app.setView(if (arg == "subtitles") "subtitles" else "notes")
            "capture" -> { app.settings.showInCapture = arg == "on"; app.saveSettings(); app.overlay.rebuild() }
            "overlay" -> if (arg == "collapse") { app.overlay.collapsed = true; app.overlay.rebuild() } else if (arg == "expand") { app.overlay.collapsed = false; app.overlay.rebuild() } else if (arg == "hide") { app.overlay.forced = false; app.overlay.hide() } else { app.overlay.forced = true; app.overlay.show() }
            // 面对面 without a voice: `hear` plays a WAV as the other side, `say` as me holding 我说.
            "hear" -> app.listen.inject(Wav.read(File(app.filesDir, arg).inputStream()))
            "say" -> { app.holdToSay(); app.listen.inject(Wav.read(File(app.filesDir, arg).inputStream())); app.releaseToSay() }
            // 会议自己结束 in seconds: `endtimes 20 10` (silence, countdown); `endtimes` alone resets.
            "endtimes" -> { val v = arg.split(Regex("\\s+")).mapNotNull { it.toDoubleOrNull() }; app.endTimesOverride = if (v.size == 2) v[0] to v[1] else null }
            "silence" -> { app.settings.silenceEnd = arg.ifEmpty { "prompt" }; app.saveSettings() }
            "keep" -> app.keepRecording()
            "tts" -> {
                val (lang, text) = arg.split(Regex("\\s+"), 2).let { it[0] to it.getOrElse(1) { "Hello." } }
                app.background.execute { Log.d("debug: tts $lang -> ${app.voice.speak(text, lang, {}, {})}") }
                return mapOf("tts" to lang)
            }
            "target" -> { app.settings.target = arg.ifEmpty { "system" }; app.saveSettings() }
            "ui" -> { app.settings.uiLanguage = arg.ifEmpty { "system" }; app.saveSettings(); app.loadStrings(); app.overlay.rebuild() }
            // Puts text on the clipboard (the shell can't), so 粘贴 can be tested.
            "clip" -> app.getSystemService(android.content.ClipboardManager::class.java).setPrimaryClip(android.content.ClipData.newPlainText("test", arg))
            "onboarded" -> { app.settings.onboarded = arg != "off"; app.saveSettings() }
            "key" -> if (arg.startsWith("import ")) {
                // A key pushed in as a plain file: sealed into the current service's key file like
                // one pasted in, and the plain copy goes at once.
                val f = File(app.filesDir, arg.removePrefix("import ").trim())
                val text = try { f.readText().trim() } catch (_: Exception) { "" } finally { f.delete() }
                if (text.isEmpty() || !app.key.save(text)) return mapOf("error" to "no key in ${f.name}")
                app.aiChanged()
                return mapOf("ok" to true, "ai" to ai(app))
            } else { app.key.reload(); app.ling.keyChanged(); app.background.execute { app.ling.check() } }
            "provider" -> { app.setAiProvider(arg); return mapOf("ok" to true, "ai" to ai(app)) }
            "ai-base" -> { app.settings.aiCustomBase = arg.removeSurrounding("\"").trim(); app.settings.save(); app.aiChanged(); return mapOf("ok" to true, "ai" to ai(app)) }
            "ai-notes" -> { app.setNotesOwn(arg == "own"); return mapOf("ok" to true, "ai" to ai(app)) }
            "ai-notes-base" -> { app.setNotesBase(arg.removeSurrounding("\"")); return mapOf("ok" to true, "ai" to ai(app)) }
            // The notes' own key, pushed in as a plain file like `key import`, sealed, the plain copy deleted.
            "notes-key" -> {
                if (arg == "remove") { app.setNotesKey(null); return mapOf("ok" to true, "ai" to ai(app)) }
                val f = File(app.filesDir, arg.removePrefix("import ").trim())
                val text = try { f.readText().trim() } catch (_: Exception) { "" } finally { f.delete() }
                if (text.isEmpty() || !app.setNotesKey(text)) return mapOf("error" to "no key in ${f.name}")
                return mapOf("ok" to true, "ai" to ai(app))
            }
            // The 改用 Ling on a status line (says when it isn't offered).
            "switchToLing" -> { val offered = app.canSwitchToLing; app.switchToLing(); return mapOf("offered" to offered, "ai" to ai(app)) }
            // ai-check-sim <reason|lowBalance|off>: every check ends this way (screenshots of each state).
            "ai-check-sim" -> {
                app.ling.simulateCheck = cicada.AICheck.reasonNamed(arg)
                app.ling.simulateBalance = if (arg == "lowBalance") 0.4 else null
                app.background.execute { app.ling.check() }
            }
            // 重新检查.
            "ai-check" -> app.background.execute { app.ling.check() }
            "ai-model" -> {
                val kind = arg.substringBefore(' ')
                val model = arg.substringAfter(' ', "").trim().removeSurrounding("\"")
                app.setAiModel(kind, model)
                return mapOf("ok" to true, "ai" to ai(app))
            }
            // 语音和文字只发给你的服务 (the Mac's aiCustomOnly:on|off): `ai-custom-only on|off`.
            "ai-custom-only" -> { app.setCustomOnly(arg == "on"); return mapOf("ok" to true, "ai" to ai(app)) }
            "voice-try" -> { app.previewVoice(app.voiceId("en"), "en", SettingsActivity.SAMPLE) { Log.d("debug: voice-try failed") }; return mapOf("voice" to app.voiceId("en")) }
            // 读出来的声音: `voice <lang>=<id>` chooses (en=ming:UK_George, zh=phone; en= back to the
            // default), `voice <lang>` says what it is and what's offered; `voice-preview <lang> <id>` is 试听.
            "voice" -> {
                val lang = arg.substringBefore('=')
                if ('=' in arg) {
                    val id = arg.substringAfter('=')
                    if (id.isEmpty()) app.settings.speakVoices.remove(VoiceCatalog.key(lang)) else app.settings.speakVoices[VoiceCatalog.key(lang)] = id
                    app.saveSettings()
                }
                return mapOf("lang" to lang, "voice" to app.voiceId(lang), "options" to VoiceCatalog.options(lang, app.ling.config()).map { it.id })
            }
            "voice-preview" -> {
                val words = arg.split(Regex("\\s+"), 2)
                val lang = words[0].ifEmpty { "en" }
                val id = words.getOrNull(1) ?: app.voiceId(lang)
                app.previewVoice(id, lang) { Log.d("debug: preview failed $it") }
                return mapOf("previewing" to id)
            }
            // 检查更新 against a test feed: the dev build checks only once one is set.
            "updatefeed" -> { app.updates.setFeed(if (arg.isEmpty() || arg.contains("://")) arg else File(app.filesDir, arg).path); app.updates.checkIfDue(0) }
            "update" -> when (arg) {
                "check" -> app.updates.checkNow()
                "download" -> app.updates.download()
                "job" -> app.background.execute { app.updates.checkInBackground() }
                "notify" -> app.updates.available?.let { app.updates.notifyAbout(it) }
            }
            // 改正听错的词 (the Mac's fixes / askNames / silentListen / heard / vocab* / fix* commands).
            "fixes" -> { app.settings.fixMisheard = arg != "off"; app.saveSettings() }
            "asknames" -> { app.settings.askNames = arg != "off"; app.saveSettings() }
            // A meeting with no audio at all, its lines given by `heard <text>` (translated and fixed
            // by the AI service in use, as a heard line is).
            "silent" -> if (!app.listen.listening) { app.listen.start(SilentAudioSource(), "file"); app.openLive() }
            "heard" -> app.listen.debugHeard(arg)
            // vocab add Morpho=莫拉、莫法|巡检 · vocab remove <word> · vocab state
            "vocab" -> {
                val (sub, rest) = arg.split(Regex("\\s+"), 2).let { it[0] to it.getOrElse(1) { "" } }
                when (sub) {
                    "add" -> { val r = app.vocabulary.importText(rest.replace("|", "\n")); return mapOf("added" to r.added, "updated" to r.updated, "skipped" to r.skipped) }
                    "remove" -> app.vocabulary.remove(rest)
                }
                return mapOf("terms" to app.vocabulary.terms.size, "heard" to app.vocabulary.terms.sumOf { it.heard.size }, "fixes" to app.vocabulary.terms.sumOf { it.fixes })
            }
            "fixstate" -> return fixState(app, arg.ifEmpty { null })
            "fixanswer" -> {   // fixanswer yes|no [session]
                val id = sessionOf(app, arg.substringAfter(' ', ""))
                val f = app.fixes.asking(id)?.fix ?: app.fixes.pending(id).firstOrNull()?.fix ?: return mapOf("error" to "nothing waiting")
                app.fixes.answer(f, arg.substringBefore(' ') == "yes", id)
            }
            "fixrevert" -> {   // fixrevert <line> [session]: the line's first applied fix
                val id = sessionOf(app, arg.substringAfter(' ', ""))
                val l = app.store.line(id, arg.substringBefore(' ')) ?: return mapOf("error" to "no line")
                val f = l.fixes?.firstOrNull { it.applied } ?: return mapOf("error" to "no fix")
                app.fixes.revert(f, l.id, id)
            }
            "fixlater" -> { val id = sessionOf(app, arg); app.fixes.asking(id)?.let { app.fixes.later(it.fix, id) } }
            "fixundo" -> app.fixes.undo()
            "fixedit" -> {   // fixedit <line>=<new text>[|one][|keep0] [, session]
                val (head, sid) = if (arg.contains(",") && !arg.substringAfterLast(",").contains("=")) arg.substringBeforeLast(",") to arg.substringAfterLast(",").trim() else arg to ""
                val line = head.substringBefore("=")
                val opts = head.substringAfter("=").split("|")
                val n = app.fixes.edit(line, sessionOf(app, sid), opts[0], everywhere = "one" !in opts, keep = "keep0" !in opts)
                return mapOf("changed" to n)
            }
            "pinyin" -> return mapOf("pinyin" to arg.map { Pinyin.of(it) })
            "import" -> {
                val s = Session.read(File(app.filesDir, arg).readText()) ?: return mapOf("error" to "unreadable")
                app.store.import(s)
            }
            "delete" -> app.store.delete(arg)
            // rename <id>=<title>, as typed into the record's title (empty: the automatic one).
            "rename" -> app.store.rename(arg.substringBefore('='), arg.substringAfter('=', ""))
            "export" -> {
                val ex = app.folderExport
                val rest = arg.substringAfter(' ', "")
                when (arg.substringBefore(' ')) {
                    "folder" -> ex.choose(android.net.Uri.parse(rest))
                    "pick" -> { SettingsActivity.pickFolder = true; open(SettingsActivity::class.java) }
                    "all" -> ex.writeAll()
                    "retry" -> ex.retry()
                    "off" -> ex.turnOff()
                    else -> return ex.debugState()
                }
            }
            // 分享… (the Mac's share: / unshare: / shareSheet:): `share <id>[,full][,pw]` shares as the
            // sheet would and logs the link; `unshare <id>` turns it off; `shares` lists them (never the token).
            "share" -> {
                val p = arg.split(",").map { it.trim() }
                val s = app.store.get(p[0])?.let { Session.from(it.toJson()) } ?: return mapOf("error" to "no such record")
                val o = cicada.ShareClient.Options(
                    scope = if ("full" in p || s.notes?.isEmpty != false) cicada.ShareScope.Full else cicada.ShareScope.Notes,
                    password = if ("pw" in p) cicada.SharePassword.make() else null)
                app.background.execute {
                    when (val out = app.share.share(s, o)) {
                        is cicada.ShareClient.Outcome.Shared -> Log.d("debug: share ${out.record.url}${out.record.password?.let { " password $it" } ?: ""}")
                        is cicada.ShareClient.Outcome.Blocked -> Log.d("debug: share blocked lines ${cicada.ShareHit.recordLines(out.hits, out.kept).sorted()}${if (out.hits.any { it.part == "notes" }) " notes" else ""}")
                        is cicada.ShareClient.Outcome.Failed -> Log.d("debug: share failed ${out.code}")
                    }
                }
                return mapOf("sharing" to s.id)
            }
            "unshare" -> {
                val r = cicada.ShareStore.read(arg) ?: return mapOf("error" to "$arg not shared")
                app.background.execute { Log.d("debug: share revoked ${app.share.revoke(r, arg)}") }
                return mapOf("unsharing" to arg)
            }
            // `shareserver http://127.0.0.1:8790` (after adb reverse) points 分享… at a local Worker (wrangler dev), with its
            // own device file so the real one stays registered; no argument goes back to cicada.indaloop.app.
            "shareserver" -> {
                app.share.base = arg.ifEmpty { "https://cicada.indaloop.app" }.trimEnd('/')
                app.share.deviceFile = if (arg.isEmpty()) null else File(cicada.Paths.root, "share-device-local.json")
                return mapOf("shareserver" to app.share.base)
            }
            // What is on the clipboard (the app must be in front to read it).
            "clipboard" -> return mapOf("clipboard" to app.getSystemService(android.content.ClipboardManager::class.java)
                .primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString())
            "shares" -> return mapOf("shares" to cicada.ShareStore.all().mapValues { (_, r) ->
                mapOf("id" to r.id, "url" to r.url, "scope" to r.scope, "password" to r.password, "expiresAt" to cicada.Iso8601.write(r.expiresAt))
            })
            "shareSheet" -> if (arg.isEmpty()) ShareSheet.open?.let { it.dismiss() } else
                app.startActivity(Intent(app, RecordActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    .putExtra("id", arg).putExtra("share", true))
            "show" -> when (arg.substringBefore(' ')) {
                "settings" -> open(SettingsActivity::class.java)
                "words" -> open(WordListActivity::class.java)
                "ai" -> open(AiServiceActivity::class.java)
                "voices" -> open(VoicesActivity::class.java, arg.substringAfter(' ', "").ifEmpty { null })
                "onboarding" -> open(OnboardingActivity::class.java)
                "record" -> open(RecordActivity::class.java, arg.substringAfter(' ', "").ifEmpty { app.store.all().firstOrNull { it.id != app.listen.sessionId || !app.listen.listening }?.id })
                "records" -> open(RecordsActivity::class.java)
                "live" -> app.openLive()
                else -> open(MainActivity::class.java)
            }
            else -> return mapOf("error" to "unknown command ${parts[0]}")
        }
        return emptyMap()
    }

    companion object {
        /// The meeting a fix command is for: the one named, else the live one, else the newest.
        fun sessionOf(app: CicadaApp, arg: String): String =
            arg.trim().ifEmpty { null } ?: app.store.liveId ?: app.store.all().firstOrNull()?.id ?: ""

        /// A meeting's fixes in numbers (never its words): lines fixed, applied, waiting, said no to.
        fun fixState(app: CicadaApp, arg: String?): Map<String, Any?> {
            val id = sessionOf(app, arg ?: "")
            val lines = app.store.lines(id)
            val all = lines.flatMap { it.fixes ?: emptyList() }
            return mapOf("session" to id, "on" to app.settings.fixMisheard, "askNames" to app.settings.askNames,
                          "lines" to lines.size, "fixedLines" to lines.count { it.fixes != null },
                          "fixedIds" to lines.filter { l -> l.fixes?.any { it.applied } == true }.map { it.id },
                          "applied" to all.count { it.applied }, "asked" to all.count { it.ask == true }, "off" to all.count { it.off == true },
                          "user" to all.count { it.user == true }, "pending" to app.fixes.pending(id).size,
                          "asking" to app.fixes.asking(id)?.of, "toast" to (app.fixes.toastNow() != null), "canUndo" to app.fixes.canUndo,
                          "translated" to lines.count { it.dst != null }, "terms" to app.vocabulary.terms.size)
        }

        /// The AI service in use and what its last check found (never the key itself).
        fun ai(app: CicadaApp): Map<String, Any?> {
            val l = app.ling
            val c = l.config()
            return mapOf("provider" to c.provider.id, "base" to c.base, "text" to c.textModel, "hear" to c.hearModel, "hearBase" to c.hearBase, "voice" to c.voiceModel,
                         "state" to l.keyState.name, "hears" to l.hears, "speaks" to l.speaks, "check" to l.aiCheck.summary,
                         "voice" to l.lastVoice?.first, "sim" to l.simulateCheck?.name,
                         "catalog" to listOf(l.textCatalog.size, l.hearCatalog.size, l.notesCatalog.size), "keyFile" to app.key.path.name,
                         "notes" to mapOf("apart" to c.notesApart, "base" to c.forNotes.base, "model" to c.forNotes.textModel,
                                          "own" to c.notesOwnService, "ownKey" to l.notesHasOwnKey, "bad" to c.notesBadAddress),
                         "customOnly" to app.settings.aiCustomOnly, "googleOff" to app.translator.googleOff,
                         "untranslated" to app.translator.sentencesUntranslated)
        }

        fun state(app: CicadaApp): Map<String, Any?> {
            val listen = app.listen
            val id = listen.sessionId
            return mapOf(
                "listening" to listen.listening,
                "source" to listen.sourceKind,
                "session" to id,
                "lines" to (id?.let { app.store.lines(it).size } ?: 0),
                "translated" to (id?.let { app.store.lines(it).count { l -> l.dst != null } } ?: 0),
                "pending" to listen.pending,
                "ending" to app.ending?.let { mapOf("reason" to it.reason.toString(), "left" to app.endingLeft(it)) },
                "autoEnded" to app.autoEnded,
                "say" to mapOf("can" to listen.canSay, "holding" to listen.holding, "saying" to listen.saying, "muted" to listen.muted, "speaking" to app.voice.speaking, "their" to listen.theirLanguage, "problem" to listen.sayProblem),
                "spoken" to listen.spoken,
                "target" to listen.target,
                "heardSeconds" to Math.round(listen.heardSeconds * 10) / 10.0,
                "peak" to Math.round(listen.peak * 10000) / 10000.0,
                "problem" to (listen.problem ?: app.startProblem),
                "notes" to app.notes.status.name,
                "topics" to app.notes.notes.topics.size,
                "key" to app.ling.keyState.name,
                "ai" to ai(app),
                "view" to app.settings.view,
                "showInCapture" to app.settings.showInCapture,
                "overlay" to app.overlay.describe(),
                "canOverlay" to app.canOverlay,
                "sessions" to app.store.all().size,
                "record" to RecordActivity.current?.debugState(),
                "ui" to Strings.language,
                "update" to mapOf("enabled" to app.updates.enabled, "current" to app.updates.checker.current, "available" to app.updates.available?.version,
                                  "apk" to app.updates.available?.apk, "lastChecked" to app.updates.checker.lastChecked, "notified" to app.settings.updateNotified,
                                  "manual" to app.updates.manual),
            )
        }
    }
}
