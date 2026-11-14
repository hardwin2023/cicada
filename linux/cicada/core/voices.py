"""The voices for what the room hears (Voices.swift › VoiceCatalog). On Ling, Ming's: hand-picked
natural ones per language; for languages Ming has no native voice for, Emma and George speak them
with `language_id`. On another service, its speech model's voices, the same in every language.
Linux has no system voice worth sending into a meeting, so only these."""
from __future__ import annotations


def key(code: str) -> str:
    """"zh" for zh-CN / zh-TW, "en" for en-US."""
    return (code or "en").split("-")[0].lower() or "en"


def ming_language(code: str, config=None) -> str | None:
    if config is not None and not config.is_ling:
        return None
    k = key(code)
    return k if k in ("ja", "ko", "de", "fr", "es") else None


# (voice, name, tags as Chinese keys)
_CATALOG = {
    "en": [("US_Emma", "Emma", ["女", "美式", "自然对话"]), ("UK_George", "George", ["男", "英式", "稳重"]),
           ("UK_Charlotte", "Charlotte", ["女", "英式", "平稳"])],
    "zh": [("灵小雅", "小雅", ["女", "清亮", "播报"]), ("灵小棠", "小棠", ["女", "温和", "沉稳"]),
           ("灵小锋", "小锋", ["男", "温暖", "亲切"]), ("灵卓然", "卓然", ["男", "沉着", "清楚"])],
}
_OTHER = [("US_Emma", "Emma", ["女"]), ("UK_George", "George", ["男"])]

# The languages the room can hear: those Ming speaks.
ROOM_LANGUAGES = ["en", "zh-CN", "zh-TW", "ja", "ko", "es", "fr", "de"]


def voices(code: str, config=None) -> list:
    """(voice, name, tags) for a language. `config` is the AI service in use (None: Ling)."""
    if config is not None and not config.is_ling:
        return [(v.id, v.id, [v.gender] if v.gender else []) for v in config.voices]
    k = key(code)
    if k in _CATALOG:
        return _CATALOG[k]
    return _OTHER if k in ("ja", "ko", "de", "fr", "es") else []


def default_voice(code: str, config=None) -> str | None:
    v = voices(code, config)
    return v[0][0] if v else None


CLONE = "clone"  # the user's own voice (voice_reference), stored in speakVoices like a Ming voice


def clones(config) -> bool:
    """Only Ling clones the user's voice (providers.py)."""
    return config is None or bool(getattr(config.provider, "clones", False))


def chosen(choice: str | None, code: str, config=None, has_reference: bool = False) -> str | None:
    """The voice a language uses: the choice while the service in use can speak it, else the default
    (AppModel.voiceID). The user's own voice needs its recording and Ling; a Ming voice saved
    before switching services isn't sent elsewhere. Either comes back with that service."""
    if choice == CLONE:
        return CLONE if has_reference and clones(config) else default_voice(code, config)
    names = [v for v, _n, _t in voices(code, config)]
    return choice if choice in names else default_voice(code, config)


def sample(code: str) -> str:
    """A short line to try a voice with, in the language it will speak (VoiceCatalog.sample)."""
    return {
        "zh": "谢谢大家。我们来看一下上线时间表，并确定谁负责麦克风测试。",
        "ja": "皆さん、ありがとうございます。発売スケジュールを確認しましょう。",
        "ko": "감사합니다. 출시 일정을 함께 확인해 보겠습니다.",
        "es": "Gracias a todos. Revisemos el calendario de lanzamiento.",
        "fr": "Merci à tous. Regardons ensemble le calendrier de lancement.",
        "de": "Danke an alle. Schauen wir uns den Zeitplan für den Start an.",
        "pt": "Obrigado a todos. Vamos ver o cronograma de lançamento.",
    }.get(key(code), "Thanks everyone. Let's look at the launch timeline and decide who owns the microphone tests.")
