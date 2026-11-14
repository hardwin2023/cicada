<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cicada icon">
</p>

<h1 align="center">Cicada · 知了</h1>

<p align="center">
  Every call. Every stream. No language barrier.<br>
  Understand, speak back, and remember everything. Live meeting notes, bilingual transcripts, subtitles and interpreting on Mac, Windows, Linux and Android.
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/Website-cicada.indaloop.app-E8552B?style=for-the-badge" alt="Website: cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/en/download/"><img src="https://img.shields.io/badge/Download-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="Download for Mac, Windows, Linux and Android" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

In meetings or livestreams, Cicada gives you live bilingual subtitles and writes structured meeting notes as it listens. When it's your turn to speak, hold the talk key (right `⌥` on Mac, right `Ctrl` on Windows, customizable) and talk—the other side hears your translated voice right in the call. Cicada listens to system audio directly without sending bots into the meeting, so no one else notices a thing. On Apple silicon Macs, all speech recognition runs on device, so audio never leaves your computer.

**Where it works**: Anything that plays sound on your computer—Tencent Meeting, Feishu, DingTalk, WeCom, Zoom, Teams, Google Meet, Webex, Discord, and Telegram voice chats, plus X Spaces, YouTube, Twitch, Bilibili Live, podcasts, and web pages. On phones, the system blocks recording audio from call and meeting apps—put it on speaker and use In person instead.

<p align="center">
  <img src="docs/demo.gif" width="800" alt="A Bloomberg English livestream on YouTube with Cicada's live Chinese notes, topics, and fishbone diagram on the right and bilingual subtitles at the bottom">
</p>

## Platforms

| Platform | Requirements | Notes |
|---|---|---|
| Mac | macOS 14.4+, Apple silicon / Intel | Full feature set. On-device recognition on Apple silicon (works without a key); Intel needs a Ling key (speech recognized by Ming) |
| Windows | Windows 10 2004+, x64 / ARM64 | Needs an AI service key (Ling, OpenRouter, ZenMux, etc.); see [windows/](windows/README.md) |
| Linux | Ubuntu 22.04 / 24.04 desktop | Needs an AI service key; the notes window is visible in screen sharing; see [linux/](linux/README.md) |
| Android | Android 10+ | Needs an AI service key; subtitles for videos and streams, face-to-face interpreting; see [android/](android/README.md) |

