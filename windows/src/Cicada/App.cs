using System.IO.Pipes;
using System.Media;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using static Cicada.Strings;
using Forms = System.Windows.Forms;

namespace Cicada.App;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        Paths.Dev = Paths.Dev || args.Contains("--dev");
        // Before the single-instance check: the installer must run while the installed copy does.
        if (!Paths.Dev)
        {
            if (args.Contains("--uninstall")) return SetupWindow.Run(SetupWindow.Mode.Uninstall);
            switch (SetupPlan.Decide(false, Environment.ProcessPath ?? "", Install.Exe, Install.InstalledVersion(), Controller.Version))
            {
                case SetupPlan.Step.Install: return SetupWindow.Run(SetupWindow.Mode.Install);
                case SetupPlan.Step.Upgrade: return SetupWindow.Run(SetupWindow.Mode.Upgrade);
                case SetupPlan.Step.Open: Native.LetOthersTakeForeground(); Install.Launch("--opened"); return 0;
            }
        }
        // One Cicada per user: a second launch just opens the records of the running one.
        using var single = new Mutex(true, Paths.Dev ? "com.wquguru.cicada.dev" : Install.Mutex, out bool first);
        if (!first) { Native.LetOthersTakeForeground(); DebugServer.Send(args.Contains("--opened") ? "setup opened" : "show records"); return 0; }
        Controller.Arrived = args.FirstOrDefault(a => a is "--installed" or "--updated" or "--opened");
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        // WPF's own Windows 11 (Fluent) look for the stock controls: menus, combo boxes, text boxes,
        // check boxes and scroll bars. Light only for now; Cicada draws its own surfaces on top.
#pragma warning disable WPF0001
        app.ThemeMode = ThemeMode.Light;
#pragma warning restore WPF0001
        app.DispatcherUnhandledException += (_, e) => { Log.Debug($"ui: unhandled {e.Exception.GetType().Name}: {e.Exception.Message}"); e.Handled = true; };
        var controller = new Controller(app) { Background = args.Contains("--background") };
        app.Startup += (_, _) => controller.Launch();
        return app.Run();
    }
}

/// Wires the engines to the windows, as AppModel does on the Mac. Engine events arrive on worker
/// threads; everything here that touches UI runs on the dispatcher.
sealed class Controller
{
    readonly Application application;
    public readonly AppSettings Settings = AppSettings.Load();
    /// The key of the AI service in use (one file per service).
    public readonly AIKey Key;
    public readonly LingClient Ling;
    public readonly SessionStore Store = new();
    public readonly NotesEngine Notes;
    public readonly Translator Translator;
    public readonly ListenEngine Listen;
    public readonly SpeakEngine Speak;
    public readonly WindowsVoice WindowsVoice = new();
    public readonly UpdateChecker Updates;
    public readonly Vocabulary Vocabulary;
    public readonly LiveFixes Fixes;
    /// 存到文件夹 (设置 › 隐私与启动): settled meetings written as Markdown into a folder.
    public readonly FolderExporter FolderExport;
    /// 分享…: the share service, its device key and the links made (sealed files, never the record).
    public readonly ShareClient Sharing = new(new DpapiProtector(), "windows", Version);
    /// 我自己的声音: the recording Ming clones the user's voice from, sealed like the keys.
    public readonly VoiceReference OwnVoice = new(new DpapiProtector());
    /// Dev (`silentlisten`): the language `heard` lines are in.
    public string? SilentLang;
    /// Started with Windows (--background): stay in the tray. Opened by hand, the main window shows.
    public bool Background { get; init; }
    Onboarding? onboarding;
    /// 检查更新 in settings: null, or the result of the last manual check for a few seconds.
    public string? UpdateCheck { get; private set; }
    bool checksUpdates;
    /// The tray panel opened: check in the background once the last answer is an hour old.
    public void PanelOpened() { if (checksUpdates) _ = Updates.CheckIfDue(UpdateChecker.Stale); }
    public static string Version => typeof(Controller).Assembly.GetName().Version?.ToString(3) ?? "0";
    /// How the installer started this copy: --installed, --updated or --opened (it was already installed).
    public static string? Arrived;
    PushToTalk? talk;
    SpeakBar? speakBar;
    /// The press's microphone: through echo cancellation, or the plain one when that won't open.
    EchoMic? echoMic;
    bool echoLogged;
    DeviceRecorder? mic;
    /// Dev builds: a WAV that stands in for the microphone (the VM has none).
    string? fakeMic;
    /// Dev builds: the input the talk key reads instead of the microphone (`talkmic CABLE Output`).
    string? talkMic;
    readonly Forms.NotifyIcon tray = new();
    System.Drawing.Icon? idleIcon, liveIcon, updateIcon;
    /// Something only the user can fix (AICheck.Blocking), said beyond the panel: the tray's orange
    /// dot and tooltip, and once a meeting a notification while the notes panel is put away.
    public string? Problem { get; private set; }
    bool problemNotified;
    /// The installer's download progress (0…1) while an update is being fetched, and why the last one failed.
    public double? UpdateProgress { get; private set; }
    public string? UpdateFailure { get; private set; }
    /// Whether the browser took the download over after the in-app one failed (it may not open).
    public bool UpdatePageOpened { get; private set; }
    Action? balloonClicked;
    Hotkey? hotkey;
    TrayFlyout? flyout;
    Window? menuHost;
    NotesWindow? notesWindow;
    MainWindow? mainWindow;
    SettingsWindow? settingsWindow;
    Dispatcher Dispatch => application.Dispatcher;
    // 结束会议 (MeetingEnd.cs): `Ending` while a meeting is about to end by itself, `AutoEnded` after
    // one did (the tray says so, and the next call starts a new meeting).
    MeetingEndWatch? endWatch;
    public MeetingEndWatch.Pending? Ending { get; private set; }
    public bool AutoEnded { get; private set; }
    /// 结束这场会议？ is showing in the notes window or subtitle bar (AppModel.requestStop).
    public bool ConfirmingEnd { get; private set; }
    /// Dev: meeting apps pretending to be in a call, and (silence, countdown, grace) in seconds.
    public Dictionary<string, string>? FakeCalls;
    public (double Silence, double Countdown, double Grace)? EndTimes;
    bool readingCalls;

    public Controller(Application application)
    {
        this.application = application;
        var ui = Settings.UiLanguage == "system" ? null : Settings.UiLanguage;
        Strings.Load(Bundled.Strings, ui);
        Key = new AIKey(new DpapiProtector(), service: () => Settings.AiProvider);
        Ling = new LingClient(Key, config: Settings.AIConfig) { ProxyHint = () => ProxyProbe.Hint(WinProxy.SystemOn) };
        Ling.Changed += Changed;
        SpeakerLabels.Voices = Settings.SpeakerVoices;
        Notes = new NotesEngine(Ling, Store);
        Translator = new Translator(Ling) { GoogleOff = Settings.GoogleOff };
        Translator.Changed += Changed;
        Listen = new ListenEngine(Ling, Translator, Store, Notes, Settings);
        Speak = new SpeakEngine(Ling, Translator, Store, Settings, () => Listen.Spoken,
            () => Listen.Listening && Listen.SessionId is { } id && Store.Get(id) is { } s ? (id, s.StartedAt) : null, WindowsVoice);
        Speak.Changed += () => Dispatch.BeginInvoke(() => { speakBar ??= new SpeakBar(this); speakBar.Refresh(); });
        Speak.Reference = OwnVoice;
        Listen.Voiceprint = new WinVoiceprint();
        // No voices on the room side: its numbers would collide with the PC's.
        // The talk key's echo check: the meeting playing through a press is sent back otherwise.
        var loudness = new LoudnessLog();
        Listen.Loudness = loudness;
        Speak.Echo = loudness;
        // 改正听错的词: the word list beside the records, and the fixes both sides' lines take.
        Vocabulary = new Vocabulary(Vocabulary.DefaultPath);
        Fixes = new LiveFixes(Store, Vocabulary, Settings);
        Fixes.Changed += Changed;
        Vocabulary.Changed += Changed;
        Listen.Fixes = Fixes;
        RoomListen = new ListenEngine(Ling, Translator, Store, Notes, Settings, roomSide: true) { Fixes = Fixes };
        RoomListen.Changed += Changed;
        Listen.Changed += Changed;
        Notes.Changed += Changed;
        Store.Changed += _ => Changed();
        Store.Words += id => Dispatch.BeginInvoke(() => HeardWords(id));
        // 存到文件夹: written once a record is settled, rewritten when it changes. Its state is the
        // dispatcher's, as the Mac's is the main actor's.
        FolderExport = new FolderExporter(Store, Settings)
        {
            Post = a => Dispatch.BeginInvoke(a),
            LiveId = () => Listen.Listening ? Listen.SessionId : null,
            Settling = Notes.Settling,
            NotifyDenied = NotifyFolderDenied,
        };
        FolderExport.Changed += () => { Changed(); Dispatch.BeginInvoke(() => settingsWindow?.ExportChanged()); };
        Store.Saved += id => Dispatch.BeginInvoke(() => FolderExport.Saved(id));
        Notes.FinalDone += id => Dispatch.BeginInvoke(() => FolderExport.Settled(id));
        Updates = new UpdateChecker(Settings.UpdateLastChecked, at => Dispatch.BeginInvoke(() => { Settings.UpdateLastChecked = at; Settings.Save(); })) { Current = Version };
        Updates.Changed += UpdatesChanged;
    }

    public void Launch()
    {
        // Process loopback and capture exclusion both arrived in Windows 10 2004 (build 19041).
        if (Environment.OSVersion.Version.Build < 19041)
        {
            MessageBox.Show(L("知了需要 Windows 10 2004 或更新的版本。"), L("知了"));
            application.Shutdown();
            return;
        }
        Log.Debug($"app: launch {(Paths.Dev ? "dev" : "release")} {Environment.OSVersion.Version}");
        SetUpTray();
        // 保存会议录音: Windows' AAC encoder; a recording the last run didn't close is finished now.
        Store.Audio = new MediaFoundationAudio();
        Store.FinishLeftovers();
        hotkey = new Hotkey(() => Dispatch.BeginInvoke(() => _ = ToggleListening()));
        PushToTalk.Current = TalkKey.Named(Settings.TalkKey);
        talk = new PushToTalk(() => Settings.Speak);
        talk.Pressed += () => Dispatch.BeginInvoke(PressBegan);
        talk.Released += () => Dispatch.BeginInvoke(PressEnded);
        talk.Interrupted += () => Dispatch.BeginInvoke(PressInterrupted);
        Log.Debug($"audio: speakers {Endpoints.Default(Endpoints.Flow.Render)?.Name ?? "none"}, mic {Endpoints.Microphone()?.Name ?? "none"}, cable {(Endpoints.Cable() is null ? "absent" : "present")}");
        DebugServer.Start(this);
        WatchNetwork();
        // 存到文件夹: what is still waiting, now and whenever Cicada comes forward (a folder fixed
        // in Windows 安全中心 meanwhile).
        FolderExport.Retry();
        application.Activated += (_, _) => FolderExport.Retry();
        // A dev build isn't what a release replaces: it checks only when pointed at a test feed.
        UpdateChecker.CleanDownloads();
        if (!Paths.Dev || Environment.GetEnvironmentVariable("CICADA_UPDATE_FEED") is { Length: > 0 }) { checksUpdates = true; Updates.Start(); }
        var watch = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        watch.Tick += (_, _) => _ = WatchEnd();
        watch.Start();
        if (AutoStart.Enabled) AutoStart.Refresh();
        // The Mac shows its main window when opened by hand; a Windows user who double-clicks the
        // exe expects a window too, not just a tray icon. Not set up yet: the onboarding on top.
        if (!Background || !Settings.Onboarded) ShowRecords();
        if (!Settings.Onboarded)
        {
            var later = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            later.Tick += (_, _) => { later.Stop(); ShowOnboarding(); };
            later.Start();
        }
        else
        {
            if (Ling.HasKey) _ = Ling.Check();
            NotifyCableSpeaker();
            if (Arrived == "--updated") Toast(LF("知了已更新到 %@", Version), L("会议记录、设置和 Ling key 都在。"));
            else if (Arrived is not null) FromInstaller();
        }
    }

