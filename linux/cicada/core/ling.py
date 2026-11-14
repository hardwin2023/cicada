"""The AI service (Ling by default, or another OpenAI-compatible one: providers.py) and the user's keys."""
from __future__ import annotations

import io
import os
import random
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import wave

from . import aicheck, jsonfmt, proxy, strings
from .jsonfmt import arr, obj, string
from .providers import LING, AIConfig, catalog, is_nearby, thought
from .support import Log, Paths


class AIKey:
    """The user's AI keys, one file per service (`ling-api-key`, `ai-key-<service>`), mode 0600, in
    ~/.config/cicada (as on the Mac): never in settings, logs or exports. `service` says which one
    is in use; `path` pins one file (cli.py reads the Mac's)."""

    def __init__(self, path: str | None = None, service=None):
        self._path = path
        self.service = service or (lambda: "ling")
        self._cache: dict = {}
        self._lock = threading.Lock()

    @property
    def path(self) -> str:
        return self._path or Paths.key_file(self.service())

    def read(self) -> str | None:
        path = self.path
        with self._lock:
            if path in self._cache:
                return self._cache[path]
            value = None
            try:
                if os.path.isfile(path):
                    with open(path, encoding="utf-8") as f:
                        value = f.read().strip() or None
            except OSError as e:
                Log.d("ai key: read failed %s" % type(e).__name__)
            self._cache[path] = value
            return value

    def save(self, key: str) -> bool:
        k = key.strip()
        path = self.path
        with self._lock:
            try:
                os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
                # Created 0600 from the start: the key is never readable by others, even briefly.
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(k)
                os.chmod(path, 0o600)
                self._cache[path] = k
                return True
            except OSError as e:
                Log.d("ai key: save failed %s" % type(e).__name__)
                return False

    def remove(self) -> None:
        path = self.path
        with self._lock:
            try:
                os.remove(path)
            except OSError:
                pass
            self._cache[path] = None

    def reload(self) -> None:
        with self._lock:
            self._cache.clear()

    @staticmethod
    def masked(key: str) -> str:
        """"sk-••••••••••••3f9a" for display."""
        return "sk-…" if len(key) <= 8 else key[:3] + "•" * 12 + key[-4:]


# Priorities, most urgent first.
SPEAK, TRANSLATE, NOTES = 0, 1, 2
PRIORITY_NAMES = {SPEAK: "speak", TRANSLATE: "translate", NOTES: "notes"}

# Key states.
NONE, UNCHECKED, CHECKING, OK, INVALID, UNREACHABLE = "none", "unchecked", "checking", "ok", "invalid", "unreachable"


class LingError(Exception):
    NO_KEY, INVALID_KEY, RATE_LIMITED, HIJACKED, TIMEOUT, HTTP, NETWORK, PARSE = (
        "NoKey", "InvalidKey", "RateLimited", "Hijacked", "Timeout", "Http", "Network", "Parse")

    def __init__(self, kind: str, status: int = 0, retry_after: float | None = None):
        super().__init__("http%d" % status if kind == self.HTTP else kind)
        self.kind = kind
        self.status = status
        self.retry_after = retry_after  # seconds the service asked us to wait (a 429's Retry-After)


class Response:
    def __init__(self, status: int, body: str, retry_after: str | None = None):
        self.status = status
        self.body = body
        self.retry_after = retry_after  # the Retry-After header, as sent


def retry_after_seconds(value: str | None, now: float | None = None) -> float | None:
    """A Retry-After header in seconds: a number, or an HTTP date. None when absent or unreadable."""
    if not value:
        return None
    try:
        return max(0.0, float(value.strip()))
    except ValueError:
        pass
    try:
        import email.utils
        when = email.utils.parsedate_to_datetime(value.strip())
    except (TypeError, ValueError, IndexError):
        return None
    if when is None:
        return None
    return max(0.0, when.timestamp() - (time.time() if now is None else now))


class Clock:
    """Time for the start gate and its waits; tests hand in a fake that moves on by itself."""

    @staticmethod
    def now() -> float:
        return time.monotonic()

    @staticmethod
    def wait(condition: threading.Condition, seconds: float | None) -> None:
        condition.wait(seconds)


class StreamResponse:
    """A reply read as it arrives: `lines` (server-sent events) or, for raw audio, `chunks` (bytes)."""

    def __init__(self, status: int, lines, content_type: str = "text/event-stream", chunks=None):
        self.status = status
        self.lines = lines
        self.content_type = content_type
        self.chunks = chunks