Installers are available on [the download page](https://cicada.indaloop.app/en/download/) and [Releases](https://github.com/wquguru/cicada/releases). All four platforms share the same version number and meeting record format. The sections below use the Mac app to walk through the features.

## Features

### Live notes and bilingual transcript

As you listen, Cicada organizes a summary, topics and key points, conclusions, to-dos, a fishbone diagram, and a glossary of names and terms. Click any conclusion or to-do to jump straight back to the original lines. Press `⌘F` to search—even misrecognized homophones show up.

With an AI service connected, misheard names and terms are fixed on the spot: homophones are corrected right away, while unfamiliar names are asked about once and fixed automatically once you confirm. You can paste common terms into **Word list** in Settings ahead of time. After the meeting, select **Edit line…** to batch-fix the same misheard word across the whole session, with full undo support.

### Live subtitles and language detection

Cicada detects the spoken language within seconds and translates it into your system language; press `⌃⌥S` to switch display modes. The subtitle bar only appears when someone speaks and turns see-through under your pointer so it stays out of the way. On macOS 26 with Apple silicon, Cicada also re-listens on device to refine each line 15 to 30 seconds later, fixing typos and missed words.

### In-person and hybrid meetings

Click **Turn on mic** to capture people speaking in the room. Hybrid meetings use this same button: computer audio is marked **Online** and microphone audio is marked **In room**, combined in a single record (on macOS 14 and 15, turning on the mic listens only to the room). On speakers, Cicada automatically deduplicates audio; with headphones on, both sides can talk at once and both are kept. Windows and Linux follow the same rules.

On a Mac, the small arrow beside the button picks which microphone to use (an iPhone or a conference mic, say) without changing the system default. What the mic hears only goes into the notes, never into the meeting; for the other side to hear you, use simultaneous interpreting below.

### Simultaneous interpreting

Hold the right `⌥` key and speak so the other side hears your translated voice in the meeting app.

On a Mac, you can also turn on **Hands-free** in **Settings › Interpreting**: just start talking while listening to a meeting, the meeting audio automatically ducks, and your translated voice goes out after a 1-second pause. It pauses while the mic is on, and we recommend switching back to the talk key when others are nearby so their voices aren't mistaken for yours.

Turning on interpreting switches the system microphone to BlackHole 2ch, a virtual driver you can download and install with one click. With a Ling API key, you can use natural voices or clone your own voice from an 8 to 30 second recording; without a key, you can still use built-in macOS voices. Windows and Linux interpreting, and Android's In person, can use your own voice too, cloned from a 10 to 15 second recording with a Ling key.

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="Interpreting settings showing the right Option talk key, target language, Ming voice previews, and macOS voices">
</p>

### Meeting records

Bilingual transcripts, notes, and raw audio recordings are saved on your device. Click any line to play from that point while the text highlights and scrolls along. The on-device voiceprint model automatically separates speakers (and fills in their names when a Ling key is set), and you can rename or merge them anytime if someone is misidentified. Right now "you" in the record only covers what you say while holding the talk key; capturing what you say directly in the meeting is on the [roadmap](#roadmap).

After a meeting, you can generate notes retroactively, export to Markdown, Word, and SRT subtitles, or transcribe local audio and video files via **File › Import Recording or Video…**. On the Mac, **Copy Notes** (⇧⌘C) pastes into Feishu, Notion or Word with its headings, lists and fishbone picture, and as Markdown into a chat. Turn on **Settings › General › Save to folder** and each meeting is also automatically saved as Markdown (with frontmatter at the top for agents) into an Obsidian vault or another folder, updating automatically whenever you rename it or regenerate its notes.

Click **Share…** to generate a link to the notes (optionally including the full bilingual transcript) with an expiration time and password; before uploading, it automatically blocks keys, unpublished company info, and other sensitive content.

<p align="center">
  <img src="docs/records.png" width="640" alt="Meeting records window showing identified speakers and a line-by-line English and Chinese transcript">
</p>

## Privacy & Permissions

**Apple silicon Macs**: Recording and speech recognition run on your computer; audio never leaves it. Only the recognized text is sent out (for translation and meeting notes). Exceptions: the lines you speak during interpreting with a Ling key configured, clicking **Use Ling for Now**, or switching to a self-hosted service in **Settings › AI Service** will send audio to the corresponding service. Without an API key, live subtitles, translation, meeting records, and interpreting all work for free. Live notes, one-step voice translation, and voice cloning require your own Ling (Ant Group's LLM service) API key. An hour of meetings costs roughly ¥0.15 to ¥1 RMB, and Ling provides ¥10 of free credit every month, enough for 10 to 50 hours.

**Intel Macs, Windows, Linux, Android**: Speech recognition runs in the cloud and requires an AI service key; audio is sent in segments to Ling's Ming or your chosen service (OpenRouter, ZenMux, etc.). Recordings and meeting records still stay only on your device.

The Mac app only asks for a permission when you use the corresponding feature, and everything else works normally if you decline:

| Permission | What it's for | Without it |
|---|---|---|
| System audio recording (Screen & System Audio Recording) | Hears system audio for subtitles; never records the screen | Subtitles and notes won't work |
| Microphone | Hold to talk or **Hands-free** for interpreting; click **Turn on mic** to listen to a meeting room | Can't speak to translate or listen to the room |
| Input Monitoring | Detects the right `⌥` key (doesn't block or log other keys) | Switch to a `⌃`/`⌘` shortcut to skip this permission |
| Administrator password | Installs the BlackHole 2ch virtual microphone (asked once) | The other side can't hear interpreting; everything else works |

- **Transparent networking**: Only connects to the internet for translation (`translate.googleapis.com`), your configured AI service (such as `api.ant-ling.com`), downloading the Apple-notarized BlackHole driver (verified against SHA-256), and checking GitHub once a day for updates. No analytics, no tracking, and no server of our own.
- **Local storage**: Records and recordings live in `~/Library/Application Support/LiveSubs`. Your key and voice sample are readable only by your current system account and excluded from Time Machine and logs.
- **Hidden from screen capture**: On Mac, screen sharing, screen recordings, and screenshots cannot capture the notes window. You can manually turn on **Show in screen sharing** when recording a demo.

## Models

The table below shows the setup on Apple silicon Macs. When using a self-hosted service (**Other (OpenAI-compatible)**), you can turn on **Send audio and text only to your service** in **Settings › AI Service** to bypass Google completely.

| Feature | With a Ling key | Without a key / fallback |
|---|---|---|
| Speech recognition and language detection | Apple `SpeechAnalyzer` / `SpeechTranscriber` (on device); macOS 14.4–15 uses `SFSpeechRecognizer` (on device, needs Dictation) | Same |
| Translating finished sentences | Ling `Ling-3.1-flash` (can be changed to `Ling-3.0-flash` in Settings › AI Service) | Google Translate → Apple `Translation` (on device, macOS 26 only) |
| Translating the sentence still being spoken | Google Translate | Shows original text until replaced by the full-sentence translation |
| Live notes and post-meeting full version | Ling `Ling-3.1-flash` | Not available |
| Checking if the key works | Ling `Ling-3.0-tiny` (1 token) | — |
| Interpreting: hearing and translating | Ming `Ming-3.0-audio-flash` (one step) | Apple on-device recognition + translation chain above |
| Interpreting: voice output and voice cloning | Ming `Ming-3.0-tts-0.5B` | Built-in Mac voices (`AVSpeechSynthesizer`), no cloning |
| Speaker identification | WeSpeaker ResNet34-LM (bundled, runs on device via Core ML) | Same |

## Setting up a Ling API key

1. Sign up and log in on the [Ling open platform](https://chat.ant-ling.com/platform/api), create a token, and copy the key starting with `sk-`.
2. Open **Settings › AI Service** in Cicada (or the banner at the top of the notes window), paste the key, and save.

**Can't sign up for Ling?** At the top right of **Settings › AI Service** (or by clicking **Can't use Ling?** during onboarding), you can switch to OpenRouter, ZenMux, OpenAI, or any OpenAI-compatible service (including local or LAN services like Ollama, vLLM, SGLang, Qwen3-ASR, and Whisper).

After switching, live notes and full-sentence translation still work, and OpenRouter and ZenMux can also use natural Gemini voices for interpreting; one-step voice translation and voice cloning are supported only by Ling. With a self-hosted service, notes and speaker naming can use a stronger model of their own, or connect to another service (enter its own address and key); search for models in the list, or type one in directly if it isn't found. When Windows, Linux, or Android switches to another service, listening to the other side also goes through the new service, so subtitles run 1–2 seconds behind Ling. If a connection fails, Settings tells you directly whether it's a key, model, or proxy issue (see the [setup page](https://cicada.indaloop.app/en/start/#proxy) for proxy details).

## Requirements & Installation

Installers are on the [Releases page](https://github.com/wquguru/cicada/releases/latest) and [the website](https://cicada.indaloop.app), and you can verify SHA-256 checksums against `checksums.txt` in Releases. If you run into questions, reach out to the author [@wquguru](https://x.com/wquguru) on X.

### Mac

Requires macOS 14.4+ (Apple silicon and Intel). On Apple silicon with macOS 14.4–15, first go to **System Settings › Keyboard** to turn on **Dictation** and add the languages you want heard; macOS 26 uses the new on-device model directly without needing Dictation; Intel Macs use cloud-based Ming recognition and require a Ling key.

Download `Cicada-<version>-macOS-AppleSilicon.dmg` or `Cicada-<version>-macOS-Intel.dmg` and drag Cicada into Applications (verify with `shasum -a 256 Cicada-*.dmg`). The app is not notarized by Apple yet, so if the first launch is blocked, go to **System Settings › Privacy & Security** and click **Open Anyway**. Follow the onboarding guide to grant permissions and try the sample meeting.

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="Onboarding step 2 playing a two-person sample meeting with live bilingual subtitles">
</p>

### Windows

Requires Windows 10 2004+ (x64 or Snapdragon ARM64). Download the installer and double-click to install without admin rights. If SmartScreen blocks it, click **More info › Run anyway**. When you use interpreting, the guide walks you through installing the free VB-Cable virtual microphone.

### Linux

Requires Ubuntu 22.04 or 24.04 desktop (x86_64 or arm64). Download `Cicada-<version>-Linux.tar.gz` and run `tar xzf Cicada-<version>-Linux.tar.gz && cicada-linux/install.sh` in a terminal. Interpreting automatically creates a "Cicada Microphone" with no driver to install. Linux windows cannot hide from screen sharing, so the notes window indicates that it is visible when sharing your screen. To enable **Settings › General › Save meeting audio**, first install system third-party media formats (such as `ubuntu-restricted-extras`) to provide an AAC encoder. Turning on **Settings › Word list › Fix misheard words live** sends one extra text request per sentence.

### Android

Requires Android 10+. Download and install `Cicada-<version>-Android.apk`; on Android 15 and later, allow restricted settings in App info the first time you turn on floating subtitles. It also includes on-device voiceprints to separate speakers and fixes misheard words live while listening. Call and meeting apps block internal audio capture on Android—just put the call on speaker and switch to **In person**.

## Roadmap

In rough order of priority; feel free to open an Issue for what you'd like to see. See [docs/ROADMAP.md](docs/ROADMAP.md) for details.

- **Record my own speech**: Continuously listen to the microphone with echo cancellation during meetings so what you say directly is also included in records and notes.
- **Code signing and notarization**: Official signing and notarization for Mac and Windows installers to eliminate security prompts and move AI keys back to the system keychain.
- **Speaker recognition**: Remember frequent coworkers' voices on device and recognize them automatically in future meetings.
- **Notes without a key**: Generate meeting notes on supported Macs using Apple's on-device models.
- **Android on app stores**: No more manual APK installs.
- **iPhone and iPad**: Starting with listening to meeting rooms, face-to-face interpreting, and meeting records.

## Uninstall

Quit Cicada and drag it from the Applications folder to the Trash. Meeting records and recordings are in `~/Library/Application Support/LiveSubs` and can be deleted manually if no longer needed. To clear settings, run:

```bash
defaults delete com.wquguru.cicada
```

## Development

The Mac app only requires Xcode Command Line Tools (`xcode-select --install`) and has no third-party dependencies. On macOS 27, if `SwiftUIMacros` is reported missing, install full Xcode and run `sudo xcode-select -s /Applications/Xcode.app`. For building on other platforms, see [windows/README.md](windows/README.md), [linux/README.md](linux/README.md), and [android/README.md](android/README.md).

```bash
scripts/build.sh            # dev build → build/Cicada.app ("Cicada Dev", runs alongside the release app)
open build/Cicada.app
scripts/package.sh          # package release DMG, zip, and SHA-256 checksums
```

See [AGENTS.md](AGENTS.md) for code architecture. The website source is in `site/` (generated by `scripts/site.py`), and release history is in [CHANGELOG.md](CHANGELOG.md) or on the [website changelog](https://cicada.indaloop.app/changelog/).

## License

This project is licensed under [Apache-2.0](LICENSE). The BlackHole 2ch virtual microphone driver is licensed under the GPL; it is not bundled in the installer and is downloaded from its official URL when you click install. The bundled voiceprint model is [WeSpeaker](https://github.com/wenet-e2e/wespeaker)'s ResNet34-LM trained on VoxCeleb (CC BY 4.0), converted to Core ML by `scripts/convert-voiceprint.py`.