    /// VB-Cable holds the speaker (installed before Cicada gave it back, or outside Cicada): the user
    /// hears nothing and may blame Cicada. Said once (CableDefaults.ShouldNotify); a click gives a
    /// real speaker back.
    public void NotifyCableSpeaker()
    {
        var onCable = Endpoints.SpeakerIsCable();
        if (CableDefaults.ShouldNotify(onCable, Settings.CableSpeakerNotified))
        {
            Toast(L("听不到电脑声音了？"), L("Windows 把输出改成了 CABLE Input，点此恢复"), () =>
            {
                if (!Endpoints.RestoreSpeaker()) Toast(L("自动恢复失败"), L("请去 Windows 声音设置，把输出设备改回你的耳机或扬声器"), () => Open("ms-settings:sound"));
            });
            Log.Debug("cable: speaker notified");
        }
        if (Settings.CableSpeakerNotified == onCable) return;
        Settings.CableSpeakerNotified = onCable;
        Settings.Save();
    }

    /// The installer ran again with this version (or an older one) already here: bring the main window.
    public void FromInstaller()
    {
        ShowRecords();
        Toast(L("知了已经装好了"), L("下载的安装包可以删掉。"), ShowRecords);
    }

    void Changed() => Dispatch.BeginInvoke(() =>
    {
        WatchProxy();
        notesWindow?.Refresh();
        mainWindow?.Refresh();
        if (flyout?.IsVisible == true) flyout.Refresh();
        UpdateTray();
    });

    /// Only update news re-renders settings: Changed fires on every line heard.
    void UpdatesChanged() => Dispatch.BeginInvoke(() => { Changed(); settingsWindow?.UpdatesChanged(); NotifyUpdate(); });

    /// One Windows notification per version, for people who never open the tray panel; a click
    /// installs. Held while listening or speaking: StopListening tells.
    void NotifyUpdate()
    {
        if (Updates.Available is not { } u) return;
        if (!UpdateChecker.ShouldNotify(u.Version, Settings.UpdateNotified, Listen.Listening || Speak.State is not (SpeakEngine.Phase.Idle or SpeakEngine.Phase.Failed))) return;
        Settings.UpdateNotified = u.Version;
        Settings.Save();
        Toast(LF("知了有新版本 %@", u.Version), u.Setup is not null ? L("点按安装，完成后自动重新打开") : L("点按下载"), InstallUpdate);
        Log.Debug($"update: notified {u.Version}");
    }

    // MARK: Tray (the Mac's menu bar panel)

