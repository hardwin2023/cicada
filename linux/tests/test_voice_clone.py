"""我自己的声音 (issue #32): the recording kept like the key, Ming's request with `references`, the
voice a language falls back to, and the Mac's pace and length checks."""
from __future__ import annotations

import base64
import os
import stat
import threading
import time
import unittest
from types import SimpleNamespace

from test_core import Base, Fake, Player, client, concat, reply, silence, sse, tone

from cicada.core import jsonfmt
from cicada.core import voice_reference as vref
from cicada.core import voices as voicemod
from cicada.core.audio import PcmAudioSource
from cicada.core.ling import LingClient, StreamResponse
from cicada.core.settings import AppSettings
from cicada.core.speak import SpeakEngine
from cicada.core.translator import Translator

PASSAGE = "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。"


class Storage(Base):
    def test_kept_private_and_read_back_as_a_data_uri(self):
        self.assertFalse(vref.exists())
        vref.save(tone(12), PASSAGE)
        self.assertTrue(vref.exists())
        self.assertEqual(0o700, stat.S_IMODE(os.stat(vref.folder()).st_mode))
        for p in (vref.audio_path(), vref.text_path()):
            self.assertEqual(0o600, stat.S_IMODE(os.stat(p).st_mode), p)
        self.assertAlmostEqual(12.0, vref.duration(), places=2)
        audio, text = vref.reference()
        self.assertTrue(audio.startswith("data:audio/wav;base64,"))
        wav = base64.b64decode(audio.split(",", 1)[1])
        self.assertEqual(b"RIFF", wav[:4])
        self.assertEqual(16000, int.from_bytes(wav[24:28], "little"), "16 kHz")
        self.assertEqual(1, int.from_bytes(wav[22:24], "little"), "mono")
        self.assertEqual(PASSAGE, text)
        vref.remove()
        self.assertFalse(vref.exists())
        self.assertIsNone(vref.reference())

    def test_no_transcript_is_no_recording(self):
        vref.save(tone(12), "   ")
        self.assertFalse(vref.exists())


class Request(Base):
    def test_clone_sends_the_reference_instead_of_a_voice(self):
        timeouts = []
        fake = Fake(lambda b: reply("ok"), speech=lambda b: sse(b"\x01\x00"))
        stream = fake.stream
        fake.stream = lambda url, body, headers, timeout: timeouts.append(timeout) or stream(url, body, headers, timeout)
        pcm = list(client(fake).speech("Hello", voice=None, language="ja", reference=("data:audio/wav;base64,UklGRg==", "你好")))
        self.assertEqual([b"\x01\x00"], pcm)
        body = jsonfmt.parse(fake.spoken[0])
        self.assertEqual([{"audio": "data:audio/wav;base64,UklGRg==", "text": "你好"}], body["references"])
        self.assertNotIn("voice", body)
        self.assertEqual("ja", body["language_id"])
        self.assertGreaterEqual(timeouts[0], 30, "a cloned voice gets Ling.swift's 30 s")

    def test_a_built_in_voice_sends_no_reference(self):
        fake = Fake(lambda b: reply("ok"), speech=lambda b: sse(b"\x01\x00"))
        list(client(fake).speech("Hello", voice="US_Emma"))
        body = jsonfmt.parse(fake.spoken[0])
        self.assertEqual("US_Emma", body["voice"])
        self.assertNotIn("references", body)


class Choice(unittest.TestCase):
    OTHER = SimpleNamespace(is_ling=False, provider=SimpleNamespace(clones=False), voices=[SimpleNamespace(id="Kore", gender="女")])

    def test_own_voice_needs_its_recording_and_ling(self):
        self.assertEqual("clone", voicemod.chosen("clone", "en", None, has_reference=True))
        self.assertEqual("US_Emma", voicemod.chosen("clone", "en", None, has_reference=False), "no recording: the default")
        self.assertEqual("灵小雅", voicemod.chosen("clone", "zh-CN", None, has_reference=False))
        self.assertEqual("Kore", voicemod.chosen("clone", "en", self.OTHER, has_reference=True), "only Ling clones")
        self.assertFalse(voicemod.clones(self.OTHER))
        self.assertEqual("UK_George", voicemod.chosen("UK_George", "en", None))
        self.assertEqual("Kore", voicemod.chosen("UK_George", "en", self.OTHER), "a Ming voice isn't sent elsewhere")


