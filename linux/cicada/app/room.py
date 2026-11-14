"""知了 麦克风: the virtual microphone the meeting app hears the interpreted voice from (the Mac's
BlackHole, without a driver). Two modules of the sound server, made while 同声传译 is on and removed
when it's off or the app quits:

  module-null-sink   cicada_room        where Cicada plays the translated voice
  module-remap-source cicada_mic         that sink's monitor as a real microphone (apps list it)

Both PulseAudio and PipeWire (pipewire-pulse) load these. While it's on, 知了 麦克风 is also made the
default input, so a meeting app left on "default" (most browsers) uses it with no setup; the real
microphone is remembered, Cicada records me from it, and it is the default again afterwards."""
from __future__ import annotations

import ctypes
import ctypes.util
import os
import time

from ..core.ling import TTS_RATE
from ..core.strings import L
from ..core.support import Log, Paths
from .capture import _INFO_CB, PA_SAMPLE_S16LE, _Attr, _libpulse, _pulse, _Spec  # one server-info type for both

SINK = "cicada_room"
MIC = "cicada_mic"
PA_STREAM_PLAYBACK = 1


class _ModuleInfo(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("name", ctypes.c_char_p), ("argument", ctypes.c_char_p)]


_MODULE_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.POINTER(_ModuleInfo), ctypes.c_int, ctypes.c_void_p)
_INDEX_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p)
_SUCCESS_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p)


def _lib():
    l = _libpulse()
    if not getattr(l, "_room_ready", False):
        l.pa_context_load_module.restype = ctypes.c_void_p
        l.pa_context_load_module.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, _INDEX_CB, ctypes.c_void_p]
        l.pa_context_unload_module.restype = ctypes.c_void_p
        l.pa_context_unload_module.argtypes = [ctypes.c_void_p, ctypes.c_uint32, _SUCCESS_CB, ctypes.c_void_p]
        l.pa_context_get_module_info_list.restype = ctypes.c_void_p
        l.pa_context_get_module_info_list.argtypes = [ctypes.c_void_p, _MODULE_CB, ctypes.c_void_p]
        l.pa_context_set_default_source.restype = ctypes.c_void_p
        l.pa_context_set_default_source.argtypes = [ctypes.c_void_p, ctypes.c_char_p, _SUCCESS_CB, ctypes.c_void_p]
        l.pa_context_set_default_sink.restype = ctypes.c_void_p
        l.pa_context_set_default_sink.argtypes = [ctypes.c_void_p, ctypes.c_char_p, _SUCCESS_CB, ctypes.c_void_p]
        l._room_ready = True
    return l


class _Session:
    """One connection to the sound server for a few blocking requests."""

    def __init__(self):
        self.l = _lib()
        self.loop = self.l.pa_mainloop_new()
        self.ctx = self.l.pa_context_new(self.l.pa_mainloop_get_api(self.loop), b"Cicada")
        self.ok = self.l.pa_context_connect(self.ctx, None, 0, None) >= 0 and self._ready()

    def _ready(self) -> bool:
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            self.l.pa_mainloop_iterate(self.loop, 0, None)
            state = self.l.pa_context_get_state(self.ctx)
            if state == 4:
                return True
            if state in (5, 6):
                return False
            time.sleep(0.005)
        return False

    def wait(self, op) -> None:
        if not op:
            return
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and self.l.pa_operation_get_state(op) == 0:
            self.l.pa_mainloop_iterate(self.loop, 0, None)
            time.sleep(0.003)
        self.l.pa_operation_unref(op)

    def server(self) -> dict:
        out = {}

        @_INFO_CB
        def got(_c, info, _u):
            if info:
                i = info.contents
                out["sink"] = i.default_sink_name.decode() if i.default_sink_name else None
                out["source"] = i.default_source_name.decode() if i.default_source_name else None
        self.wait(self.l.pa_context_get_server_info(self.ctx, got, None))
        return out

    def modules(self) -> list:
        found = []

        @_MODULE_CB
        def got(_c, info, eol, _u):
            if eol == 0 and info:
                i = info.contents
                found.append((i.index, (i.name or b"").decode(), (i.argument or b"").decode()))
        self.wait(self.l.pa_context_get_module_info_list(self.ctx, got, None))
        return found

    def load(self, name: str, args: str):
        box = {}

        @_INDEX_CB
        def got(_c, index, _u):
            box["index"] = index
        self.wait(self.l.pa_context_load_module(self.ctx, name.encode(), args.encode(), got, None))
        index = box.get("index")
        return None if index is None or index == 0xFFFFFFFF else index

    def unload(self, index: int) -> None:
        @_SUCCESS_CB
        def done(_c, _ok, _u):
            pass
        self.wait(self.l.pa_context_unload_module(self.ctx, index, done, None))

    def set_default_source(self, name: str) -> None:
        @_SUCCESS_CB
        def done(_c, _ok, _u):
            pass
        self.wait(self.l.pa_context_set_default_source(self.ctx, name.encode(), done, None))

    def set_default_sink(self, name: str) -> None:
        @_SUCCESS_CB
        def done(_c, _ok, _u):
            pass
        self.wait(self.l.pa_context_set_default_sink(self.ctx, name.encode(), done, None))

    def close(self) -> None:
        self.l.pa_context_disconnect(self.ctx)
        self.l.pa_context_unref(self.ctx)
        self.l.pa_mainloop_free(self.loop)