    void SetUpTray()
    {
        idleIcon = LoadIcon();
        liveIcon = WithDot(idleIcon, System.Drawing.Color.FromArgb(0xE8, 0x55, 0x2B));
        updateIcon = WithDot(idleIcon, System.Drawing.Color.FromArgb(0x6B, 0x70, 0x80));
        tray.Icon = idleIcon;
        tray.Text = L("知了");
        tray.Visible = true;
        // Left click: the panel, or while listening the notes window (both live in this corner, so
        // the panel would cover the notes). Right click: the menu, any time.
        tray.MouseUp += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) Dispatch.BeginInvoke(() => { if (Listen.Listening && Settings.View == "notes") ToggleNotes(); else ShowFlyout(); });
            else if (e.Button == Forms.MouseButtons.Right) Dispatch.BeginInvoke(ShowMenu);
        };
        // Cleared before the run: a click may show the next notification, with its own action.
        tray.BalloonTipClicked += (_, _) => Dispatch.BeginInvoke(() => { var c = balloonClicked; balloonClicked = null; c?.Invoke(); });
        UpdateTray();
    }

    static System.Drawing.Icon LoadIcon()
    {
        try
        {
            var info = Application.GetResourceStream(new Uri("pack://application:,,,/cicada.ico"));
            return new System.Drawing.Icon(info!.Stream, 32, 32);
        }
        catch { return System.Drawing.SystemIcons.Application; }
    }

    /// The logo with a dot on its corner: orange while listening or something needs fixing, grey
    /// for a new version (it can wait).
    static System.Drawing.Icon WithDot(System.Drawing.Icon icon, System.Drawing.Color colour)
    {
        using var bmp = new System.Drawing.Bitmap(32, 32);
        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.DrawIcon(icon, new System.Drawing.Rectangle(0, 0, 32, 32));
            using var ring = new System.Drawing.SolidBrush(System.Drawing.Color.White);
            using var dot = new System.Drawing.SolidBrush(colour);
            g.FillEllipse(ring, 16, 16, 16, 16);
            g.FillEllipse(dot, 19, 19, 10, 10);
        }
        return System.Drawing.Icon.FromHandle(bmp.GetHicon());
    }

    void UpdateTray()
    {
        CheckProblem();
        // Orange says 正在听 or something to fix (the Mac's problem badge), grey a new version;
        // the tooltip names the problem first.
        tray.Icon = Listen.Listening || Problem is not null ? liveIcon : Updates.Available is not null ? updateIcon : idleIcon;
        var text = Problem is { } p ? L("知了") + " · " + p
            : Listen.Listening ? L("知了") + " · " + L("正在听")
            : Updates.Available is { } u ? L("知了") + " · " + LF("有新版本 %@", u.Version) : L("知了");
        // NotifyIcon.Text throws past 127 characters (a long model id in the title).
        tray.Text = text.Length > 127 ? text[..126] + "…" : text;
    }

    /// On every change: the tray's problem, and its one notification a meeting. Only while
    /// listening, and only when the notes panel isn't up (its banner says so; the subtitle bar has
    /// none). Never a dialog: it would take the focus from the meeting app.
    void CheckProblem()
    {
        var p = Ling.HasKey && Ling.Health.Blocking ? AIProblem()?.Title : null;
        if (p != Problem)
        {
            Problem = p;
            Log.Debug($"tray: problem {(p is null ? "-" : Ling.Health.Failure?.Why.ToString())}");
        }
        if (p is null || problemNotified || !Listen.Listening || (NotesVisible && Settings.View == "notes")) return;
        problemNotified = true;
        Toast(p, LF("%@。点按去设置", AIProblem()?.Detail ?? ""), ShowAISettings);
        Log.Debug($"tray: notified problem {Ling.Health.Failure?.Why}");
    }

    public void ShowFlyout()
    {
        flyout ??= new TrayFlyout(this);
        flyout.Toggle();
    }

    /// The right-click menu needs a window of ours in front, or it won't close on an outside click.
    public void ShowMenu()
    {
        menuHost ??= new Window { WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent, ShowInTaskbar = false, Width = 1, Height = 1, Left = -10000, Top = -10000, Topmost = true };
        menuHost.Show();
        menuHost.Activate();
        var menu = new ContextMenu { Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint, FontFamily = Palette.Font, MinWidth = 260 };
        MenuItem Item(string label, Action act, string? keys = null, System.Windows.Media.Brush? ink = null)
        {
            var item = new MenuItem { Header = label, InputGestureText = keys ?? "" };
            if (ink is not null) item.Foreground = ink;
            item.Click += (_, _) => act();
            return item;
        }
        // The Mac's status menu: what the AI service needs from the user, where it stands, then what
        // to do, then the windows, then 退出.
        if (AIProblem() is { } ai)
        {
            var (problem, detail) = ai;
            var first = new MenuItem { Header = Ui.Stack(1, Ui.Text(problem, 13, Palette.AccentText, Palette.Strong, wrap: false), Ui.Text(detail + " · " + L("打开设置"), 12, Palette.Secondary, wrap: false)) };
            first.Click += (_, _) => ShowAISettings();
            menu.Items.Add(first);
            menu.Items.Add(new Separator());
        }
        if (Listen.Listening && Listen.SessionId is { } sid && Store.Get(sid) is { } live)
        {
            var head = new MenuItem { Header = Ui.Row(8, Ui.Dot(Palette.Live, 6), Ui.Text($"{L("正在听")} · {Languages.Clock((DateTimeOffset.Now - live.StartedAt).TotalSeconds)}", 13, Palette.Secondary, wrap: false)), IsEnabled = false };
            menu.Items.Add(head);
            menu.Items.Add(Item(L("结束"), RequestStop, Hotkey.Label.Replace('+', ' '), Palette.AccentText));
            if (Settings.View == "notes") menu.Items.Add(NotesVisible ? Item(L("隐藏纪要窗"), ToggleNotes) : Item(L("显示纪要"), ShowNotes));
        }
        else menu.Items.Add(Item(L("开始听"), () => _ = ToggleListening(), Hotkey.Label.Replace('+', ' ')));
        // 麦克风: one checkable item for what 听哪里's three were.
        var micItem = Item(L("麦克风"), () => SetMic(!MicOn));
        micItem.IsCheckable = true; micItem.IsChecked = MicOn;
        menu.Items.Add(micItem);
        menu.Items.Add(Settings.View == "subtitles" ? Item(L("换成纪要"), () => SetView("notes")) : Item(L("换成字幕条"), () => SetView("subtitles")));
        menu.Items.Add(new Separator());
        if (Updates.Available is { } update) menu.Items.Add(Item(LF("有新版本 %@", update.Version), InstallUpdate, ink: Palette.AccentText));
        menu.Items.Add(Item(L("会议记录"), () => ShowRecords()));
        menu.Items.Add(Item(L("设置"), ShowSettings));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("退出知了"), () => _ = Quit()));
        menu.Closed += (_, _) => menuHost.Hide();
        menu.IsOpen = true;
    }

    /// 存到文件夹 couldn't write after a meeting (not inside a folder controlled folder access
    /// protects: Windows says that itself). Once until a write works again.
    void NotifyFolderDenied()
    {
        if (FolderExport.Folder is not { } folder) return;
        Toast(L("纪要没存到文件夹"), LF("知了没有权限写入 %@。点按去设置", FolderExportUi.ShortPath(folder)), ShowFolderSettings);
    }

    /// 设置 › 隐私与启动, where 会后存一份 says what is wrong.
    public void ShowFolderSettings()
    {
        ShowSettings();
        SettingsPage("privacy");
    }

    /// A Windows notification from the tray icon; a click on it runs `clicked`.
    public void Toast(string title, string body, Action? clicked = null)
    {
        balloonClicked = clicked;
        tray.ShowBalloonTip(6000, title, body, Forms.ToolTipIcon.None);
        Log.Debug("toast: shown");
    }

    // MARK: Listening

    public async Task ToggleListening()
    {
        if (Listen.Listening) RequestStop();
        else await StartChecked(NewSource);
    }

    /// What 听哪里 says to listen to: the PC's audio, or the room through a microphone.
    public IAudioSource NewSource() => Settings.ListensToRoom ? RoomSource() : new SystemAudioTap();

    /// The room mic, muted while you hold the talk key. Dev: a WAV stands in (the VM has no mic).
    GatedSource RoomSource()
    {
        if (fakeRoom is { } wav) return new GatedSource(new FileAudioSource(wav)) { Name = "fake" };
        return new GatedSource(new MicSource(Endpoints.RoomMic)) { Muted = Speak.State == SpeakEngine.Phase.Recording };
    }

    /// The room mic listening hears right now, if any (muted while you speak).
    readonly List<GatedSource> roomSources = [];

    /// Dev builds: a WAV the room mic hears instead of a microphone.
    string? fakeRoom;
    public void SetFakeRoom(string? path) { fakeRoom = path; Log.Debug($"room: fake mic {(path is null ? "off" : "on")}"); }
    /// Dev builds: what the echo measurement says, instead of measuring (the VM has no speakers).
    bool? fakeEcho;
    public void SetFakeEcho(bool? on) { fakeEcho = on; if (Listen.Echo is { } e) e.Gate.Forced = on; Log.Debug($"room: echo sim {on?.ToString() ?? "real"}"); }

    /// 打开麦克风 / 关闭麦克风 (AppModel.setMic on the Mac): the PC's audio is always heard; the mic
    /// adds the people in the room to the same meeting. Not kept for the next launch: listening
    /// never starts with the microphone open. Turning it on while nothing is heard starts listening.
    public bool MicOn => Settings.HearsBoth;

    public void SetMic(bool on)
    {
        var value = on ? ListenSource.Both : ListenSource.System;
        if (value == Settings.Listens)
        {
            if (on && !Listen.Listening) _ = StartChecked(NewSource);
            return;
        }
        Settings.ListenSourceValue = value;
        Log.Debug($"mic {(on ? "on" : "off")}");
        if (Listen.Listening)
        {
            if (on) StartRoomSide(); else _ = StopRoomSide();
        }
        else if (on) _ = StartChecked(NewSource);
        Changed();
    }

    // MARK: 电脑和会议室

    /// The room side of 电脑和会议室: its own engine on the room mic, adding to the same meeting.
    public readonly ListenEngine RoomListen;
    /// 电脑和会议室 but Windows won't give Cicada the microphone: the PC's side keeps recording.
    public bool HybridMicDenied { get; private set; }


    void StartRoomSide()
    {
        if (RoomListen.Listening || !Listen.Listening || Listen.SessionId is not { } id || Store.Get(id) is not { } session) return;
        var echo = new EchoFilter(new EchoGate());
        Listen.Echo = echo;
        RoomListen.Echo = echo;
        var mic = RoomSource();
        mic.Silenced = () => echo.Gate.Closed;
        mic.Heard = echo.Gate.RoomLevel;
        echo.Gate.Forced = fakeEcho;
        roomSources.Add(mic);
        mic.Ended += reason =>
        {
            if (reason is null) return;
            Log.Debug($"hybrid: room mic ended {reason}");
            Dispatch.BeginInvoke(() =>
            {
                if (reason == "denied")
                {
                    HybridMicDenied = true;
                    Toast(L("听会议室要先允许麦克风"), L("电脑声音照常在记"), () => Open("ms-settings:privacy-microphone"));
                }
                else if (reason == "none") Toast(L("没有可用的麦克风"), L("电脑声音照常在记"));
                _ = StopRoomSide();
                Changed();
            });
        };
        HybridMicDenied = false;
        RoomListen.Join(mic, id, session.StartedAt, Listen.Mix);
        Log.Debug("hybrid: room side started");
    }

    async Task StopRoomSide()
    {
        Listen.Echo = null;
        if (!RoomListen.Listening) return;
        await RoomListen.Stop();
        Log.Debug("hybrid: room side stopped");
    }

    /// A source about to be listened to: a room mic is remembered (the talk key mutes it), and one
    /// that can't go on says why.
    IAudioSource Watch(IAudioSource source)
    {
        if (source is GatedSource room) roomSources.Add(room);
        source.Ended += reason =>
        {
            if (reason is null) return;
            Log.Debug($"listen: source ended {reason}");
            Dispatch.BeginInvoke(() =>
            {
                if (source is GatedSource && reason == "denied")
                    Toast(L("听会议室要先允许麦克风"), L("Windows 不让知了用麦克风：设置 › 隐私和安全性 › 麦克风"), () => Open("ms-settings:privacy-microphone"));
                else if (source is GatedSource && reason == "none")
                    Toast(L("没有可用的麦克风"), L("插上麦克风后再开始听。"));
                _ = StopListening();
            });
        };
        return source;
    }

    /// The user's 开始听: blocked only by a failure the last result knows of. A hear model that
    /// can't hear asks to switch to the recommended one; an unreachable service is looked at once
    /// more, but only waited for briefly (a check that can't connect takes 10–20 s): still unknown
    /// then, the dialog says what the last check found and its 重新检查并开始 waits in place, with
    /// 正在检查… on the button. Unknown or busy starts as usual. A dialog comes after a yield, so
    /// the debug pipe that asked for the start replies first; a start that needs none has happened by then.
    public async Task StartChecked(Func<IAudioSource> source)
    {
        if (Listen.Listening || starting) return;
        if (!Ling.HasKey) { StartListening(source()); return; }
        starting = true;
        try
        {
            var shown = Ling.Health;
            Task? recheck = null;
            if (shown.Failure?.Why == AICheck.Reason.Unreachable)
            {
                recheck = Ling.Check();
                if (await Task.WhenAny(recheck, Task.Delay(QuickLook)) == recheck) shown = Ling.Health;
                else Log.Debug($"listen: start, the service still unreachable after {QuickLook.TotalSeconds:0} s, asking");
            }
            var f = shown.Failure;
            if (f?.Why == AICheck.Reason.Deaf)
            {
                var service = Ling.ServiceName;
                var recommended = Ling.Recommended(AICheck.StepId.Hear);
                await Task.Yield();
                var choice = Dialogs.Choose(VisibleWindow(), LF("%@ 现在听不了声音", service), LF("%@ 只收文字。换成推荐的模型就能开始听。", Ling.HearName),
                    recommended is null ? null : L("换成推荐的并开始"), L("打开设置"));
                if (choice == 1 && recommended is not null)
                {
                    UseRecommended(AICheck.StepId.Hear);
                    StartListening(source());
                }
                else if (choice == 2) ShowAISettings();
                return;
            }
            if (f?.Why == AICheck.Reason.Unreachable)
            {
                string Body(AICheck h) => (h.Message(Ling.ServiceLabel, Ling.ServiceHost, Ling.Config.TextModel, Ling.HearName) ?? "")
                    + (h.ProxyLine(Ling.ServiceLabel, Ling.ServiceHost) is { } proxy ? "\n" + proxy : "");
                await Task.Yield();
                // 重新检查并开始: the check already under way (or one that finished reachable while the
                // dialog was up), else a new one; reachable closes the dialog.
                async Task<string?> Retry()
                {
                    var under = recheck;
                    recheck = null;
                    if (under is null || under.IsCompleted && Ling.Health.Failure?.Why == AICheck.Reason.Unreachable) await Ling.Check();
                    else await under;
                    var h = Ling.Health;
                    return h.Failure?.Why == AICheck.Reason.Unreachable ? Body(h) : null;
                }
                var choice = Dialogs.Choose(VisibleWindow(), LF("连不上 %@", Ling.ServiceName), Body(shown), L("重新检查并开始"), L("打开设置"), Retry);
                if (choice == 2) ShowAISettings();
                else if (choice == 1)
                {
                    // Reached now; the check may still have found something else (a deaf model): ask again.
                    starting = false;
                    await StartChecked(source);
                }
                return;
            }
            StartListening(source());
        }
        finally { starting = false; }
    }

    bool starting;
    /// How long 开始听 waits for a fresh look at an unreachable service before asking.
    static readonly TimeSpan QuickLook = TimeSpan.FromSeconds(2);

    /// A window of ours to put a dialog over; null (the screen's centre) from the tray.
    Window? VisibleWindow() => new Window?[] { settingsWindow, mainWindow, onboarding }.FirstOrDefault(w => w?.IsVisible == true && w.WindowState != WindowState.Minimized);

    /// The user's 结束 (buttons, menu, hotkey): a meeting with lines ends only after asking, in the
    /// notes window or subtitle bar, which never take focus, so no modal dialog fights them for it.
    /// An empty one just stops.
    public void RequestStop()
    {
        if (!Listen.Listening) return;
        if (Listen.SessionId is not { } id || Store.Get(id) is not { Lines.Count: > 0 }) { _ = StopListening(); return; }
        ConfirmingEnd = true;
        ShowNotes();
        Changed();
    }

    public void CancelStop()
    {
        ConfirmingEnd = false;
        Changed();
    }

    public void StartListening(IAudioSource source)
    {
        if (Listen.Listening) return;
        if (!Ling.HasKey) { ShowOnboarding(0); return; }
        Watch(source);
        AutoEnded = false;
        Ending = null;
        problemNotified = false;
        endWatch = new MeetingEndWatch(EndConfig(), DateTimeOffset.Now);
        Listen.Start(source, room: source is GatedSource);
        if (Settings.HearsBoth && source is SystemAudioTap) StartRoomSide();
        ShowNotes();
    }

    /// The meeting being ended: Quit waits for it, or a meeting ended a moment before quitting
    /// (its last sentences still out at the AI service) was never closed and came back empty.
    Task stopping = Task.CompletedTask;

    public Task StopListening(DateTimeOffset? endedAt = null, bool auto = false)
    {
        var t = Stopping(endedAt, auto);
        if (!t.IsCompleted) stopping = t; // a second, empty stop mustn't hide the one still running
        return t;
    }

    async Task Stopping(DateTimeOffset? endedAt, bool auto)
    {
        var id = Listen.SessionId;
        endWatch = null;
        Ending = null;
        ConfirmingEnd = false;
        AutoEnded = auto;
        HybridMicDenied = false;
        await StopRoomSide();
        roomSources.Clear();
        await Listen.Stop(endedAt);
        if (id is not null) FolderExport.Ended(id);
        Changed();
        NotifyUpdate(); // held while the meeting was on
        if (id is not null) _ = TellWhenNotesReady(id);
    }

    // MARK: 结束会议

    MeetingEndWatch.Config EndConfig()
    {
        var c = new MeetingEndWatch.Config(Settings.EndWithApp, MeetingEndWatch.ParseSilence(Settings.SilenceEnd), Settings.SilenceMinutes * 60);
        return EndTimes is { } t ? c with { SilenceAfter = t.Silence, Countdown = t.Countdown, AppGrace = t.Grace } : c;
    }

    /// Words recognised in the live meeting (theirs or mine): the silence countdown stops now.
    void HeardWords(string id)
    {
        if (endWatch is null || !Listen.Listening || id != Listen.SessionId) return;
        endWatch.Heard(DateTimeOffset.Now);
        SetEnding(endWatch.Waiting);
    }

    /// Every 2 s: while listening, whether the meeting is over; after one ended by itself, whether a
    /// meeting app started the next call. The registry is read off the UI thread.
    async Task WatchEnd()
    {
        bool live = Listen.Listening && endWatch is not null, after = !Listen.Listening && AutoEnded;
        if (readingCalls || !(live || after) || (!live && !Settings.EndWithApp)) return;
        readingCalls = true;
        Dictionary<string, string> found = Settings.EndWithApp ? FakeCalls ?? await Task.Run(MicReaders.Calls) : new();
        readingCalls = false;
        var calls = Settings.EndWithApp ? found : new();
        var now = DateTimeOffset.Now;
        if (Listen.Listening && endWatch is { } w)
        {
            w.Settings = EndConfig();
            var said = Listen.SessionId is { } id && Store.Get(id) is { Lines.Count: > 0 };
            var reason = w.Tick(now, calls, said);
            SetEnding(w.Waiting);
            if (reason is not null) await AutoEnd(reason, w);
        }
        else if (!Listen.Listening && AutoEnded && Settings.EndWithApp && calls.Count > 0)
        {
            Log.Debug("meeting end: a meeting app started a call, starting a new meeting");
            StartListening(NewSource());
        }
    }

    void SetEnding(MeetingEndWatch.Pending? p)
    {
        if (p == Ending) return;
        if (p is not null) Log.Debug($"meeting end: pending {p.Reason}, ends in {(int)(p.Deadline - DateTimeOffset.Now).TotalSeconds} s");
        else if (Ending is not null) Log.Debug("meeting end: pending cleared");
        Ending = p;
        Changed();
    }

    /// Ends where the meeting really ended: a little after the last words, or at the hang-up if that
    /// was later.
    async Task AutoEnd(MeetingEndWatch.Reason reason, MeetingEndWatch w)
    {
        if (reason.Kind == "nobody")
        {
            // Nothing to keep or summarise: back to 开始听, not 会议已自动结束.
            Log.Debug($"meeting end: nobody spoke for {(int)w.Settings.SilenceAfter} s, stopped");
            await StopListening();
            return;
        }
        var now = DateTimeOffset.Now;
        var at = w.LastSpeech.AddSeconds(5);
        if (reason.Kind == "app" && now.AddSeconds(-w.Settings.AppGrace) > at) at = now.AddSeconds(-w.Settings.AppGrace);
        if (at > now) at = now;
        Log.Debug($"meeting end: ended by itself ({reason}), end time {(int)(now - at).TotalSeconds} s ago");
        await StopListening(at, auto: true);
    }

    /// 继续记录 on the ending prompt.
    public void KeepRecording()
    {
        endWatch?.KeepGoing(DateTimeOffset.Now);
        SetEnding(null);
        Log.Debug("meeting end: kept going");
    }

    public string EndingTitle(MeetingEndWatch.Pending p) => p.Reason.Kind == "app"
        ? LF("%@ 已挂断", p.Reason.Name)
        : LF("已经 %lld 分钟没人说话", Math.Max(1, (int)Math.Round(EndConfig().SilenceAfter / 60)));

    public static int EndingLeft(MeetingEndWatch.Pending p) => Math.Max(0, (int)Math.Round((p.Deadline - DateTimeOffset.Now).TotalSeconds));

    /// The final notes take a few seconds after 结束; say so once they're written.
    async Task TellWhenNotesReady(string id)
    {
        for (int i = 0; i < 120; i++)
        {
            await Task.Delay(1000);
            var s = Store.Get(id);
            if (s is null || Listen.SessionId == id && Listen.Listening) return;
            if (s.Notes is { Final: true, IsEmpty: false })
            {
                Dispatch.Invoke(() => Toast(L("纪要整理好了"), LF("%@ · 点这里打开", SessionStore.DisplayTitle(s)), () => ShowRecords(id)));
                return;
            }
        }
    }

    /// The panel was closed while listening: the first time, say that listening goes on.
    public void CollapsedWhileListening()
    {
        if (!Listen.Listening || Settings.ToldStillListening) return;
        Settings.ToldStillListening = true; Settings.Save();
        Toast(L("知了还在听"), L("点任务栏右下角的知了图标再打开纪要。"), ShowNotes);
    }

    /// The onboarding sample: heard straight from the file (Cicada's own sound is left out of
    /// the system capture) while it plays aloud for the user.
    public async Task PlaySample()
    {
        if (Bundled.Sample() is not { } wav || Listen.Listening) return;
        var source = new FileAudioSource(wav);
        var done = new TaskCompletionSource();
        source.Ended += _ => done.TrySetResult();
        StartListening(source);
        try { new SoundPlayer(wav).Play(); } catch (Exception e) { Log.Debug($"sample: play failed {e.GetType().Name}"); }
        await done.Task;
        await Task.Delay(3000); // the last segment's reply
        await StopListening();
    }

    // MARK: Speaking (同声传译)

    public bool NotesVisible => notesWindow?.IsVisible == true;
    /// Where the notes panel is on screen, when it shows as a panel: the talk bar keeps out of it.
    public Rect? NotesBounds => NotesVisible && Settings.View == "notes"
        ? new Rect(notesWindow!.Left, notesWindow.Top, notesWindow.ActualWidth, notesWindow.ActualHeight) : null;

    public void SetFakeMic(string? path) { fakeMic = path; Log.Debug($"speak: fake mic {(path is null ? "off" : "on")}"); }
    public void SetTalkMic(string? name) { talkMic = name; Log.Debug($"speak: talk mic {name ?? "default"}"); }

    /// Dev: what the meeting hears. Records "CABLE Output" for `seconds` into `path` ("8 C:\x.wav").
    public async Task RecordCable(string arg)
    {
        var parts = arg.Split(' ', 2);
        if (parts.Length < 2 || !double.TryParse(parts[0], out var seconds) || Endpoints.CableOutput() is not { } d) { Log.Debug("record: no cable output"); return; }
        var r = new DeviceRecorder(d.Id);
        r.Start();
        await Task.Delay(TimeSpan.FromSeconds(seconds));
        var pcm = r.Stop();
        File.WriteAllBytes(parts[1], Wav.Bytes(pcm));
        double sum = 0; foreach (var x in pcm) sum += (double)x * x;
        Log.Debug($"record: {pcm.Length / 16000.0:F1} s from {d.Name}, rms {Math.Sqrt(sum / Math.Max(1, pcm.Length)) / 32768:F4}");
    }

    void PressBegan()
    {
        if (!Settings.Speak || Speak.State is SpeakEngine.Phase.Recording or SpeakEngine.Phase.Translating) return;
        if (!Ling.HasKey) { Speak.Report(Ling.Config.IsLing ? L("需要 Ling key 才能说") : LF("需要 %@ 的 key 才能说", Ling.Config.Name)); return; }
        if (Endpoints.Cable() is null) { Speak.Report(L("还没装虚拟麦克风，去设置里装一下")); return; }
        // With a fake mic the WAV is what is sent; a dev talk mic still opens, to run the real capture.
        if (fakeMic is null || talkMic is not null)
        {
            if (TalkMic() is not { } m) { if (fakeMic is null) { Speak.Report(L("没找到麦克风")); return; } }
            else if (OpenTalkMic(m) is { } err)
            {
                if (fakeMic is null) { Speak.Report(err == "denied" ? L("Windows 不让知了用麦克风：设置 › 隐私和安全性 › 麦克风") : L("麦克风打不开")); return; }
            }
        }
        Speak.BeginRecording();
        // What you say isn't someone in the room.
        foreach (var r in roomSources) r.Muted = true;
    }

    /// The press's microphone: through Windows' echo cancellation when it opens, so what I say while
    /// the other side talks on the speakers is sent (EchoMic); the plain mic when it doesn't. Null,
    /// or why the mic can't be had ("denied").
    string? OpenTalkMic(Endpoints.Device m)
    {
        var speakers = Endpoints.Default(Endpoints.Flow.Render);
        // The cable is where my own voice goes, never the meeting's speakers.
        var reference = speakers is not null && speakers.Id != Endpoints.Cable()?.Id ? speakers.Id : null;
        var aec = new EchoMic(m.Id, reference);
        aec.Start();
        if (aec.Error is null)
        {
            echoMic = aec;
            echoLogged = aec.EchoCancelled;
            Log.Debug($"speak: mic {(aec.EchoCancelled ? "with echo cancellation" : "plain, no echo cancellation")} ({aec.Detail})");
            return null;
        }
        if (aec.Error == "denied") return "denied";
        mic = new DeviceRecorder(m.Id);
        mic.Start();
        Log.Debug($"speak: mic plain, the communications stream failed {aec.Error}");
        if (mic.Error is { } err) { mic = null; return err; }
        return null;
    }

    /// The talk key's microphone. Dev: `talkmic <name>` picks any input (the VM's only one is CABLE Output).
    Endpoints.Device? TalkMic() => talkMic is { } name
        ? Endpoints.All(Endpoints.Flow.Capture).FirstOrDefault(d => d.Description == name || d.Name.StartsWith(name))
        : Endpoints.Microphone();

    /// Ends the press's recording: what it heard, and whether through echo cancellation.
    (short[] pcm, bool echoCancelled) StopTalkMic()
    {
        // As logged when the press began (a stream still opening then counts as plain), and still so.
        var cancelled = echoLogged && echoMic?.EchoCancelled == true;
        echoLogged = false;
        var pcm = echoMic?.Stop() ?? mic?.Stop() ?? [];
        echoMic = null;
        mic = null;
        return (pcm, cancelled);
    }

    /// Another key went down while a modifier talk key was held (Ctrl C): a shortcut, not talking.
    void PressInterrupted()
    {
        foreach (var r in roomSources) r.Muted = false;
        if (Speak.State != SpeakEngine.Phase.Recording) return;
        StopTalkMic();
        Speak.Cancel();
        Log.Debug("talk: interrupted by another key");
    }

    /// 更改 the talk key: the next key pressed anywhere comes to `chosen` (on the UI thread).
    public void ChooseTalkKey(Action<int> chosen)
    {
        if (talk is null) return;
        talk.Capture = vk => Dispatch.BeginInvoke(() => chosen(vk));
    }

    public void StopChoosingTalkKey() { if (talk is not null) talk.Capture = null; }

    public void SetTalkKey(TalkKey.Key key)
    {
        PushToTalk.Current = key;
        Settings.TalkKey = key.Name; Settings.Save();
        Log.Debug($"talk: key {key.Name}");
        Changed();
    }

    void PressEnded()
    {
        foreach (var r in roomSources) r.Muted = false;
        if (Speak.State != SpeakEngine.Phase.Recording) return;
        var (recorded, echoCancelled) = StopTalkMic();
        var pcm = fakeMic is { } f ? Wav.Read(f) : recorded;
        // A tap, not a sentence.
        if (pcm.Length < Segmenter.Rate * 3 / 10) { Speak.Cancel(); return; }
        // Held but nothing said (a muted mic): Ming would make something up from the hiss.
        if (pcm.Max(x => Math.Abs((int)x)) < 300) { Speak.Report(L("没听到你说话，没有发出去")); return; }
        _ = Speak.Speak(Wav.Bytes(pcm), new DeviceSpeaker(Endpoints.Cable), echoCancelled);
    }

    public enum PreviewResult { Played, Stopped, NoSpeaker, NoVoice, FellBack, Failed }
    DeviceSpeaker? previewing;
    public bool Previewing => previewing is not null;
    public void StopPreview() => previewing?.Stop();

    /// 试听: a voice speaks its sample line on the speakers (not into the meeting). It used to fail
    /// without a word (#22); now the result says why, for the line under the voice.
    public async Task<PreviewResult> Preview(string language)
    {
        previewing?.Stop();
        var speaker = new DeviceSpeaker(() => Endpoints.Default(Endpoints.Flow.Render));
        PreviewResult result;
        if (!speaker.Ready) result = PreviewResult.NoSpeaker;
        else
        {
            previewing = speaker;
            Changed();
            try
            {
                var chosen = Speak.ChosenVoice(language);
                var voiced = await Speak.Voice(VoiceCatalog.Sample(language), language, speaker);
                result = speaker.Stopped ? PreviewResult.Stopped
                    : !voiced ? (WindowsVoice.Has(language) ? PreviewResult.Failed : PreviewResult.NoVoice)
                    : speaker.Failed ? PreviewResult.NoSpeaker
                    : chosen != VoiceCatalog.SystemId && Speak.LastVoice == "system" ? PreviewResult.FellBack
                    : PreviewResult.Played;
            }
            catch (Exception e) { Log.Debug($"preview: failed {e.GetType().Name}"); result = PreviewResult.Failed; }
            finally { if (previewing == speaker) previewing = null; }
        }
        Log.Debug($"preview: {language} {result}");
        Changed();
        return result;
    }

    // MARK: 我自己的声音

    /// The microphone a recording for the user's own voice comes from: the talk key's.
    public Endpoints.Device? OwnVoiceMic() => TalkMic();

    /// What a recording says, as the hear model (Ming on Ling) hears it; null when it heard nothing.
    public async Task<string?> Transcribe(byte[] wav) =>
        (await Translator.Hear(wav, Speak.Target, Speak.MyLanguage, Priority.Speak))?.Original;

    /// Plays a recording (16 kHz mono WAV) on the speakers; 停止 is StopPreview.
    public async Task PlayRecording(byte[] wav)
    {
        previewing?.Stop();
        var speaker = new DeviceSpeaker(() => Endpoints.Default(Endpoints.Flow.Render));
        if (!speaker.Ready) return;
        previewing = speaker;
        try
        {
            speaker.Begin(Segmenter.Rate);
            speaker.Write(wav.Length > 44 ? wav[44..] : wav);
            await speaker.End();
        }
        finally { if (previewing == speaker) previewing = null; }
    }

    /// The review's 用你的声音说…: the language's sample line in a voice cloned from a recording not
    /// yet kept, on the speakers. True once something played.
    public async Task<bool> PreviewOwnVoice(byte[] wav, string text, string language)
    {
        previewing?.Stop();
        var speaker = new DeviceSpeaker(() => Endpoints.Default(Endpoints.Flow.Render));
        if (!speaker.Ready || !Ling.Clones) return false;
        previewing = speaker;
        Changed();
        int chunks = 0;
        try
        {
            var reference = ("data:audio/wav;base64," + Convert.ToBase64String(wav), text);
            await foreach (var pcm in Ling.Speech(VoiceCatalog.Sample(language), null, VoiceCatalog.MingLanguage(language), reference))
            {
                if (speaker.Stopped) break;
                if (chunks++ == 0) speaker.Begin(24000);
                speaker.Write(pcm);
            }
            if (chunks > 0) await speaker.End();
        }
        catch (LingException e) { Log.Debug($"preview: cloned voice failed {e.Message}"); }
        finally { if (previewing == speaker) previewing = null; Changed(); }
        Log.Debug($"preview: cloned voice {language} {(chunks > 0 ? "played" : "silent")}");
        return chunks > 0;
    }

    /// Keeps a recording as the user's own voice and uses it for `language` (VoiceCloneSheet.save).
    public void SaveOwnVoice(byte[] wav, string text, string language)
    {
        OwnVoice.Save(wav, text);
        Settings.SpeakVoices[VoiceCatalog.Key(language)] = VoiceCatalog.CloneId;
        Settings.Save();
        Log.Debug($"voice clone saved {(wav.Length - 44) / 32000.0:F0} s");
        Changed();
    }

    /// 删除: the recording goes, and every language that used it gets its default back.
    public void RemoveOwnVoice()
    {
        OwnVoice.Remove();
        foreach (var k in Settings.SpeakVoices.Where(p => p.Value == VoiceCatalog.CloneId).Select(p => p.Key).ToList()) Settings.SpeakVoices.Remove(k);
        Settings.Save();
        Log.Debug("voice clone removed");
        Changed();
    }

    // MARK: Windows

    /// The tray icon while listening: the notes window comes and goes.
    public void HideNotes()
    {
        if (NotesVisible) ToggleNotes();
    }

    public void ToggleNotes()
    {
        if (NotesVisible) notesWindow!.Hide(); else ShowNotes();
        Changed();
    }

    /// The first time a window's × is clicked: closing it doesn't quit, Cicada stays in the tray.
    public void WindowClosed()
    {
        if (Settings.TrayHintShown) return;
        Settings.TrayHintShown = true; Settings.Save();
        Toast(L("知了还在任务栏右下角"), LF("关掉窗口不会退出，按 %@ 随时开始听。", Hotkey.Label.Replace('+', ' ')));
    }

    public void ShowNotes()
    {
        notesWindow ??= new NotesWindow(this);
        notesWindow.Show();
        notesWindow.Refresh();
    }

    // MARK: Setup (the main window's 还差几步 and the title bar's pill)

    /// The setup steps, as the onboarding numbers them: what is done, by what really happened
    /// rather than by "the onboarding was finished".
    public (bool Key, bool Audio, bool Sample) SetupDone => (Ling.HasKey && !KeyStepFailed, Settings.HeardSystemAudio || Settings.Onboarded, Settings.SampleSeen || Settings.Onboarded);

    /// The AI service's last result is a failure only the user can fix (not "still checking", not
    /// busy, not a server error, not a balance running low): 还差几步 shows it as not done yet.
    public bool KeyStepFailed => Ling.Health is { NeedsUser: true, Failure: not null };

    /// Steps left before listening works; 0 once set up. 同声传译 is optional and never counted.
    public int SetupLeft
    {
        get
        {
            var (k, a, sm) = SetupDone;
            if (Settings.Onboarded && k) return 0;
            // Set up once, and the service broke later: that one step is left.
            if (Settings.Onboarded && Ling.HasKey) return 1;
            return (k ? 0 : 1) + (a ? 0 : 1) + (sm ? 0 : 1);
        }
    }

    /// The onboarding, at `step` or at the first step not done; one window at a time.
    public void ShowOnboarding(int? step = null)
    {
        var (k, a, _) = SetupDone;
        var at = step ?? (!k ? 0 : !a ? 1 : 2);
        if (onboarding is null)
        {
            onboarding = new Onboarding(this, installed: Arrived == "--installed");
            onboarding.Closed += (_, _) => { onboarding = null; Changed(); };
            if (mainWindow?.IsVisible == true) { onboarding.Owner = mainWindow; onboarding.WindowStartupLocation = WindowStartupLocation.CenterOwner; }
        }
        onboarding.At(at);
        onboarding.Show();
        onboarding.Activate();
    }

    public void SetupChanged() => Changed();

    public void ShowRecords() => ShowRecords(null);

    /// Debug pipe: a record opened at a tab, and the player in it.
    public void OpenRecord(string id, string tab) { ShowRecords(id); mainWindow?.Select(id, tab); }
    public void Play(string arg) => mainWindow?.DebugPlay(arg);

    /// 分享…: the dialog over the records window (or the screen's centre without it).
    public ShareDialog ShareSheet(Session s)
    {
        ShareDialog.Current?.Close();
        var d = new ShareDialog(this, s, mainWindow is { IsVisible: true } ? mainWindow : null);
        d.Show();
        return d;
    }

    public void ShowRecords(string? id)
    {
        if (mainWindow is null) { mainWindow = new MainWindow(this, id); mainWindow.Closed += (_, _) => { mainWindow = null; WindowClosed(); }; }
        else if (id is not null) mainWindow.Select(id);
        if (mainWindow.WindowState == WindowState.Minimized) mainWindow.WindowState = WindowState.Normal;
        mainWindow.Show();
        mainWindow.Activate();
    }

    public void ShowSettings()
    {
        if (settingsWindow is null) { settingsWindow = new SettingsWindow(this); settingsWindow.Closed += (_, _) => { settingsWindow = null; WindowClosed(); }; }
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    public void SettingsPage(string id) => settingsWindow?.Show(id);
    /// The open settings window, for the debug pipe's preview and talkkey.
    public SettingsWindow? OpenSettings => settingsWindow;
    /// Debug: 改这句… on a record's line; 词表 › 粘贴导入 with `text` pasted in.
    public void DebugEditLine(string id, string line) { ShowRecords(id); mainWindow?.DebugEdit(id, line); }
    public void DebugPaste(string text) { ShowSettings(); SettingsPage("words"); settingsWindow?.DebugImport(text); }

    // MARK: AI 服务

    /// 设置 › AI 服务: another service, with its own key file and models; checked again.
    public void SetAIProvider(string provider)
    {
        if (AIProvider.Named(provider).Id != provider || provider == Settings.AiProvider) return;
        Settings.AiProvider = provider;
        Settings.Save();
        AIChanged();
    }

    /// A model chosen over the recommended one ("text", "hear" or "voice"; "" goes back to it).
    public void SetAIModel(string kind, string model)
    {
        var p = Settings.AiProvider;
        if (kind == "text" && p == "ling") Settings.Model = model.Length > 0 ? model : LingClient.DefaultModel;
        // A custom service's notes model: "" is the translation model's.
        else if (kind == "notes")
        {
            if (model.Length > 0) Settings.AiModels["custom.notes"] = model; else Settings.AiModels.Remove("custom.notes");
        }
        else
        {
            var table = kind switch { "text" => Settings.AiModels, "hear" => Settings.AiHearModels, "voice" => Settings.AiVoiceModels, _ => null };
            if (table is null) return;
            if (model.Length > 0) table[p] = model; else table.Remove(p);
        }
        Settings.Save();
        AIChanged();
    }

    /// 设置 › AI 服务, opened at its page (the fix for every AI problem the app names).
    public void ShowAISettings()
    {
        ShowSettings();
        SettingsPage("ai");
    }

    /// One click on 换成推荐的: the service's first recommended text or hear model, then a fresh check.
    public void UseRecommended(AICheck.StepId step)
    {
        if (Ling.Recommended(step) is not { } id) return;
        Log.Debug($"ai: {step} model -> the recommended {id}");
        SetAIModel(step == AICheck.StepId.Hear ? "hear" : "text", id);
    }

    /// A key pasted for one service that belongs to another (改用 OpenRouter): switch, keep it there, check.
    public void SwitchService(string provider, string key)
    {
        if (AIProvider.Named(provider).Id != provider) return;
        Settings.AiProvider = provider;
        Settings.Save();
        Key.Save(key);
        AIChanged();
    }

    /// "改用 Ling" where another service is out of reach: only when a Ling key is already saved,
    /// so the one click works without a trip to the settings.
    public bool CanSwitchToLing => Settings.AiProvider != "ling" && Key.Read("ling") is not null;

    public void SwitchToLing()
    {
        if (!CanSwitchToLing) return;
        Log.Debug("ai: switched to Ling from the status line");
        SetAIProvider("ling");
    }

    /// What the tray says first when the AI service needs the user (title, detail); null otherwise.
    /// On Windows the service hears too, so a dead service means no subtitles either.
    public (string Title, string Detail)? AIProblem()
    {
        var h = Ling.Health;
        if (!Ling.HasKey || !h.NeedsUser) return null;
        var name = Ling.ServiceLabel;
        if (h.Failure is not { } f) return h.BalanceLine(name) is { } low ? (low, L("用完后就听不了对方")) : null;
        var stopped = L("听对方暂时用不了");
        return f.Why switch
        {
            AICheck.Reason.Unreachable => (LF("连不上 %@", name), stopped),
            AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey => (LF("%@ 的 key 用不了", name), stopped),
            AICheck.Reason.NoCredit => (LF("%@ 账户余额不足。", name), stopped),
            AICheck.Reason.NoModel => (LF("%@ 上找不到 %@ 这个模型。", name, Ling.Config.TextModel), L("纪要和整句翻译先停下")),
            AICheck.Reason.Deaf => (LF("%@ 听不了声音。", Ling.HearName), stopped),
            _ => (L("AI 服务的设置要改一下"), L("纪要和整句翻译先停下")),
        };
    }

    /// Network changes (Wi-Fi back, a proxy app's TUN, a cable): 3 s for it to settle, then the AI
    /// service is looked at again if it was unreachable. No timer: nothing is checked while it stays the same.
    void WatchNetwork()
    {
        var settle = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        settle.Tick += (_, _) => { settle.Stop(); Ling.NetworkChanged(); };
        void Changed() => Dispatch.BeginInvoke(() => { settle.Stop(); settle.Start(); });
        System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += (_, _) => Changed();
        System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged += (_, e) => { if (e.IsAvailable) Changed(); };
    }

    /// Turning the system proxy on or off (or pointing it elsewhere) changes no address, so the
    /// watch above misses it. While the service is unreachable (and through the check that follows)
    /// the proxy settings are read every 3 s (three registry values; HttpClient follows them by
    /// itself) and a change is checked like a network change. Not polled otherwise. ProxyWatch decides.
    void WatchProxy()
    {
        var h = Ling.Health;
        if (!proxyWatch.Update(Ling.HasKey && h.Failure?.Why == AICheck.Reason.Unreachable, Ling.HasKey && h.IsRunning, WinProxy.Snapshot))
        {
            proxyPoll?.Stop();
            return;
        }
        if (proxyPoll is null)
        {
            proxyPoll = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            proxyPoll.Tick += (_, _) =>
            {
                if (!proxyWatch.Changed(WinProxy.Snapshot(), Ling.Health.IsRunning)) return;
                Log.Debug("proxy: system proxy settings changed");
                Ling.NetworkChanged();
            };
        }
        if (!proxyPoll.IsEnabled) proxyPoll.Start();
    }

    DispatcherTimer? proxyPoll;
    readonly ProxyWatch proxyWatch = new();

    /// The service, its address, models or key changed: forget the old check and check again.
    public void AIChanged()
    {
        Translator.GoogleOff = Settings.GoogleOff;
        Ling.KeyChanged();
        if (Ling.HasKey) _ = Ling.Check();
        Changed();
    }

    /// For the debug pipe: the AI service in use and what its last check found (never the key).
    public JsonObject AIState()
    {
        var c = Ling.Config;
        return new JsonObject
        {
            ["provider"] = c.Provider.Id, ["base"] = c.Base, ["hearBase"] = c.HearBase, ["text"] = c.TextModel, ["hear"] = c.HearModel, ["voice"] = c.VoiceModel,
            ["notesBase"] = c.NotesApart ? c.ForNotes.Base : null, ["notesModel"] = c.NotesApart ? c.ForNotes.TextModel : null, ["notesOwnKey"] = Ling.NotesHasOwnKey,
            ["state"] = Ling.KeyState.ToString(), ["hears"] = Ling.Hears, ["seconds"] = Ling.Seconds is { } s ? Math.Round(s, 1) : null,
            ["check"] = Ling.Health.Summary,
            ["problem"] = Ling.Health.Message(Ling.ServiceLabel, Ling.ServiceHost, Ling.Config.TextModel, Ling.HearName),
            ["proxy"] = Ling.Health.ProxyLine(Ling.ServiceLabel, Ling.ServiceHost),
            ["tray"] = AIProblem()?.Title,
            ["dot"] = Problem is not null ? "problem" : Listen.Listening ? "live" : Updates.Available is not null ? "update" : null,
            ["blocking"] = Problem,
            ["notified"] = problemNotified,
            ["simulated"] = Ling.SimulateCheck?.ToString() ?? (Ling.SimulateBalance is null ? null : "lowBalance"),
            ["catalog"] = new JsonArray(Ling.TextCatalog.Count, Ling.HearCatalog.Count), ["keyFile"] = Path.GetFileName(Key.File_),
            ["customOnly"] = Settings.AiCustomOnly, ["googleOff"] = Translator.GoogleOff, ["untranslated"] = Translator.SentencesUntranslated,
        };
    }

    public void SetView(string view)
    {
        Settings.View = view;
        Settings.Save();
        if (notesWindow is null) return;
        notesWindow.Place();
        notesWindow.Refresh();
    }

    public void CaptureSettingChanged() => notesWindow?.ApplyCaptureSetting();

    public void SetShowInCapture(bool on)
    {
        Settings.ShowInCapture = on;
        Settings.Save();
        CaptureSettingChanged();
        Changed();
    }

    public void SetTarget(string target)
    {
        Settings.Target = target;
        Settings.Save();
        Changed();
    }

    // MARK: Updates

    /// 安装: Cicada downloads the installer itself and checks it against checksums.txt, then opens
    /// it; its 更新知了 window quits this copy, replaces it and reopens (--updated). A release with
    /// only the zip, or a failed download, falls back to the browser.
    public async void InstallUpdate()
    {
        if (Updates.Available is not { } u || UpdateProgress is not null) return;
        if (u.Setup is null) { _ = DownloadUpdate(); return; }
        UpdateProgress = 0; UpdateFailure = null; UpdatePageOpened = false;
        UpdatesChanged();
        try
        {
            var exe = await Updates.Download(u, p => Dispatch.BeginInvoke(() => { UpdateProgress = p; UpdatesChanged(); }));
            UpdateProgress = null;
            UpdatesChanged();
            Log.Debug($"update: opening the installer for {u.Version}");
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true });
        }
        catch (Exception e)
        {
            UpdateProgress = null;
            UpdateFailure = e is UpdateChecker.Failure f ? L(f.Key) : L("更新包无效");
            Log.Debug($"update: in-app install failed ({e.GetType().Name}), opening the download");
            UpdatePageOpened = DownloadUpdate();
            UpdatesChanged();
        }
    }

    /// 下载: the browser fetches this PC's installer or zip (or opens the release page when there is none).
    public bool DownloadUpdate()
    {
        if (Updates.Available is not { } u) return false;
        Log.Debug($"update: download {u.Version}");
        return Open(u.Download ?? u.Page);
    }

    public void OpenReleaseNotes() { if (Updates.Available is { } u) Open(u.Page); }

    /// False when no browser took it (none set, or Windows refused).
    public static bool Open(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); return true; }
        catch (Exception e) { Log.Debug($"update: open failed {e.GetType().Name}: {e.Message}"); return false; }
    }

    /// 检查更新: says 正在检查… / 已是最新版本 / 连不上 GitHub for a few seconds.
    public async Task CheckForUpdates()
    {
        if (UpdateCheck == L("正在检查…")) return;
        UpdateCheck = L("正在检查…");
        UpdatesChanged();
        var reached = await Updates.Check();
        UpdateCheck = Updates.Available is not null ? null : reached ? L("已是最新版本") : L("连不上 GitHub，请稍后再试");
        UpdatesChanged();
        await Task.Delay(4000);
        if (UpdateCheck != L("正在检查…")) { UpdateCheck = null; UpdatesChanged(); }
    }

    public bool HotkeyRegistered => hotkey?.Registered ?? false;
    public void SettingsChanged()
    {
        SpeakerLabels.Voices = Settings.SpeakerVoices;
        Changed();
    }

    public async Task Quit()
    {
        if (Listen.Listening) await StopListening();
        else await stopping;
        Store.Flush();
        hotkey?.Dispose();
        talk?.Dispose();
        tray.Visible = false;
        tray.Dispose();
        application.Shutdown();
    }

    /// For the debug pipe: what a test needs to see (never meeting text).
    /// 存到文件夹 for the debug pipe (paths and file names, never meeting text).
    public JsonObject ExportState()
    {
        var ex = FolderExport;
        return new JsonObject
        {
            ["on"] = ex.On, ["folder"] = ex.Folder, ["short"] = ex.Folder is { } f ? FolderExportUi.ShortPath(f) : null,
            ["checking"] = ex.Checking, ["problem"] = ex.Trouble?.Kind.ToString(), ["message"] = ex.Trouble?.Message,
            ["protected"] = ex.Folder is { } pf && FolderExportFormat.Protected(pf), ["vault"] = ex.Folder is { } vf ? FolderExportFormat.Vault(vf) : null,
            ["files"] = new JsonObject(ex.State.Files.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)kv.Value))),
            ["pending"] = new JsonArray(ex.State.Pending.Select(id => (JsonNode?)id).ToArray()),
            ["unwritten"] = ex.Unwritten.Count, ["lastFile"] = ex.State.LastFile, ["lastAt"] = ex.State.LastAt?.ToString("o"),
        };
    }

    public JsonObject State() => new()
    {
        ["listening"] = Listen.Listening,
        ["session"] = Listen.SessionId,
        ["lines"] = Listen.SessionId is { } id ? Store.Get(id)?.Lines.Count ?? 0 : 0,
        ["pending"] = Listen.Pending,
        ["spoken"] = Listen.Spoken,
        ["target"] = Listen.Target,
        ["problem"] = Listen.Problem?.ToString(),
        ["notes"] = Notes.Status.ToString(),
        ["topics"] = Notes.Notes.Topics.Count,
        ["key"] = Ling.KeyState.ToString(),
        ["ai"] = AIState(),
        ["view"] = Settings.View,
        ["showInCapture"] = Settings.ShowInCapture,
        ["sessions"] = Store.All().Count,
        ["hotkey"] = HotkeyRegistered,
        ["speakerVoices"] = Settings.SpeakerVoices,
        ["confirmingEnd"] = ConfirmingEnd,
        ["voices"] = Listen.SessionId is { } vid && Store.Get(vid) is { } vs ? string.Join(",", vs.Lines.Where(l => l.Speaker == "them").Select(l => SpeakerLabels.Numbers(vs.Lines).TryGetValue(l.Id, out var n) ? n.ToString() : l.Voice is { } v ? $"v{v}" : "-")) : "",
        ["speak"] = Settings.Speak,
        ["speakState"] = Speak.State.ToString(),
        ["speakTarget"] = Speak.Target,
        ["said"] = Speak.Said,
        ["heard"] = Speak.Heard,
        ["speakProblem"] = Speak.Problem,
        ["voice"] = Speak.LastVoice,
        ["ownVoice"] = OwnVoice.Exists ? Math.Round(OwnVoice.Duration, 1) : null,
        ["ownVoiceReady"] = Speak.CloneReady,
        ["voiceFor"] = Speak.ChosenVoice(Speak.Target),
        ["cable"] = Endpoints.Cable() is not null,
        ["autostart"] = AutoStart.Enabled,
        ["ending"] = Ending is { } p ? $"{EndingTitle(p)} · {EndingLeft(p)}" : null,
        ["autoEnded"] = AutoEnded,
        ["update"] = Updates.Available?.Version,
        ["updateChecked"] = Updates.LastChecked?.ToString("o"),
        ["inCall"] = endWatch is { } w ? string.Join(",", w.InCall.Values) : null,
        ["listenSource"] = Settings.Listens,
        ["mic"] = MicOn,
        ["roomEcho"] = Listen.Echo?.Gate.Echo,
        ["roomMusic"] = Listen.Echo?.Gate.PlayingMusic,
        ["room"] = Listen.Room,
        ["recordAudio"] = Settings.RecordAudio,
        ["export"] = ExportState(),
        ["hasAudio"] = Listen.SessionId is { } aid && Store.Get(aid) is { } a ? a.HasAudio : null,
        ["player"] = mainWindow?.PlayerState(),
    };
}