class UrlTransport:
    """How requests leave the app: urllib through this computer's proxy (proxy.urlopen: the
    environment's, else GNOME's manual one), or a fake in tests.
    Raises TimeoutError on a timeout and OSError when the network fails."""

    @staticmethod
    def send(url: str, method: str, body: str | None, headers: dict, timeout: float) -> Response:
        req = urllib.request.Request(url, data=body.encode() if body is not None else None, method=method, headers=headers)
        try:
            with proxy.urlopen(req, timeout=timeout) as r:
                return Response(r.status, r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            return Response(e.code, e.read().decode("utf-8", "replace") if e.fp else "",
                            e.headers.get("Retry-After") if e.headers else None)
        except socket.timeout as e:
            raise TimeoutError() from e
        except urllib.error.URLError as e:
            if isinstance(e.reason, socket.timeout):
                raise TimeoutError() from e
            raise OSError(str(e.reason)) from e

    @staticmethod
    def stream(url: str, body: str, headers: dict, timeout: float) -> StreamResponse:
        """A POST whose reply is read as it arrives (speech): by line for server-sent events, else in
        raw pieces (OpenRouter's speech streams the PCM bytes themselves)."""
        req = urllib.request.Request(url, data=body.encode(), method="POST", headers=headers)
        try:
            r = proxy.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            return StreamResponse(e.code, iter(()))
        except socket.timeout as e:
            raise TimeoutError() from e
        except urllib.error.URLError as e:
            raise OSError(str(e.reason)) from e

        def lines():
            with r:
                for raw in r:
                    yield raw.decode("utf-8", "replace").rstrip("\r\n")

        def chunks():
            with r:
                while True:
                    b = r.read(4800)  # 0.1 s at 24 kHz: playback starts early
                    if not b:
                        return
                    yield b
        return StreamResponse(r.status, lines(), r.headers.get("Content-Type") or "", chunks())


BASE = LING.base
TTS_MODEL = LING.voice_models[0].id
TTS_RATE = 24000  # Ming, Gemini TTS and Kokoro all speak 24 kHz
AUDIO_MODEL = LING.hear_models[0].id
# Search essays (Ling.swift), and the canned refusal some audio prompts get.
HIJACK_PREFIXES = ("根据现有检索证据", "暂未找到足够可靠的信息", "根据检索", "作为一个人工智能语言模型")


# The custom service's check: one real sentence, timed (Ling.swift › check).
CHECK_SENTENCE = ("Translate the text into Simplified Chinese. Reply with the translation only.\n\n"
                  "We will ship the new version on Friday after the design review.")


def silence_wav(seconds: float = 0.5) -> bytes:
    """A short quiet WAV (16 kHz mono 16-bit), to ask a model whether it takes audio at all."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * int(16000 * seconds))
    return buf.getvalue()


# The key file of the custom service's notes server (另一个服务), named as on the Mac.
NOTES_KEY = "custom-notes"


class _Gate:
    """One server's request starts (by host): notes on another server don't wait behind
    translation, and its 429 doesn't hold translation back."""

    def __init__(self):
        self.waiting: list = []
        self.last_start = -1e9
        self.paused_until = 0.0  # after a 429 no request starts here before this (clock time)


def _ling_config() -> AIConfig:
    return AIConfig(LING, LING.base, LING.text_models[0].id, LING.hear_models[0].id, LING.voice_models[0].id, LING.base)


class LingClient:
    """One instance for the app, for whichever AI service the settings name (`config`). Request
    *starts* go through one gate in priority order: Ling allows about 2 a second across every model
    (≥ 0.6 s apart, overlapping is fine), the aggregators far more. Ling's gateway shapes every call
    (see Ling.swift): thinking is always disabled, and the content goes in the system message with
    a fixed user instruction, because a question-like user message gets a search essay back; such
    replies are dropped. The other services get the same messages. Calls block: run them off the
    UI thread."""
    spacing: float | None = None  # tests only: overrides the service's

    def __init__(self, key: AIKey, transport=UrlTransport, config=None, clock=None, notes_key: AIKey | None = None):
        self.key = key
        # 另一个服务's own key for notes; without one, notes use `key` ("不填就用上面的 key").
        self.notes_key_file = notes_key or AIKey(service=lambda: NOTES_KEY)
        self.transport = transport
        self.clock = clock or Clock()
        self.config = config or _ling_config
        self.key_state = NONE if self.current_key() is None else UNCHECKED
        # Step by step, where the service stands (aicheck.py); `key_state` is its short form.
        self.check_result = aicheck.AICheck()
        self.seconds: float | None = None   # how long the last good check took
        # The last time the room voice spoke (or failed to) through this service: (ok, time).
        self.last_voice: tuple | None = None
        # Words the "can't reach" hint from the proxy requests go through (proxy.py).
        self.proxy_hint = proxy.hint
        # Debug control only: every check ends this way (a reason, or "lowBalance"), for screenshots.
        self.simulate: str | None = None
        self.text_catalog: list = []
        self.hear_catalog: list = []
        # Notes' own server's text models from its `/models` (empty while notes share translation's address).
        self.notes_catalog: list = []
        # Every model id the service lists, and those that take audio, to tell whether the chosen
        # ones still exist (None: the service can't tell).
        self._listed: tuple = (None, None)
        self.rate_limited_at = None
        self._listeners = []
        # Every server's start gate (_Gate, by host) shares this one lock.
        self._gate = threading.Condition()
        self._gates: dict = {}
        self._seq = 0
        self._check_lock = threading.Lock()
        self._check_seq = 0
        self._checking = 0  # a check's own requests aren't real ones: they don't feed `observe`
        # Custom addresses that refused `chat_template_kwargs` (a strict gateway answers 400 or 422
        # to a field it doesn't know): left out there until settings change.
        self._plain_bases: set = set()

    def on_change(self, listener) -> None:
        self._listeners.append(listener)

    def _changed(self) -> None:
        for l in list(self._listeners):
            l()

    @property
    def provider(self):
        return self.config().provider

    def current_key(self) -> str | None:
        """The key for the service in use. A custom service on this computer or the local network
        may need none: ""."""
        c = self.config()
        k = self.key.read()
        if k is None and c.provider.id == "custom" and c.base and is_nearby(c.base):
            return ""
        return k

    @property
    def has_key(self) -> bool:
        return self.current_key() is not None

    def notes_key(self) -> str | None:
        """The key notes are sent with: with 另一个服务, their own key file if there is one, else the
        translation key."""
        if self.config().notes_own_service:
            own = self.notes_key_file.read()
            if own is not None:
                return own
        return self.current_key()

    @property
    def notes_has_own_key(self) -> bool:
        """Notes have a key file of their own (另一个服务 only)."""
        return self.config().notes_own_service and self.notes_key_file.read() is not None

    @property
    def usable(self) -> bool:
        return self.has_key and self.key_state != INVALID

    @property
    def speaks(self) -> bool:
        """Voices in the room from this service. Linux has no system voice to fall back on."""
        return self.usable and self.config().has_voices

    @property
    def hears(self) -> bool | None:
        """Whether the hear model takes audio: False when found deaf, True once proved (always on
        Ling, whose Ming hears by design), None until something asked."""
        st = self.check_result["hear"]
        if st.kind == aicheck.FAIL and st.reason == aicheck.DEAF:
            return False
        if st.kind in (aicheck.OK, aicheck.BUSY_STATE) or self.config().is_ling:
            return True
        return None

    @property
    def can_hear(self) -> bool:
        """Listening and 同声传译 can work: the hear model wasn't found to refuse audio."""
        return self.usable and self.hears is not False and bool(self.config().hear_model)

    @property
    def service_name(self) -> str:
        """The service's name for messages ("这个服务" for a custom address, localized)."""
        p = self.provider
        return p.name if p.id != "custom" else strings.L("这个服务")

    @property
    def service_label(self) -> str:
        """Who a status line names: a custom service by its address, which says more than 这个服务
        and reads right in "The … key doesn't work"."""
        host = self.service_host
        return host if self.provider.id == "custom" and host else self.service_name

    @property
    def service_host(self) -> str:
        c = self.config()
        return urllib.parse.urlsplit(c.base or c.provider.base or "").hostname or ""

    @property
    def hear_host(self) -> str:
        """Where the hear model is asked (a custom service's own hear address, else the service's)."""
        c = self.config()
        return urllib.parse.urlsplit(c.hear_url or "").hostname or self.service_host

    def message(self) -> str | None:
        """The failed step's sentence (or the busy note), in the UI language."""
        c = self.config()
        f = self.check_result.failure
        host = self.hear_host if f is not None and f[0] == "hear" else self.service_host
        return self.check_result.message(self.service_label, host, c.text_model, c.hear_model)

    def _classify(self, e: LingError, at: str, audio: bool = False):
        """aicheck.classify, except that a hear model at an address of its own that can't be reached
        stops at the hear step: the text model's address may be fine."""
        cl = aicheck.classify(e, at, audio)
        if audio and cl is not None and cl[1] == aicheck.UNREACHABLE and self.config().own_hear_address:
            return "hear", aicheck.UNREACHABLE, None
        return cl

    def key_changed(self) -> None:
        """The key, the service or its models changed: forget what the last check found."""
        self.key.reload()
        self.notes_key_file.reload()
        with self._check_lock:
            self._check_seq += 1  # a check still running for the old settings is dropped
            self.check_result = aicheck.AICheck()
        self.key_state = NONE if self.current_key() is None else UNCHECKED
        self.last_voice = None
        self._plain_bases = set()
        self.text_catalog, self.hear_catalog, self.notes_catalog = [], [], []
        self._listed = (None, None)
        self._changed()

    def check(self) -> str:
        """The cheapest requests that prove each step: Ling's tiny model, else one token from the
        text model, then half a second of silence to the hear model (a 400 or 404 says it can't
        take audio). A custom service must also return JSON (the notes need it); OpenRouter's key
        and credits give the balance. The model list then tells whether the chosen models still
        exist. Returns the short form (`key_state`)."""
        with self._check_lock:
            self._check_seq += 1
            seq = self._check_seq
        k = self.current_key()
        c = self.config()
        if k is None:
            with self._check_lock:
                self.check_result = aicheck.AICheck()
            self.key_state = NONE
            self._changed()
            return NONE
        r = aicheck.AICheck()
        r["reach"] = aicheck.State(aicheck.RUNNING)
        with self._check_lock:
            self.check_result = r.copy()
        self.key_state = CHECKING
        self._changed()
        with self._check_lock:
            self._checking += 1
        try:
            r = self._run_check(r, c, k, seq)
        finally:
            with self._check_lock:
                self._checking -= 1
        return self._finish_check(r, c, seq)

    def _run_check(self, r, c: AIConfig, k: str, seq: int = 0):
        if self.simulate:
            return aicheck.simulated(self.simulate)
        if c.provider.id == "custom" and c.base is None:
            r.fail("reach", aicheck.BAD_ADDRESS, reached=False)
            return r
        if (aicheck.owner(k) or ("", False))[1]:
            r.fail("key", aicheck.MGMT_KEY, reached=False)
            return r
        started = time.monotonic()
        try:
            if c.is_ling:
                self.chat("Reply with OK.", "Reply.", SPEAK, max_tokens=5, timeout=10.0, model="Ling-3.0-tiny")
            elif c.provider.id == "custom":
                # A real sentence, the way a meeting translates: one token says nothing about a model
                # that thinks for six seconds before every answer.
                roots: list = []
                asked = time.monotonic()
                self.chat(CHECK_SENTENCE, "Translate.", SPEAK, max_tokens=120, timeout=30.0, reply=roots)
                r.translate = aicheck.Speed(time.monotonic() - asked, bool(roots) and thought(roots[-1]))
            else:
                self.chat("Reply with OK.", "Reply.", SPEAK, max_tokens=5, timeout=20.0)
            self.seconds = time.monotonic() - started
            r.pass_up_to("text", self.seconds)
            if c.notes_apart:
                # Notes at their own model or server: their failure is theirs, translation goes on.
                r.notes = aicheck.State(aicheck.RUNNING)
                with self._check_lock:
                    if seq == self._check_seq:
                        self.check_result = r.copy()
                self._changed()
                r.notes = self._check_notes(c)
            elif c.provider.id == "custom":
                ask = "Reply with the JSON object {\"ok\": true}."
                try:
                    self.chat(ask, "Reply.", SPEAK, json=True, max_tokens=20, timeout=30.0, json_fallback=False)
                except LingError as e:
                    if e.kind != LingError.HTTP:
                        raise
                    # JSON mode refused (some hosts of a model do): meetings then ask without it, so
                    # what counts is whether the model still answers with a JSON object.
                    try:
                        said = self.chat(ask, "Reply.", SPEAK, max_tokens=20, timeout=30.0)
                    except LingError:
                        said = None
                    if not answers_json(said):
                        r.fail("text", aicheck.NO_JSON, e.status)
        except LingError as e:
            self._failed(r, aicheck.classify(e, "text"), "text")
        except Exception:  # noqa: BLE001
            r.fail("reach", aicheck.UNREACHABLE)
        if r.failure is not None or c.is_ling:
            return r  # Ling's hearing is Ming: a meeting proves it, no probe
        if not c.hear_model:
            r.fail("hear", aicheck.DEAF)
        elif c.hear_url is None:
            r.fail("hear", aicheck.BAD_ADDRESS)  # its own address, typed but not valid
        else:
            started = time.monotonic()
            try:
                self.chat("Transcribe the audio.", "Reply with what is said, or NONE.", SPEAK, max_tokens=10, timeout=20.0,
                          model=c.hear_model, audio=silence_wav())
                r["hear"] = aicheck.State(aicheck.OK, time.monotonic() - started)
            except LingError as e:
                if e.kind == LingError.HIJACKED:
                    r["hear"] = aicheck.State(aicheck.OK, time.monotonic() - started)  # it answered: it took the audio
                else:
                    self._failed(r, self._classify(e, "hear", audio=True), "hear")
            except Exception:  # noqa: BLE001
                r.fail("hear" if c.own_hear_address else "reach", aicheck.UNREACHABLE)
        if c.provider.id == "openrouter" and r.failure is None:
            r.balance = aicheck.balance(self._get_json("key", k), self._get_json("credits", k))
        if r.failure is None or r.failure[0] == "hear":  # the menus want the models even when the hear one is deaf
            self.fetch_catalog()
            every, hear = self._listed
            # A model the service no longer lists fails here, before a meeting finds out. One a real
            # request just went through exists whatever the list says (an alias, a name typed by hand).
            if every is not None and c.text_model and r["text"].kind == aicheck.UNTESTED:
                if c.text_model not in every:
                    r.fail("text", aicheck.NO_MODEL)
                else:
                    r["text"] = aicheck.State(aicheck.OK)
            # The list is the text address's: a hear model elsewhere isn't in it.
            if hear is not None and not c.own_hear_address and c.hear_model not in hear and r.failure is None:
                r.fail("hear", aicheck.DEAF)
        return r

    def _check_notes(self, config: AIConfig):
        """Notes' own model or server: one JSON request the way a meeting's notes ask, then (another
        address) its model list for the menu. Straight to the server, not through `chat`: notes'
        429 retries are a meeting's, not a check's."""
        if config.notes_bad_address:
            return aicheck.State(aicheck.FAIL, reason=aicheck.BAD_ADDRESS)
        c = config.for_notes
        k = self.notes_key()
        if k is None or c.base is None:
            return aicheck.State(aicheck.FAIL, reason=aicheck.INVALID_KEY)
        body = {"model": c.text_model,
                "messages": [{"role": "system", "content": "Reply with the JSON object {\"ok\": true}."},
                             {"role": "user", "content": "Reply."}],
                "stream": False}
        c.shape(body, 20, template_kwargs=c.base not in self._plain_bases)
        body["response_format"] = {"type": "json_object"}
        asked = time.monotonic()
        try:
            self._acquire(SPEAK, c.provider.spacing, base=c.base)
            try:
                self._post_chat(c.base, body, k, 60.0, notes=True)
                result = aicheck.State(aicheck.OK, time.monotonic() - asked)
            except LingError as e:
                if not (e.kind == LingError.HTTP and e.status in (400, 422)):
                    raise
                # JSON mode refused: meetings then ask without it, so what counts is a JSON answer.
                del body["response_format"]
                try:
                    root = self._post_chat(c.base, body, k, 60.0, notes=True)
                except LingError:
                    root = None
                choices = arr((root or {}).get("choices"))
                said = string((obj((obj(choices[0]) or {}).get("message")) or {}).get("content")) if choices else None
                result = (aicheck.State(aicheck.OK, time.monotonic() - asked) if answers_json(said)
                          else aicheck.State(aicheck.FAIL, reason=aicheck.NO_JSON, code=e.status))
        except LingError as e:
            _, reason, code = aicheck.classify(e, "text") or ("text", aicheck.SERVER_ERROR, None)
            result = aicheck.State(aicheck.FAIL, reason=reason, code=code)
        except Exception:  # noqa: BLE001
            result = aicheck.State(aicheck.FAIL, reason=aicheck.UNREACHABLE)
        if c.base != config.base:
            self.fetch_notes_catalog()
        return result

    @staticmethod
    def _failed(r, classified, step: str) -> None:
        """A check's request failed: busy passes (the key works), anything else stops there."""
        if classified is None:
            r.pass_up_to(step, None)  # a reply came (a search essay, odd JSON): the service answers
            return
        at, reason, code = classified
        if reason == aicheck.BUSY:
            r.pass_up_to(at, None)
            r[at] = aicheck.State(aicheck.BUSY_STATE)
        else:
            r.fail(at, reason, code)

    def _finish_check(self, r, c: AIConfig, seq: int) -> str:
        if r.reason == aicheck.UNREACHABLE and r.proxy is None:
            try:
                r.proxy = self.proxy_hint()
            except Exception:  # noqa: BLE001 - it only words a hint
                r.proxy = None
        if self.simulate == "lowBalance":
            r.balance = 0.4
        r.at = time.time()
        with self._check_lock:
            if seq != self._check_seq:
                Log.d("ai %s: check result dropped (settings changed meanwhile)" % c.provider.id)
                return self.key_state
            self.check_result = r
        self._sync_key_state()
        Log.d("ai %s: check -> %s" % (c.provider.id, r.summary()))
        self._changed()
        return self.key_state

    def _sync_key_state(self) -> None:
        """The short form older callers read: invalid stops every request; a failure before the
        hear step is "unreachable" with a reason; a deaf hear model leaves notes and translation ok."""
        if not self.has_key:
            self.key_state = NONE
            return
        r = self.check_result
        f = r.failure
        if f is not None and f[1] in (aicheck.INVALID_KEY, aicheck.MGMT_KEY):
            self.key_state = INVALID
        elif f is not None and f[0] != "hear" and f[1] != aicheck.BUSY:
            self.key_state = UNREACHABLE
        elif r.at is not None and not r.running:
            self.key_state = OK
            for s in ("reach", "key", "text"):
                if r[s].kind == aicheck.OK and r[s].seconds is not None:
                    self.seconds = r[s].seconds

    def observe(self, failure: LingError | None, seconds: float = 0.0, audio: bool = False, notes: bool = False) -> None:
        """A real request (hearing, notes, translation) came back: keep the steps current without a
        check. One server error in a meeting isn't worth repainting the settings for. `notes`: it
        went to the notes' own model or server, whose result is theirs alone."""
        if self._checking or self.simulate or not self.has_key:
            return
        if notes:
            # Sent before notes went back to translation's model and server: not theirs any more.
            if not self.config().notes_apart:
                return
            if failure is not None:
                cl = aicheck.classify(failure, "text")
                if cl is None or cl[1] == aicheck.SERVER_ERROR:
                    return
                now = aicheck.State(aicheck.FAIL, reason=cl[1], code=cl[2])
            else:
                now = aicheck.State(aicheck.OK, seconds)
            with self._check_lock:
                old = self.check_result
                if old.running or (old.notes is not None and old.notes.kind == aicheck.OK and now.kind == aicheck.OK):
                    return
                r = old.copy()
                r.notes = now
                self.check_result = r
            Log.d("ai: notes from a real request -> %s" % r.summary())
            self._changed()
            return
        with self._check_lock:
            old = self.check_result
            if old.running:
                return
            r = old.copy()
            if failure is not None:
                cl = self._classify(failure, "hear" if audio else "text", audio)
                if cl is None or cl[1] == aicheck.SERVER_ERROR:
                    return
                step, reason, code = cl
                if reason == aicheck.BUSY:
                    r.pass_up_to("key", None)
                    r[step] = aicheck.State(aicheck.BUSY_STATE)
                else:
                    r.fail(step, reason, code)
            elif audio:
                # Heard: says nothing about the text model, which keeps what it had.
                r.pass_up_to("key", None)
                r["hear"] = aicheck.State(aicheck.OK, seconds)
            else:
                r.pass_up_to("text", seconds)
            r.at = time.time()
            r.passive = True
            if r.reason != aicheck.UNREACHABLE:
                r.proxy = None
            if [r[s] for s in aicheck.STEPS] == [old[s] for s in aicheck.STEPS] and old.passive and old.at is not None:
                old.at = r.at  # only the time: nothing worth repainting for
                return
            newly_unreachable = r.reason == aicheck.UNREACHABLE and old.reason != aicheck.UNREACHABLE
            self.check_result = r
        self._sync_key_state()
        Log.d("ai: from a real request -> %s" % r.summary())
        self._changed()
        if newly_unreachable:
            threading.Thread(target=self._word_proxy, daemon=True).start()

    def _word_proxy(self) -> None:
        hint = self.proxy_hint()
        with self._check_lock:
            if self.check_result.reason != aicheck.UNREACHABLE:
                return
            nxt = self.check_result.copy()
            nxt.proxy = hint
            self.check_result = nxt
        self._changed()

    def network_changed(self) -> bool:
        """The network came back (or changed) while the service was unreachable: look again.
        True when a check started."""
        r = self.check_result
        if not self.has_key or r.reason != aicheck.UNREACHABLE or r.running:
            return False
        Log.d("ai: network changed while unreachable, checking again")
        threading.Thread(target=self.check, daemon=True).start()
        return True

    def _get_json(self, path: str, k: str):
        """A GET under the service's address, as JSON; None when it fails (it only adds detail)."""
        c = self.config()
        try:
            res = self.transport.send(c.base + path, "GET", None, self._headers(k), 15.0)
        except (OSError, TimeoutError):
            return None
        return jsonfmt.parse_object(res.body) if res.status == 200 else None

    def fetch_catalog(self) -> None:
        """The service's models, for the model menus: those that chat, and those that hear. Quietly
        just the recommended ones when the service has no `/models`."""
        c = self.config()
        k = self.current_key()
        if c.is_ling or k is None or c.base is None:
            return
        try:
            res = self.transport.send(c.base + "models", "GET", None, self._headers(k), 20.0)
        except (OSError, TimeoutError):
            return
        if res.status != 200:
            return
        self.text_catalog = catalog(res.body, [m.id for m in c.provider.text_models], hears=False)
        self.hear_catalog = catalog(res.body, [m.id for m in c.provider.hear_models], hears=True)
        self._listed = aicheck.listed(res.body)
        Log.d("ai %s: %d models, %d hear" % (c.provider.id, len(self.text_catalog), len(self.hear_catalog)))
        self._changed()

    def fetch_notes_catalog(self) -> None:
        """Notes' own address's text models, for its menu. Quietly empty when it has no `/models`."""
        c = self.config()
        n = c.for_notes
        k = self.notes_key()
        if not c.notes_apart or n.base is None or n.base == c.base or k is None:
            return
        try:
            res = self.transport.send(n.base + "models", "GET", None, self._headers(k), 20.0)
        except (OSError, TimeoutError):
            return
        if res.status != 200:
            return
        self.notes_catalog = catalog(res.body, [], hears=False)
        Log.d("ai notes: %d models" % len(self.notes_catalog))
        self._changed()

    def chat(self, content: str, instruction: str, priority: int, json: bool = False, max_tokens: int = 1024,
             timeout: float = 30.0, model: str | None = None, audio: bytes | None = None, patient: bool = False,
             reply: list | None = None, json_fallback: bool = True) -> str:
        """One chat completion. `content` goes in the system message, `instruction` is the fixed user
        message, `audio` (a WAV) goes before it for the hear model. Notes and heard audio retry 429s
        with backoff (retry_waits); the rest fail fast so the caller can fall back. `patient` (the
        final notes) keeps retrying for about a minute. A 429 holds every request start for a while
        (_rate_limited), and a retry keeps its place in the queue, so lines stay in order. Audio goes
        to the hear model's address (`hear_url`). `reply`, when given, gets the whole JSON reply. A JSON
        request refused with 400 is asked again without JSON mode unless `json_fallback` is off (the
        check asks again itself). Notes (实时纪要, 说话人) go to their own model, server and key when
        the custom service sets them (`AIConfig.for_notes`)."""
        c = self.config()
        notes_side = priority == NOTES and audio is None and c.notes_apart
        if notes_side:
            c = c.for_notes
        k = self.notes_key() if notes_side else self.current_key()
        if k is None:
            raise LingError(LingError.NO_KEY)
        # A refused notes key stops only notes; translation's stops everything but those.
        if (self.check_result.notes is not None and self.check_result.notes.reason == aicheck.INVALID_KEY) if notes_side \
                else self.key_state == INVALID:
            raise LingError(LingError.INVALID_KEY)
        base = c.base if audio is None else c.hear_url
        if base is None:
            raise LingError(LingError.NO_KEY)
        model = model or c.text_model
        user = instruction if audio is None else [c.audio_part(audio, model), {"type": "text", "text": instruction}]
        body = {"model": model,
                "messages": [{"role": "system", "content": content}, {"role": "user", "content": user}],
                "stream": False}
        c.shape(body, max_tokens, template_kwargs=base not in self._plain_bases)
        if json:
            body["response_format"] = {"type": "json_object"}
        waits = retry_waits(priority, audio is not None, patient)
        attempt = 1
        name = PRIORITY_NAMES[priority]
        ticket = None
        while True:
            # One that wouldn't retry fails at once while the service is cooling down: its caller falls back.
            ticket = self._acquire(priority, c.provider.spacing, ticket, fail_if_paused=not waits, base=c.base)
            started = time.monotonic()
            try:
                try:
                    root = self._post_chat(base, body, k, timeout, notes=notes_side)
                except LingError as e:
                    if not (json_fallback and e.kind == LingError.HTTP and e.status == 400 and "response_format" in body):
                        raise
                    # Some hosts of a model refuse JSON mode (on OpenRouter, Novita for Ling 3.1 Flash)
                    # while the model answers JSON anyway: the prompt asks for it, the parsers find it.
                    Log.d("ling: %s JSON mode refused (400), asking again without it" % name)
                    del body["response_format"]
                    root = self._post_chat(base, body, k, timeout, notes=notes_side)
                choices = arr(root.get("choices"))
                choice = obj(choices[0]) if choices else None
                text = string((obj(choice.get("message")) or {}).get("content")) if choice else None
                if text is None:
                    raise LingError(LingError.PARSE)
                finish = string(choice.get("finish_reason"))
                trimmed = text.strip()
                # Ling's search essays come without a finish reason; other services may simply omit it.
                if (finish is None and c.is_ling) or trimmed.startswith(HIJACK_PREFIXES):
                    Log.d("ling: %s search-style reply dropped" % name)
                    raise LingError(LingError.HIJACKED)
                usage = obj(root.get("usage")) or {}
                Log.d("ai %s: %s ok %d ms tokens=%s/%s" % (c.provider.id, name, (time.monotonic() - started) * 1000,
                                                           usage.get("prompt_tokens"), usage.get("completion_tokens")))
                if self.rate_limited_at is not None:
                    self.rate_limited_at = None
                    self._changed()
                self.observe(None, time.monotonic() - started, audio is not None, notes=notes_side)
                if reply is not None:
                    reply.append(root)
                return trimmed
            except LingError as e:
                self.observe(e, audio=audio is not None, notes=notes_side)
                if e.kind != LingError.RATE_LIMITED:
                    raise
                wait = self._rate_limited(waits[min(attempt, len(waits)) - 1] if waits else 1.0, e.retry_after, base=c.base)
                if attempt > len(waits) or wait is None:
                    self.rate_limited_at = time.time()
                    self._changed()
                    raise
                Log.d("ling: %s 429, retry in %.1f s" % (name, wait))
                attempt += 1

    def speech(self, text: str, voice: str | None = "UK_Charlotte", language: str | None = None, timeout: float = 20.0,
               reference: tuple | None = None):
        """_speech, remembering how it went (现在能用的 › 同传声音 says so). Cut short on purpose (stop,
        a new press) is neither."""
        try:
            yield from self._speech(text, voice, language, timeout, reference)
        except GeneratorExit:
            raise
        except Exception:
            self.last_voice = (False, time.time())
            raise
        self.last_voice = (True, time.time())

    def _speech(self, text: str, voice: str | None, language: str | None, timeout: float, reference: tuple | None = None):
        """The service's voice for `text`, as raw 24 kHz mono 16-bit PCM chunks while they arrive (a
        generator). On Ling, `voice` is Ming's, or a voice cloned from `reference` (a WAV data URI and
        what it says, voice_reference.reference), and `language` its language_id, needed for Japanese,
        Korean, German, French and Spanish (Ling.swift › speech); elsewhere the configured speech
        model and `voice`. Replies come three ways and all are read: server-sent base64 chunks (Ling,
        ZenMux), raw PCM (OpenRouter), or one JSON `{"audio": <WAV>}`."""
        k = self.current_key()
        if k is None:
            raise LingError(LingError.NO_KEY)
        c = self.config()
        if not c.has_voices:
            raise LingError(LingError.NO_KEY)
        body = {"model": c.voice_model, "input": text, "response_format": "pcm"}
        if c.is_ling:
            body.update({"sample_rate": TTS_RATE, "stream": True, "stream_format": "sse"})
            if reference:
                # The clip goes with every sentence: Ming takes longer to start (Ling.swift waits 30 s).
                body["references"] = [{"audio": reference[0], "text": reference[1]}]
                timeout = max(timeout, 30.0)
            else:
                body["voice"] = voice or "UK_Charlotte"
            if language:
                body["language_id"] = language
        else:
            # OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
            if c.provider.id != "openrouter":
                body["stream"] = True
            ids = [v.id for v in c.voices]
            body["voice"] = voice if voice in ids else (ids[0] if ids else (c.custom_voice or "Kore"))
        self._acquire(SPEAK, c.provider.spacing)
        try:
            res = self.transport.stream(c.voice_base + "audio/speech", jsonfmt.write(body, pretty=False), self._headers(k), timeout)
        except TimeoutError:
            raise LingError(LingError.TIMEOUT) from None
        except OSError:
            raise LingError(LingError.NETWORK) from None
        if res.status in (401, 403):
            self.key_state = INVALID
            self._changed()
            raise LingError(LingError.INVALID_KEY)
        if res.status == 429:
            raise LingError(LingError.RATE_LIMITED)
        if res.status != 200:
            Log.d("ai %s: speech HTTP %d" % (c.provider.id, res.status))
            raise LingError(LingError.HTTP, res.status)
        kind = res.content_type or ""
        if "event-stream" in kind or res.chunks is None:
            for line in res.lines:
                if not line.startswith("data:"):
                    continue
                o = jsonfmt.parse_object(line[5:].strip())
                if o is None:
                    continue
                if o.get("type") == "speech.audio.done":
                    break
                audio = o.get("audio")
                if isinstance(audio, str) and audio:
                    yield _b64(audio)
        elif "json" in kind:
            o = jsonfmt.parse_object(b"".join(res.chunks).decode("utf-8", "replace"))
            audio = (o or {}).get("audio")
            if not isinstance(audio, str):
                raise LingError(LingError.PARSE)
            yield pcm_from_wav(_b64(audio))
        else:
            for b in res.chunks:
                yield b

    def _headers(self, k: str) -> dict:
        h = {"Content-Type": "application/json", "User-Agent": "Cicada-Linux/0.1"}
        if k:
            h["Authorization"] = "Bearer " + k
        return h

    def _post_chat(self, base: str, body: dict, k: str, timeout: float, notes: bool = False) -> dict:
        """A chat completion. A custom server that refuses `chat_template_kwargs` (400 or 422) is
        asked again without it, and once that works it isn't sent there again until settings change
        (Ling.swift › postChat). A 400 the plain request gets too is the model's or the audio's, not
        the field's: that one is raised and nothing is remembered."""
        try:
            return self._post(base + "chat/completions", jsonfmt.write(body, pretty=False), k, timeout, notes)
        except LingError as e:
            if not (e.kind == LingError.HTTP and e.status in (400, 422) and "chat_template_kwargs" in body):
                raise
            plain = {kk: v for kk, v in body.items() if kk != "chat_template_kwargs"}
            root = self._post(base + "chat/completions", jsonfmt.write(plain, pretty=False), k, timeout, notes)
            Log.d("ai custom: chat_template_kwargs refused (HTTP %d), sent without it from now on" % e.status)
            self._plain_bases.add(base)
            return root

    def _post(self, url: str, payload: str, k: str, timeout: float, notes: bool = False) -> dict:
        """`notes`: it went with the notes' own key or to their server, so a refused key is theirs,
        not translation's."""
        try:
            res = self.transport.send(url, "POST", payload, self._headers(k), timeout)
        except TimeoutError:
            raise LingError(LingError.TIMEOUT) from None
        except OSError as e:
            Log.d("ling: network error %s" % type(e).__name__)
            raise LingError(LingError.NETWORK) from None
        if res.status in (401, 403):
            if not notes and self.key_state != INVALID:
                self.key_state = INVALID
                self._changed()
            raise LingError(LingError.INVALID_KEY)
        if res.status == 429:
            raise LingError(LingError.RATE_LIMITED, retry_after=retry_after_seconds(getattr(res, "retry_after", None)))
        if res.status != 200:
            Log.d("ling: HTTP %d" % res.status)
            raise LingError(LingError.HTTP, res.status)
        root = jsonfmt.parse_object(res.body)
        if root is None:
            raise LingError(LingError.PARSE)
        return root

    # Start gate: request starts ≥ `spacing` apart, the most urgent waiting one first, none while
    # the server is cooling down after a 429. One per server (by host).

    def _server(self, base: str | None = None) -> _Gate:
        """The gate of the server at `base` (None: the service's own). Called with `_gate` held."""
        if base is None:
            c = self.config()
            base = c.base or c.provider.base
        host = urllib.parse.urlsplit(base or "").hostname or ""
        g = self._gates.get(host)
        if g is None:
            g = self._gates[host] = _Gate()
        return g

    def _acquire(self, priority: int, spacing: float = 0.6, ticket: int | None = None,
                 fail_if_paused: bool = False, base: str | None = None) -> int:
        """Waits for this request's turn to start at the server at `base` (None: the service's).
        `ticket` is a retry's first one, which keeps its place ahead of requests queued after it.
        Returns the ticket."""
        spacing = LingClient.spacing if LingClient.spacing is not None else spacing
        with self._gate:
            g = self._server(base)
            if fail_if_paused and g.paused_until > self.clock.now():
                raise LingError(LingError.RATE_LIMITED)
            if ticket is None:
                self._seq += 1
                ticket = self._seq
            me = (priority, ticket)
            g.waiting.append(me)
            try:
                while True:
                    head = min(g.waiting)
                    now = self.clock.now()
                    wait = max(spacing - (now - g.last_start), g.paused_until - now)
                    if head == me and wait <= 0:
                        g.waiting.remove(me)
                        g.last_start = now
                        self._gate.notify_all()
                        return ticket
                    self.clock.wait(self._gate, wait if head == me else None)
            except BaseException:
                if me in g.waiting:
                    g.waiting.remove(me)
                self._gate.notify_all()
                raise

    def _rate_limited(self, backoff: float, retry_after: float | None, base: str | None = None) -> float | None:
        """After a 429: no request starts for `backoff` seconds, or as long as the service asked
        (Retry-After; Ling sends none), plus a little jitter. The queue waits at the gate instead of
        each request spending its retries on the same limit. None when the service asks for longer
        than MAX_PAUSE: that is an outage, not a busy moment (the gate still holds for MAX_PAUSE)."""
        wait = max(backoff, retry_after or 0.0) + random.random() * 0.5
        with self._gate:
            g = self._server(base)
            g.paused_until = max(g.paused_until, self.clock.now() + min(wait, MAX_PAUSE))
            self._gate.notify_all()
        return wait if wait <= MAX_PAUSE else None


MAX_PAUSE = 30.0


def answers_json(text: str | None) -> bool:
    """A chat reply's text holds a JSON object (a fence or a sentence around it is fine)."""
    if not text:
        return False
    a, z = text.find("{"), text.rfind("}")
    return 0 <= a < z and jsonfmt.parse_object(text[a:z + 1]) is not None


def retry_waits(priority: int, audio: bool = False, patient: bool = False) -> list:
    """Seconds before each retry of a 429 (Ling.swift › retryWaits). Notes retry a few times; the
    rest fail fast so the caller can fall back, except heard audio. A meeting's: there a lost reply
    loses the words, and Ling's 429s came in runs of up to ~10 s (two in a row lost a line with one
    retry, about 2 a minute in 2026-11 testing), so it keeps at it for about 15 s. What the user says
    (SPEAK) retries once: late into the room is worse than a short "try again". `patient` (the final notes)
    keeps at it for about a minute: a model limited upstream (OpenRouter's Ling 3.1 by DeepInfra,
    2026-11) came back after ~15 s, and a meeting left without its notes is worse than notes a little late."""
    if priority == NOTES:
        return [1, 2, 4, 8, 16, 30] if patient else [1, 2, 4]
    if audio:
        return [1, 2, 4, 8] if priority == TRANSLATE else [1]
    return []


def _b64(s: str) -> bytes:
    import base64
    return base64.b64decode(s)


def pcm_from_wav(wav: bytes) -> bytes:
    """The samples of a WAV (its `data` chunk); the bytes themselves when there's no header."""
    if wav[:4] != b"RIFF":
        return wav
    at = 12
    while at + 8 <= len(wav):
        size = int.from_bytes(wav[at + 4:at + 8], "little")
        if wav[at:at + 4] == b"data":
            return wav[at + 8:at + 8 + size]
        at += 8 + size + (size & 1)
    return b""
