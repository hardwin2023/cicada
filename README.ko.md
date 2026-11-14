<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cicada 아이콘">
</p>

<h1 align="center">Cicada · 知了</h1>

<p align="center">
  어떤 회의도, 어떤 방송도 언어 장벽 없이.<br>
  알아듣고, 말하고, 기록합니다. Mac, Windows, Linux, Android에서 실시간 회의록, 이중 언어 기록, 자막, 동시통역을 제공합니다.
</p>

<p align="center">
  <a href="https://cicada.indaloop.app/ko/"><img src="https://img.shields.io/badge/%EC%9B%B9%EC%82%AC%EC%9D%B4%ED%8A%B8-cicada.indaloop.app-E8552B?style=for-the-badge" alt="웹사이트: cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/ko/download/"><img src="https://img.shields.io/badge/%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="Mac, Windows, Linux, Android 다운로드" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/%EB%9D%BC%EC%9D%B4%EC%84%A0%EC%8A%A4-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

회의를 하거나 라이브 방송을 볼 때, Cicada는 실시간으로 이중 언어 자막을 보여주고 들으면서 체계적인 회의록을 작성합니다. 발언 차례가 되면 말하기 키(Mac은 오른쪽 `⌥`, Windows는 오른쪽 `Ctrl`, 변경 가능)를 누른 채 말하면 상대방이 회의에서 바로 번역된 음성을 듣습니다. Cicada는 시스템 소리를 직접 읽기 때문에 회의에 봇을 넣지 않아 상대방은 전혀 눈치채지 못합니다. Apple silicon Mac에서는 인식이 모두 기기 안에서 이루어져 소리가 컴퓨터 밖으로 나가지 않습니다.

**사용 가능한 곳**: 컴퓨터에서 소리가 나는 모든 곳에서 쓸 수 있습니다. Tencent Meeting, Feishu, DingTalk, WeCom, Zoom, Teams, Google Meet, Webex, Discord, Telegram 음성 채팅은 물론 X Spaces, YouTube, Twitch, Bilibili 라이브, 팟캐스트 및 웹페이지도 지원합니다. 스마트폰에서는 시스템에서 통화 및 회의 앱 소리 녹음을 허용하지 않으므로, 스피커폰을 켜고 '대면' 모드를 사용하면 됩니다.

<p align="center">
  <img src="docs/demo.gif" width="800" alt="YouTube에서 재생 중인 Bloomberg 영어 라이브 방송과 오른쪽의 Cicada가 실시간으로 정리한 중국어 회의록, 안건, 피시본 다이어그램, 하단의 이중 언어 자막">
</p>

## 지원 플랫폼

| 플랫폼 | 요구 사항 | 비고 |
|---|---|---|
| Mac | macOS 14.4+, Apple silicon / Intel | 모든 기능 지원. Apple silicon은 기기 내 음성 인식(키 없이도 사용 가능), Intel 버전은 Ling 키 필요(Ming으로 음성 인식) |
| Windows | Windows 10 2004+, x64 / ARM64 | Ling, OpenRouter, ZenMux 등 AI 서비스 키 필요. [windows/](windows/README.md) 참고 |
| Linux | Ubuntu 22.04 / 24.04 데스크톱 | AI 서비스 키 필요. 화면 공유 시 회의록 창이 보임. [linux/](linux/README.md) 참고 |
| Android | Android 10+ | AI 서비스 키 필요. 동영상·라이브 자막, 대면 통역. [android/](android/README.md) 참고 |

