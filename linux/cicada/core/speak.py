"""同声传译 (the Mac's 说): what I say into my microphone, interpreted and spoken into the meeting.

Each sentence (cut by the same Segmenter as listening) goes to the AI service's hear model (Ming on
Ling), which returns what was said and its translation in one call; the translation is voiced by the
service's speech model (Ming's TTS on Ling) and played
into 知了 麦克风, the virtual microphone the meeting app uses. Sentences play one after another, in
order. A sentence that couldn't be interpreted is never spoken (AGENTS.md: never speak untranslated
text into the room).

Without headphones my microphone also hears the other side through the speakers. The app reads it
through the sound server's echo canceller when it can (app/room.py), which takes their voices out, so
what I say over them goes out. From the plain microphone, a sentence heard while the system audio was
loud for most of it is dropped instead, so the room doesn't get its own words back. UI-free like
ListenEngine: on_change is called on worker threads."""
from __future__ import annotations

import queue
import re
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from . import strings
from . import voice_reference
from . import voices as voicemod
from .audio import RATE, Wav
from .ling import LingError, TTS_RATE
from .models import TranscriptLine
from .segmenter import Segmenter
from .support import Log

_END = object()


class LoudnessLog:
    """When the system audio was loud: (monotonic time, loud) per buffer, the last minute. Fed by
    listening, read by the echo check."""

    def __init__(self):
        self._items: deque = deque(maxlen=600)
        self._lock = threading.Lock()

    def add(self, loud: bool) -> None:
        with self._lock:
            self._items.append((time.monotonic(), loud))

    def fraction(self, start: float, end: float) -> float:
        with self._lock:
            span = [l for t, l in self._items if start <= t <= end]
        return sum(span) / len(span) if span else 0.0


ECHO = 0.5  # from the plain mic, drop a sentence if the system audio was loud for more than half of it


def echo_dropped(listening: bool, headphones: bool, loud: float, echo_cancelled: bool) -> bool:
    """Whether a sentence may be the other side's voice from the speakers, not mine. Only from the
    plain microphone (the Mac's rule): through the echo canceller their voices are taken out, and
    dropping what I say over them is what the canceller is there to stop. Unknown (not listening, so
    nothing measured the system audio) or 戴着耳机: kept."""
    return listening and not headphones and not echo_cancelled and loud > ECHO


