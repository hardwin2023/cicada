<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cicada のアイコン">
</p>

<h1 align="center">Cicada · 知了</h1>

<p align="center">
  どんな会議も、どんな配信も、言葉の壁なく。<br>
  聞き取れて、話せて、記録に残る。Mac・Windows・Linux・Android で使えるリアルタイムの議事メモ、二か国語の書き起こし、字幕、同時通訳。
</p>

<p align="center">
  <a href="https://cicada.indaloop.app/ja/"><img src="https://img.shields.io/badge/Website-cicada.indaloop.app-E8552B?style=for-the-badge" alt="Website: cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/ja/download/"><img src="https://img.shields.io/badge/Download-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="Mac・Windows・Linux・Android 版をダウンロード" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

会議やライブ配信の間、Cicada はリアルタイムの二か国語字幕を出しながら、構造化された議事メモを書き進めます。発言するときは、話すキー（Mac は右の `⌥`、Windows は右の `Ctrl`、変更可）を押したまま話せば、翻訳された音声がそのまま会議の相手に届きます。システムの音声を直接読み取るため、会議にボットを入れる必要はなく、相手には気づかれません。Apple シリコンの Mac ではすべて端末内で認識するため、音声が外に出ることはありません。

**使える場所**：パソコンから音が出るものなら何でも使えます。Tencent Meeting、Feishu、DingTalk、WeCom、Zoom、Teams、Google Meet、Webex、Discord、Telegram の音声通話、X スペース、YouTube、Twitch、Bilibili Live、ポッドキャスト、ブラウザなどに対応しています。スマートフォンでは、OS の制限により通話や会議アプリの音声を録音できないため、スピーカーフォンにして「対面」モードをお使いください。

<p align="center">
  <img src="docs/demo.gif" width="800" alt="YouTube の Bloomberg の英語のライブ配信。右側に Cicada のリアルタイムの中国語のメモ、トピック、フィッシュボーン図、下部に二か国語の字幕が表示されています">
</p>

## 対応プラットフォーム

| プラットフォーム | 動作環境 | 備考 |
|---|---|---|
| Mac | macOS 14.4 以降、Apple シリコン / Intel | すべての機能に対応。Apple シリコンは端末内で認識（キーなしでも利用可）、Intel 版は Ling のキーが必要（Ming で認識） |
| Windows | Windows 10 2004 以降、x64 / ARM64 | Ling、OpenRouter、ZenMux などの AI サービスのキーが必要。[windows/](windows/README.md) を参照 |
| Linux | Ubuntu 22.04 / 24.04 デスクトップ | AI サービスのキーが必要。メモのウィンドウは画面共有に映ります。[linux/](linux/README.md) を参照 |
| Android | Android 10 以降 | AI サービスのキーが必要。動画や配信の字幕、対面での通訳。[android/](android/README.md) を参照 |

