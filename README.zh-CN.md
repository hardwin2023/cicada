<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="知了图标">
</p>

<h1 align="center">知了 · Cicada</h1>

<p align="center">
  任何会议、任何直播，没有语言障碍。<br>
  听得懂，说得出，记得住。Mac、Windows、Linux 和 Android 上的实时纪要、双语记录、字幕与同声传译。
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/官网-cicada.indaloop.app-E8552B?style=for-the-badge" alt="官网 cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/download/"><img src="https://img.shields.io/badge/下载-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="下载 Mac、Windows、Linux、Android 版" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

开会或看直播时，知了实时给双语字幕，边听边写结构化纪要。轮到你发言，按住说话键（Mac 右 `⌥`，Windows 右 `Ctrl`，没有右 Ctrl 可在设置里换）开口，对方直接在会里听到译文语音。知了直接听系统声音，不往会里塞机器人，对方完全无感。在 Apple 芯片的 Mac 上全部本机识别，声音不出电脑。

**能在哪里用**：电脑能出声的地方都行——腾讯会议、飞书、钉钉、企业微信、Zoom、Teams、Google Meet、Webex、Discord、Telegram 语音，还有 X Spaces、YouTube、Twitch、B 站直播、播客和网页。手机上系统不让录通话和会议 app 的声音，开外放用“面对面”就行。

<p align="center">
  <img src="docs/demo.gif" width="800" alt="YouTube 播着 Bloomberg 英文直播，右边是知了实时整理的中文纪要、议题与鱼骨图，底部是双语字幕">
</p>

## 平台

| 平台 | 系统要求 | 说明 |
|---|---|---|
| Mac | macOS 14.4+，Apple 芯片 / Intel | 功能最全。Apple 芯片本机识别（不填 key 也能用），Intel 版需 Ling key（识别走 Ming） |
| Windows | Windows 10 2004+，x64 / ARM64 | 需 Ling、OpenRouter、ZenMux 等 AI 服务 key，见 [windows/](windows/README.md) |
| Linux | Ubuntu 22.04 / 24.04 桌面版 | 需 AI 服务 key；纪要窗会被屏幕共享看到，见 [linux/](linux/README.md) |
| Android | Android 10+ | 需 AI 服务 key；视频与直播字幕、面对面互译，见 [android/](android/README.md) |