class Pace(unittest.TestCase):
    def test_tokens_count_characters_and_words(self):
        self.assertEqual(["大", "家", "好", "hello", "it's", "2"], vref.tokens("大家好, Hello it’s 2!"))

    def test_too_slow_is_caught_like_the_mac(self):
        # 54 characters over 12 s of speech: 4.5 a second, an ordinary pace.
        self.assertIsNone(vref.check(concat(silence(0.5), tone(12), silence(0.5)), PASSAGE))
        p = vref.pace(PASSAGE, concat(silence(1), tone(12), silence(2)))
        self.assertAlmostEqual(len(vref.tokens(PASSAGE)) / 12, p, delta=0.05, msg="silence at both ends left out")
        # The same over 14 s of a recital at a third of it.
        self.assertEqual("slow", vref.check(tone(14), PASSAGE[:30]))
        self.assertTrue(vref.is_slow("hello there everyone", 1.5))
        self.assertFalse(vref.is_slow("hello there everyone", 2.0))

    def test_the_quiet_around_the_reading_is_cut(self):
        # A second of silence after the last word made Ming answer every sentence with 0.4 s of nothing.
        cut = vref.trim(concat(silence(1.5), tone(11), silence(1.2)))
        self.assertAlmostEqual(11 + 2 * vref.TRIM_PAD, len(cut) / 16000, delta=0.05)
        self.assertEqual(16000 * 3, len(vref.trim(silence(3))), "nothing to cut by in silence")
        self.assertEqual("short", vref.check(concat(tone(9), silence(3)), PASSAGE), "long enough is the reading itself")

    def test_kept_without_its_silence(self):
        home = __import__("tempfile").mkdtemp()
        from cicada.core.support import Paths
        Paths.home_override = home
        try:
            vref.save(concat(tone(11), silence(1)), PASSAGE)
            self.assertAlmostEqual(11 + vref.TRIM_PAD, vref.duration(), delta=0.05)
        finally:
            Paths.home_override = None
            __import__("shutil").rmtree(home, ignore_errors=True)

    def test_too_short_or_not_understood(self):
        self.assertEqual("short", vref.check(tone(9.5), PASSAGE))
        self.assertEqual("unclear", vref.check(tone(12), "你好"))
        self.assertEqual(10.0, vref.MIN_SECONDS)
        self.assertEqual(15.0, vref.MAX_SECONDS)


class Speaking(Base):
    def _engine(self, speech, voices):
        LingClient.spacing = 0.01
        fake = Fake(lambda b: reply("ORIGINAL: 我们周五上线\nTRANSLATION: We launch on Friday"), speech=speech)
        ling = client(fake)
        player = Player()
        settings = AppSettings(target="zh-CN", speakTo="en", speakVoices=voices)
        return SpeakEngine(ling, Translator(ling), settings, player=lambda: player), fake, player

    def _say(self, eng):
        src = PcmAudioSource(lambda: concat(tone(1.2), silence(1.0)), speed=0)
        done = threading.Event()
        src.on_ended = lambda why: done.set()
        eng.start(src)
        done.wait(5)
        time.sleep(0.6)
        eng.stop()

    def test_speaks_in_my_own_voice(self):
        vref.save(tone(12), PASSAGE)
        eng, fake, player = self._engine(lambda b: sse(b"\x10\x00" * 100), {"en": "clone"})
        self.assertEqual("clone", eng.voice("en"))
        self._say(eng)
        self.assertEqual(1, eng.spoken)
        body = jsonfmt.parse(fake.spoken[0])
        self.assertEqual(PASSAGE, body["references"][0]["text"])
        self.assertNotIn("voice", body)
        with open(os.path.join(self.home, "debug.log"), encoding="utf-8") as f:
            self.assertNotIn("主持人", f.read(), "the transcript never goes into the log")

    def test_without_the_recording_the_default_voice(self):
        eng, fake, player = self._engine(lambda b: sse(b"\x10\x00" * 100), {"en": "clone"})
        self.assertEqual("US_Emma", eng.voice("en"))
        self._say(eng)
        self.assertEqual("US_Emma", jsonfmt.parse(fake.spoken[0])["voice"])

    def test_a_refused_clone_falls_back_to_the_default_voice(self):
        vref.save(tone(12), PASSAGE)
        eng, fake, player = self._engine(lambda b: sse(b"\x10\x00" * 100), {"en": "clone"})
        stream = fake.stream

        def refuse(url, body, headers, timeout):
            if "references" in body:
                fake.spoken.append(body)
                return StreamResponse(400, iter([]))
            return stream(url, body, headers, timeout)
        fake.stream = refuse
        self._say(eng)
        self.assertEqual(1, eng.spoken, "still said, in the default voice")
        self.assertEqual(b"\x10\x00" * 100, player.data)
        self.assertIn("references", jsonfmt.parse(fake.spoken[0]))
        self.assertEqual("US_Emma", jsonfmt.parse(fake.spoken[1])["voice"])


if __name__ == "__main__":
    unittest.main()
