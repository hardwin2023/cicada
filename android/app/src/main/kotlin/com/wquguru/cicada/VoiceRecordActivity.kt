package com.wquguru.cicada

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import cicada.Log
import cicada.Segmenter
import cicada.Strings
import cicada.Strings.L
import cicada.VoiceCatalog
import cicada.VoiceReference
import cicada.Wav
import java.io.File
import kotlin.concurrent.thread

/// 我自己的声音: the Mac's VoiceCloneSheet as a page. Read a passage for 10–15 s → Ming writes down
/// what it says → listen to the recording and to the clone → 用这个声音 keeps it (VoiceReference)
/// and picks it for the language the picker was on (`id`). Nothing is kept until then.
class VoiceRecordActivity : Activity() {
    private enum class Phase { Idle, Recording, Checking, Ready, Failed }

    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private lateinit var language: String
    private var phase = Phase.Idle
    private var problem = ""
    private var seconds = 0.0
    @Volatile private var pcm = ShortArray(0)
    private var transcript = ""
    @Volatile private var record: AudioRecord? = null
    private var player: AudioTrack? = null
    private var playingOriginal = false
    private var unobserve: (() -> Unit)? = null

    /// My language: the passage is in it, and it decides 最像你 / 会带你的口音.
    private val own get() = cicada.settings.targetCode

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        language = intent.getStringExtra("id") ?: cicada.listen.theirLanguage
        page = ui.stack(0).apply { setPadding(ui.dp(24), 0, ui.dp(24), ui.dp(32)) }
        setContentView(ui.screen(this, null, back = true, ground = Palette.card, body = page))
        // Debug (`show record <wav in files/>`): a pushed WAV stands in for the microphone.
        intent.getStringExtra("wav")?.let { name ->
            try { pcm = Wav.read(File(filesDir, name).inputStream()); seconds = pcm.size / Segmenter.RATE.toDouble(); phase = Phase.Recording; finishRecording(); return } catch (e: Exception) { Log.d("voice clone: no ${e.javaClass.simpleName}") }
        }
        build()
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe { if (phase == Phase.Ready) build() } }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    override fun onDestroy() {
        super.onDestroy()
        stopRecorder()
        stopPlayer()
    }

    private fun build() {
        page.removeAllViews()
        if (phase == Phase.Ready) review() else recording()
    }

    // MARK: Reading the passage

    private fun recording() {
        page.addView(ui.title(L("录制你的声音")))
        page.addView(ui.helper(L("请用平时开会的自然语气朗读以下段落，约 15 秒，在安静环境下录制效果最佳。")).apply { leading(1.5f) }, ui.lp(top = 10))
        page.addView(ui.text(VoiceReference.passage(own), 17f, Palette.ink).apply {
            leading(1.75f)
            background = ui.rounded(Palette.ground, 16)
            setPadding(ui.dp(18), ui.dp(16), ui.dp(18), ui.dp(16))
        }, ui.lp(top = 18))
        page.addView(ui.helper(L("这是我自己的声音。只在我说话时用它替我翻译。"), Palette.tertiary), ui.lp(top = 12))

        val clock = ui.text("%d:%02d".format(seconds.toInt() / 60, seconds.toInt() % 60), 32f, Palette.ink).apply { gravity = Gravity.CENTER }
        val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = (VoiceReference.MAX_SECONDS * 10).toInt()
            progress = (seconds * 10).toInt()
            progressTintList = ColorStateList.valueOf(Palette.accent)
            progressBackgroundTintList = ColorStateList.valueOf(Palette.divider)
        }
        val range = ui.helper(Strings.LF("%lld–%lld 秒", VoiceReference.MIN_SECONDS.toInt(), VoiceReference.MAX_SECONDS.toInt()), Palette.tertiary).apply { gravity = Gravity.CENTER }
        clockView = clock; barView = bar
        page.addView(clock, ui.lp(top = 36))
        page.addView(bar,LinearLayout.LayoutParams(ui.dp(240), ui.dp(6)).apply { topMargin = ui.dp(10); gravity = Gravity.CENTER_HORIZONTAL })
        page.addView(range, ui.lp(top = 8))

        when (phase) {
            Phase.Checking -> page.addView(ui.row(10,
                ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply { indeterminateTintList = ColorStateList.valueOf(Palette.accent) },
                ui.helper(L("正在听写…"))).apply { gravity = Gravity.CENTER }, ui.lp(top = 28))
            else -> {
                if (phase == Phase.Failed) page.addView(ui.text(problem, 14f, Palette.link).apply { gravity = Gravity.CENTER }, ui.lp(top = 20))
                val label = when (phase) { Phase.Recording -> L("读完了"); Phase.Failed -> L("再录一次"); else -> L("开始录") }
                page.addView(recordButton(label), LinearLayout.LayoutParams(ui.dp(88), ui.dp(88)).apply { topMargin = ui.dp(20); gravity = Gravity.CENTER_HORIZONTAL })
                page.addView(ui.helper(label).apply { gravity = Gravity.CENTER; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, ui.lp(top = 10))
            }
        }
    }

    /// The big round button: a mic to start, a square to finish.
    private fun recordButton(label: String) = FrameLayout(this).apply {
        contentDescription = label
        background = ui.rounded(Palette.accentPale, 44)
        val inner = FrameLayout(context).apply { background = ui.rounded(Palette.accent, 32) }
        if (phase == Phase.Recording) inner.addView(View(context).apply { background = ui.rounded(Color.WHITE, 4) }, FrameLayout.LayoutParams(ui.dp(22), ui.dp(22), Gravity.CENTER))
        else inner.addView(ui.icon(R.drawable.i_mic, 28, Color.WHITE), FrameLayout.LayoutParams(ui.dp(28), ui.dp(28), Gravity.CENTER))
        addView(inner, FrameLayout.LayoutParams(ui.dp(64), ui.dp(64), Gravity.CENTER))
        ui.tappable(this, 44, background) { if (phase == Phase.Recording) finishRecording() else startRecording() }
    }

    private fun startRecording() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
            return
        }
        stopPlayer()
        val rate = Segmenter.RATE
        val size = maxOf(AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT), rate)
        val r = try {
            AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                .setBufferSizeInBytes(size).build().also { it.startRecording() }
        } catch (e: Exception) { Log.d("voice clone: mic ${e.javaClass.simpleName}"); null }
        if (r == null || r.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            r?.release()
            phase = Phase.Failed; problem = L("麦克风没收到声音，请检查麦克风权限"); build(); return
        }
        record = r
        pcm = ShortArray(0); seconds = 0.0; phase = Phase.Recording
        val max = (VoiceReference.MAX_SECONDS * rate).toInt()
        thread(name = "VoiceRecord", isDaemon = true) {
            val all = ShortArray(max)
            var n = 0
            val chunk = ShortArray(rate / 10)
            while (record === r && n < max) {
                val got = r.read(chunk, 0, minOf(chunk.size, max - n))
                if (got <= 0) break
                System.arraycopy(chunk, 0, all, n, got)
                n += got
                pcm = all.copyOf(n)
            }
        }
        tick()
        build()
    }

    private var clockView: android.widget.TextView? = null
    private var barView: ProgressBar? = null

    /// The clock, 10 times a second; at 15 s the recording finishes by itself. Only the clock and
    /// bar change: rebuilding the page would drop a tap on 读完了 halfway through.
    private fun tick() {
        if (phase != Phase.Recording || isDestroyed) return
        seconds = pcm.size / Segmenter.RATE.toDouble()
        if (seconds >= VoiceReference.MAX_SECONDS - 0.05) { finishRecording(); return }
        clockView?.text = "%d:%02d".format(seconds.toInt() / 60, seconds.toInt() % 60)
        barView?.progress = (seconds * 10).toInt()
        cicada.main.postDelayed(::tick, 100)
    }

    private fun stopRecorder() {
        val r = record ?: return
        record = null
        try { r.stop() } catch (_: Exception) {}
        r.release()
    }

    /// Stops, then the Mac's checks: long enough, heard, not read too slowly.
    private fun finishRecording() {
        if (phase != Phase.Recording) return
        stopRecorder()
        val clip = pcm
        seconds = clip.size / Segmenter.RATE.toDouble()
        phase = Phase.Checking
        build()
        val app = cicada
        app.background.execute {
            val result = VoiceReference.check(app.translator, clip, own)
            app.main.post {
                if (isDestroyed) return@post
                when (result) {
                    is VoiceReference.Check.Ok -> { transcript = result.text; phase = Phase.Ready }
                    is VoiceReference.Check.Again -> { problem = Strings.LF(result.reason, *result.args.toTypedArray()); phase = Phase.Failed }
                }
                build()
            }
        }
    }

    // MARK: Listening back

    private fun review() {
        val app = cicada
        page.addView(ui.title(L("录好了，先听听像不像")))
        page.addView(ui.helper(Strings.LF("%lld 秒 · 识别出的文字会与录音一起用于学习你的音色", Math.round(seconds).toInt())).apply { leading(1.5f) }, ui.lp(top = 10))
        val original = clipRow(playingOriginal, false, L("你的原声"), transcript, null) { playOriginal() }
        val clone = clipRow(app.previewing == DRAFT, true, Strings.LF("用你的声音说%@", VoiceCatalog.title(language)), VoiceCatalog.sample(language), L("对方会听到这个")) {
            if (!app.ling.clones) return@clipRow
            stopPlayer()
            app.previewVoice(DRAFT, language, draft = draft(), failed = { android.widget.Toast.makeText(this, it, android.widget.Toast.LENGTH_SHORT).show() })
        }
        clone.background = ui.rounded(Palette.accentPale, 0)
        page.addView(ui.group(listOf(original, clone), radius = 16).apply { background = ui.rounded(Palette.card, 16, stroke = Palette.line) }, ui.lp(top = 20))
        if (!app.ling.clones) page.addView(ui.text(L("需先在“AI 服务”中填入 Ling key，才能使用你自己的声音。"), 13f, Palette.link), ui.lp(top = 12))
        page.addView(ui.helper(L("听起来不像或有杂音？换个安静的地方重录一次。录音只存在这台手机上，可随时删除。"), Palette.tertiary).apply { leading(1.5f) }, ui.lp(top = 14))
        page.addView(ui.button(L("用这个声音")) { save() }.apply { if (!app.ling.clones) alpha = 0.5f }, ui.lp(top = 32))
        page.addView(ui.button(L("重录"), kind = "quiet") { stopPlayer(); phase = Phase.Idle; seconds = 0.0; build() }, ui.lp(top = 10))
    }

    private fun draft(): Pair<String, String> =
        "data:audio/wav;base64," + java.util.Base64.getEncoder().encodeToString(Wav.bytes(pcm)) to transcript

    private fun clipRow(playing: Boolean, accent: Boolean, title: String, detail: String, tag: String?, play: () -> Unit): View {
        val button = FrameLayout(this).apply {
            contentDescription = title
            background = ui.rounded(if (accent) Palette.accent else Palette.ground, 22)
            if (playing) addView(ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
                indeterminateTintList = ColorStateList.valueOf(if (accent) Color.WHITE else Palette.accent)
            }, FrameLayout.LayoutParams(ui.dp(20), ui.dp(20), Gravity.CENTER))
            else addView(ui.icon(R.drawable.i_play, 18, if (accent) Color.WHITE else Palette.ink), FrameLayout.LayoutParams(ui.dp(18), ui.dp(18), Gravity.CENTER))
            ui.tappable(this, 22, background) { play() }
        }
        val texts = ui.stack(3, ui.text(title, 15f, Palette.ink, bold = true))
        if (tag != null) texts.addView(ui.text(tag, 12f, Palette.link))
        texts.addView(ui.text(detail, 13f, Palette.secondary).apply { leading(1.5f) })
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16))
            addView(button, LinearLayout.LayoutParams(ui.dp(44), ui.dp(44)).apply { rightMargin = ui.dp(14) })
            addView(texts, ui.weight())
        }
    }

    private fun playOriginal() {
        if (playingOriginal) { stopPlayer(); build(); return }
        cicada.voice.stop()
        val clip = pcm
        val t = try {
            AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(Segmenter.RATE).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(clip.size * 2).build()
        } catch (_: Exception) { return }
        t.write(clip, 0, clip.size)
        t.notificationMarkerPosition = clip.size
        t.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(track: AudioTrack) { stopPlayer(); if (!isDestroyed) build() }
            override fun onPeriodicNotification(track: AudioTrack) {}
        })
        player = t
        playingOriginal = true
        t.play()
        build()
    }

    private fun stopPlayer() {
        player?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
        player = null
        playingOriginal = false
    }

    private fun save() {
        val app = cicada
        if (!app.ling.clones) { startActivity(Intent(this, AiServiceActivity::class.java)); return }
        stopPlayer()
        if (app.saveVoiceReference(pcm, transcript, language)) finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startRecording()
        else { phase = Phase.Failed; problem = L("麦克风没收到声音，请检查麦克风权限"); build() }
    }

    companion object {
        /// previewVoice's id while the unsaved recording is tried.
        const val DRAFT = VoiceCatalog.CLONE
    }
}