def _saved_path() -> str:
    # Beside the log in the state folder: if Cicada is killed while 知了 麦克风 is the default input,
    # the next launch still knows which microphone to give back.
    return os.path.join(os.path.dirname(Paths.log()), "real-mic")


class VirtualMic:
    def __init__(self):
        self.real_mic = self._load()  # the input that was the default before: Cicada records me from it
        self.on = False

    @staticmethod
    def _load():
        try:
            with open(_saved_path()) as f:
                return f.read().strip() or None
        except OSError:
            return None

    def _save(self) -> None:
        try:
            with open(_saved_path(), "w") as f:
                f.write(self.real_mic or "")
        except OSError:
            pass

    def leftovers(self) -> None:
        """At launch with 同声传译 off: a killed Cicada may have left 知了 麦克风 as everyone's default
        input, which would make every meeting app silent. Gives the real microphone back."""
        try:
            s = _Session()
        except OSError:
            return
        try:
            if s.ok and self._ours(s.modules()):
                Log.d("room: removing 知了 麦克风 left by an earlier run")
                self._give_back(s)
        finally:
            s.close()

    def _give_back(self, s) -> None:
        if s.server().get("source") == MIC and self.real_mic:
            s.set_default_source(self.real_mic)
        for index in self._ours(s.modules()):
            s.unload(index)  # with no remembered mic the server falls back to a real one itself

    def _ours(self, modules) -> list:
        return [i for i, name, arg in modules if name in ("module-null-sink", "module-remap-source")
                and (("sink_name=" + SINK) in arg or ("source_name=" + MIC) in arg)]

    def create(self) -> bool:
        """Makes 知了 麦克风 and makes it the default input. Left over from a crash: removed first."""
        try:
            s = _Session()
        except OSError as e:
            Log.d("room: no libpulse (%s)" % e)
            return False
        try:
            if not s.ok:
                Log.d("room: can't reach the sound server")
                return False
            for index in self._ours(s.modules()):
                s.unload(index)
            current = s.server().get("source")
            # A real microphone to record me from; never our own (left as default after a crash).
            self.real_mic = current if current and current != MIC else self.real_mic
            self._save()
            # Quoted the way module arguments and property lists parse: names with spaces survive.
            sink_desc = L("知了 · 给会议的声音").replace("'", "")
            mic_desc = L("知了 麦克风").replace("'", "")
            a = s.load("module-null-sink", "sink_name=%s sink_properties=\"device.description='%s'\"" % (SINK, sink_desc))
            b = s.load("module-remap-source", "master=%s.monitor source_name=%s source_properties=\"device.description='%s'\""
                       % (SINK, MIC, mic_desc))
            if a is None or b is None:
                Log.d("room: modules not loaded (%s, %s)" % (a, b))
                for index in self._ours(s.modules()):
                    s.unload(index)
                return False
            s.set_default_source(MIC)
            self.on = True
            Log.d("room: 知了 麦克风 ready, recording me from the previous default input")
            return True
        finally:
            s.close()

    def remove(self) -> None:
        try:
            s = _Session()
        except OSError:
            return
        try:
            if not s.ok:
                return
            self._give_back(s)
            self.on = False
            Log.d("room: 知了 麦克风 removed")
        finally:
            s.close()


AEC_SINK = "cicada_aec_out"
AEC_MIC = "cicada_aec_mic"
# 同声传译's own canceller: the talk key reads the microphone through it.
TALK_SINK = "cicada_talk_out"
TALK_MIC = "cicada_talk_mic"
# PulseAudio's WebRTC canceller turns on gain control unless told not to, which moves the
# microphone's own volume; off, as on the Mac. pipewire-pulse ignores these keys (its default is off).
NO_AGC = 'aec_args="analog_gain_control=0 digital_gain_control=0"'