/// Debug commands over a named pipe (\\.\pipe\cicada-dev), dev builds only: the Windows
/// counterpart of the Mac's `tools/lsctl`. One command per connection, one JSON line back.
///   state | start | stop | feed <wav> | sample | view notes|subtitles | capture on|off
///   listensource system|room|both | fakeroom <wav>|off (a WAV the room mic hears; the VM has no mic)
///   show notes|records|settings [page]|flyout|menu | quit
///   updatefeed <url or file> | checkupdate
///   calls <program=name,…>|none|real | realcalls | endtimes <silence> <countdown> <grace>|off | endkeep
///   provider ling|openrouter|zenmux|custom | ai-model hear|text|voice <id> (设置 › AI 服务; no id: the recommended)
///   ownvoice <wav>[|<text>] | ownvoice remove | ownvoice dialog [<wav>] | voice <lang>=<id> (我自己的声音)
///   open <id> [transcript] | play <seconds>|toggle|speed|follow|row <i> | recordaudio on|off (保存会议录音 and 回放)
///   aacencode <wav>|<out.aac> | aacrewrap <in.aac>|<out.m4a>[|<seconds>]
///   ai-check | ai-check-sim <reason|lowBalance|off> (unreachable, invalidKey, noCredit, noModel, deaf, busy…)
///   ai-custom-only on|off (语音和文字只发给你的服务; acts with the custom service only)
///   改正听错的词: silentlisten [lang] | heard <text> (a finished sentence, no audio) | fixes on|off | asknames on|off
///   vocabadd <word = heard、…|…> | vocabremove <word> | vocabstate | fixstate [@id] | fixanswer yes|no [@id]
///   fixlater | fixrevert <line> [@id] | fixedit <line>=<text>[|one][|keep0] [@id] | fixundo
static class DebugServer
{
    static string Pipe => Paths.Dev ? "cicada-dev" : "cicada";