class SpeakEngine:
    ECHO = ECHO

    def __init__(self, ling, translator, settings, store=None, listen=None, player=None):
        self.ling = ling
        self.translator = translator
        self.settings = settings
        self.store = store
        self.listen = listen
        self.player = player  # make() -> object with write(pcm bytes), drain(), close(); 24 kHz mono s16
        self.loudness = LoudnessLog()
        self._listeners = []
        self._source = None
        self._audio = None
        self._work: queue.Queue = queue.Queue()
        self._gen = 0  # bumped by cancel(): sentences queued before it are never spoken
        self._pool = ThreadPoolExecutor(max_workers=3, thread_name_prefix="Interpret")
        self._worker = None
        self._feeder = None
        self.active = False
        self.stage = "idle"      # idle, hearing, interpreting, speaking
        self.last = None          # (original, translation) of the last sentence spoken
        self.problem = None       # the last thing worth saying (a sentence not spoken, a missing voice)
        self.level = 0.0
        self.spoken = 0
        self.echo_cancelled = False  # this press reads the echo-cancelled microphone
        self._me = 0

    def on_change(self, listener) -> None:
        self._listeners.append(listener)

    def _changed(self) -> None:
        for l in list(self._listeners):
            l()

    # Languages

    @property
    def source(self) -> str:
        return self.settings.speak_from_code

    @property
    def target(self) -> str:
        """What the room hears: "room" follows the language they have been speaking."""
        to = self.settings.speakTo
        if to != "room":
            return to
        heard = self.listen.spoken if self.listen is not None else None
        if heard and voicemod.key(heard) != voicemod.key(self.source):
            return heard
        return "en" if voicemod.key(self.source) != "en" else "zh-CN"

    def voice(self, code: str) -> str | None:
        """The voice id for a language: a Ming voice (or the service's), or voicemod.CLONE."""
        choice = (self.settings.speakVoices or {}).get(voicemod.key(code))
        return voicemod.chosen(choice, code, self.ling.config(), voice_reference.exists())

    def speech(self, text: str, code: str, voice: str | None = None):
        """The voice for `text` in `code`'s language, as 24 kHz PCM chunks (a generator). The user's
        own voice that fails before its first sound (Ming refused the clip, or took too long) says
        the sentence in the language's default voice instead, as the Mac falls back to its own."""
        config = self.ling.config()
        voice = voice or self.voice(code)
        language = voicemod.ming_language(code, config)
        if voice != voicemod.CLONE:
            yield from self.ling.speech(text, voice=voice, language=language)
            return
        ref = voice_reference.reference()
        started = False
        if ref is not None:
            try:
                for pcm in self.ling.speech(text, voice=None, language=language, reference=ref):
                    started = True
                    yield pcm
                return
            except LingError as e:
                if started:
                    raise
                Log.d("speak: own voice failed %s, the default voice instead" % e)
        yield from self.ling.speech(text, voice=voicemod.default_voice(code, config), language=language)

    # Running

    def start(self, mic, echo_cancelled: bool = False, why: str = "") -> None:
        """`echo_cancelled`: `mic` is the echo canceller's source (the meeting's voices taken out), so
        nothing said over them is dropped; `why` says why not, for the log."""
        if self.active:
            return
        self.echo_cancelled = echo_cancelled
        self.active = True
        self.stage = "hearing"
        self.problem = None
        self.last = None  # the strip starts empty, not on a sentence from an earlier time
        segmenter = Segmenter()
        gen = self._gen
        audio: queue.Queue = queue.Queue()
        self._audio = audio

        def emitted(seg):
            # Interpreted at once, while the sentence before may still be playing; spoken in order.
            ended = time.monotonic()
            self._work.put((gen, seg, self._pool.submit(self._interpret, seg, ended - seg.seconds, ended, echo_cancelled)))
        segmenter.on_segment = emitted

        def feed():
            while True:
                buf = audio.get()
                if buf is _END:
                    break
                segmenter.feed(buf)
                self.level = Wav.rms(buf)
            segmenter.flush()
        self._feeder = threading.Thread(target=feed, name="SpeakFeed", daemon=True)
        self._feeder.start()
        if self._worker is None or not self._worker.is_alive():
            self._worker = threading.Thread(target=self._run, name="Speak", daemon=True)
            self._worker.start()
        self._source = mic
        mic.on_samples = audio.put
        mic.start()
        Log.d("speak: started %s -> %s, %s" % (self.source, self.target, "through the echo canceller" if echo_cancelled else
                                                   "from the plain mic (%s), said over the meeting is dropped" % (why or "no canceller")))
        self._changed()

    def stop(self) -> None:
        if not self.active:
            return
        self.active = False
        if self._source is not None:
            self._source.on_samples = None
            self._source.stop()
        if self._audio is not None:
            self._audio.put(_END)
        Log.d("speak: stopped, %d sentences spoken" % self.spoken)
        self._changed()

    def cancel(self) -> None:
        """同声传译 off or 退出: stop, and nothing still waiting is said (知了 麦克风 is going away).
        A plain stop() still says what I finished before pressing it, as releasing the key does on the Mac."""
        self._gen += 1
        self.stop()

    def _run(self) -> None:
        while True:
            gen, seg, job = self._work.get()
            try:
                if gen != self._gen:
                    Log.d("speak: segment %d dropped, cancelled before it was said" % seg.index)
                    continue
                self._say(seg, job.result(), gen)
            except Exception as e:  # noqa: BLE001 - one bad sentence never stops the next
                Log.d("speak: sentence failed %s" % type(e).__name__)
            finally:
                self.stage = "hearing" if self.active else "idle"
                self._changed()

    def _interpret(self, seg, start: float, end: float, echo_cancelled: bool = False):
        """(original, translation, source, target, ended, voice chunks) or None, on the pool."""
        listening = self.listen is not None and self.listen.listening
        loud = self.loudness.fraction(start, end) if listening else 0.0
        if listening:
            Log.d("speak: segment %d %.1fs, system audio loud %d%% of it, %s" % (
                seg.index, seg.seconds, round(loud * 100), "echo cancelled" if echo_cancelled else "plain mic"))
        if echo_dropped(listening, self.settings.speakHeadphones, loud, echo_cancelled):
            Log.d("speak: segment %d dropped, the system audio was playing (echo)" % seg.index)
            # Said, so the user knows: talking over them (or no headphones) is why it didn't go out.
            self.problem = strings.L("对方在说话时说的，没有说出去")
            self._changed()
            return None
        source, target = self.source, self.target
        if self.voice(target) is None:
            self.problem = strings.L("这种语言还没有可用的声音")
            return None
        self.stage = "interpreting"
        self._changed()
        try:
            heard = self.translator.interpret(Wav.bytes(seg.samples), source, target)
        except LingError as e:
            Log.d("speak: interpret failed %s" % e)
            heard = None
        if heard is None:
            # Never the original, never a guess.
            self.problem = strings.L("这句没翻译成 · 没有说出去")
            Log.d("speak: segment %d %.1fs not interpreted, not spoken" % (seg.index, seg.seconds))
            return None
        original, translation = heard
        if filler(original):
            # The room's hush or an echo's tail cut as a segment: Ming hears 嗯, the room would hear "Hmm."
            Log.d("speak: segment %d only a filler, not spoken" % seg.index)
            return None
        # The voice starts now, on its own thread: ready the moment the sentence before stops playing,
        # instead of each sentence waiting out Ming's first chunk after the last one's playback.
        return original, translation, source, target, end, self._fetch(translation, target)

    def _fetch(self, text: str, target: str) -> queue.Queue:
        chunks: queue.Queue = queue.Queue()

        def run():
            try:
                for pcm in self.speech(text, target):
                    chunks.put(pcm)
                chunks.put(_END)
            except LingError as e:
                chunks.put(e)
            except Exception as e:  # noqa: BLE001
                chunks.put(LingError(LingError.NETWORK))
                Log.d("speak: voice fetch failed %s" % type(e).__name__)
        threading.Thread(target=run, name="SpeakVoice", daemon=True).start()
        return chunks

    def _say(self, seg, interpreted, gen: int = 0) -> None:
        if interpreted is None:
            return
        original, translation, source, target, ended, chunks = interpreted
        self.problem = None
        self.last = (original, translation)
        self.stage = "speaking"
        self._changed()
        n = 0
        played = 0
        lag = None
        out = self.player() if self.player else None
        try:
            while True:
                pcm = chunks.get(timeout=30)
                if pcm is _END or gen != self._gen:
                    break  # finished, or stopped mid-sentence
                if isinstance(pcm, LingError):
                    raise pcm
                if lag is None:
                    lag = time.monotonic() - ended  # what the room waits: end of my sentence → its voice
                if out is not None:
                    out.write(pcm)
                n += 1
                played += len(pcm)
            if out is not None:
                out.drain()
        except (LingError, queue.Empty) as e:
            Log.d("speak: voice failed %s" % e)
            self.problem = strings.L("连不上 Ling，检查网络或代理")
        finally:
            if out is not None:
                out.close()
        if n:
            self.spoken += 1
            Log.d("speak: segment %d %.1fs -> %s, voice %.1f s, lag %.2f s after the sentence, %d chunks"
                  % (seg.index, seg.seconds, target, played / 2 / TTS_RATE, lag or 0, n))
            # Stamped when I started the sentence, not when its voice finished (the Mac's secondsAgo).
            self._record(original, translation, source, target, time.monotonic() - (ended - seg.seconds))

    def _record(self, original, translation, source, target, ago: float = 0.0) -> None:
        """My sentence in the meeting's record, as the Mac writes it (speaker "me", ids m<n>)."""
        if self.store is None or self.listen is None or not self.listen.listening or not self.listen.session_id:
            return
        sid = self.listen.session_id
        s = self.store.get(sid)
        if s is None:
            return
        self._me += 1
        t = round(max(0.0, (datetime.now(timezone.utc) - s.startedAt).total_seconds() - ago), 3)
        self.store.append(sid, TranscriptLine(id="m%d" % self._me, t=t, speaker="me", src=original, dst=translation,
                                              srcLang=source, dstLang=target))


FILLERS = {"嗯", "啊", "呃", "哦", "唔", "额", "噢", "哎", "um", "uh", "hmm", "hm", "mm", "mhm", "ah", "oh", "er", "えー", "あの", "음", "어"}


def filler(text: str) -> bool:
    """Nothing but fillers (嗯, 啊, um, hmm…), whatever the punctuation (the Mac's PressSpeech.filler).
    A heading with nothing after it ("翻译结果：", "Translation:") is the model's answer to noise, too."""
    trimmed = text.strip()
    if 0 < len(trimmed) <= 12 and trimmed[-1] in ":：":
        return True
    words = [w for w in re.split(r"[^\w]+|[\d_]+", text.lower()) if w]
    return not words or all(w in FILLERS or (len(w) > 1 and len(set(w)) == 1 and w[0] in FILLERS) for w in words)