class EchoCanceller:
    """The meeting's voices taken out of a microphone (the Mac's voice-processing unit). One
    sound-server module, module-echo-cancel (WebRTC's canceller, in PipeWire and PulseAudio):

      <sink>     an output in front of the speakers, made the default while it runs: what it plays
                 goes on to the speakers and is what the canceller takes out (the meeting app's
                 voices). The canceller only hears what is played into it, so it has to be the
                 default; the speakers stay where the sound comes out.
      <source>   the microphone with them taken out

    Two of them: 电脑和会议室's room side (cicada_aec_*, debug only, the room stays unprocessed by
    default) and 同声传译's talk key (cicada_talk_*, made with 知了 麦克风 so it has settled before a
    press). Removed when they stop, on 退出, SIGTERM, and after a crash at the next launch; the output
    that was the default is the default again each time."""

    def __init__(self, sink: str = AEC_SINK, source: str = AEC_MIC, state: str = "real-sink",
                 agc_off: bool = False):
        self.sink = sink
        self.source = source
        self.state = state
        self.agc_off = agc_off
        self.on = False
        self.mic = None  # the microphone it was made on
        try:
            with open(self._state_path()) as f:
                self.real_sink = f.read().strip() or None
        except OSError:
            self.real_sink = None

    def _state_path(self) -> str:
        return os.path.join(os.path.dirname(Paths.log()), self.state)

    def _ours(self, modules) -> list:
        return [i for i, name, arg in modules if name == "module-echo-cancel" and ("sink_name=" + self.sink) in arg]

    def create(self, mic: str) -> str | None:
        """Puts the canceller between `mic` and the speakers; the source to listen to, or None when the
        sound server won't (the caller then uses the plain mic)."""
        try:
            s = _Session()
        except OSError:
            return None
        try:
            if not s.ok:
                return None
            self._give_back(s)
            sink = s.server().get("sink")
            if not sink or sink.startswith("cicada_"):
                # Another canceller of ours is the default already: two in a row fight over it.
                Log.d("echo cancel %s: the default output is %s, not made" % (self.sink, sink))
                return None
            self.real_sink = sink
            try:
                with open(self._state_path(), "w") as f:
                    f.write(sink)
            except OSError:
                pass
            desc = L("知了 · 防回声").replace("'", "")
            args = ("aec_method=webrtc source_master=%s sink_master=%s source_name=%s sink_name=%s "
                    "source_properties=\"device.description='%s'\" sink_properties=\"device.description='%s'\""
                    % (mic, sink, self.source, self.sink, desc, desc))
            index = s.load("module-echo-cancel", args + " " + NO_AGC) if self.agc_off else None
            if index is None:
                if self.agc_off:
                    Log.d("echo cancel %s: not loaded with gain control off, again with the defaults" % self.sink)
                index = s.load("module-echo-cancel", args)
            if index is None:
                Log.d("echo cancel %s: module not loaded" % self.sink)
                return None
            s.set_default_sink(self.sink)
            self.on = True
            self.mic = mic
            Log.d("echo cancel %s: on, in front of the default output" % self.sink)
            return self.source
        finally:
            s.close()

    def ready(self, mic: str) -> bool:
        """Whether it is there for `mic` and still the default output: the meeting plays through it.
        False after the output was changed (a headset, the sound settings) or the module went away."""
        if not self.on or mic != self.mic:
            return False
        try:
            s = _Session()
        except OSError:
            return False
        try:
            return s.ok and s.server().get("sink") == self.sink and bool(self._ours(s.modules()))
        finally:
            s.close()

    def _give_back(self, s) -> None:
        if s.server().get("sink") == self.sink and self.real_sink:
            s.set_default_sink(self.real_sink)
        for index in self._ours(s.modules()):
            s.unload(index)

    def remove(self) -> None:
        """Also what launch does (a crash may have left it): harmless when there is nothing to remove."""
        try:
            s = _Session()
        except OSError:
            return
        try:
            if s.ok:
                had = bool(self._ours(s.modules()))
                self._give_back(s)
                if had:
                    Log.d("echo cancel %s: removed" % self.sink)
            self.on = False
            self.mic = None
        finally:
            s.close()


class Player:
    """Plays 24 kHz (or `rate`) mono 16-bit PCM into a sink: 知了 麦克风's (the room) or, for 试听, the speakers."""

    def __init__(self, device: str | None = SINK, rate: int = TTS_RATE):
        lib = _pulse()
        lib.pa_simple_write.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_int)]
        lib.pa_simple_drain.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
        self.lib = lib
        spec = _Spec(PA_SAMPLE_S16LE, rate, 1)
        attr = _Attr(0xFFFFFFFF, rate // 5 * 2, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)  # ~200 ms buffered
        err = ctypes.c_int(0)
        self.s = lib.pa_simple_new(None, b"Cicada", PA_STREAM_PLAYBACK, device.encode() if device else None,
                                   L("同声传译的声音").encode(), ctypes.byref(spec), None, ctypes.byref(attr), ctypes.byref(err))
        if not self.s:
            Log.d("room: can't play to %s: %s" % (device, lib.strerror(err.value).decode()))
        self._odd = b""

    def write(self, pcm: bytes) -> None:
        if not self.s:
            return
        data = self._odd + pcm
        if len(data) % 2:
            self._odd, data = data[-1:], data[:-1]
        else:
            self._odd = b""
        err = ctypes.c_int(0)
        self.lib.pa_simple_write(self.s, data, len(data), ctypes.byref(err))

    def drain(self) -> None:
        if self.s:
            err = ctypes.c_int(0)
            self.lib.pa_simple_drain(self.s, ctypes.byref(err))

    def close(self) -> None:
        if self.s:
            self.lib.pa_simple_free(self.s)
            self.s = None