安装包都在 [官网下载页](https://cicada.indaloop.app/download/) 和 [Releases](https://github.com/wquguru/cicada/releases)。四个平台共用版本号和会议记录格式，下面以 Mac 版为例说明功能。

## 主要功能

### 实时纪要与双语文字记录

边听边整理总结、议题要点、结论、待办、鱼骨图和人名术语表，点结论或待办就能跳回原话。按 `⌘F` 搜索，连识别错的同音词也能搜出来。

接上 AI 服务后，听错的人名和术语会当场改对：同音字直接改，生僻名字先问你一次，答“对”以后自动改。常用词可以提前贴进设置的“词表”。会后也能选“改这句…”批量改整场同样的错词，随时可撤销。

### 实时字幕与语言识别

对方开口几秒就能认出语言并翻成你的系统语言，按 `⌃⌥S` 切换显示方式。字幕条只在有人说话时出现，鼠标划过自动变透明，不挡视线。在 Apple 芯片的 macOS 26 上，15 到 30 秒后还会在本机重听校准，修掉错字和漏字。

### 线下与混合会议

点“打开麦克风”就能记下现场说话。混合会议也是这一个按钮：电脑声音标为“线上”，麦克风标为“现场”，合在同一份记录里（macOS 14 和 15 打开麦克风时只听现场）。外放时自动去重，戴耳机时两边同时说也能记下。Windows 和 Linux 规则相同。

Mac 上点按钮旁的小箭头能单独换麦克风（比如 iPhone 或会议麦），不改系统默认设置。麦克风听到的只记进纪要，不会传进会议；要对方听到你，用下面的同声传译。

### 同声传译

按住右 `⌥` 说话，对方就能在会议软件里听到翻译后的语音。

Mac 上还能在“设置 › 同声传译”打开“不用按键”：听会时直接开口，会议声音会自动压低，停顿 1 秒后译文就说出去。打开麦克风时它会暂停，身边有人时也建议改回按键，免得把别人的话当成你。

开启后会把系统麦克风切到一键下载安装的虚拟驱动 BlackHole 2ch。填了 Ling API key 可以用自然人声，或用 8 到 30 秒录音克隆你自己的声音；不填也能用 Mac 自带语音。Windows、Linux 的同传和 Android 的面对面也能用你自己的声音，填了 Ling key 后录 10 到 15 秒即可。

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="同声传译设置页，包含按住右 Option 键说话、目标语言、Ming 声音试听与本机声音选择">
</p>

### 会议记录

双语记录、纪要和原始录音都存在本机。点任意一句就能从那儿回放，文字跟着高亮滚动。本机声纹模型会自动区分说话人（填了 Ling key 会填上名字），认错了随时改名或合并。目前记录里的你只包含按住说话键说的话，会上直接开口的部分见[路线图](#路线图)。

会后可以补生成纪要，导出 Markdown、Word 和 SRT 字幕，或者点“文件 › 导入录音或视频…”转写本地音视频。Mac 上“复制纪要”（⇧⌘C）贴进飞书、Notion、Word 时标题、列表和鱼骨图都在，贴进聊天框是 Markdown。打开“设置 › 通用 › 存到文件夹”后，每场会议还会自动存成 Markdown（开头带给 agent 读的 frontmatter）放进 Obsidian 库等文件夹，改名或重新整理后文件跟着更新。

点“分享…”能生成纪要链接（可选带上双语全文），支持设有效期和密码，上传前会自动拦截密钥、未公开公司信息等敏感内容。

<p align="center">
  <img src="docs/records.png" width="640" alt="会议记录窗口，显示识别出的说话人名字和逐句英中双语文字记录">
</p>

## 隐私与权限

**Apple 芯片的 Mac**：录音和语音识别都在本机跑，声音不出电脑。发出去的只有转好的文字（用来翻译和写纪要）。例外：配了 Ling key 用同传时你说的那几句，点了“先用 Ling 听”，或在“设置 › AI 服务”里改成了自建服务，声音才会发给对应服务。不填 API key，实时字幕、翻译、会议记录和同传全部免费。实时纪要、一步语音翻译和声音克隆要填你自己的 Ling（蚂蚁集团大模型服务）API key。开会一小时大概 0.15 到 1 元人民币，Ling 每月送 10 元额度，够用 10 到 50 小时。

**Intel 版 Mac、Windows、Linux、Android**：语音识别走云端，必须填 AI 服务 key，声音会分段发给 Ling 的 Ming 或你选的 OpenRouter、ZenMux 等服务。录音和会议记录依然只存本机。

Mac 版用到什么功能才要什么权限，拒了也不耽误别的功能：

| 权限 | 用途 | 不给的话 |
|---|---|---|
| 录制系统声音（屏幕与系统录音） | 听系统声音出字幕，不录画面 | 用不了字幕和纪要 |
| 麦克风 | 按住说话或“不用按键”做同传；点“打开麦克风”听会议室 | 不能说话翻译、不能听会议室 |
| 输入监控 | 检测右 `⌥` 按键（不拦截、不记别的键） | 改用 `⌃`/`⌘` 组合键就不用给 |
| 管理员密码 | 安装虚拟麦克风 BlackHole 2ch（只问一次） | 对方听不到同传，别的照常 |

- **联网透明**：只有翻译（`translate.googleapis.com`）、你配的 AI 服务（如 `api.ant-ling.com`）、下载苹果公证的 BlackHole 驱动（会核对 SHA-256）和每天去 GitHub 查更新会联网。无统计、无埋点，也没有我们自己的服务器。
- **数据存本机**：记录和录音存在 `~/Library/Application Support/LiveSubs`。Key 和声音样本只有当前系统账户能读，不进 Time Machine 和日志。
- **防录屏**：Mac 上共享屏幕、录屏和截图都拍不到纪要窗口。要录演示可以手动打开“共享屏幕时让对方看到”。

## 用到的模型

以下为 Apple 芯片 Mac 的配置。用自建服务（“其他（兼容 OpenAI）”）时，可在“设置 › AI 服务”打开“语音和文字只发给你的服务”，完全不经过 Google。

| 功能 | 填了 Ling key | 不填 key / 退回 |
|---|---|---|
| 语音识别、语言识别 | Apple `SpeechAnalyzer` / `SpeechTranscriber`（本机）；macOS 14.4–15 为 `SFSpeechRecognizer`（本机，需开听写） | 同左 |
| 整句翻译 | Ling `Ling-3.1-flash`（可在“设置 › AI 服务”改为 `Ling-3.0-flash`） | Google 翻译 → Apple `Translation`（本机，仅 macOS 26） |
| 正在说的半句话翻译 | Google 翻译 | 只显示原文，说完换整句翻译 |
| 实时纪要、会后完整版 | Ling `Ling-3.1-flash` | 不可用 |
| 检查 key 是否有效 | Ling `Ling-3.0-tiny`（1 token） | — |
| 同传：听懂并翻译 | Ming `Ming-3.0-audio-flash`（一步完成） | Apple 本机识别 + 上述翻译链 |
| 同传：发声与声音克隆 | Ming `Ming-3.0-tts-0.5B` | Mac 自带语音（`AVSpeechSynthesizer`），无克隆 |
| 说话人识别 | WeSpeaker ResNet34-LM（随 app 附带，本机 Core ML 运行） | 同左 |

## 配置 Ling API key

1. 去 [Ling 开放平台](https://chat.ant-ling.com/platform/api) 注册登录，创建令牌，复制 `sk-` 开头的 key。
2. 打开知了“设置 › AI 服务”（或纪要窗口顶部提示框），粘贴保存即可。

**注册不了 Ling？** 在“设置 › AI 服务”右上角（或引导页点“用不了 Ling？”）可以换成 OpenRouter、ZenMux、OpenAI，或任何 OpenAI 兼容服务（包括 Ollama、vLLM、SGLang、Qwen3-ASR、Whisper 等本机或局域网服务）。

换服务后，实时纪要和整句翻译照样能用，OpenRouter 和 ZenMux 还能用 Gemini 的自然人声做同传；一步语音翻译和声音克隆则只有 Ling 支持。用自建服务时，纪要和说话人识别可以单独换更强的模型，或者接另一个服务（填自己的地址和 key）；模型从列表里搜，搜不到也能直接手填。Windows、Linux、Android 换其他服务后，“听对方”也交给新服务处理，字幕会比 Ling 晚 1–2 秒。连不上时，设置里会直接提示是 key、模型还是代理问题（代理说明见[设置页](https://cicada.indaloop.app/start/#proxy)）。

## 系统要求与安装

安装包都在 [Releases 页面](https://github.com/wquguru/cicada/releases/latest) 或 [官网](https://cicada.indaloop.app)，可用 Releases 里的 `checksums.txt` 核对 SHA-256。有问题可以去 X 找作者 [@wquguru](https://x.com/wquguru)。

### Mac

需要 macOS 14.4+（支持 Apple 芯片与 Intel）。Apple 芯片在 macOS 14.4–15 上要先去系统设置 › 键盘里打开“听写”并添加要听的语言；macOS 26 直接用新本机模型，不用开听写；Intel 版走云端 Ming 识别，需要配 Ling key。

下载 `Cicada-<版本>-macOS-AppleSilicon.dmg` 或 `Cicada-<版本>-macOS-Intel.dmg`，拖进应用程序文件夹（可用 `shasum -a 256 Cicada-*.dmg` 校验）。目前还没有苹果公证，第一次打开被拦时，去系统设置 › 隐私与安全性里点仍要打开。跟着首次引导开权限、试听示例会议即可。

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="首次引导第二步，播放双人示例会议并实时显示双语字幕">
</p>

### Windows

需要 Windows 10 2004+（x64 或骁龙 ARM64）。下载安装包双击即装，不用管理员权限。SmartScreen 拦下时点更多信息 › 仍要运行。用同传时引导会带你装免费的 VB-Cable 虚拟麦克风。

### Linux

需要 Ubuntu 22.04 或 24.04 桌面版（x86_64 或 arm64）。下载 `Cicada-<版本>-Linux.tar.gz`，终端运行 `tar xzf Cicada-<版本>-Linux.tar.gz && cicada-linux/install.sh`。同传会自动建一个“知了 麦克风”，免装驱动。Linux 窗口无法避开屏幕共享，纪要窗会标明“共享屏幕时此窗口可见”。想打开“设置 › 通用 › 保存会议录音”，需先装系统第三方媒体格式（如 `ubuntu-restricted-extras`）提供 AAC 编码器。打开“设置 › 词表 › 会中改正听错的词”后每句会多发一次文字请求。

### Android

需要 Android 10+。下载 `Cicada-<版本>-Android.apk` 安装；Android 15 起第一次开悬浮字幕要先在应用信息里允许受限制的设置。同样自带本机声纹区分说话人、支持“正在听”时实时改错词。微信通话和会议 app 的声音系统不让内录，开外放、改选“面对面”就行。

## 路线图

按先后排，想要哪一项欢迎提 Issue。细节见 [docs/ROADMAP.zh-CN.md](docs/ROADMAP.zh-CN.md)。

- **记录我的发言**：开会时持续听麦克风并消除回声，把你直接开口说的话也记进记录和纪要。
- **正式签名与公证**：Mac 和 Windows 安装包加上正式签名与公证，不再弹窗拦截，AI key 放回系统钥匙串。
- **声纹识别**：在本机记住常开会同事的声音，下次自动认出。
- **不用 key 也有纪要**：在支持的 Mac 上用 Apple 本机模型整理纪要。
- **Android 上架应用商店**：不用再手动装 APK。
- **iPhone 和 iPad**：先做听会议室、面对面互译和会议记录。

## 卸载

退出知了，从应用程序文件夹拖进废纸篓即可。会议记录和录音在 `~/Library/Application Support/LiveSubs`，不用可手动删。清除设置运行：

```bash
defaults delete com.wquguru.cicada
```

## 开发

Mac 版只需安装 Xcode Command Line Tools（`xcode-select --install`），无第三方依赖。macOS 27 上若报 `SwiftUIMacros` 缺失，安装完整 Xcode 并运行 `sudo xcode-select -s /Applications/Xcode.app`。其他平台构建见 [windows/README.md](windows/README.md)、[linux/README.md](linux/README.md)、[android/README.md](android/README.md)。

```bash
scripts/build.sh            # 编译开发版 → build/Cicada.app（名为 Cicada Dev，可与正式版同时运行）
open build/Cicada.app
scripts/package.sh          # 打包正式版 DMG、zip 和 SHA-256 校验值
```

代码架构见 [AGENTS.md](AGENTS.md)，官网源码在 `site/`（由 `scripts/site.py` 生成），更新记录见 [CHANGELOG.md](CHANGELOG.md) 或[官网更新日志](https://cicada.indaloop.app/changelog/)。

## 开源协议

本项目采用 [Apache-2.0](LICENSE) 协议开源。虚拟麦克风驱动 BlackHole 2ch 采用 GPL 协议，不打包在安装包内，点安装时从其官方地址下载。随附的声纹模型是 [WeSpeaker](https://github.com/wenet-e2e/wespeaker) 在 VoxCeleb 上训练的 ResNet34-LM（CC BY 4.0 协议），由 `scripts/convert-voiceprint.py` 转为 Core ML。
