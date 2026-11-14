"""我自己的声音 (the Mac's VoiceCloneSheet and VoiceRecorder): read a passage for 10–15 s, Ming hears
what it says, listen to the original and to the clone, then keep it (voice_reference). The
recording stays in memory until 用这个声音; the network runs on worker threads."""
from __future__ import annotations

import threading
from array import array

from gi.repository import GLib, Gtk

from ..core import voice_reference as ref
from ..core import voices as voicemod
from ..core.audio import RATE, Wav
from ..core.ling import LingError
from ..core.strings import L, LF
from ..core.support import TARGETS, Log, clock
from . import ui


def own_and_other(app) -> tuple:
    """My language, and one to interpret it into (the room's, else English or Chinese): Ming hears
    the recording through the interpreting prompt, whose ORIGINAL line is what it says."""
    mine = app.settings.speak_from_code
    other = app.speak.target
    if voicemod.key(other) == voicemod.key(mine):
        other = "en" if voicemod.key(mine) != "en" else "zh-CN"
    return mine, other


def transcribe(app, samples: array) -> str:
    """What the recording says, as Ming hears it; "" when it heard nothing usable."""
    mine, other = own_and_other(app)
    heard = app.translator.interpret(Wav.bytes(samples), mine, other)
    return heard[0].strip() if heard else ""


class Recorder:
    """The microphone into memory, 16 kHz mono, stopping by itself at 15 s. Phases as on the Mac:
    idle, recording, checking (Ming hears it), ready, failed (`why`). `on_change` comes on the main loop."""

    def __init__(self, app, on_change):
        self.app = app
        self.on_change = on_change
        self.phase = "idle"
        self.why = ""
        self.samples = array("h")
        self.level = 0.0
        self.transcript = ""
        self._lock = threading.Lock()
        self._source = None
        self._tick = None
        self._gen = 0

    @property
    def seconds(self) -> float:
        return len(self.samples) / RATE

    def start(self, source=None) -> None:
        """`source`: an AudioSource (a WAV for tests); else the real microphone, not 知了 麦克风."""
        from .capture import SystemAudio
        self.cancel()
        self._gen += 1
        gen = self._gen
        self.samples = array("h")
        self.transcript = ""
        self.why = ""
        if source is None:
            real = self.app.room.real_mic if self.app.room.on else None
            source = SystemAudio(real or "@DEFAULT_SOURCE@", name=L("录制你的声音"))

        def got(samples):
            if gen != self._gen:
                return
            with self._lock:
                self.samples.extend(samples)
            if samples:
                self.level = (sum(x * x for x in samples) / len(samples)) ** 0.5 / 32768.0  # RMS; ui.loudness shows it

        def ended(why):
            if gen != self._gen:
                return
            if why:
                Log.d("voice clone: microphone ended %s" % why)
                GLib.idle_add(lambda: self._fail(L("麦克风没收到声音，请检查麦克风权限")) or False)
            else:  # a file ran out
                GLib.idle_add(lambda: self.finish() or False)
        source.on_samples = got
        source.on_ended = ended
        self._source = source
        self.phase = "recording"
        source.start()
        self._tick = GLib.timeout_add(100, self._tock)
        self.on_change()

    def _tock(self) -> bool:
        if self.phase != "recording":
            self._tick = None
            return False
        if self.seconds >= ref.MAX_SECONDS:
            self._tick = None
            self.finish()
            return False
        self.on_change()
        return True

    def _stop(self) -> None:
        if self._source is not None:
            self._source.stop()
            self._source = None
        if self._tick is not None:
            GLib.source_remove(self._tick)
            self._tick = None
        self.level = 0.0

    def _fail(self, why: str) -> None:
        self._stop()
        self.phase, self.why = "failed", why
        self.on_change()

    def finish(self) -> None:
        """Stops and has Ming hear it; ready when it is long enough, understood and not too slow."""
        if self.phase != "recording":
            return
        self._stop()
        with self._lock:
            samples = ref.trim(self.samples[:int(ref.MAX_SECONDS * RATE)])
            self.samples = samples
        if self.seconds < ref.MIN_SECONDS:
            self._fail(LF("录音太短了，请至少朗读 %lld 秒", int(ref.MIN_SECONDS)))
            return
        self.phase = "checking"
        self.on_change()
        gen = self._gen

        def run():
            try:
                text = transcribe(self.app, samples)
                failed = None
            except LingError as e:
                text, failed = "", e
            why = ref.check(samples, text)
            Log.d("voice clone: %.1f s, %d chars, %s" % (len(samples) / RATE, len(text), failed or why or "ok"))

            def done():
                if gen != self._gen:
                    return False
                self.transcript = text
                if failed is not None and failed.kind in (LingError.NETWORK, LingError.TIMEOUT):
                    self._fail(L("连不上 Ling，检查网络或代理"))
                elif why == "unclear" or failed is not None:
                    self._fail(L("没听清录音内容，请换个安静的地方再录一次"))
                elif why == "slow":
                    self._fail(L("读得有点慢，克隆的声音也会这么慢。请用平时说话的语速再录一次"))
                else:
                    self.phase = "ready"
                    self.on_change()
                return False
            GLib.idle_add(done)
        threading.Thread(target=run, name="VoiceClone", daemon=True).start()

    def cancel(self) -> None:
        self._gen += 1
        self._stop()
        self.phase = "idle"


