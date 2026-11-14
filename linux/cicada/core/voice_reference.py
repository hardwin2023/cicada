"""The user's own voice (Voices.swift › VoiceReference): the recording Ming clones it from,
`voice/reference.wav` (16 kHz mono, 10–15 s) and `voice/reference.txt` (what it says, as Ming
heard it) in the config folder. The folder is 0700 and the files 0600, like the key; they never go
into a record, an export or the log, and leave the computer only inside a speech request to Ling.
UI-free: the settings window records, this keeps, checks and hands it to LingClient.speech."""
from __future__ import annotations

import base64
import math
import os
import shutil
from array import array

from .audio import RATE, Wav
from .support import Paths

# The issue's advice (#32): the reference goes with every sentence, so a longer one makes each
# sentence later. Under 10 s Ming has too little to go on; recording stops by itself at 15.
MIN_SECONDS = 10.0
MAX_SECONDS = 15.0

# Ming copies the recording's pace into every sentence (Voices.swift › slowCharacters): below these
# (characters a second for Chinese, Japanese and Korean, words otherwise) the clone is too slow for
# a meeting; reading the passage at an ordinary pace gives 3.5–5 and 2.3–3.
SLOW_CHARACTERS = 2.5
SLOW_WORDS = 1.6

CLONE = "clone"


def folder() -> str:
    return os.path.join(Paths.config(), "voice")


def audio_path() -> str:
    return os.path.join(folder(), "reference.wav")


def text_path() -> str:
    return os.path.join(folder(), "reference.txt")


def text() -> str | None:
    try:
        with open(text_path(), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def exists() -> bool:
    return os.path.isfile(audio_path()) and bool((text() or "").strip())


def duration() -> float:
    try:
        return len(Wav.read_file(audio_path())) / RATE
    except (OSError, ValueError):
        return 0.0


def reference() -> tuple[str, str] | None:
    """What Ming needs: the clip as a data URI and its transcript."""
    t = (text() or "").strip()
    if not t:
        return None
    try:
        with open(audio_path(), "rb") as f:
            data = f.read()
    except OSError:
        return None
    return "data:audio/wav;base64," + base64.b64encode(data).decode(), t


def _private(path: str, mode: int, data: bytes) -> None:
    """Written 0600 from the first byte, then swapped in, so a half-written clip is never used."""
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def save(samples: array, transcript: str) -> None:
    """16 kHz mono samples and what they say."""
    os.makedirs(folder(), mode=0o700, exist_ok=True)
    os.chmod(folder(), 0o700)
    _private(audio_path(), 0o600, Wav.bytes(trim(samples)))
    _private(text_path(), 0o600, transcript.strip().encode("utf-8"))
    global _saved_pace
    _saved_pace = None


def remove() -> None:
    global _saved_pace
    _saved_pace = None
    shutil.rmtree(folder(), ignore_errors=True)


# Pace

def is_cjk(ch: str) -> bool:
    o = ord(ch)
    return 0x3040 <= o <= 0x30FF or 0x3400 <= o <= 0x4DBF or 0x4E00 <= o <= 0x9FFF or 0xAC00 <= o <= 0xD7AF or 0xF900 <= o <= 0xFAFF


def tokens(s: str) -> list:
    """Characters for Chinese, Japanese and Korean, words otherwise (SpeakTest.swift › tokens)."""
    out, word = [], ""
    for ch in s:
        if is_cjk(ch):
            if word:
                out.append(word.lower())
                word = ""
            out.append(ch)
        elif ch.isalnum() or ch in "'’":
            word += "'" if ch == "’" else ch
        elif word:
            out.append(word.lower())
            word = ""
    if word:
        out.append(word.lower())
    return out


def _speech_windows(samples, rate: int = RATE):
    """(first, last, size): the 20 ms windows within 35 dB of the loudest one; None when silent."""
    size = max(1, int(rate * 0.02))
    levels = []
    for i in range(0, len(samples), size):
        part = samples[i:i + size]
        levels.append(math.sqrt(sum((x / 32768.0) ** 2 for x in part) / len(part)))
    if not levels or max(levels) <= 0.003:
        return None
    floor = max(levels) * 0.0178
    loud = [i for i, l in enumerate(levels) if l >= floor]
    return loud[0], loud[-1], size


def speech_span(samples, rate: int = RATE) -> float | None:
    """Seconds from the first to the last 20 ms window within 35 dB of the loudest one."""
    w = _speech_windows(samples, rate)
    return None if w is None else (w[1] - w[0] + 1) * w[2] / rate


TRIM_PAD = 0.2


def trim(samples, rate: int = RATE):
    """The recording without the quiet before and after the reading, 0.2 s kept each side. Ming
    copies the clip's ending: a second of silence after the last word (the pause before 读完了)
    made every cloned sentence come back as 0.4 s of nothing (measured 2026-11 against Ling)."""
    w = _speech_windows(samples, rate)
    if w is None:
        return samples
    pad = int(TRIM_PAD * rate)
    return samples[max(0, w[0] * w[2] - pad):min(len(samples), (w[1] + 1) * w[2] + pad)]


def pace(transcript: str, samples, rate: int = RATE) -> float | None:
    """Characters or words a second of speech; None when there is no speech to measure."""
    units = len(tokens(transcript))
    span = speech_span(samples, rate)
    if units == 0 or span is None or span <= 0.5:
        return None
    return units / span


def is_slow(transcript: str, p: float) -> bool:
    t = tokens(transcript)
    characters = sum(1 for x in t if any(is_cjk(c) for c in x))
    return p < (SLOW_CHARACTERS if characters * 2 >= len(t) else SLOW_WORDS)


_saved_pace = None  # (mtime, slow)


def saved_is_slow() -> bool:
    """The saved recording is read too slowly (worked out once per recording)."""
    global _saved_pace
    try:
        mtime = os.path.getmtime(audio_path())
    except OSError:
        return False
    if _saved_pace and _saved_pace[0] == mtime:
        return _saved_pace[1]
    t = text() or ""
    try:
        p = pace(t, Wav.read_file(audio_path()))
    except (OSError, ValueError):
        p = None
    slow = p is not None and is_slow(t, p)
    _saved_pace = (mtime, slow)
    return slow


def passage(code: str) -> str:
    """The passage to read, in the user's own language (Voices.swift › passage)."""
    k = (code or "en").split("-")[0].lower()
    if k == "zh":
        return "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。请大家先看一下屏幕上的议程。"
    if k == "ja":
        return "皆さん、こんにちは。今日の会議では、新製品の発売計画について話し合います。スケジュール、テストの範囲、そしてマーケティングについて順番に確認しましょう。"
    return ("Hello everyone, thanks for joining. Today we'll walk through the launch plan for the new product: the schedule, "
            "what we still need to test, and how we'll tell people about it. Let's start with the agenda on the screen.")


def check(samples, transcript: str) -> str | None:
    """Why a recording can't be used ("short", "unclear", "slow"), or None; the Mac's order. Long
    enough is measured on the reading itself (trim), not the quiet around it."""
    if len(trim(samples)) / RATE < MIN_SECONDS:
        return "short"
    if len(transcript.strip()) < 6:
        return "unclear"
    p = pace(transcript, samples)
    if p is not None and is_slow(transcript, p):
        return "slow"
    return None
