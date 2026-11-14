using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// 我自己的声音's recording, the Mac's VoiceCloneSheet in a Windows 11 dialog: read a passage for
/// 10–15 s (it stops by itself at 15) → Ming hears what was said → listen to the recording and to the
/// clone speaking the room's language → 用这个声音 keeps it. Nothing is kept until then.
sealed class VoiceCloneDialog
{
    enum Phase { Idle, Recording, Checking, Failed, Ready }

    readonly Controller app;
    readonly string target;
    readonly Window window;
    readonly Border body = new() { Padding = new Thickness(24) };
    Phase phase;
    string? failure;
    byte[]? wav;
    string transcript = "";
    DeviceRecorder? recorder;
    DispatcherTimer? timer;
    DateTime started;
    double seconds;
    bool saved, playingOriginal, playingClone;
    // Updated ten times a second while recording, without rebuilding the dialog.
    ColumnDefinition? levelOn, levelOff, timeOn, timeOff;
    TextBlock? clock;

    VoiceCloneDialog(Controller app, string target, Window? owner)
    {
        this.app = app;
        this.target = target;
        window = new Window
        {
            Owner = owner, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, SizeToContent = SizeToContent.Height, Width = 520 + 32,
            WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
            Topmost = owner is null, FontFamily = Palette.Font, Title = L("录制你的声音"),
            Content = new Border
            {
                Margin = new Thickness(16), Background = Palette.Surface, BorderBrush = Palette.Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16),
                Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 32, ShadowDepth = 8, Opacity = 0.25 },
                Child = body,
            },
        };
        window.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { window.DragMove(); } catch { } };
        window.KeyDown += (_, e) => { if (e.Key == Key.Escape) window.Close(); };
        window.Closed += (_, _) => { StopRecording(); app.StopPreview(); };
    }

    /// Shows the dialog; true when a recording was kept. `recorded`: a WAV taken as just read (the
    /// debug pipe's `ownvoice dialog <wav>`, for a machine without a microphone).
    public static bool Open(Controller app, string target, byte[]? recorded)
    {
        var d = new VoiceCloneDialog(app, target, app.OpenSettings);
        d.Render();
        if (recorded is not null) d.window.Loaded += (_, _) => _ = d.Check(recorded);
        d.window.ShowDialog();
        return d.saved;
    }

    string MyLanguage => app.Speak.MyLanguage;

    void Render()
    {
        levelOn = levelOff = timeOn = timeOff = null; clock = null;
        body.Child = phase == Phase.Ready ? Review() : Record();
    }

    // MARK: Reading

    FrameworkElement Record()
    {
        var stack = new StackPanel();
        stack.Children.Add(Ui.Text(L("录制你的声音"), 20, Palette.Ink, FontWeights.Bold));
        stack.Children.Add(Spaced(Ui.Helper(L("请用平时开会的自然语气朗读以下段落，约 15 秒，在安静环境下录制效果最佳。")), 6));
        var passage = Ui.Text(VoiceCloneCheck.Passage(MyLanguage), 15, Palette.Ink);
        passage.LineHeight = 26;
        stack.Children.Add(Spaced(new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(10), Padding = new Thickness(16, 14, 16, 14), Child = passage }, 16));
        stack.Children.Add(Spaced(Ui.Text(L("这是我自己的声音。只在我说话时用它替我翻译。"), 12, Palette.Secondary), 12));

        // The level and the time read so far; the range under them.
        var level = Bar(Palette.Live, 6, out levelOn, out levelOff);
        clock = Ui.Text(Clock(seconds), 13, Palette.Ink, FontWeights.SemiBold, wrap: false);
        clock.Margin = new Thickness(12, 0, 0, 0);
        var meter = new DockPanel { Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(clock, Dock.Right);
        meter.Children.Add(clock);
        meter.Children.Add(level);
        stack.Children.Add(meter);
        stack.Children.Add(Spaced(Bar(Palette.Live, 4, out timeOn, out timeOff, Palette.Subtle), 8));
        Show(0, Math.Min(1, seconds / VoiceReference.MaxSeconds));
        stack.Children.Add(Spaced(Ui.Text(LF("%lld–%lld 秒", (int)VoiceReference.MinSeconds, (int)VoiceReference.MaxSeconds), 12, Palette.Tertiary), 6));
        if (phase == Phase.Failed && failure is not null) stack.Children.Add(Spaced(Ui.Text(failure, 12, Palette.Danger), 10));

        FrameworkElement action = phase switch
        {
            Phase.Recording => Ui.Button(L("读完了"), () => _ = Finish(), Ui.Kind.Primary),
            Phase.Checking => Centered(Ui.Text(L("正在听写…"), 13, Palette.Secondary, wrap: false)),
            _ => Ui.Button(phase == Phase.Idle ? L("开始录") : L("再录一次"), Start, Ui.Kind.Primary),
        };
        stack.Children.Add(Spaced(Buttons(Ui.Button(L("取消"), window.Close), action), 24));
        return stack;
    }

    void Start()
    {
        app.StopPreview();
        failure = null;
        seconds = 0;
        if (app.OwnVoiceMic() is not { } mic) { Fail(L("麦克风没收到声音，请检查麦克风权限")); return; }
        var r = new DeviceRecorder(mic.Id);
        r.Start();
        if (r.Error is { } err)
        {
            Fail(err == "denied" ? L("麦克风没收到声音，请检查麦克风权限") : LF("无法打开麦克风：%@", err));
            return;
        }
        recorder = r;
        started = DateTime.UtcNow;
        phase = Phase.Recording;
        Log.Debug($"voice clone: recording from {mic.Name}");
        Render();
        timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        timer.Tick += (_, _) =>
        {
            if (recorder is not { } rec) return;
            seconds = (DateTime.UtcNow - started).TotalSeconds;
            Show(rec.Level, Math.Min(1, seconds / VoiceReference.MaxSeconds));
            if (seconds >= VoiceReference.MaxSeconds) _ = Finish();
        };
        timer.Start();
    }

    short[] StopRecording()
    {
        timer?.Stop();
        timer = null;
        var pcm = recorder?.Stop() ?? [];
        recorder = null;
        return pcm;
    }

    async Task Finish()
    {
        if (phase != Phase.Recording) return;
        var pcm = StopRecording();
        await Check(Wav.Bytes(pcm));
    }

    /// The Mac's VoiceRecorder.finish: long enough, heard, and read at a meeting's pace.
    async Task Check(byte[] recorded)
    {
        wav = recorded;
        seconds = Math.Max(0, recorded.Length - 44) / 32000.0;
        phase = Phase.Checking;
        Render();
        var (outcome, text) = await VoiceCloneCheck.Check(recorded, app.Transcribe);
        transcript = text;
        Log.Debug($"voice clone: {outcome}");
        switch (outcome)
        {
            case VoiceCloneCheck.Outcome.TooShort: Fail(LF("录音太短了，请至少朗读 %lld 秒", (int)VoiceReference.MinSeconds)); break;
            case VoiceCloneCheck.Outcome.NotHeard: Fail(L("没听清录音内容，请换个安静的地方再录一次")); break;
            case VoiceCloneCheck.Outcome.Slow: Fail(L("读得有点慢，克隆的声音也会这么慢。请用平时说话的语速再录一次")); break;
            default: phase = Phase.Ready; Render(); break;
        }
    }

    void Fail(string why)
    {
        StopRecording();
        failure = why;
        phase = Phase.Failed;
        Render();
    }

    // MARK: Listening

    FrameworkElement Review()
    {
        var stack = new StackPanel();
        // A way out without keeping it: this step's two buttons are 重录 and 用这个声音.
        var close = Ui.IconButton(Icons.Close, L("关闭"), window.Close, Palette.Secondary, size: 32, iconSize: 14);
        close.VerticalAlignment = VerticalAlignment.Top;
        close.Margin = new Thickness(8, -4, -8, 0);
        var header = new DockPanel();
        DockPanel.SetDock(close, Dock.Right);
        header.Children.Add(close);
        header.Children.Add(Ui.Text(L("录好了，先听听像不像"), 20, Palette.Ink, FontWeights.Bold));
        stack.Children.Add(header);
        stack.Children.Add(Spaced(Ui.Helper(LF("%lld 秒 · 识别出的文字会与录音一起用于学习你的音色", (int)Math.Round(seconds))), 6));
        var rows = new StackPanel();
        rows.Children.Add(Row(playingOriginal, accent: false, L("你的原声"), transcript, null, PlayOriginal));
        rows.Children.Add(Row(playingClone, accent: true, LF("用你的声音说%@", Ui.TargetName(target)), VoiceCatalog.Sample(target), L("对方会听到这个"), PlayClone));
        stack.Children.Add(Spaced(new Border { BorderBrush = Palette.Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), ClipToBounds = true, Child = rows }, 16));
        if (!app.Ling.Clones) stack.Children.Add(Spaced(Ui.Text(L("需先在“AI 服务”中填入 Ling key，才能使用你自己的声音。"), 12, Palette.Danger), 10));
        stack.Children.Add(Spaced(Ui.Text(L("听起来不像或有杂音？换个安静的地方重录一次。录音仅保存在本机，可随时删除。"), 12, Palette.Tertiary), 12));
        var use = Ui.Button(L("用这个声音"), Save, Ui.Kind.Primary);
        use.IsEnabled = app.Ling.Clones;
        stack.Children.Add(Spaced(Buttons(Ui.Button(L("重录"), () => { app.StopPreview(); Start(); }), use), 24));
        return stack;
    }

    FrameworkElement Row(bool playing, bool accent, string title, string detail, string? tag, Action play)
    {
        var button = Ui.IconButton(playing ? Icons.Stop : Icons.Play, playing ? L("停止") : L("试听"), play, accent ? Brushes.White : Palette.Ink, size: 32, iconSize: 12, fill: true);
        button.Background = accent ? Palette.Live : Palette.Subtle;
        button.VerticalAlignment = VerticalAlignment.Top;
        var head = Ui.Row(8, Ui.Text(title, 14, Palette.Ink, FontWeights.SemiBold, wrap: false));
        if (tag is not null) head.Children.Add(Ui.Badge(tag, Palette.AccentPale, Palette.AccentText));
        var text = Ui.Stack(4, head, Ui.Text(detail, 12, Palette.Secondary));
        text.Margin = new Thickness(12, 0, 0, 0);
        var dock = new DockPanel();
        DockPanel.SetDock(button, Dock.Left);
        dock.Children.Add(button);
        dock.Children.Add(text);
        return new Border
        {
            Padding = new Thickness(16, 14, 16, 14), Child = dock,
            Background = accent ? Palette.AccentPale : Palette.Surface,
            BorderBrush = Palette.Line, BorderThickness = new Thickness(0, accent ? 1 : 0, 0, 0),
        };
    }

    async void PlayOriginal()
    {
        if (wav is null) return;
        if (playingOriginal || playingClone) { app.StopPreview(); return; }
        playingOriginal = true; Render();
        try { await app.PlayRecording(wav); } finally { playingOriginal = false; Render(); }
    }

    async void PlayClone()
    {
        if (wav is null) return;
        if (playingOriginal || playingClone) { app.StopPreview(); return; }
        playingClone = true; Render();
        try { await app.PreviewOwnVoice(wav, transcript, target); } finally { playingClone = false; Render(); }
    }

    void Save()
    {
        if (wav is null) return;
        app.StopPreview();
        try { app.SaveOwnVoice(wav, transcript, target); saved = true; }
        catch (Exception e) { Log.Debug($"voice clone save failed {e.GetType().Name}"); }
        window.Close();
    }

    // MARK: Pieces

    static FrameworkElement Spaced(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }

    static FrameworkElement Centered(FrameworkElement e) { e.HorizontalAlignment = HorizontalAlignment.Center; e.VerticalAlignment = VerticalAlignment.Center; return e; }

    static string Clock(double s) => $"{(int)s / 60}:{(int)s % 60:00}";

    /// A bar filled from the left by two star columns; Show sets the share.
    static Grid Bar(Brush fill, double height, out ColumnDefinition on, out ColumnDefinition off, Brush? track = null)
    {
        var grid = new Grid { Height = height, VerticalAlignment = VerticalAlignment.Center };
        on = new ColumnDefinition { Width = new GridLength(0, GridUnitType.Star) };
        off = new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) };
        grid.ColumnDefinitions.Add(on);
        grid.ColumnDefinitions.Add(off);
        var back = new Border { Background = track ?? Palette.Subtle, CornerRadius = new CornerRadius(height / 2) };
        Grid.SetColumnSpan(back, 2);
        grid.Children.Add(back);
        grid.Children.Add(new Border { Background = fill, CornerRadius = new CornerRadius(height / 2) });
        return grid;
    }

    void Show(float level, double elapsed)
    {
        if (levelOn is not null && levelOff is not null)
        {
            levelOn.Width = new GridLength(Math.Clamp(level, 0, 1), GridUnitType.Star);
            levelOff.Width = new GridLength(1 - Math.Clamp(level, 0, 1), GridUnitType.Star);
        }
        if (timeOn is not null && timeOff is not null)
        {
            timeOn.Width = new GridLength(elapsed, GridUnitType.Star);
            timeOff.Width = new GridLength(1 - elapsed, GridUnitType.Star);
        }
        if (clock is not null) clock.Text = Clock(seconds);
    }

    /// Two equal buttons, the main one on the right (Dialogs.Show's band).
    static Grid Buttons(FrameworkElement cancel, FrameworkElement primary)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(primary, 2);
        grid.Children.Add(cancel);
        grid.Children.Add(primary);
        return grid;
    }
}