class VoiceCloneDialog:
    """The sheet: record, then review. `on_done(saved)` when it closes."""

    def __init__(self, app, parent=None, on_done=None):
        self.app = app
        self.on_done = on_done
        self.consent = False
        self.playing = None          # "original" or "clone" while one plays
        self._play_gen = 0
        self.recorder = Recorder(app, self.render)
        d = Gtk.Dialog(transient_for=parent, modal=True)
        d.set_decorated(False)
        d.set_resizable(False)
        ui.classes(d, "endask", "sharesheet")
        d.connect("key-press-event", self._key)
        d.connect("destroy", lambda *_: self._gone())
        self.window = d
        self.body = ui.vbox(16)
        self.body.set_size_request(504, -1)  # 560 with the padding, as on the Mac
        d.get_content_area().pack_start(ui.pad(self.body, 28), True, True, 0)
        self._last = None
        self.render()
        d.show_all()

    @property
    def target(self) -> str:
        return self.app.speak.target

    def _key(self, _w, ev) -> bool:
        from gi.repository import Gdk
        if ev.keyval == Gdk.KEY_Escape:
            self.close(False)
            return True
        return False

    def _gone(self) -> None:
        self.recorder.cancel()
        self._play_gen += 1
        if self.window is not None:
            self.window = None
            if self.on_done:
                self.on_done(False)
                self.on_done = None

    def close(self, saved: bool) -> None:
        cb, self.on_done = self.on_done, None
        w, self.window = self.window, None
        self.recorder.cancel()
        self._play_gen += 1
        if w is not None:
            w.destroy()
        if cb:
            cb(saved)

    # Layout

    def render(self) -> None:
        if self.window is None:
            return
        r = self.recorder
        # The meter ticks ten times a second: only its labels change then, not the whole sheet.
        shape = (r.phase, r.why, self.consent, self.playing, self.app.ling.speaks)
        if shape == self._last and r.phase == "recording" and hasattr(self, "_clock"):
            ui.retext(self._clock, clock(r.seconds))
            self._bar.set_fraction(min(1.0, r.seconds / ref.MAX_SECONDS))
            self._level.set_value(ui.loudness(r.level))
            return
        self._last = shape
        ui.clear(self.body)
        (self._review if r.phase == "ready" else self._record)()
        self.body.show_all()
        GLib.idle_add(lambda: self.window is not None and self.window.resize(1, 1) and False)

    def _heading(self, title: str, sub: str) -> None:
        self.body.pack_start(ui.vbox(6, ui.text(title, 18, "ink", bold=True), ui.text(sub, 13, "secondary", width_chars=50)),
                             False, False, 0)

    def _buttons(self, left, right) -> None:
        row = ui.hbox(8)
        row.pack_start(left, False, False, 0)
        row.pack_end(right, False, False, 0)
        self.body.pack_start(row, False, False, 0)

    def _record(self) -> None:
        r = self.recorder
        self._heading(L("录制你的声音"), L("请用平时开会的自然语气朗读以下段落，约 15 秒，在安静环境下录制效果最佳。"))
        passage = ui.text(ref.passage(self.app.settings.speak_from_code), 16, "ink", width_chars=44, selectable=True)
        self.body.pack_start(ui.panel(ui.pad(passage, 16, 20), "voicepassage"), False, False, 0)
        if r.phase == "recording":
            meter = ui.hbox(14)
            meter.pack_start(ui.breathing_dot(), False, False, 0)
            self._clock = ui.text(clock(r.seconds), 14, "ink", bold=True, wrap=False)
            meter.pack_start(self._clock, False, False, 0)
            self._level = Gtk.LevelBar()
            self._level.set_value(ui.loudness(r.level))
            self._level.set_valign(Gtk.Align.CENTER)
            meter.pack_start(self._level, True, True, 0)
            meter.pack_end(ui.text(LF("%lld–%lld 秒", int(ref.MIN_SECONDS), int(ref.MAX_SECONDS)), 12, "tertiary", wrap=False), False, False, 0)
            self._bar = Gtk.ProgressBar()
            self._bar.set_fraction(min(1.0, r.seconds / ref.MAX_SECONDS))
            self.body.pack_start(ui.panel(ui.pad(ui.vbox(10, meter, self._bar), 12, 16), "voicemeter"), False, False, 0)
        elif r.phase == "failed":
            self.body.pack_start(ui.panel(ui.pad(ui.text(r.why, 12, "", width_chars=50), 12), "voicefail"), False, False, 0)
        check = Gtk.CheckButton()
        ui.classes(check, "voicecheck")
        check.add(ui.text(L("这是我自己的声音。只在我说话时用它替我翻译。"), 12, "secondary", width_chars=46))
        check.set_active(self.consent)
        check.set_sensitive(r.phase != "recording")

        def toggled(w):
            self.consent = w.get_active()
            self.render()
        check.connect("toggled", toggled)
        self.body.pack_start(check, False, False, 0)
        cancel = ui.soft_button(L("取消"), lambda: self.close(False))
        if r.phase == "recording":
            go = ui.soft_button(L("读完了"), r.finish, dark=True)
            go.set_sensitive(r.seconds >= ref.MIN_SECONDS)
            GLib.timeout_add(int(max(0.0, ref.MIN_SECONDS - r.seconds) * 1000) + 50,
                             lambda: self.window is not None and go.set_sensitive(True) and False)
        elif r.phase == "checking":
            go = ui.hbox(8, Gtk.Spinner(active=True), ui.text(L("正在听写…"), 12, "secondary", wrap=False))
        else:
            go = ui.soft_button(L("开始录") if r.phase == "idle" else L("再录一次"), lambda: r.start(), dark=True)
            go.set_sensitive(self.consent)
        self._buttons(cancel, go)

    def _review(self) -> None:
        r = self.recorder
        self._heading(L("录好了，先听听像不像"), LF("%lld 秒 · 识别出的文字会与录音一起用于学习你的音色", int(round(r.seconds))))
        names = {voicemod.key(c): n for n, c in TARGETS}
        title = LF("用你的声音说%@", names.get(voicemod.key(self.target), self.target))
        rows = ui.vbox(0, self._row("original", False, L("你的原声"), r.transcript),
                       self._row("clone", True, title, voicemod.sample(self.target), L("对方会听到这个")))
        rows.get_children()[1].get_style_context().add_class("prow-top")
        self.body.pack_start(ui.panel(rows, "voicerows"), False, False, 0)
        if not self._clones():
            self.body.pack_start(ui.text(L("需先在“AI 服务”中填入 Ling key，才能使用你自己的声音。"), 12, "warn", width_chars=50), False, False, 0)
        self.body.pack_start(ui.text(L("听起来不像或有杂音？换个安静的地方重录一次。录音仅保存在本机，可随时删除。"), 12, "tertiary", width_chars=50),
                             False, False, 0)
        use = ui.soft_button(L("用这个声音"), self.save, dark=True)
        use.set_sensitive(self._clones())
        self._buttons(ui.soft_button(L("重录"), self.rerecord), use)

    def _clones(self) -> bool:
        return self.app.ling.usable and voicemod.clones(self.app.ling.config())

    def _row(self, which: str, accent: bool, title: str, detail: str, tag: str | None = None) -> Gtk.Widget:
        row = ui.hbox(12)
        b = Gtk.Button()
        if self.playing == which and which == "clone":
            b.add(Gtk.Spinner(active=True))
        else:
            b.add(ui.icon("media-playback-stop-symbolic" if self.playing == which else "media-playback-start-symbolic", 12))
        ui.classes(b, "voiceplay", "accent" if accent else "")
        b.set_valign(Gtk.Align.CENTER)
        b.get_accessible().set_name(title)
        b.connect("clicked", lambda *_: self.play(which))
        b.set_sensitive(which == "original" or self._clones())
        row.pack_start(b, False, False, 0)
        words = ui.vbox(2, ui.text(title, 13, "ink", bold=True, wrap=False), ui.text(detail, 12, "tertiary", wrap=False))
        for l in words.get_children():
            l.set_max_width_chars(36)  # one line each, cut short, so the sheet keeps the Mac's width
        row.pack_start(words, True, True, 0)
        if tag:
            t = ui.text(tag, 11, "", wrap=False)
            ui.classes(t, "voicetag")
            t.set_valign(Gtk.Align.CENTER)
            row.pack_end(t, False, False, 0)
        return ui.panel(ui.pad(row, 12, 14), "voicewash" if accent else "")

    # Actions

    def rerecord(self) -> None:
        self._play_gen += 1
        self.playing = None
        self.recorder.start()

    def play(self, which: str) -> None:
        """The original from memory, or the clone saying the sample line, on the speakers."""
        from .room import Player
        if self.playing == which:
            self._play_gen += 1
            self.playing = None
            self.render()
            return
        self._play_gen += 1
        gen = self._play_gen
        self.playing = which
        self.render()
        r = self.recorder
        samples, transcript, target = r.samples, r.transcript, self.target
        ling = self.app.ling

        def run():
            out = None
            n = 0
            try:
                if which == "original":
                    out = Player(None, rate=RATE)
                    data = samples.tobytes()
                    for i in range(0, len(data), RATE // 5 * 2):
                        if gen != self._play_gen:
                            break
                        out.write(data[i:i + RATE // 5 * 2])
                        n += 1
                else:
                    clip = ("data:audio/wav;base64," + __import__("base64").b64encode(Wav.bytes(samples)).decode(), transcript)
                    lang = voicemod.ming_language(target, ling.config())
                    for pcm in ling.speech(voicemod.sample(target), voice=None, language=lang, reference=clip):
                        if gen != self._play_gen:
                            break
                        if out is None:
                            out = Player(None)
                        out.write(pcm)
                        n += 1
                if out is not None and gen == self._play_gen:
                    out.drain()
                Log.d("voice clone: played %s, %d chunks" % (which, n))
            except Exception as e:  # noqa: BLE001
                Log.d("voice clone: play %s failed %s" % (which, e))
            finally:
                if out is not None:
                    out.close()

                def done():
                    if gen == self._play_gen:
                        self.playing = None
                        self.render()
                    return False
                GLib.idle_add(done)
        threading.Thread(target=run, name="VoiceClonePlay", daemon=True).start()

    def save(self) -> None:
        r = self.recorder
        try:
            ref.save(r.samples, r.transcript)
        except OSError as e:
            Log.d("voice clone: save failed %s" % type(e).__name__)
            return
        Log.d("voice clone: saved %d s" % int(r.seconds))
        s = self.app.settings
        s.speakVoices[voicemod.key(self.target)] = voicemod.CLONE
        s.save()
        self.close(True)