インストーラーは[公式サイトのダウンロードページ](https://cicada.indaloop.app/ja/download/)と [Releases](https://github.com/wquguru/cicada/releases) にあります。4 つのプラットフォームはバージョン番号と会議の記録形式を共有しており、以下では Mac 版を例に機能を説明します。

## 主な機能

### リアルタイムのメモと二か国語の書き起こし

聞き取りながら要約、トピックと要点、結論、ToDo、フィッシュボーン図、人名・用語集を整理し、結論や ToDo をクリックすると元の発言に直接戻れます。`⌘F` で検索すると、誤認識された同音語までヒットします。

AI サービスをつなぐと、聞き間違えた人名や用語をその場で修正します。同音の誤字はすぐに直し、珍しい名前は一度だけ確認して「はい」と答えると以降は自動で直します。よく使う語は設定の「単語リスト」に貼り付けておけます。会議のあとも「この行を修正…」で同じ誤りを会議全体で一括修正でき、いつでも元に戻せます。

### リアルタイムの字幕と言語の検出

相手が話し始めて数秒で言語を検出し、システムの言語に翻訳します。`⌃⌥S` で表示方法を切り替えられます。字幕バーは誰かが話しているときだけ表示され、マウスを重ねると自動で透けて視界を邪魔しません。Apple シリコンの macOS 26 では、15〜30 秒後に端末内で聞き直して補正し、誤字や抜けを直します。

### 対面・ハイブリッド会議

「マイクをオン」をクリックするとその場の会話を記録できます。ハイブリッド会議も同じボタンひとつで対応し、PC の音は「オンライン」、マイクは「会議室」として同じ記録にまとめます（macOS 14 と 15 ではマイクがオンの間は会議室のみを聞き取ります）。スピーカー出力時は自動で重複を省き、イヤホン使用時は双方が同時に話しても両方記録されます。Windows と Linux も同じ仕組みです。

Mac ではボタン横の小さな矢印で、システムの既定を変えずにマイク（iPhone や会議用マイクなど）を個別に切り替えられます。マイクで聞き取った内容は議事メモに残るだけで、会議には流れません。相手に声を届けるには、下の同時通訳を使います。

### 同時通訳

右の `⌥` を押したまま話すと、会議アプリ越しに翻訳された音声が相手に届きます。

Mac では「設定 › 同時通訳」で「キーを押さずに」もオンにできます。会議を聞いている間にそのまま話し始めると会議の音が自動で下がり、1 秒止まると訳文が相手に届きます。マイクをオンにしている間は一時停止し、周りに人がいるときは他の人の声をあなたと誤認しないようキー操作に戻すことをおすすめします。

オンにすると、ワンクリックでダウンロード・インストールできる仮想ドライバー BlackHole 2ch にシステムマイクを切り替えます。Ling API キーを設定すれば自然な音声を使ったり、8〜30 秒の録音から自分の声をクローンしたりできます。設定しなくても Mac 標準の音声が使えます。Windows と Linux の同時通訳、Android の対面モードでも、Ling API キーがあれば 10〜15 秒の録音から自分の声を使えます。

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="右 Option の話すキー、翻訳先の言語、Ming の音声のプレビュー、macOS の音声を表示した通訳の設定">
</p>

### 会議の記録

二か国語の記録、メモ、元の録音はすべて端末内に保存されます。任意の文をクリックするとその位置から再生でき、文字がハイライトされて自動でスクロールします。端末内の声紋モデルが話者を自動で区別し（Ling キーがあれば名前も補完）、間違っていればいつでも名前の変更や統合ができます。現在、記録内の「あなた」に含まれるのは話すキーを押して話した内容のみで、会議でそのまま話した分については[ロードマップ](#ロードマップ)をご覧ください。

会議後にメモを追加生成したり、Markdown、Word、SRT 字幕にエクスポートしたり、「ファイル › 録音・動画を読み込む…」から手元の音声や動画を文字起こししたりできます。Mac の「議事メモをコピー」（⇧⌘C）は、Feishu・Notion・Word に貼ると見出し・箇条書き・フィッシュボーン図がそのまま入り、チャットには Markdown で貼られます。「設定 › 一般 › フォルダに保存」をオンにすると、会議ごとに Markdown（先頭にエージェント向けの frontmatter 付き）が Obsidian の保管庫などのフォルダに自動保存され、名前の変更や再整理に合わせてファイルも更新されます。

「共有…」でメモのリンク（任意で二か国語の全文付き）を作成でき、有効期限とパスワードの設定に対応しています。アップロード前にはキーや未公開の社内情報などの機密内容を自動でブロックします。

<p align="center">
  <img src="docs/records.png" width="640" alt="識別された話者と、1 行ずつの英語と中国語の書き起こしを表示した会議の記録のウィンドウ">
</p>

## プライバシーと権限

**Apple シリコンの Mac**：録音と音声認識はすべて端末内で動作し、音声は外に出ません。送信されるのは文字起こし済みのテキスト（翻訳とメモ作成用）だけです。例外として、Ling キーを設定して通訳を使う際にあなたが話した発話、「先に Ling で聞く」を選んだ場合、または「設定 › AI サービス」で自前のサービスに変更した場合に限り、音声が対応するサービスに送られます。API キーを入力しなくても、リアルタイム字幕、翻訳、会議の記録、同時通訳はすべて無料です。リアルタイムのメモ、ワンステップの音声翻訳、声のクローンにはあなた自身の Ling（Ant Group の大規模モデルサービス）API キーが必要です。会議 1 時間あたり約 0.15〜1 人民元で、Ling から毎月付与される 10 元の枠で 10〜50 時間使えます。

**Intel 版 Mac、Windows、Linux、Android**：音声認識はクラウドで行われるため AI サービスのキーが必須で、音声は短く区切って Ling の Ming や選択した OpenRouter、ZenMux などのサービスに送られます。録音と会議の記録は端末内にのみ保存されます。

Mac 版は使う機能に必要な権限だけを求め、拒否してもほかの機能には影響しません。

| 権限 | 用途 | 許可しない場合 |
|---|---|---|
| システム音声の録音（画面とシステムオーディオの録音） | システム音声を聞いて字幕を出します（画面は録画しません） | 字幕とメモが使えません |
| マイク | 押して話すか「キーを押さずに」で通訳する、または「マイクをオン」で会議室を聞き取る | 話して翻訳する機能と会議室の聞き取りが使えません |
| 入力監視 | 右の `⌥` キーを検出するだけ（遮断やほかのキーの記録はしません） | `⌃`/`⌘` のショートカットに変えれば不要です |
| 管理者パスワード | 仮想マイク BlackHole 2ch のインストール（初回のみ） | 相手に通訳が聞こえません。ほかは通常どおり使えます |

- **通信の透明性**：通信を行うのは、翻訳（`translate.googleapis.com`）、設定した AI サービス（`api.ant-ling.com` など）、Apple 公証済みの BlackHole ドライバーのダウンロード（SHA-256 を検証）、1 日 1 回の GitHub での更新確認だけです。統計やトラッキング、独自のサーバーはありません。
- **データは端末内に保存**：記録と録音は `~/Library/Application Support/LiveSubs` に保存されます。キーと声のサンプルは現在のシステムアカウントのみが読み取れ、Time Machine やログには含まれません。
- **画面収録の防止**：Mac では画面共有、画面収録、スクリーンショットにメモのウィンドウは映りません。デモを録画するときは手動で「画面共有で相手にも見せる」をオンにできます。

## 使用モデル

以下は Apple シリコン Mac の構成です。自前のサービス（「その他（OpenAI 互換）」）を使う場合、「設定 › AI サービス」で「音声とテキストを自分のサービスにのみ送信」をオンにすると、Google を一切経由しません。

| 機能 | Ling のキーあり | キーなし / フォールバック |
|---|---|---|
| 音声認識・言語の検出 | Apple `SpeechAnalyzer` / `SpeechTranscriber`（端末内）。macOS 14.4〜15 は `SFSpeechRecognizer`（端末内、音声入力が必要） | 左と同じ |
| 文全体の翻訳 | Ling `Ling-3.1-flash`（「設定 › AI サービス」で `Ling-3.0-flash` に変更可） | Google 翻訳 → Apple `Translation`（端末内、macOS 26 のみ） |
| 話している途中の翻訳 | Google 翻訳 | 原文のみ表示し、話し終えたら文全体の翻訳に切り替え |
| リアルタイムのメモ・会議後の完全版 | Ling `Ling-3.1-flash` | 利用不可 |
| キーの有効性チェック | Ling `Ling-3.0-tiny`（1 トークン） | — |
| 通訳：聞き取りと翻訳 | Ming `Ming-3.0-audio-flash`（ワンステップで実行） | Apple 端末内認識 + 上記の翻訳チェーン |
| 通訳：音声合成と声のクローン | Ming `Ming-3.0-tts-0.5B` | Mac 標準の音声（`AVSpeechSynthesizer`）、クローンなし |
| 話者識別 | WeSpeaker ResNet34-LM（アプリに同梱、端末内の Core ML で実行） | 左と同じ |

## Ling API キーの設定

1. [Ling オープンプラットフォーム](https://chat.ant-ling.com/platform/api)で登録・ログインし、トークンを作成して `sk-` で始まるキーをコピーします。
2. Cicada の「設定 › AI サービス」（またはメモのウィンドウ上部のプロンプト）を開き、貼り付けて保存します。

**Ling に登録できない場合：**「設定 › AI サービス」の右上（または初回ガイドの「Ling が使えませんか？」）から、OpenRouter、ZenMux、OpenAI、または任意の OpenAI 互換サービス（Ollama、vLLM、SGLang、Qwen3-ASR、Whisper などのローカル・LAN 内サービスを含む）に切り替えられます。

切り替えたあともリアルタイムのメモと文全体の翻訳はそのまま使え、OpenRouter と ZenMux では Gemini の自然な音声で通訳もできます。ワンステップの音声翻訳と声のクローンは Ling のみ対応です。自前のサービスでは、メモと話者の識別だけ別の強いモデルや別サービス（独自のアドレスとキーを入力）を使えます。モデルは一覧から検索でき、見つからない名前も直接入力できます。Windows、Linux、Android でほかのサービスに切り替えると、相手の音声の聞き取りもそのサービスが行うため、字幕は Ling より 1〜2 秒遅れます。接続できないときは、キー、モデル、プロキシのどれが原因かを設定画面で直接案内します（プロキシの説明は[セットアップページ](https://cicada.indaloop.app/ja/start/#proxy)を参照）。

## 動作環境とインストール

インストーラーはすべて [Releases ページ](https://github.com/wquguru/cicada/releases/latest)または[公式サイト](https://cicada.indaloop.app/ja/)にあり、Releases の `checksums.txt` で SHA-256 を照合できます。質問があれば X で作者の [@wquguru](https://x.com/wquguru) までご連絡ください。

### Mac

macOS 14.4 以降（Apple シリコンおよび Intel 対応）が必要です。Apple シリコンの macOS 14.4〜15 では、先にシステム設定 › キーボードで「音声入力」をオンにし、聞き取りたい言語を追加してください。macOS 26 では新しい端末内モデルを直接使うため音声入力は不要です。Intel 版はクラウドの Ming で認識するため、Ling キーの設定が必要です。

`Cicada-<バージョン>-macOS-AppleSilicon.dmg` または `Cicada-<バージョン>-macOS-Intel.dmg` をダウンロードし、アプリケーションフォルダにドラッグします（`shasum -a 256 Cicada-*.dmg` で検証可能）。現在はまだ Apple の公証を受けていないため、初回起動時にブロックされた場合は、システム設定 › プライバシーとセキュリティで「このまま開く」をクリックしてください。初回ガイドに従って権限を許可し、サンプル会議を試聴すれば準備完了です。

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="オンボーディングのステップ 2。リアルタイムの二か国語の字幕付きで、2 人のサンプルの会議を再生しています">
</p>

### Windows

Windows 10 2004 以降（x64 または Snapdragon ARM64）が必要です。インストーラーをダウンロードしてダブルクリックするだけで、管理者権限なしでインストールできます。SmartScreen に止められた場合は「詳細情報 › 実行」をクリックしてください。同時通訳を使う際は、無料の仮想マイク VB-Cable の導入をガイドが案内します。

### Linux

Ubuntu 22.04 または 24.04 デスクトップ版（x86_64 または arm64）が必要です。`Cicada-<バージョン>-Linux.tar.gz` をダウンロードし、ターミナルで `tar xzf Cicada-<バージョン>-Linux.tar.gz && cicada-linux/install.sh` を実行します。同時通訳では「Cicada Microphone」を自動で作成するため、ドライバーの導入は不要です。Linux のウィンドウは画面共有から隠せないため、メモのウィンドウには「画面共有中はこのウィンドウが見えます」と表示されます。「設定 › 一般 › 会議の音声を保存」をオンにするには、AAC エンコーダーを提供するサードパーティのメディア形式（`ubuntu-restricted-extras` など）を先に導入してください。「設定 › 単語リスト › 会議中に聞き間違いを直す」をオンにすると、1 文ごとにテキストのリクエストが 1 回増えます。

### Android

Android 10 以降が必要です。`Cicada-<バージョン>-Android.apk` をダウンロードしてインストールします。Android 15 以降で初めてフローティング字幕をオンにするときは、先にアプリ情報で制限付き設定を許可してください。端末内の声紋による話者区別や、「聞き取り中」のリアルタイムな誤字修正にも同様に対応しています。WeChat 通話や会議アプリの音声はシステム上内部録音できないため、スピーカー出力にして「対面」に切り替えてください。

## ロードマップ

優先順です。欲しい機能があればぜひ Issue を立ててください。詳細は [docs/ROADMAP.md](docs/ROADMAP.md) をご覧ください。

- **自分の発言の記録**：会議中にマイクを継続して聞き取り、エコーを消去して、そのまま話した内容も記録とメモに残します。
- **正式な署名と公証**：Mac と Windows のインストーラーに正式な署名と公証を付け、起動時の警告をなくし、AI キーをシステムのキーチェーンに戻します。
- **声紋認識**：よく会議をする同僚の声を端末内で記憶し、次回から自動で判別します。
- **キーなしでのメモ作成**：対応する Mac で Apple の端末内モデルを使ってメモを整理します。
- **Android のアプリストア公開**：APK を手動でインストールする必要をなくします。
- **iPhone と iPad**：まずは会議室の聞き取り、対面での通訳、会議の記録から対応します。

## アンインストール

Cicada を終了し、アプリケーションフォルダからゴミ箱にドラッグします。会議の記録と録音は `~/Library/Application Support/LiveSubs` にあり、不要であれば手動で削除できます。設定を消去するには次を実行します：

```bash
defaults delete com.wquguru.cicada
```

## 開発

Mac 版は Xcode Command Line Tools（`xcode-select --install`）を入れるだけでよく、サードパーティの依存関係はありません。macOS 27 で `SwiftUIMacros` が見つからないエラーが出る場合は、完全版の Xcode をインストールして `sudo xcode-select -s /Applications/Xcode.app` を実行してください。ほかのプラットフォームのビルドについては [windows/README.md](windows/README.md)、[linux/README.md](linux/README.md)、[android/README.md](android/README.md) をご覧ください。

```bash
scripts/build.sh            # 编译开发版 → build/Cicada.app（名为 Cicada Dev，可与正式版同时运行）
open build/Cicada.app
scripts/package.sh          # 打包正式版 DMG、zip 和 SHA-256 校验值
```

コードの設計は [AGENTS.md](AGENTS.md) を参照してください。公式サイトのソースは `site/` にあり（`scripts/site.py` で生成）、更新履歴は [CHANGELOG.md](CHANGELOG.md) または[公式サイトの更新履歴](https://cicada.indaloop.app/changelog/)にあります。

## ライセンス

本プロジェクトは [Apache-2.0](LICENSE) ライセンスのもとで公開されています。仮想マイクドライバーの BlackHole 2ch は GPL ライセンスであり、インストーラーには同梱されず、インストールをクリックした際に公式の配布元からダウンロードされます。同梱の声紋モデルは [WeSpeaker](https://github.com/wenet-e2e/wespeaker) が VoxCeleb で学習した ResNet34-LM（CC BY 4.0 ライセンス）で、`scripts/convert-voiceprint.py` によって Core ML に変換されています。