    public static void Start(Controller app)
    {
        new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var server = new NamedPipeServerStream(Pipe, PipeDirection.InOut, 1);
                    server.WaitForConnection();
                    using var reader = new StreamReader(server);
                    using var writer = new StreamWriter(server) { AutoFlush = true };
                    var line = reader.ReadLine() ?? "";
                    // A release build only takes a second launch's and the installer's few commands; the
                    // rest is for dev builds.
                    if (!Paths.Dev && line is not ("show records" or "setup status" or "setup quit" or "setup opened")) { writer.WriteLine("{\"error\":\"dev builds only\"}"); continue; }
                    var reply = app.Dispatcher().Invoke(() => Run(app, line));
                    writer.WriteLine(reply.ToJsonString());
                }
                catch (Exception e) { Log.Debug($"debug: {e.GetType().Name}"); Thread.Sleep(200); }
            }
        }) { IsBackground = true, Name = "DebugServer" }.Start();
    }

    static Dispatcher Dispatcher(this Controller _) => Application.Current.Dispatcher;

    static JsonObject Quitting(Controller app) { _ = app.Quit(); return new JsonObject { ["ok"] = true }; }
    static JsonObject Opened(Controller app) { app.FromInstaller(); return new JsonObject { ["ok"] = true }; }

    static JsonObject Run(Controller app, string line)
    {
        var parts = line.Trim().Split(' ', 2);
        var arg = parts.Length > 1 ? parts[1].Trim() : "";
        // The installer asks for status every 2 seconds while its window is open: not worth a line each.
        if (line != "setup status") Log.Debug($"debug: {parts[0]}");
        switch (parts[0])
        {
            // The installer (Install.cs): is a meeting on, quit for the new copy, show yourself.
            case "setup": return arg switch
            {
                "status" => new JsonObject { ["listening"] = app.Listen.Listening },
                "quit" => Quitting(app),
                _ => Opened(app),
            };
            case "start": _ = app.StartChecked(app.NewSource); break;
            // mic:<on|off> is the button; listenSource:<system|room|both> the old names for it.
            case "mic" or "listensource": app.SetMic(arg is "on" or "both" or "room"); break;
            case "roomechosim": app.SetFakeEcho(arg is "real" or "" ? null : arg != "off"); break;
            case "fakeroom": app.SetFakeRoom(arg is "" or "off" ? null : arg); break;
            case "stop": _ = app.StopListening(); break;
            case "end": app.RequestStop(); break;  // the user's 结束: asks first when anything was said
            case "notesproblem": app.Notes.SimulateStatus(arg); break;
            case "feed": _ = app.StartChecked(() => new FileAudioSource(arg)); break;
            case "sample": _ = app.PlaySample(); break;
            case "view": app.SetView(arg == "subtitles" ? "subtitles" : "notes"); break;
            case "capture": app.Settings.ShowInCapture = arg == "on"; app.Settings.Save(); app.CaptureSettingChanged(); break;
            case "show":
                if (arg == "records") app.ShowRecords();
                else if (arg.StartsWith("settings")) { app.ShowSettings(); if (arg.Length > 9) app.SettingsPage(arg[9..]); }
                else if (arg == "flyout") app.ShowFlyout();
                else if (arg == "menu") app.ShowMenu();
                else if (arg.StartsWith("onboarding")) app.ShowOnboarding(int.TryParse(arg[10..].Trim(), out var n) ? n : null);
                else app.ShowNotes();
                break;
            case "hide": if (arg == "notes") app.HideNotes(); break;
            case "toast": app.Toast(L("纪要整理好了"), LF("%@ · 点这里打开", "Test"), () => app.ShowRecords()); break;
            case "problem": app.Listen.SimulateProblem(arg); break;
            case "speak":
                if (arg == "on" || arg == "off") { app.Settings.Speak = arg == "on"; app.Settings.Save(); app.SettingsChanged(); }
                else _ = app.Speak.Speak(Wav.Bytes(Wav.Read(arg)), new DeviceSpeaker(Endpoints.Cable));
                break;
            // 我自己的声音 without a microphone: "ownvoice <wav>[|<what it says>]" checks a recording as
            // the dialog does (heard by Ming unless the words are given) and keeps it; "ownvoice remove"
            // is 删除; "ownvoice dialog [<wav>]" opens the recording dialog (with a WAV: as if just read).
            case "ownvoice":
            {
                if (arg == "remove") { app.RemoveOwnVoice(); return new JsonObject { ["ownVoice"] = app.OwnVoice.Exists }; }
                if (arg.StartsWith("dialog"))
                {
                    var file = arg[6..].Trim();
                    app.Dispatcher().BeginInvoke(() => VoiceCloneDialog.Open(app, app.Speak.Target, file.Length > 0 ? Wav.Bytes(Wav.Read(file)) : null));
                    break;
                }
                var p = arg.Split('|', 2);
                var wav = Wav.Bytes(Wav.Read(p[0]));
                var given = p.Length > 1 ? p[1].Trim() : null;
                var target = app.Speak.Target;
                _ = Task.Run(async () =>
                {
                    var (outcome, text, trimmed) = await VoiceCloneCheck.Check(wav, w => given is not null ? Task.FromResult<string?>(given) : app.Transcribe(w));
                    Log.Debug($"ownvoice: {outcome}");
                    if (outcome == VoiceCloneCheck.Outcome.Ready) app.Dispatcher().Invoke(() => app.SaveOwnVoice(trimmed, text, target));
                });
                break;
            }
            // voice <lang>=<id>: 线上的人听到的声音 for a language ("voice en=clone", "voice zh=ming:灵小雅").
            case "voice":
            {
                var kv = arg.Split('=', 2);
                if (kv.Length == 2) { app.Settings.SpeakVoices[VoiceCatalog.Key(kv[0])] = kv[1]; app.Settings.Save(); app.SettingsChanged(); }
                return new JsonObject { ["voice"] = app.Speak.ChosenVoice(kv[0]), ["clone"] = app.Speak.CloneReady };
            }
            case "provider": app.SetAIProvider(arg); break;
            // switchtoling: the 改用 Ling on a status line (logs why when it isn't offered).
            case "switchtoling": Log.Debug($"switchtoling offered={app.CanSwitchToLing}"); app.SwitchToLing(); break;
            case "ai-check":
                // ai-check: a check now; ai-check-sim <reason|lowBalance|off>: every check ends this way (screenshots).
                _ = app.Ling.Check();
                break;
            case "ai-check-sim":
                app.Ling.SimulateCheck = Enum.TryParse<AICheck.Reason>(arg, true, out var reason) ? reason : null;
                app.Ling.SimulateBalance = arg == "lowBalance" ? 0.4 : null;
                _ = app.Ling.Check();
                break;
            case "ai-custom-only": app.Settings.AiCustomOnly = arg == "on"; app.Settings.Save(); app.AIChanged(); break;
            // 纪要 on a custom service: "ai-notes same|own [address]" (the notes model: ai-model notes <id>).
            case "ai-notes":
            {
                var p = arg.Split(' ', 2);
                app.Settings.AiCustomNotesOwn = p[0] == "own";
                if (p.Length > 1) app.Settings.AiCustomNotesBase = p[1].Trim();
                app.Settings.Save(); app.AIChanged();
                break;
            }
            case "ai-model":
            {
                var kv = arg.Split(' ', 2);
                app.SetAIModel(kv[0], kv.Length > 1 ? kv[1].Trim() : "");
                break;
            }
            case "speakers": app.Settings.SpeakerVoices = arg == "on"; app.Settings.Save(); app.SettingsChanged(); break;
            // speaker: the defaults and whether the cable holds the speaker; "cable" hands it the speaker
            // (what Windows may do on install), "install" does that and then the installer's give-back,
            // "restore" is 恢复声音, "notify" the startup notification again.
            case "speaker":
                if (arg is "cable" or "install")
                {
                    var before = Endpoints.Defaults();
                    var to = Endpoints.Cable()!.Id;
                    for (var role = 0; role < 3; role++) Endpoints.SetDefault(to, role);
                    if (arg == "install") _ = CableInstaller.GiveBackDefaults(before); // about 4 s; ask "speaker" after
                }
                else if (arg == "restore") Endpoints.RestoreSpeaker();
                else if (arg == "notify") { app.Settings.CableSpeakerNotified = false; app.NotifyCableSpeaker(); }
                return new JsonObject { ["onCable"] = Endpoints.SpeakerIsCable(), ["speaker"] = Endpoints.Default(Endpoints.Flow.Render)?.Name, ["notified"] = app.Settings.CableSpeakerNotified,
                    ["defaults"] = string.Join(" ", Endpoints.Defaults().OrderBy(d => d.Key).Select(d => $"{d.Key}={(Endpoints.CableIds().Contains(d.Value) ? "cable" : "real")}")) };
            case "fakemic": app.SetFakeMic(arg == "off" ? null : arg); break;
            // talkmic <name>: the talk key reads this input (with fakemic the WAV is still what is sent).
            case "talkmic": app.SetTalkMic(arg is "" or "off" ? null : arg); break;
            case "record": _ = app.RecordCable(arg); break;
            // 回放: "open <id> [transcript]", "play <seconds>|toggle|speed|follow|row <i>" (follow: 回到正在播放; row: a line
            // clicked), "recordaudio on|off".
            case "rename": { var p = arg.Split(' ', 2); app.Store.Rename(p[0], p.Length > 1 ? p[1] : ""); break; }  // rename <id> <title> ("" back to automatic)
            case "open": { var p = arg.Split(' '); app.OpenRecord(p[0], p.Length > 1 ? p[1] : "notes"); break; }
            case "play": app.Play(arg); break;
            // 存到文件夹: export [state] | on | off | folder <path> | choose | all | retry
            case "export":
            {
                var p = arg.Split(' ', 2);
                switch (p[0])
                {
                    case "on": if (app.FolderExport.Folder is { } f) app.FolderExport.Choose(f); else app.FolderExport.Choose(FolderExportFormat.DefaultFolder()); break;
                    case "off": app.FolderExport.TurnOff(); break;
                    case "folder" when p.Length > 1: app.FolderExport.Choose(p[1].Trim().Trim('"')); break;
                    case "choose": // modal: shown after the reply, or the pipe would wait for it
                        app.ShowFolderSettings();
                        app.Dispatcher().BeginInvoke(() => { if (FolderExportUi.Choose(app.OpenSettings, app.FolderExport.Folder) is { } picked) app.FolderExport.Choose(picked); });
                        break;
                    case "all": app.FolderExport.WriteAll(); break;
                    case "retry": app.FolderExport.Retry(); break;
                }
                return app.ExportState();
            }
            case "recordaudio": app.Settings.RecordAudio = arg == "on"; app.Settings.Save(); app.SettingsChanged(); break;
            // 保存会议录音 on its own: "aacencode <wav>|<out.aac>", "aacrewrap <in.aac>|<out.m4a>[|<seconds>]".
            case "aacencode":
                {
                    var p = arg.Split('|');
                    var w = app.Store.Audio?.Open(p[1]);
                    if (w is null) return new JsonObject { ["error"] = "no encoder" };
                    var pcm = Wav.Read(p[0]);
                    for (int i = 0; i < pcm.Length; i += 1600) w.Write(pcm.AsSpan(i, Math.Min(1600, pcm.Length - i)));
                    w.Close();
                    return new JsonObject { ["ok"] = true };
                }
            case "aacrewrap":
                {
                    var p = arg.Split('|');
                    return new JsonObject { ["ok"] = app.Store.Audio?.Rewrap(p[0], p[1], p.Length > 2 ? double.Parse(p[2], System.Globalization.CultureInfo.InvariantCulture) : null) ?? false };
                }
            // preview: 试听 in the open settings (its result line shows there), else on its own.
            case "preview":
                if (arg.Length == 0 && app.OpenSettings is { } sw) _ = sw.RunPreview();
                else _ = app.Preview(arg.Length > 0 ? arg : app.Speak.Target);
                break;
            // talkkey <name>: set it; talkkey choose: settings' 更改 (the next key pressed).
            case "talkkey":
                if (arg == "choose") app.OpenSettings?.StartChoosingKey();
                else if (TalkKey.All.FirstOrDefault(k => k.Name == arg) is { } tk) app.SetTalkKey(tk);
                return new JsonObject { ["talkKey"] = PushToTalk.Current.Name };
            case "calls":
                app.FakeCalls = arg switch { "real" => null, "" or "none" => [], _ => arg.Split(',').Select(p => p.Split('=', 2)).ToDictionary(p => p[0], p => p[^1]) };
                break;
            case "realcalls": return new JsonObject { ["calls"] = string.Join(",", MicReaders.Calls().Select(p => $"{p.Key}={p.Value}")) };
            case "endtimes":
                app.EndTimes = arg is "" or "off" ? null : arg.Split(' ') is [var a, var b, var c] ? (double.Parse(a), double.Parse(b), double.Parse(c)) : null;
                break;
            case "endkeep": app.KeepRecording(); break;
            case "quit": _ = app.Quit(); break;
            case "updatefeed": app.Updates.Feed = arg; _ = app.CheckForUpdates(); break;
            case "updateinstall": app.InstallUpdate(); break;
            case "checkupdate": _ = app.CheckForUpdates(); break;
            // 改正听错的词 (AppModel.debugCommand's fix commands). A command acts on the meeting being
            // listened to, else the newest; "… @<id>" names another.
            case "silentlisten": app.SilentLang = arg.Length > 0 ? arg : "zh-CN"; app.StartListening(new SilentSource()); break;
            case "heard": app.Listen.DebugHeard(arg, app.SilentLang ?? "zh-CN"); break;
            case "target": app.SetTarget(arg.Length > 0 ? arg : "system"); break;  // 翻译成: a code, or system
            case "fixes": app.Settings.FixMisheard = arg != "off"; app.Settings.Save(); app.SettingsChanged(); break;
            case "asknames": app.Settings.AskNames = arg != "off"; app.Settings.Save(); app.SettingsChanged(); break;
            case "vocabadd": return new JsonObject { ["result"] = app.Vocabulary.Import(arg.Replace('|', '\n')).ToString() };
            case "vocabremove": app.Vocabulary.Remove(arg); break;
            case "vocabstate":
                return new JsonObject { ["terms"] = new JsonArray(app.Vocabulary.Terms.Select(t => (JsonNode)$"{t.Word} = {string.Join("、", t.Heard)} · {t.Source} · {t.Fixes}").ToArray()) };
            case "fixstate":
                {
                    var (id, _) = FixTarget(app, arg);
                    var lines = app.Store.Get(id)?.Lines.ToList() ?? [];
                    var all = lines.SelectMany(l => l.Fixes ?? []).ToList();
                    return new JsonObject
                    {
                        ["session"] = id, ["on"] = app.Settings.FixMisheard,
                        ["applied"] = all.Count(f => f.Applied), ["asked"] = all.Count(f => f.Ask == true), ["off"] = all.Count(f => f.Off == true),
                        ["asking"] = app.Fixes.Asking(id) is { } ask ? $"{ask.Fix.From}→{ask.Fix.To}" : null,
                        ["toast"] = app.Fixes.Toast?.Text, ["canUndo"] = app.Fixes.CanUndo,
                        ["lines"] = new JsonArray(lines.Where(l => l.Fixes is not null).Select(l => (JsonNode)
                            $"{l.Id} [{string.Join(", ", l.Fixes!.Select(f => $"{f.From}→{f.To}{(f.Ask == true ? "?" : f.Off == true ? "✗" : f.User == true ? "✓" : "")}"))}] {l.Shown} | {l.Dst}").ToArray()),
                    };
                }
            case "fixanswer":   // fixanswer yes|no [@id]
                {
                    var (id, rest) = FixTarget(app, arg);
                    if ((app.Fixes.Asking(id)?.Fix ?? app.Fixes.Pending(id).Select(p => p.Fix).FirstOrDefault()) is { } f) app.Fixes.Answer(f, rest == "yes", id);
                    break;
                }
            case "fixlater": { var (id, _) = FixTarget(app, arg); if (app.Fixes.Asking(id) is { } ask) app.Fixes.Later(ask.Fix, id); break; }
            case "fixrevert":   // fixrevert <line id> [@id]: the line's first applied fix
                {
                    var (id, lineId) = FixTarget(app, arg);
                    if (app.Store.Get(id)?.Lines.FirstOrDefault(l => l.Id == lineId)?.Fixes?.FirstOrDefault(f => f.Applied) is { } f) app.Fixes.Revert(f, lineId, id);
                    break;
                }
            case "fixedit":     // fixedit <line id>=<new text>[|one][|keep0] [@id]
                {
                    var (id, rest) = FixTarget(app, arg);
                    var p = rest.Split('=', 2);
                    if (p.Length < 2) break;
                    var opts = p[1].Split('|');
                    return new JsonObject { ["changed"] = app.Fixes.Edit(p[0], id, opts[0], everywhere: !opts.Contains("one"), remember: !opts.Contains("keep0")) };
                }
            case "fixundo": app.Fixes.Undo(); break;
            case "fixeditor": { var (id, lineId) = FixTarget(app, arg); app.DebugEditLine(id, lineId); break; }  // fixeditor <line> [@id]
            case "vocabpaste": app.DebugPaste(arg); break;  // vocabpaste <line|line…>: 粘贴导入, filled in, not imported
            case "share":
            {
                // share <record id>[,full][,pw] shares a meeting as the dialog would (CICADA_SHARE_SERVER
                // points a dev build at a local Worker); unshare <record id> turns it off.
                var p = arg.Split(',');
                if (app.Store.Get(p[0]) is not { } s) return new JsonObject { ["error"] = "no such record" };
                var o = new ShareOptions
                {
                    Scope = p.Contains("full") || s.Notes is not { IsEmpty: false } ? ShareScope.Full : ShareScope.Notes,
                    Password = p.Contains("pw") ? SharePassword.Make() : null,
                };
                _ = Task.Run(async () =>
                {
                    var r = await app.Sharing.Share(s, o);
                    Log.Debug(r switch
                    {
                        ShareOutcome.Shared x => $"share: {x.Record.Url}",
                        ShareOutcome.Blocked b => $"share: blocked lines {string.Join(",", ShareHit.RecordLines(b.Hits, b.Kept).Order())}{(b.Hits.Any(h => h.Part == "notes") ? " and notes" : "")}",
                        ShareOutcome.Failed f => $"share: failed {f.Code}",
                        _ => "share: ?",
                    });
                });
                break;
            }
            case "unshare":
            {
                if (app.Sharing.Store.Read(arg) is not { } r) return new JsonObject { ["error"] = "not shared" };
                _ = Task.Run(async () => Log.Debug($"share: revoked {await app.Sharing.Revoke(r, arg)}"));
                break;
            }
            // sharesheet <record id>[,full][,pw][,names][,30|365][,more][,go] opens 分享… (more presses 更改,
            // go 生成并复制); sharesheet leaveout presses 去掉这些内容后分享; on the done step
            // sharesheet copy|copylink|copypw|menu presses 复制, its menu's items, or opens the menu;
            // sharesheet alone closes it.
            case "sharesheet" or "shareSheet":
            {
                var p = arg.Split(',', StringSplitOptions.RemoveEmptyEntries);
                if (p.Length == 0) { ShareDialog.Current?.Close(); break; }
                if (p[0] == "leaveout") { ShareDialog.Current?.DebugLeaveOut(); break; }
                if (p[0] is "copy" or "copylink" or "copypw" or "menu") { ShareDialog.Current?.Debug(p); break; }
                if (app.Store.Get(p[0]) is not { } s) return new JsonObject { ["error"] = "no such record" };
                app.ShowRecords(p[0]);
                app.Dispatcher().BeginInvoke(() => app.ShareSheet(s).Debug(p));
                break;
            }
            // shareinfo <record id>: the link kept for it (dev builds only, never logged) and the open dialog's step.
            case "shareinfo":
            {
                var r = app.Sharing.Store.Read(arg);
                return new JsonObject
                {
                    ["url"] = r?.Url, ["expiresAt"] = r?.ExpiresAt.ToUnixTimeSeconds(), ["scope"] = r?.Scope, ["password"] = r?.Password,
                    ["sheet"] = ShareDialog.Current?.StepName,
                };
            }
            case "state": break;
            default: return new JsonObject { ["error"] = $"unknown command {parts[0]}" };
        }
        return app.State();
    }

    /// The meeting a fix command acts on ("… @<id>", else the one being listened to, else the
    /// newest), and the rest of its argument.
    static (string Id, string Arg) FixTarget(Controller app, string arg)
    {
        var at = arg.LastIndexOf(" @", StringComparison.Ordinal);
        if (arg.StartsWith('@')) return (arg[1..].Trim(), "");
        if (at >= 0) return (arg[(at + 2)..].Trim(), arg[..at].Trim());
        return (app.Listen.SessionId ?? app.Store.All().FirstOrDefault()?.Id ?? "", arg);
    }

    /// Sends one command to the running app (a second launch uses it to bring records forward).
    public static string? Send(string command)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", Pipe, PipeDirection.InOut);
            client.Connect(2000);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            using var reader = new StreamReader(client);
            writer.WriteLine(command);
            return reader.ReadLine();
        }
        catch { return null; }
    }
}