설치 파일은 [웹사이트 다운로드 페이지](https://cicada.indaloop.app/ko/download/)와 [Releases](https://github.com/wquguru/cicada/releases)에서 받을 수 있습니다. 네 플랫폼 모두 버전 번호와 회의 기록 형식을 공유하며, 아래 기능은 Mac 버전을 기준으로 설명합니다.

## 주요 기능

### 실시간 회의록 및 이중 언어 기록

들으면서 요약, 안건 요점, 결론, 할 일, 피시본 다이어그램, 인명·용어집을 정리하며, 결론이나 할 일을 클릭하면 원래 발언으로 바로 이동합니다. `⌘F`로 검색하면 잘못 인식된 동음이의어까지 함께 찾아줍니다.

AI 서비스를 연결하면 잘못 들은 인명과 용어를 그 자리에서 고칩니다. 발음이 같은 오타는 바로 고치고, 낯선 이름은 먼저 한 번 물어본 뒤 "네"라고 답하면 그다음부터 자동으로 고칩니다. 자주 쓰는 단어는 설정의 "단어 목록"에 미리 붙여 넣을 수 있습니다. 회의 후에도 "이 줄 고치기…"로 회의 전체의 같은 오류를 한꺼번에 고칠 수 있으며 언제든 되돌릴 수 있습니다.

### 실시간 자막 및 언어 감지

상대방이 말하기 시작하면 몇 초 안에 언어를 감지해 시스템 언어로 번역하며, `⌃⌥S`로 표시 방식을 전환합니다. 자막 바는 누군가 말할 때만 나타나고 마우스를 올리면 자동으로 투명해져 시야를 가리지 않습니다. Apple silicon 탑재 macOS 26에서는 15~30초 뒤에 기기에서 다시 듣고 보정하여 오타와 빠진 글자를 고칩니다.

### 오프라인 및 하이브리드 회의

"마이크 켜기"를 누르면 현장의 말을 기록합니다. 하이브리드 회의도 이 버튼 하나로 됩니다. 컴퓨터 소리는 "온라인", 마이크는 "현장"으로 표시해 하나의 기록에 함께 남깁니다(macOS 14와 15에서는 마이크를 켜면 현장 소리만 듣습니다). 스피커를 쓸 때는 자동으로 중복을 제거하며, 이어폰을 끼면 양쪽이 동시에 말해도 모두 기록합니다. Windows와 Linux도 규칙이 같습니다.

Mac에서는 버튼 옆 작은 화살표로 마이크(iPhone이나 회의용 마이크 등)만 따로 바꿀 수 있으며, 시스템 기본 설정은 건드리지 않습니다. 마이크로 들은 내용은 회의록에만 남고 회의로 보내지지 않습니다. 상대가 내 말을 듣게 하려면 아래 동시통역을 쓰세요.

### 동시통역

오른쪽 `⌥` 키를 누른 채 말하면 상대방이 회의 앱에서 번역된 음성을 듣습니다.

Mac에서는 "설정 › 동시통역"에서 "키 없이 말하기"를 켤 수도 있습니다. 회의를 듣는 동안 그냥 말을 꺼내면 회의 소리가 자동으로 줄고, 1초 멈추면 번역이 전달됩니다. 마이크를 켜 둔 동안에는 일시 정지되며, 주변에 사람이 있으면 다른 사람의 말이 내 말로 처리되지 않도록 다시 키 입력 방식으로 바꾸는 것이 좋습니다.

기능을 켜면 클릭 한 번으로 내려받아 설치하는 가상 드라이버 BlackHole 2ch로 시스템 마이크를 전환합니다. Ling API 키를 입력하면 자연스러운 음성을 쓰거나 8~30초 녹음으로 내 목소리를 복제할 수 있고, 입력하지 않아도 Mac 기본 음성을 쓸 수 있습니다. Windows와 Linux의 동시통역, Android의 대면 모드에서도 Ling API 키가 있으면 10~15초 녹음으로 내 목소리를 쓸 수 있습니다.

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="오른쪽 Option 말하기 키, 대상 언어, Ming 음성 미리 듣기, macOS 음성이 표시된 동시통역 설정 화면">
</p>

### 회의 기록

이중 언어 기록, 회의록, 원본 녹음은 모두 기기에 저장됩니다. 아무 문장이나 클릭하면 그 위치부터 다시 들을 수 있고, 글자가 강조되며 함께 스크롤됩니다. 기기 내 성문 모델이 화자를 자동으로 구분하며(Ling 키가 있으면 이름도 채움), 잘못 구분되면 언제든 이름을 바꾸거나 합칠 수 있습니다. 현재 기록에 남는 내 발언은 말하기 키를 누르고 말한 내용뿐이며, 회의에서 바로 말한 부분은 [로드맵](#로드맵)을 참고하세요.

회의 후 회의록을 추가로 생성하고 Markdown, Word, SRT 자막으로 내보내거나, "파일 › 녹음 또는 동영상 가져오기…"로 로컬 오디오·비디오를 변환할 수 있습니다. Mac의 "회의록 복사하기"(⇧⌘C)는 Feishu, Notion, Word에 붙이면 제목·목록·피시본 다이어그램이 그대로 들어가고, 채팅창에는 Markdown으로 붙습니다. "설정 › 일반 › 폴더에 저장"을 켜면 회의마다 Markdown(앞부분에 에이전트용 frontmatter 포함)으로 Obsidian 보관함 등의 폴더에 자동 저장되고, 이름을 바꾸거나 다시 정리하면 파일도 함께 갱신됩니다.

"공유…"를 누르면 회의록 링크(선택 시 이중 언어 전문 포함)를 만들 수 있으며, 유효 기간과 비밀번호 설정을 지원합니다. 업로드 전에는 키나 미공개 회사 정보 같은 민감한 내용을 자동으로 차단합니다.

<p align="center">
  <img src="docs/records.png" width="640" alt="구분된 화자 이름과 문장별 영중 이중 언어 기록이 표시된 회의 기록 창">
</p>

## 개인정보 보호 및 권한

**Apple silicon Mac**: 녹음과 음성 인식이 모두 기기에서 이루어져 소리가 컴퓨터 밖으로 나가지 않습니다. 전송되는 것은 변환된 텍스트(번역 및 회의록 작성용)뿐입니다. 예외: Ling 키를 설정해 동시통역을 쓸 때 내가 말한 몇 마디, "먼저 Ling 사용하기"를 눌렀을 때, 또는 "설정 › AI 서비스"에서 자체 서비스로 바꾼 경우에만 소리가 해당 서비스로 전송됩니다. API 키를 입력하지 않아도 실시간 자막, 번역, 회의 기록, 동시통역을 모두 무료로 쓸 수 있습니다. 실시간 회의록, 원스텝 음성 번역, 목소리 복제에는 본인의 Ling(Ant Group 대규모 모델 서비스) API 키가 필요합니다. 1시간 회의에 약 0.15~1위안이 들며, Ling에서 매달 주는 10위안 무료 크레딧으로 10~50시간 동안 쓸 수 있습니다.

**Intel Mac, Windows, Linux, Android**: 음성 인식이 클라우드에서 이루어지므로 AI 서비스 키를 꼭 입력해야 하며, 소리는 구간별로 나누어 Ling의 Ming이나 선택한 OpenRouter, ZenMux 등의 서비스로 전송됩니다. 녹음과 회의 기록은 여전히 기기에만 저장됩니다.

Mac 버전은 필요한 기능을 쓸 때만 권한을 요청하며, 거부해도 다른 기능은 문제없이 작동합니다.

| 권한 | 용도 | 허용하지 않을 경우 |
|---|---|---|
| 시스템 오디오 녹음(화면 및 시스템 오디오 녹음) | 시스템 소리를 듣고 자막 생성, 화면은 녹화하지 않음 | 자막과 회의록 사용 불가 |
| 마이크 | 길게 눌러 말하기나 "키 없이 말하기"로 동시통역, "마이크 켜기"를 눌러 회의실 소리 듣기 | 말하기 번역 및 회의실 듣기 불가 |
| 입력 모니터링 | 오른쪽 `⌥` 키 입력 감지(가로채거나 다른 키를 기록하지 않음) | `⌃`/`⌘` 조합 키로 바꾸면 권한 불필요 |
| 관리자 암호 | 가상 마이크 BlackHole 2ch 설치(한 번만 물어봄) | 상대방이 동시통역을 들을 수 없음, 나머지는 정상 작동 |

- **투명한 네트워크 연결**: 번역(`translate.googleapis.com`), 설정한 AI 서비스(예: `api.ant-ling.com`), Apple 공증을 받은 BlackHole 드라이버 다운로드(SHA-256 대조), 하루 한 번 GitHub 업데이트 확인에만 인터넷에 연결합니다. 통계 수집이나 추적 코드, 자체 서버가 없습니다.
- **로컬 데이터 저장**: 기록과 녹음은 `~/Library/Application Support/LiveSubs`에 저장됩니다. 키와 목소리 샘플은 현재 시스템 계정만 읽을 수 있으며 Time Machine과 로그에 들어가지 않습니다.
- **화면 녹화 방지**: Mac에서 화면 공유, 화면 기록, 스크린샷에 회의록 창이 찍히지 않습니다. 시연 영상을 녹화하려면 "화면 공유 시 상대방에게 표시"를 수동으로 켜면 됩니다.

## 사용 모델

아래는 Apple silicon Mac 기준 구성입니다. 자체 서비스("기타(OpenAI 호환)")를 쓸 때는 "설정 › AI 서비스"에서 "음성과 텍스트를 내 서비스로만 전송"을 켜면 Google을 전혀 거치지 않습니다.

| 기능 | Ling 키 사용 시 | 키 없음 / 대체 작동 시 |
|---|---|---|
| 음성 인식, 언어 감지 | Apple `SpeechAnalyzer` / `SpeechTranscriber`(기기 내); macOS 14.4–15는 `SFSpeechRecognizer`(기기 내, 받아쓰기 켜야 함) | 왼쪽과 같음 |
| 끝난 문장 번역 | Ling `Ling-3.1-flash`("설정 › AI 서비스"에서 `Ling-3.0-flash`로 변경 가능) | Google 번역 → Apple `Translation`(기기 내, macOS 26 전용) |
| 말하는 중인 문장 번역 | Google 번역 | 원문만 표시, 말이 끝나면 전체 문장 번역으로 교체 |
| 실시간 회의록, 회의 후 전체본 | Ling `Ling-3.1-flash` | 사용 불가 |
| 키 유효성 확인 | Ling `Ling-3.0-tiny`(1토큰) | — |
| 동시통역: 듣고 번역하기 | Ming `Ming-3.0-audio-flash`(원스텝 처리) | Apple 기기 내 인식 + 위 번역 체인 |
| 동시통역: 음성 합성 및 목소리 복제 | Ming `Ming-3.0-tts-0.5B` | Mac 기본 음성(`AVSpeechSynthesizer`), 복제 불가 |
| 화자 구분 | WeSpeaker ResNet34-LM(앱에 포함, 기기 내 Core ML 실행) | 왼쪽과 같음 |

## Ling API 키 설정

1. [Ling 오픈 플랫폼](https://chat.ant-ling.com/platform/api)에 가입·로그인하여 토큰을 만들고 `sk-`로 시작하는 키를 복사합니다.
2. Cicada의 "설정 › AI 서비스"(또는 회의록 창 상단 입력란)를 열고 붙여넣어 저장하면 됩니다.

**Ling에 가입할 수 없나요?** "설정 › AI 서비스" 오른쪽 위(또는 초기 안내에서 "Ling을 사용할 수 없나요?" 클릭)에서 OpenRouter, ZenMux, OpenAI 또는 모든 OpenAI 호환 서비스(Ollama, vLLM, SGLang, Qwen3-ASR, Whisper 등 로컬·LAN 서비스 포함)로 바꿀 수 있습니다.

서비스를 바꿔도 실시간 회의록과 문장 번역은 그대로 쓸 수 있으며, OpenRouter와 ZenMux에서는 Gemini의 자연스러운 음성으로 동시통역도 쓸 수 있습니다. 원스텝 음성 번역과 목소리 복제는 Ling만 지원합니다. 자체 서비스를 쓸 때는 회의록과 화자 구분만 더 강한 모델로 바꾸거나 다른 서비스(별도 주소와 키 입력)에 연결할 수 있으며, 모델은 목록에서 검색하거나 목록에 없으면 직접 입력할 수 있습니다. Windows, Linux, Android에서 다른 서비스로 바꾸면 "상대방 듣기"도 새 서비스가 처리하며 자막이 Ling보다 1~2초 늦습니다. 연결되지 않을 때는 키, 모델, 프록시 중 어디에 문제가 있는지 설정에서 바로 알려 줍니다(프록시 설명은 [설정 페이지](https://cicada.indaloop.app/ko/start/#proxy) 참고).

## 시스템 요구 사항 및 설치

설치 파일은 모두 [Releases 페이지](https://github.com/wquguru/cicada/releases/latest)나 [웹사이트](https://cicada.indaloop.app/ko/)에 있으며, Releases의 `checksums.txt`로 SHA-256을 대조할 수 있습니다. 문의 사항은 X에서 개발자 [@wquguru](https://x.com/wquguru)에게 연락해 주세요.

### Mac

macOS 14.4 이상(Apple silicon 및 Intel 지원)이 필요합니다. Apple silicon의 경우 macOS 14.4–15에서는 먼저 시스템 설정 › 키보드에서 "받아쓰기"를 켜고 들을 언어를 추가해야 하며, macOS 26에서는 새 기기 내 모델을 바로 쓰므로 받아쓰기를 켤 필요가 없습니다. Intel 버전은 클라우드 Ming으로 인식하므로 Ling 키를 설정해야 합니다.

`Cicada-<버전>-macOS-AppleSilicon.dmg` 또는 `Cicada-<버전>-macOS-Intel.dmg`를 내려받아 응용 프로그램 폴더로 끌어다 놓으세요(`shasum -a 256 Cicada-*.dmg`로 검증 가능). 아직 Apple 공증을 받지 않아 처음 열 때 차단되면 시스템 설정 › 개인정보 보호 및 보안에서 확인 없이 열기를 누르세요. 초기 안내에 따라 권한을 켜고 샘플 회의를 들어보면 됩니다.

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="2인 샘플 회의를 재생하며 실시간 이중 언어 자막을 보여주는 초기 안내 2단계">
</p>

### Windows

Windows 10 2004 이상(x64 또는 Snapdragon ARM64)이 필요합니다. 설치 파일을 내려받아 더블 클릭하면 관리자 권한 없이 바로 설치됩니다. SmartScreen이 막으면 추가 정보 › 실행을 누르세요. 동시통역을 쓸 때는 무료 VB-Cable 가상 마이크를 설치하도록 안내합니다.

### Linux

Ubuntu 22.04 또는 24.04 데스크톱 버전(x86_64 또는 arm64)이 필요합니다. `Cicada-<버전>-Linux.tar.gz`를 내려받아 터미널에서 `tar xzf Cicada-<버전>-Linux.tar.gz && cicada-linux/install.sh`를 실행하세요. 동시통역은 드라이버 설치 없이 "Cicada 마이크"를 자동으로 만듭니다. Linux 창은 화면 공유를 피할 수 없어 회의록 창에 "화면 공유 시 이 창이 보입니다"라고 표시됩니다. "설정 › 일반 › 회의 녹음 저장"을 켜려면 AAC 인코더를 제공하는 시스템 서드파티 미디어 형식(예: `ubuntu-restricted-extras`)을 먼저 설치해야 합니다. "설정 › 단어 목록 › 회의 중 잘못 들은 단어 고치기"를 켜면 문장마다 텍스트 요청을 한 번 더 보냅니다.

### Android

Android 10 이상이 필요합니다. `Cicada-<버전>-Android.apk`를 내려받아 설치하세요. Android 15부터는 플로팅 자막을 처음 켤 때 앱 정보에서 제한된 설정을 먼저 허용해야 합니다. 마찬가지로 기기 내 성문으로 화자를 구분하고 "듣는 중"일 때 잘못 들은 단어를 실시간으로 고칩니다. 위챗 통화나 회의 앱 소리는 시스템이 내부 녹음을 막으므로 스피커폰을 켜고 "대면"으로 바꾸면 됩니다.

## 로드맵

우선순위 순이며, 원하는 항목이 있다면 Issue로 남겨 주세요. 자세한 내용은 [docs/ROADMAP.md](docs/ROADMAP.md)를 참고하세요.

- **내 발언 기록**: 회의 중 반향을 제거하며 마이크를 계속 들어, 내가 직접 입을 열어 말한 내용도 기록과 회의록에 포함.
- **정식 서명 및 공증**: Mac과 Windows 설치 파일에 정식 서명과 공증을 추가해 차단 팝업을 없애고 AI 키를 시스템 키체인에 보관.
- **성문 인식**: 자주 회의하는 동료의 목소리를 기기에 기억해 다음번에 자동으로 인식.
- **키 없이 쓰는 회의록**: 지원되는 Mac에서 Apple 기기 내 모델로 회의록 정리.
- **Android 앱 스토어 출시**: APK를 수동으로 설치할 필요 없음.
- **iPhone 및 iPad**: 회의실 듣기, 대면 통역, 회의 기록부터 지원.

## 제거

Cicada를 종료하고 응용 프로그램 폴더에서 휴지통으로 끌어다 놓으면 됩니다. 회의 기록과 녹음은 `~/Library/Application Support/LiveSubs`에 있으며 필요 없으면 수동으로 지우세요. 설정을 지우려면 다음을 실행하세요.

```bash
defaults delete com.wquguru.cicada
```

## 개발

Mac 버전은 Xcode Command Line Tools(`xcode-select --install`)만 설치하면 되며 서드파티 의존성이 없습니다. macOS 27에서 `SwiftUIMacros` 누락 오류가 나면 전체 Xcode를 설치하고 `sudo xcode-select -s /Applications/Xcode.app`을 실행하세요. 다른 플랫폼 빌드는 [windows/README.md](windows/README.md), [linux/README.md](linux/README.md), [android/README.md](android/README.md)를 참고하세요.

```bash
scripts/build.sh            # 개발 버전 빌드 → build/Cicada.app (이름은 Cicada Dev, 정식 버전과 동시 실행 가능)
open build/Cicada.app
scripts/package.sh          # 정식 버전 DMG, zip 및 SHA-256 체크섬 패키징
```

코드 아키텍처는 [AGENTS.md](AGENTS.md)에 있으며, 웹사이트 소스는 `site/`(`scripts/site.py`로 생성)에 있고, 업데이트 내역은 [CHANGELOG.md](CHANGELOG.md) 또는 [웹사이트 변경 로그](https://cicada.indaloop.app/ko/changelog/)에서 볼 수 있습니다.

## 라이선스

이 프로젝트는 [Apache-2.0](LICENSE) 라이선스로 공개되어 있습니다. 가상 마이크 드라이버 BlackHole 2ch는 GPL 라이선스를 따르며 설치 패키지에 포함되지 않고 설치를 누를 때 공식 주소에서 내려받습니다. 포함된 성문 모델은 [WeSpeaker](https://github.com/wenet-e2e/wespeaker)가 VoxCeleb으로 학습한 ResNet34-LM(CC BY 4.0 라이선스)이며 `scripts/convert-voiceprint.py`로 Core ML로 변환했습니다.
