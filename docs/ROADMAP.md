# Cicada roadmap

English · [简体中文](ROADMAP.zh-CN.md)

In rough order, and subject to change. Tell us what you need in Issues.

**Next (Mac)**
- **Recording what you say.** Cicada only hears what your Mac plays, so what you say into the meeting isn't captured; only the lines you speak while holding the talk key are recorded as "you". A switch will let it listen to your microphone throughout the meeting, so your proposals and the to-dos you take on make it into the transcript and notes. Without headphones, echo cancellation keeps the other side's voice from being recorded twice. While it's on, the microphone indicator in the menu bar stays lit.
- **Developer ID signing and notarization.** Removes the "Open Anyway" prompt on first launch and stores the AI key in the macOS Keychain.
- **Speaker recognition on the other platforms.** Since 1.10 the Mac remembers frequent meeting participants by voice and names them in the next meeting (stored only on your Mac, only after you click Remember this voice, deletable anytime). Windows, Linux and Android come next.
- **Local notes without an API key.** Use Apple's on-device model to generate meeting notes on supported Macs, keeping all audio and text local.

**Later**
- **Live voice changing.** No translation: your voice goes into the meeting as a different voice, changed as you speak, without holding the talk key. Setting "I speak" and "They hear" to the same language already swaps the voice today, but it goes through text, so the room hears it only after you let go and your tone is lost.
- **Android in the app stores.** Since 1.1.0 the Android app installs from an APK on the website; app store listings will spare people allowing unknown apps.
- **iPhone / iPad.** iOS does not allow capturing audio from other apps, so the app starts with listening to the room through the microphone, face-to-face interpreting and meeting records.

The Windows, Linux and Android apps shipped in 1.1.0; see the README in each one's folder.

Back to the [README](../README.md).
