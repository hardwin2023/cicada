using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using static Cicada.Strings;

namespace Cicada.App;

/// 设置, as the Mac's settings window with no title bar: the categories as plain words on the left,
/// the chosen one on a white pill, and its page on the right under a big title, the settings in
/// white cards on the grey ground with each control at the right.
sealed partial class SettingsWindow : Window
{
    readonly Controller app;
    readonly ScrollViewer scroll = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(40, 44, 40, 40) };
    readonly StackPanel nav = new() { Margin = new Thickness(12, 52, 12, 12) };
    readonly Dictionary<string, FrameworkElement> sections = [];
    readonly PasswordBox keyBox = new();
    bool editingKey;
    // A custom service's notes key (另一个服务), typed until 保存并检查; 更换 shows the field again.
    readonly PasswordBox notesKeyBox = new();
    bool editingNotesKey;
    string current = "ai";
    // AI 服务: 自己选模型 unfolded, and a model being typed by hand ("hear", "text", "voice").
    bool modelsOpen;
    string? typing;
    // A custom service's address and models as typed, kept across re-renders until 保存并检查.
    readonly Dictionary<string, TextBox> customFields = [];
    // 其他（兼容 OpenAI）: the per-use rows unfolded ("text", "voice", "hear"); null until the page first shows.
    HashSet<string>? open;
    /// A pasted key that belongs elsewhere: what it is, and (another service's key) where it fits.
    (string Text, string? Service, string Key)? keyHint;

    public SettingsWindow(Controller app)
    {
        this.app = app;
        Title = L("设置") + " · " + L("知了");
        Width = 1000; Height = Math.Min(780, SystemParameters.WorkArea.Height - 24); MinWidth = 760; MinHeight = 480;
        Background = Palette.Page; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        System.Windows.Automation.AutomationProperties.SetName(keyBox, L("API key"));
        keyBox.PasswordChanged += (_, _) => KeyPlaceholder();
        System.Windows.Automation.AutomationProperties.SetName(notesKeyBox, L("纪要") + " key");
        notesKeyBox.PasswordChanged += (_, _) => { if (notesKeyPlaceholder is { } h) h.Visibility = notesKeyBox.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed; };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(scroll, 1);
        grid.Children.Add(nav); grid.Children.Add(scroll);
        Content = Ui.Frameless(this, grid);
        scroll.ScrollChanged += (_, e) => { if (e.ViewportWidthChange != 0 && scroll.Content is FrameworkElement p) p.Width = PageWidth(); };
        app.Ling.Changed += OnLingChanged;
        app.OwnVoice.Changed += OnLingChanged;
        Closed += (_, _) => { app.Ling.Changed -= OnLingChanged; app.OwnVoice.Changed -= OnLingChanged; };
        // While a talk key is being chosen no key reaches any app: leaving the window ends it.
        Deactivated += (_, _) => StopChoosingKey();
        Closed += (_, _) => { if (choosingKey) app.StopChoosingTalkKey(); };
        Render();
    }

    void OnLingChanged() => Dispatcher.BeginInvoke(Render);

    void Render()
    {
        var offset = scroll.VerticalOffset;
        sections.Clear();
        var page = new StackPanel { Width = PageWidth(), HorizontalAlignment = HorizontalAlignment.Left };
        Section(page, "ai", L("AI 服务"), AICards().ToArray());
        Section(page, "lang", L("语言"), Group(
            Card(Icons.Globe, L("翻译成"), null, Ui.Choice(Ui.TargetOptions(), app.Settings.Target, app.SetTarget)),
            Card(null, L("纪要语言"), null, Ui.Choice([("system", L("和字幕一样")), .. Languages.Targets.Select(t => (t.Code, t.Name))], app.Settings.NotesLanguage, v => { app.Settings.NotesLanguage = v; Save(); })),
            Card(null, L("界面语言"), L("重新打开知了后生效"), Ui.Choice([("system", L("跟随系统")), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")], app.Settings.UiLanguage, v => { app.Settings.UiLanguage = v; Save(); }))));
        if (current == "words") Section(page, "words", L("词表"), WordCards());
        var size = new Slider { Minimum = 18, Maximum = 32, Value = app.Settings.SubtitleSize, Width = 200, IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(size, L("字幕文字大小"));
        size.ValueChanged += (_, e) => { app.Settings.SubtitleSize = (int)e.NewValue; Save(); };
        Section(page, "listen", L("听的时候"), Group(
            Card(Icons.Subtitles, L("听的时候显示"), null, Ui.Segmented([("notes", L("纪要")), ("subtitles", L("字幕条"))], app.Settings.View, app.SetView)),
            Card(null, L("字幕文字大小"), null, size),
            Card(Icons.Keyboard, L("开始或结束"), app.HotkeyRegistered ? L("在任何程序里都能按") : L("这个快捷键被别的程序占用了"), Keys(Hotkey.Label))));
        Section(page, "speak", L("同声传译"), SpeakCards().ToArray());
        Section(page, "end", L("结束会议"), EndCards());
        Section(page, "privacy", L("隐私与启动"), [Group(
            Card(Icons.Eye, L("共享屏幕时让对方看到"), L("关着时，截图和屏幕共享里看不到纪要和字幕"), Ui.Switch(app.Settings.ShowInCapture, app.SetShowInCapture, L("共享屏幕时让对方看到"))),
            Card(Icons.List, L("说话人识别"), L("按声音标出说话人 1、2…，只在这台电脑上处理"), Ui.Switch(app.Settings.SpeakerVoices, v => { app.Settings.SpeakerVoices = v; Save(); }, L("说话人识别"))),
            Card(Icons.Wave, L("保存会议录音"), L("只存在这台电脑上"), Ui.Switch(app.Settings.RecordAudio, v => { app.Settings.RecordAudio = v; Save(); }, L("保存会议录音"))),
            Card(Icons.Power, L("开机时启动知了"), null, Ui.Switch(AutoStart.Enabled, v => AutoStart.Enabled = v, L("开机时启动知了"))),
            Card(Icons.Folder, L("会议记录存放位置"), $"{Paths.Sessions} · {L("和 Mac 版格式相同")}", Ui.Button(L("打开文件夹"), () => OpenFolder(Paths.Sessions), height: 32))),
            .. ExportCards()]);
        // 卸载 as in Settings › Apps, with the same confirmation; only an installed copy offers it.
        FrameworkElement[] about =
        [
            Card(null, LF("知了 %@", Controller.Version), UpdateDetail(), UpdateControl(), AppIcon.Small(24)),
            Card(null, L("日志"), null, Ui.LinkText(L("打开日志"), () => OpenFolder(Path.GetDirectoryName(Paths.Log)!))),
            .. (!Paths.Dev && File.Exists(Install.Exe) ? new[] { Card(null, L("卸载知了"), L("会议记录默认留着"), Ui.LinkText(L("卸载…"), () => Install.Launch("--uninstall"))) } : []),
        ];
        Section(page, "about", L("关于"), Group(about),
            Credit());
        scroll.Content = page;
        scroll.ScrollToVerticalOffset(shownPage == current ? offset : 0);
        shownPage = current;
        Nav();
    }

    string? shownPage;

    /// The page column is one width whatever it shows (a check running, failed or passed): 640, or
    /// less in a narrow window. Sized by its content it jumped between states.
    double PageWidth() => scroll.ViewportWidth > 0 ? Math.Min(640, scroll.ViewportWidth) : 640;

    /// What to do with the download: the installer upgrades itself; an older release has only the zip.
    public static string UpdateHint(UpdateChecker.Update u) => u.Setup is not null ? L("安装后自动重新打开") : L("下载后解压，替换旧的知了");

    static FrameworkElement Credit() { var t = Ui.Helper(L("说话人识别用 WeSpeaker 的声纹模型（CC BY 4.0）")); t.Margin = new Thickness(6, 0, 0, 0); return t; }

    /// Opens one category's page (the debug pipe's `show settings about`; `ai models` unfolds
    /// 自己选模型; the old `ling` is AI 服务).
    public void Show(string id)
    {
        var parts = id.Split(' ');
        current = parts[0] == "ling" ? "ai" : parts[0];
        if (current == "ai") modelsOpen = parts.Contains("models");
        Render();
    }

    /// An update was found or a check finished: only 关于 shows it.
    public void UpdatesChanged() { if (current == "about") Render(); }

    // The Mac's AppRows version row: what the last check found, and 检查更新 or 下载.
    string? UpdateDetail()
    {
        if (app.Updates.Available is { } u)
            return app.UpdateProgress is { } p ? LF("正在下载 %@：%lld%%", u.Version, (long)(p * 100))
                : app.UpdateFailure is { } f ? (app.UpdatePageOpened ? LF("没能自动更新：%@。已打开下载页", f) : LF("没能自动更新：%@", f))
                : LF("有新版本 %@", u.Version) + " · " + UpdateHint(u);
        if (app.UpdateCheck is { } c) return c;
        if (app.Updates.LastChecked is not { } d) return null;
        var local = d.ToLocalTime();
        return LF("上次检查 %@", local.ToString(local.Date == DateTime.Today ? "HH:mm" : L("M月d日 HH:mm"), Strings.Culture));
    }

    FrameworkElement UpdateControl()
    {
        if (app.Updates.Available is not null)
        {
            var install = Ui.Button(app.Updates.Available.Setup is null ? L("下载") : L("安装并重新打开"), app.InstallUpdate, Ui.Kind.Primary, height: 32);
            install.IsEnabled = app.UpdateProgress is null;
            return Ui.Row(12, Ui.LinkText(L("更新说明"), app.OpenReleaseNotes), install);
        }
        var check = Ui.Button(L("检查更新"), () => _ = app.CheckForUpdates(), height: 32);
        check.IsEnabled = app.UpdateCheck != L("正在检查…");
        return check;
    }

    void Nav()
    {
        nav.Children.Clear();
        (string id, string icon, string label)[] items =
        [
            ("ai", Icons.Key, L("AI 服务")), ("lang", Icons.Globe, L("语言")), ("words", Icons.List, L("词表")), ("listen", Icons.Wave, L("听的时候")),
            ("speak", Icons.Mic, L("同声传译")), ("end", Icons.Stop, L("结束会议")), ("privacy", Icons.Shield, L("隐私与启动")), ("about", Icons.Info, L("关于")),
        ];
        foreach (var (id, icon, label) in items)
        {
            var on = id == current;
            var content = new Grid();

            _ = icon;
            content.Children.Add(Ui.Text(label, 14, Palette.Ink, on ? FontWeights.Bold : FontWeights.Normal, wrap: false));
            var b = new Button { HorizontalAlignment = HorizontalAlignment.Stretch, Content = content, Height = 38, Padding = new Thickness(12, 0, 12, 0), HorizontalContentAlignment = HorizontalAlignment.Left, Background = on ? Palette.Surface : Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand, Margin = new Thickness(0, 0, 0, 2) };
            b.Template = NavTemplate();
            b.Click += (_, _) => { current = id; Render(); };
            System.Windows.Automation.AutomationProperties.SetName(b, label);
            nav.Children.Add(b);
        }
    }

    static ControlTemplate NavTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(10));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        var hover = new MultiTrigger();
        hover.Conditions.Add(new Condition(UIElement.IsMouseOverProperty, true));
        hover.Conditions.Add(new Condition(Control.BackgroundProperty, Brushes.Transparent));
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Selected, "bg"));
        t.Triggers.Add(hover);
        return t;
    }

    /// One category's page: only the chosen one is shown, under its name in big type (and, for
    /// 同声传译, its on/off switch beside it).
    void Section(StackPanel page, string id, string title, params FrameworkElement[] groups)
    {
        if (id != current) return;
        FrameworkElement h = Ui.Text(title, 28, Palette.Ink, FontWeights.Bold);
        if (id == "speak") h = Ui.Spread(h, Ui.Switch(app.Settings.Speak, v => { app.Settings.Speak = v; Save(); }, L("同声传译")));
        // The service menu in the page's header, Ling first and recommended.
        if (id == "ai") h = Ui.Spread(h, Ui.Choice(AIProvider.All.Select(p => (p.Id, p.Id == "ling" ? "Ling" + L("（推荐）") : L(p.Name))), app.Settings.AiProvider,
            v => { editingKey = false; editingNotesKey = false; notesKeyBox.Clear(); typing = null; keyHint = null; customFields.Clear(); open = null; app.SetAIProvider(v); }, 220));
        h.Margin = new Thickness(0, 0, 0, 20);
        sections[id] = h;
        page.Children.Add(h);
        foreach (var g in groups) { g.Margin = new Thickness(0, 0, 0, 12); page.Children.Add(g); }
    }

    /// A grey label over a group, as the Mac's settings sections.
    static FrameworkElement Label(string text) { var t = Ui.Text(text, 13, Palette.Secondary); t.Margin = new Thickness(6, 8, 0, 0); return t; }

    /// Cards that belong together on one white card, with hairlines between them.
    static FrameworkElement Group(params FrameworkElement[] cards)
    {
        var s = new StackPanel();
        for (int i = 0; i < cards.Length; i++)
            s.Children.Add(new Border { BorderBrush = Palette.Line, BorderThickness = new Thickness(0, i == 0 ? 0 : 1, 0, 0), Margin = new Thickness(20, 0, 20, 0), Child = cards[i] });
        return new Border { Background = Palette.Surface, CornerRadius = new CornerRadius(16), Child = s, Padding = new Thickness(0, 2, 0, 2) };
    }

    /// One setting: icon, name, one grey line, and its control on the right.
    static FrameworkElement Card(string? icon, string title, string? description, FrameworkElement control, FrameworkElement? image = null)
    {
        // No icons: the Mac's rows are words and a control. (`icon` stays for the call sites.)
        _ = icon;
        var dock = new DockPanel { MinHeight = 40, Margin = new Thickness(0, 10, 0, 10) };
        if (image is not null) { image.Margin = new Thickness(0, 0, 14, 0); DockPanel.SetDock(image, Dock.Left); dock.Children.Add(image); }
        control.VerticalAlignment = VerticalAlignment.Center;
        control.Margin = new Thickness(16, 0, 0, 0);
        DockPanel.SetDock(control, Dock.Right);
        dock.Children.Add(control);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(title, 14, Palette.Ink));
        if (description is not null) { var d = Ui.Helper(description); d.Margin = new Thickness(0, 2, 0, 0); text.Children.Add(d); }
        dock.Children.Add(text);
        return dock;
    }

    string? cableProgress;

    /// 同声传译: the switch, the virtual mic, the two languages and the room's voice.
    /// 结束会议: when a meeting ends by itself (MeetingEnd.cs), as the Mac's settings say it.
    FrameworkElement EndCards()
    {
        var s = app.Settings;
        var cards = new List<FrameworkElement>
        {
            Card(Icons.Stop, L("会议应用挂断后结束"), L("Zoom、腾讯会议、飞书、Teams 等"), Ui.Switch(s.EndWithApp, v => { s.EndWithApp = v; Save(); }, L("会议应用挂断后结束"))),
            Card(null, L("没人说话时"), L("按识别出的话算，背景音乐不算"),
                Ui.Segmented([("prompt", L("提醒后结束")), ("end", L("直接结束")), ("off", L("一直记录"))], s.SilenceEnd, v => { s.SilenceEnd = v; Save(); Render(); })),
        };
        if (s.SilenceEnd != "off")
            cards.Add(Card(null, L("多久算没人说话"), null,
                Ui.Segmented(new[] { 5, 10, 15, 30 }.Select(m => (m.ToString(), LF("%lld 分钟", m))), ((int)s.SilenceMinutes).ToString(), v => { s.SilenceMinutes = double.Parse(v); Save(); })));
        return Group(cards.ToArray());
    }

    IEnumerable<FrameworkElement> SpeakCards()
    {
        var s = app.Settings;
        var cable = Endpoints.Cable() is not null;
        FrameworkElement cableControl = cable
            ? new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 7, 12, 8), Child = Ui.Row(8, Ui.Dot(Palette.Success, 7), Ui.Text(L("VB-Cable 已装好"), 13, Palette.Ink, wrap: false)) }
            : cableProgress is { } busy ? Ui.Text(busy, 13, Palette.Secondary, wrap: false)
            : Ui.Button(L("安装"), () => _ = InstallCable(), Ui.Kind.Primary, height: 32);
        var target = app.Speak.Target;
        var config = app.Ling.Config;
        var voices = VoiceCatalog.Options(target, config, app.WindowsVoice.Has(target), app.Speak.CloneReady)
            .Select(v => (v.Id, v.Id == VoiceCatalog.SystemId ? L("Windows 自带") : v.Id == VoiceCatalog.CloneId ? L(v.Name) : v.Tags.Length == 0 ? v.Name : $"{v.Name} · {string.Join(" · ", v.Tags.Split(" · ").Select(L))}")).ToList();
        var chosen = app.Speak.ChosenVoice(target);
        var voice = Ui.Row(8,
            Ui.Choice(voices, chosen, v => { s.SpeakVoices[VoiceCatalog.Key(target)] = v; previewNote = null; Save(); Render(); }, 280),
            Ui.Button(app.Previewing ? L("停止") : L("试听"), () => { if (app.Previewing) app.StopPreview(); else _ = RunPreview(); }, height: 32));
        // No voice at all for the language (Windows has none, the service speaks none): say so before
        // 试听 is pressed, as it would after.
        var note = previewNote ?? (voices.Count == 0 ? PreviewNote(Controller.PreviewResult.NoVoice, target) : null);
        var mine = Languages.Sources.FirstOrDefault(x => x.Code == Languages.FromSystem(System.Globalization.CultureInfo.CurrentUICulture.Name))?.Name ?? "";
        var key = PushToTalk.Current;
        FrameworkElement keyControl = choosingKey ? ChoosingKeyBox()
            : Ui.Row(10, Ui.Keycap(PushToTalk.Label, big: true), Ui.Button(L("更改"), StartChoosingKey, height: 32));
        var keyHelp = choosingKey ? L(keyRefused ?? "Esc 取消")
            : TalkKey.Note(key) is { } n ? L(n) : LF("按住%@说话，线上的人听到的是翻译后的声音", PushToTalk.Label);
        yield return Label(L("说话"));
        yield return Group(
            Card(null, L("按住说话"), keyHelp, keyControl),
            Card(null, L("我说的语言"), null, Ui.Choice([("system", LF("跟随系统（%@）", mine)), .. Languages.Sources.Select(x => (x.Code, x.Name))], s.SpeakFrom, v => { s.SpeakFrom = v; Save(); Render(); })),
            Card(null, L("线上的人听到的语言"), s.SpeakTo == "room" ? LF("现在是 %@", Ui.TargetName(target)) : null,
                Ui.Choice([("room", L("对方说的语言")), .. Languages.Targets.Select(t => (t.Code, t.Name))], s.SpeakTo, v => { s.SpeakTo = v; Save(); Render(); })),
            note is null ? Card(null, LF("线上的人听到的声音（%@）", Ui.TargetName(target)), null, voice)
                : Ui.Stack(0, Card(null, LF("线上的人听到的声音（%@）", Ui.TargetName(target)), null, voice), PreviewNoteBox(note.Value)),
            OwnVoiceCard(target, chosen == VoiceCatalog.CloneId));
        yield return Label(L("麦克风"));
        var mic = Card(null, L("译文送进会议"), cable ? L("在会议软件里把麦克风选成 CABLE Output") : L("需要装免费的 VB-Cable；装的时候 Windows 会请你确认"), cableControl);
        if (cable && Endpoints.SpeakerIsCable())
        {
            var strip = CableInstaller.SpeakerStrip(this, Render);
            strip.Margin = new Thickness(0, 4, 0, 12);
            yield return Group(mic, strip);
        }
        else yield return Group(mic);
    }

    // 按住说话's 更改: waiting for a key, and why the last one pressed can't be it.
    bool choosingKey;
    string? keyRefused;

    public void StartChoosingKey()
    {
        choosingKey = true; keyRefused = null;
        app.ChooseTalkKey(KeyPressed);
        Render();
    }

    void StopChoosingKey()
    {
        if (!choosingKey) return;
        choosingKey = false; keyRefused = null;
        app.StopChoosingTalkKey();
        Render();
    }

    void KeyPressed(int vk)
    {
        if (!choosingKey) return;
        if (vk == 0x1B) { StopChoosingKey(); return; }
        var (key, refused) = TalkKey.Choose(vk);
        if (key is null) { keyRefused = refused; app.ChooseTalkKey(KeyPressed); Render(); return; }
        choosingKey = false; keyRefused = null;
        app.SetTalkKey(key);
        Render();
    }

    /// "按下想用的键…" in a dashed accent box where the keycap was.
    static FrameworkElement ChoosingKeyBox()
    {
        var box = new Grid { Width = 176, Height = 36 };
        box.Children.Add(new System.Windows.Shapes.Rectangle { Fill = Palette.AccentPale, Stroke = Palette.AccentFill, StrokeThickness = 1.5, StrokeDashArray = [4, 3], RadiusX = 8, RadiusY = 8 });
        var t = Ui.Text(L("按下想用的键…"), 13, Palette.AccentText, wrap: false);
        t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center;
        box.Children.Add(t);
        System.Windows.Automation.AutomationProperties.SetName(box, L("按下想用的键…"));
        return box;
    }

    /// 我自己的声音 (VoicePicker.swift › cloneRow), under the voice: 录制 before there is a recording;
    /// then its length and how close it will sound, with 重录 and 删除; greyed with 去换成 Ling on a
    /// service that can't clone. Choosing it is the voice menu's last item.
    FrameworkElement OwnVoiceCard(string target, bool chosen)
    {
        var own = app.OwnVoice;
        if (!app.Ling.Config.Provider.Clones)
        {
            var title = Ui.Text(L("我自己的声音"), 14, Palette.Secondary);
            return CardWith(title, L("只有 Ling 能用你自己的声音"), Ui.Button(L("去换成 Ling"), () => Show("ai"), height: 32));
        }
        if (own.Exists)
        {
            var note = own.SavedIsSlow ? L("读得偏慢")
                : VoiceCatalog.Key(app.Speak.MyLanguage) == VoiceCatalog.Key(target) ? L("最像你") : L("会带你的口音");
            var buttons = Ui.Row(8,
                Ui.Button(L("重录"), () => RecordOwnVoice(target), height: 32),
                Ui.Button(L("删除"), () => { app.RemoveOwnVoice(); Render(); }, height: 32));
            var title = Ui.Text(L("我自己的声音"), 14, Palette.Ink, chosen ? Palette.Strong : (FontWeight?)null);
            return CardWith(title, LF("已录 %lld 秒 · %@", (int)Math.Round(own.Duration), note), buttons);
        }
        var record = Ui.Button(L("录制"), () => RecordOwnVoice(target), Ui.Kind.Primary, height: 32);
        record.IsEnabled = app.Ling.Clones;
        return CardWith(Ui.Text(L("我自己的声音"), 14, Palette.Ink), L("录 15 秒原声，对方听到你的音色，晚约 3 秒"), record);
    }

    /// A Card whose title is already a TextBlock (greyed or bold).
    static FrameworkElement CardWith(TextBlock title, string description, FrameworkElement control)
    {
        var card = (DockPanel)Card(null, "", description, control);
        var text = (StackPanel)card.Children[^1];
        text.Children.RemoveAt(0);
        text.Children.Insert(0, title);
        return card;
    }

    void RecordOwnVoice(string target)
    {
        if (VoiceCloneDialog.Open(app, target, null)) previewNote = null;
        Render();
    }

    // 试听's result, shown under the voice until another voice is picked or 试听 is pressed again.
    (string Title, string Help, bool VoiceSettings)? previewNote;

    public async Task RunPreview()
    {
        var target = app.Speak.Target;
        previewNote = null;
        var playing = app.Preview(target);
        Render();
        var result = await playing;
        previewNote = PreviewNote(result, target);
        Render();
    }

    (string Title, string Help, bool VoiceSettings)? PreviewNote(Controller.PreviewResult result, string target) => result switch
    {
        Controller.PreviewResult.NoVoice => (LF("这台电脑没有%@的声音，没放出来。", Ui.TargetName(target)), L("在 Windows 设置里添加这个语言的语音，或者换一个 AI 服务的声音。"), true),
        Controller.PreviewResult.NoSpeaker => (L("没放出声音：找不到扬声器。"), L("看看耳机或扬声器有没有连上。"), false),
        Controller.PreviewResult.FellBack => (LF("%@ 的声音没连上，刚才放的是 Windows 自带的。", app.Ling.Config.Name), L("开会时也会这样换过去，不会不出声。"), false),
        Controller.PreviewResult.Failed => (L("没放出声音。"), L("再试一次，还不行就换一个声音。"), false),
        _ => null,
    };

    static FrameworkElement PreviewNoteBox((string Title, string Help, bool VoiceSettings) note)
    {
        // One wrapping line with the link inline: English runs wider than the card.
        var help = Ui.Helper(note.Help);
        help.TextWrapping = TextWrapping.Wrap;
        if (note.VoiceSettings)
        {
            var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(L("打开语音设置"))) { Foreground = Palette.AccentText, TextDecorations = null, Cursor = System.Windows.Input.Cursors.Hand };
            link.Click += (_, _) => { try { Process.Start(new ProcessStartInfo("ms-settings:speech") { UseShellExecute = true }); } catch { } };
            help.Inlines.Add(new System.Windows.Documents.Run(" "));
            help.Inlines.Add(link);
        }
        var text = Ui.Stack(3, Ui.Text(note.Title, 13, Palette.Ink), help);
        return new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(8), Padding = new Thickness(12, 9, 12, 10), Margin = new Thickness(0, 0, 0, 12), Child = text };
    }

    async Task InstallCable()
    {
        cableProgress = L("正在下载…"); Render();
        var result = await CableInstaller.Install(p => Dispatcher.BeginInvoke(() => { cableProgress = p; Render(); }));
        cableProgress = null;
        Render();
        if (result != CableInstaller.Result.Installed)
            Dialogs.Tell(this, L("虚拟麦克风没装上"), result switch
            {
                CableInstaller.Result.DownloadFailed => L("下载失败，检查网络后再试。"),
                CableInstaller.Result.BadPackage => L("下载到的安装包和预期的不一样，为了安全没有安装。"),
                CableInstaller.Result.Declined => L("需要你在 Windows 的提示里点“是”才能安装。"),
                _ => L("安装没有完成，可以重启电脑后再试。"),
            });
    }

    /// AI 服务 (the Mac's AISettings): a custom service's address and models, the key, what works
    /// with this service, its models folded away (the recommended ones are already chosen), and
    /// what is sent where. The service menu is in the page's header.
    IEnumerable<FrameworkElement> AICards()
    {
        var c = app.Ling.Config;
        var p = c.Provider;
        if (p.Id == "custom")
        {
            foreach (var e in CustomCards()) yield return e;
            yield break;
        }
        yield return KeyCard();
        var host = (c.Base ?? "").Split("//")[^1].Split('/')[0];
        if (host.Length == 0) host = L("你填的地址");
        var lockLine = Ui.Helper(p.Id == "ling" ? L("仅保存在本机当前账户下，仅发送至 Ling（ant-ling.com）")
            : p.Id == "custom" ? LF("仅保存在本机当前账户下，仅发送至 %@", host) : LF("仅保存在本机当前账户下，仅发送至 %@（%@）", c.Name, host));
        lockLine.Margin = new Thickness(6, -4, 0, 0);
        yield return lockLine;
        yield return Label(L("现在能用的"));
        yield return Group(UsesRows().ToArray());
        var fold = Ui.LinkText(L("自己选模型") + (modelsOpen ? " ⌄" : " ›"), () => { modelsOpen = !modelsOpen; Render(); });
        fold.Foreground = Palette.Secondary;
        fold.Margin = new Thickness(6, 4, 0, 0);
        yield return fold;
        if (modelsOpen) yield return Group(ModelRows().ToArray());
        var sent = p.Id == "custom" ? host : c.Name;
        var foot = Ui.Helper(p.Id == "ling" ? LF("听的时候，电脑里的声音会发给 %@。", sent) : L("按所选模型计费。") + LF("听的时候，电脑里的声音会发给 %@。", sent));
        foot.Margin = new Thickness(6, 0, 0, 0);
        yield return foot;
    }

    /// 现在能用的 (AISettings.swift › usage), with 听对方 first: on the ports the service hears.
    /// Only what the last result supports: when the service can't be reached (or the key fails)
    /// nothing says "用 ZenMux" in green. Windows has no voice of the user's own on any service.
    IEnumerable<FrameworkElement> UsesRows()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var check = ling.Health;
        var reason = check.Failure?.Why;
        var down = ling.HasKey && reason is AICheck.Reason.Unreachable or AICheck.Reason.BadAddress or AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey or AICheck.Reason.NoCredit;
        var on = ling.Usable && !down;
        var textOn = on && reason != AICheck.Reason.NoModel;
        var notesOn = textOn && reason != AICheck.Reason.NoJSON;
        var uses = LF("用 %@", c.Name);
        FrameworkElement Row(string title, string tag, string style, string note)
        {
            var (bg, fg) = style switch
            {
                "ok" => ((Brush)new SolidColorBrush(Color.FromRgb(0xE3, 0xF1, 0xE8)), (Brush)Palette.Success),
                "warn" => (Palette.WarnBg, Palette.WarnIcon),
                "local" => (Palette.Mica, Palette.Body),
                _ => (Palette.Subtle, Palette.Tertiary),
            };
            return Card(null, title, note, Ui.Badge(tag, bg, fg));
        }
        var later = !ling.HasKey ? L("填好 key 后可用") : reason == AICheck.Reason.Unreachable ? LF("连上 %@ 后可用", ling.ServiceName) : L("换好 key 后可用");
        var off = ling.HasKey ? L("暂不可用") : L("需要 key");
        var hear = !on ? (off, "off", later)
            : ling.Hears == false ? (L("暂不可用"), "off", LF("%@ 听不了声音。", ling.HearName))
            : c.IsLing ? (uses, "ok", L("Ming 一次识别并翻译"))
            : (uses, "ok", c.HearModel + " · " + L("比 Ling 晚 1–2 秒出字"));
        yield return Row(L("听对方"), hear.Item1, hear.Item2, hear.Item3);
        yield return notesOn && check.IsBusy ? Row(L("实时纪要"), L("很忙"), "warn", L("会自动重试，纪要可能晚一点"))
            : notesOn ? Row(L("实时纪要"), uses, "ok", L("会中每 45 秒更新"))
            : Row(L("实时纪要"), off, "off", reason == AICheck.Reason.NoJSON ? L("这个服务不支持 JSON") : reason == AICheck.Reason.NoModel ? L("换一个模型后可用") : later);
        yield return textOn ? Row(L("翻译"), uses, "ok", L("整句用它；不行时换 Google")) : Row(L("翻译"), "Google", "off", ling.HasKey ? L("先用 Google 翻译") : L("没有 key 时照常可用"));
        // 改正听错的词 (the Mac hides this row where the service hears, as here: Windows has no other
        // way to hear, so it is shown, and says what it costs: Ming's translation leaves no text
        // request to ride on, so each finished line is one more).
        var fixOn = textOn && app.Settings.FixMisheard;
        yield return Row(L("改正听错的词"), fixOn ? uses : textOn ? L("已关") : off, fixOn ? "ok" : "off",
            fixOn ? L("每句话说完多发一次文字请求") : textOn ? L("在“词表”里打开") : later);
        // Windows speaks when the service can't, as the Mac does with its own voice.
        var speaks = ling.Speaks && !down;
        yield return speaks ? Row(L("同传声音"), uses, "ok", ling.LastVoice is { } last ? (last.Ok ? L("上次同传时正常") : L("上次同传没出声，用了 Windows 的声音")) : c.IsLing ? L("Ming 的声音") : c.VoiceModel!)
            : down ? Row(L("同传声音"), L("本机"), "local", L("先用 Windows 的声音"))
            : on ? Row(L("同传声音"), L("本机"), "local", L("没填声音模型，用 Windows 的声音"))
            : Row(L("同传声音"), L("本机"), "local", L("填好 key 前用 Windows 的声音"));
    }

    /// 自己选模型: what hears, what writes, what speaks for this service.
    IEnumerable<FrameworkElement> ModelRows()
    {
        var c = app.Ling.Config;
        var p = c.Provider;
        if (p.Id == "ling")
        {
            yield return Card(null, L("文字模型"), L("3.1 更准；3.0 更快、更省"), Ui.Choice(p.TextModels.Select(m => (m.Id, m.Id)), c.TextModel, v => app.SetAIModel("text", v), 280));
            yield return Card(null, L("听的模型"), L("Ming 一次识别并翻译"), Ui.Text(c.HearModel, 13, Palette.Tertiary, wrap: false));
            yield break;
        }
        yield return Card(null, L("听的模型"), L("听对方和“我说”都用它"), ModelMenu("hear", c.HearModel, p.HearModels, app.Ling.HearCatalog));
        yield return Card(null, L("文字模型"), L("纪要和整句翻译"), ModelMenu("text", c.TextModel, p.TextModels, app.Ling.TextCatalog));
        if (p.HasVoices) yield return Card(null, L("声音模型"), L("同传念给对方"), ModelMenu("voice", c.VoiceModel ?? "", p.VoiceModels, []));
    }

    /// Recommended models first, with why, then everything the service lists that fits; or a
    /// name typed by hand.
    FrameworkElement ModelMenu(string kind, string current, AIModel[] recommended, IReadOnlyList<string> listed)
    {
        if (typing == kind)
        {
            var box = new TextBox { Text = current };
            var field = Ui.Field(box); field.Width = 240; field.Height = 34;
            void Done() { typing = null; app.SetAIModel(kind, box.Text.Trim()); Render(); }
            box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Done(); };
            Dispatcher.BeginInvoke(() => box.Focus());
            return Ui.Row(8, field, Ui.Button(L("保存"), Done, Ui.Kind.Primary, height: 34), Ui.Button(L("取消"), () => { typing = null; Render(); }, height: 34));
        }
        var options = recommended.Select(m => (m.Id, m.Note.Length > 0 ? $"{m.Id} · {L(m.Note)}" : m.Id)).ToList();
        foreach (var id in listed.Append(current))
            if (id.Length > 0 && !options.Any(o => o.Item1 == id)) options.Add((id, id));
        options.Add(("", L("手动填写…")));
        var menu = Ui.Choice(options, current, v => { if (v.Length == 0) { typing = kind; Render(); } else if (v != current) app.SetAIModel(kind, v); }, 280);
        // The button shows the id alone; the menu says why.
        if (menu.Content is DockPanel d && d.Children.OfType<TextBlock>().FirstOrDefault() is { } label) { label.Text = current; label.TextTrimming = TextTrimming.CharacterEllipsis; }
        return menu;
    }

    /// One of a custom service's fields, with a grey hint while empty.
    FrameworkElement CustomField(string name, string value, string hint)
    {
        if (!customFields.TryGetValue(name, out var box)) customFields[name] = box = new TextBox { Text = value };
        if (box.Parent is Grid old) old.Children.Remove(box);
        var hintText = Ui.Text(hint, 14, Palette.Tertiary, wrap: false);
        hintText.IsHitTestVisible = false; hintText.VerticalAlignment = VerticalAlignment.Center;
        void Hint() => hintText.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        box.TextChanged += (_, _) => Hint();
        Hint();
        Ui.StyleField(box);
        var frame = Ui.FieldFrame(new Grid { Children = { box, hintText } }, box);
        frame.Width = 260; frame.Height = 34;
        return frame;
    }

    // MARK: Own service

    /// 其他（兼容 OpenAI） (AISettings.swift › customPage): one card with a row per use, each at its
    /// own address if need be (a text model, a hear model and a speech model often run as separate
    /// servers), each saying whether it works and how fast. What isn't set up or doesn't work yet
    /// opens where it needs filling in.
    IEnumerable<FrameworkElement> CustomCards()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var check = ling.Health;
        open ??= !check.Passed || check.Slow || check.NotesFailed ? new HashSet<string> { "text" } : new HashSet<string>();
        var intro = Ui.Helper(L("每样可以接不同的机器；这台电脑和局域网里的服务可以用 http。"));
        intro.Margin = new Thickness(6, -8, 0, 0);
        yield return intro;
        yield return Group(TextSection(), VoiceSection(), HearSection());
        yield return Group(OnlyRow());
        var lockLine = Ui.Helper(LF("仅保存在本机当前账户下，仅发送至 %@", KeyHosts()));
        lockLine.Margin = new Thickness(6, -4, 0, 0);
        yield return lockLine;
        // What it costs depends on where it runs; what is sent where is the port's own line (it hears through the service).
        var cost = c.Base is { } b && AIProvider.IsNearby(b) ? L("跑在你自己的机器上，不按量计费。") : L("费用以这个服务为准。");
        var foot = Ui.Helper(cost + (app.Settings.AiCustomOnly
            ? LF("会议的语音和文字只发给 %@，不经过 Google 等外部服务。", CustomHosts())
            : LF("听的时候，电脑里的声音会发给 %@。", ling.HearHost.Length > 0 ? ling.HearHost : L("你填的地址"))));
        foot.Margin = new Thickness(6, 0, 0, 0);
        yield return foot;
    }

    /// 语音和文字只发给你的服务 (AISettings.swift › onlyRow): Google is never asked. The grey line says
    /// what it costs, and while the service can't be reached, that new lines show the original
    /// (Windows has no translation of its own to stand in).
    FrameworkElement OnlyRow()
    {
        var s = app.Settings;
        var ling = app.Ling;
        var check = ling.Health;
        var down = s.AiCustomOnly && ling.HasKey && !check.IsRunning && check.Failure is not null && !check.IsBusy;
        var detail = down ? L("现在连不上：新字幕暂时只有原文") : L("不用 Google 翻译；说话时要等整句说完才出译文");
        return Card(null, L("语音和文字只发给你的服务"), detail,
            Ui.Switch(s.AiCustomOnly, v => { s.AiCustomOnly = v; s.Save(); app.AIChanged(); Render(); }, L("语音和文字只发给你的服务")));
    }

    /// Where the custom service's audio and text go: one host when text, hearing, voice and notes
    /// share it, two by name.
    string CustomHosts() => Hosts(notes: true);

    /// Where the custom service's key is sent: every use's address, the notes' only while they share it.
    string KeyHosts() => Hosts(notes: !app.Ling.NotesHasOwnKey);

    string Hosts(bool notes)
    {
        var ling = app.Ling;
        var c = ling.Config;
        var hosts = new List<string> { ling.ServiceHost, ling.HearHost };
        if (notes && c.NotesApart) hosts.Add(HostOf(c.ForNotes.Base));
        if (c.HasVoices) hosts.Add(HostOf(c.VoiceBase));
        var set = hosts.Where(h => h.Length > 0).Distinct().ToList();
        return set.Count switch { 1 => set[0], 2 => LF("%@ 和 %@", set[0], set[1]), _ => L("你填的地址") };
    }

    static string HostOf(string? url) => url is not null && Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host : "";

    /// A row that opens to its fields: a state dot, the use, what it runs on, and how it's doing.
    FrameworkElement SectionHeader(string id, string title, string detail, Brush dot, string? trailing, Brush? trailingColor = null)
    {
        var isOpen = open!.Contains(id);
        var dock = new DockPanel { MinHeight = 40, Margin = new Thickness(0, 10, 0, 10), Background = Brushes.Transparent, Cursor = System.Windows.Input.Cursors.Hand };
        var chevron = Ui.Text(isOpen ? "⌄" : "›", 15, Palette.Secondary, wrap: false);
        chevron.VerticalAlignment = VerticalAlignment.Center; chevron.Margin = new Thickness(12, 0, 0, 0);
        DockPanel.SetDock(chevron, Dock.Right);
        dock.Children.Add(chevron);
        if (trailing is not null)
        {
            var t = Ui.Text(trailing, 13, trailingColor ?? Palette.Tertiary, wrap: false);
            t.VerticalAlignment = VerticalAlignment.Center; t.Margin = new Thickness(12, 0, 0, 0);
            DockPanel.SetDock(t, Dock.Right);
            dock.Children.Add(t);
        }
        var d = Ui.Dot(dot);
        d.Margin = new Thickness(0, 0, 12, 0);
        DockPanel.SetDock(d, Dock.Left);
        dock.Children.Add(d);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(title, 14, Palette.Ink));
        var sub = Ui.Text(detail, 12, Palette.Secondary, wrap: false);
        sub.TextTrimming = TextTrimming.CharacterEllipsis; sub.Margin = new Thickness(0, 2, 0, 0);
        text.Children.Add(sub);
        dock.Children.Add(text);
        dock.MouseLeftButtonUp += (_, _) => { if (!open.Remove(id)) open.Add(id); Render(); };
        System.Windows.Automation.AutomationProperties.SetName(dock, title);
        return dock;
    }

    /// A row's fields, under its title.
    static FrameworkElement Body(params FrameworkElement[] parts)
    {
        var s = new StackPanel { Margin = new Thickness(20, 0, 0, 12) };
        foreach (var x in parts) s.Children.Add(x);
        return s;
    }

    static FrameworkElement Line(string text, Brush color)
    {
        var t = Ui.Text(text, 13, color);
        t.Margin = new Thickness(0, 4, 0, 4);
        return t;
    }

    FrameworkElement SaveButton()
    {
        var check = app.Ling.Health;
        var b = Ui.Button(check.IsRunning ? L("正在检查…") : L("保存并检查"), () => _ = SaveKey(), Ui.Kind.Primary, height: 32);
        b.IsEnabled = !check.IsRunning;
        return b;
    }

    static string Secs(double s) => s.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);

    /// 翻译和纪要 (AISettings.swift › textSection): 翻译's address, key and model; then 纪要, the
    /// same service (another model at most) or another one with its own address and key; how long
    /// a sentence took and whether the model thinks; the steps when something failed.
    FrameworkElement TextSection()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var s = app.Settings;
        var check = ling.Health;
        var textFailed = check.Failure is { Step: not AICheck.StepId.Hear };
        // Translation works, the notes' own model or server doesn't.
        var notesDown = !textFailed && check.NotesFailed;
        var trailing = check.IsRunning ? L("正在检查…")
            : textFailed && ling.HasKey ? AICheckView.Status(check)
            : notesDown ? L("纪要写不了")
            : check.Translate is { } sp ? LF("翻一句 %@ 秒", Secs(sp.Seconds)) : null;
        Brush dot = !ling.HasKey ? Palette.Toggle : check.IsRunning ? Palette.Live : textFailed ? Palette.Danger
            : check.Slow || check.IsBusy || check.NotesFailed ? Palette.WarnIcon : check.Passed ? Palette.Success : Palette.Toggle;
        var header = SectionHeader("text", L("翻译和纪要"), TextDetail(), dot, trailing, textFailed || notesDown ? Palette.Danger : check.Slow ? Palette.WarnIcon : null);
        if (!open!.Contains("text")) return header;
        var model = ModelField("text", s.AiModels.GetValueOrDefault("custom", ""), L("例如 qwen3:14b"), null, ling.TextCatalog, ling.ServiceHost,
            () => _ = ling.FetchCatalog(), v => app.SetAIModel("text", v));
        var address = CustomField("base", s.AiCustomBase, "http://192.168.1.20:8000/v1");
        var parts = new List<FrameworkElement>
        {
            GroupTitle(L("翻译")),
            Card(null, L("地址"), null, address),
            BadAddressLine(customFields["base"]),
            Card(null, "key", null, CustomKey()),
            Card(null, L("模型"), null, model),
            new Border { Height = 1, Background = Palette.Line, Margin = new Thickness(0, 6, 0, 6) },
        };
        parts.AddRange(NotesGroup());
        parts.Add(Card(null, "", null, SaveButton()));
        if (check.SlowLine(app.Settings.GoogleOff) is { } slow) parts.Add(Line(slow, Palette.WarnIcon));
        var key = ling.CurrentKey();
        if (key is not null && (check.IsRunning || textFailed || check.IsBusy || check.At is not null && !check.Passed && check.Failure is null))
            parts.Add(AICheckView.Steps(app, ChangeKey, recheckInStep: false));
        else if (check.At is not null && !check.IsRunning && check.Failure is null or { Step: AICheck.StepId.Hear })
        {
            if (c.NotesApart && check.Translate is { } t) parts.Add(CheckRows(t));
            else
            {
                var facts = new List<string> { L("能写纪要") };
                if (check.Translate is { } t2) facts.Add(t2.Thinks ? L("会先思考") : L("不思考"));
                parts.Add(Line(string.Join(" · ", facts), Palette.Tertiary));
            }
        }
        return new StackPanel { Children = { header, Body([.. parts]) } };
    }

    /// "192.168.1.20 · qwen-mt-turbo", then the notes' model, or their own server after a bar.
    string TextDetail()
    {
        var ling = app.Ling;
        var c = ling.Config;
        if (ling.ServiceHost.Length == 0 || c.TextModel.Length == 0) return L("填上地址和模型");
        var line = $"{ling.ServiceHost} · {c.TextModel}";
        if (!c.NotesApart) return line;
        var n = c.ForNotes;
        if (n.Base != c.Base && HostOf(n.Base) is { Length: > 0 } host) return line + $" ｜ {host} · {n.TextModel}";
        return n.TextModel == c.TextModel ? line : line + $" · {n.TextModel}";
    }

    /// 纪要: the same service as translation, or another one with its own address and key (switching
    /// back keeps what was typed); then the notes' model, 和翻译模型一样 first. The grey line says what
    /// it's for, or in red why notes can't be written.
    IEnumerable<FrameworkElement> NotesGroup()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var s = app.Settings;
        var own = s.AiCustomNotesOwn;
        var notesHost = HostOf(c.ForNotes.Base) is { Length: > 0 } h ? h : ling.ServiceHost;
        var elsewhere = c.ForNotes.Base != c.Base;
        yield return GroupTitle(L("纪要"), Ui.Segmented([("same", L("同一个服务")), ("own", L("另一个服务"))], own ? "own" : "same",
            v => { s.AiCustomNotesOwn = v == "own"; s.Save(); app.AIChanged(); Render(); }));
        if (own)
        {
            var address = CustomField("notesBase", s.AiCustomNotesBase, L("跟上面一样"));
            yield return Card(null, L("地址"), null, address);
            yield return BadAddressLine(customFields["notesBase"]);
            yield return Card(null, "key", null, NotesKey());
        }
        yield return Card(null, L("模型"), null, ModelField("notesModel", s.AiModels.GetValueOrDefault("custom.notes", ""), L("和翻译模型一样"), L("和翻译模型一样"),
            elsewhere ? ling.NotesCatalog : ling.TextCatalog, notesHost,
            () => _ = elsewhere ? ling.FetchNotesCatalog() : ling.FetchCatalog(), v => app.SetAIModel("notes", v)));
        yield return ling.Health.NotesLine(notesHost, c.ForNotes.TextModel, sharedKey: !ling.NotesHasOwnKey) is { } why
            ? Line(why, Palette.Danger)
            : Line(L("用来写实时纪要、识别说话人，默认和翻译用同一个"), Palette.Tertiary);
    }

    /// A group's name in the 翻译和纪要 row (翻译, 纪要), with its control on the right.
    static FrameworkElement GroupTitle(string text, FrameworkElement? control = null)
    {
        var title = Ui.Text(text, 14, Palette.Ink, FontWeights.SemiBold, wrap: false);
        title.VerticalAlignment = VerticalAlignment.Center;
        FrameworkElement row = control is null ? title : Ui.Spread(title, control);
        row.Margin = new Thickness(0, 8, 0, 2);
        return row;
    }

    /// As typed (AISettings.swift › textSection): an http address out on the internet is refused,
    /// and without a key no check runs to say so.
    static FrameworkElement BadAddressLine(TextBox box)
    {
        var bad = Line(L("地址要用 https；这台电脑和局域网里的服务可以用 http。"), Palette.Danger);
        void Bad() => bad.Visibility = box.Text.Trim().Length > 0 && AIProvider.CustomBase(box.Text) is null ? Visibility.Visible : Visibility.Collapsed;
        box.TextChanged += (_, _) => Bad();
        Bad();
        return bad;
    }

    /// A custom service's model: the names its `/models` lists (ModelPicker, picking saves and
    /// checks), or without a list a field saved by 保存并检查, with 重新获取 to ask for the list again.
    FrameworkElement ModelField(string name, string value, string hint, string? sameLabel, IReadOnlyList<string> catalog, string host,
        Action refetch, Action<string> pick)
    {
        if (catalog.Count > 0)
        {
            customFields.Remove(name);
            return ModelPicker.Make(value, sameLabel, catalog, host, refetch, pick);
        }
        var field = CustomField(name, value, hint);
        field.ToolTip = L("这个地址没列出模型，直接填名字");
        return host.Length == 0 ? field : Ui.Row(8, field, Ui.Button(L("重新获取"), refetch, height: 34));
    }

    /// After a check with notes apart: one row each, what it runs and how it did.
    FrameworkElement CheckRows(AICheck.Speed t)
    {
        var c = app.Ling.Config;
        var notes = app.Ling.Health.Notes;
        var notesText = notes switch
        {
            { Kind: AICheck.Kind.Ok, Seconds: { } secs } => LF("能写纪要 · %@ 秒", Secs(secs)),
            { Kind: AICheck.Kind.Ok } => L("能写纪要"),
            { Kind: AICheck.Kind.Fail, Why: AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey } => L("key 不对"),
            { Kind: AICheck.Kind.Fail } => L("纪要写不了"),
            { Kind: AICheck.Kind.Running } => L("正在检查…"),
            _ => "",
        };
        static FrameworkElement Row(string use, string model, bool ok, string result)
        {
            var color = ok ? Palette.Success : Palette.Danger;
            var dock = new DockPanel { MinHeight = 36 };
            var r = Ui.Text(result, 13, color, wrap: false);
            r.VerticalAlignment = VerticalAlignment.Center; r.Margin = new Thickness(8, 0, 0, 0);
            DockPanel.SetDock(r, Dock.Right);
            var d = Ui.Dot(color, 6);
            d.Margin = new Thickness(0, 0, 10, 0);
            DockPanel.SetDock(d, Dock.Left);
            var u = Ui.Text(use, 13, Palette.Ink, wrap: false);
            u.MinWidth = 40; u.VerticalAlignment = VerticalAlignment.Center; u.Margin = new Thickness(0, 0, 8, 0);
            DockPanel.SetDock(u, Dock.Left);
            var m = Ui.Text(model, 13, Palette.Secondary, wrap: false);
            m.TextTrimming = TextTrimming.CharacterEllipsis; m.VerticalAlignment = VerticalAlignment.Center;
            m.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            dock.Children.Add(r); dock.Children.Add(d); dock.Children.Add(u); dock.Children.Add(m);
            return dock;
        }
        return new Border
        {
            BorderBrush = Palette.Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 0, 12, 0),
            Margin = new Thickness(0, 4, 0, 4),
            Child = new StackPanel
            {
                Children =
                {
                    Row(L("翻译"), c.TextModel, true, LF("翻一句 %@ 秒", Secs(t.Seconds)) + " · " + (t.Thinks ? L("会先思考") : L("不思考"))),
                    new Border { Height = 1, Background = Palette.Line },
                    Row(L("纪要"), c.ForNotes.TextModel, notes?.Kind != AICheck.Kind.Fail, notesText),
                },
            },
        };
    }

    // The grey hint in a custom service's key field (a PasswordBox has none), shown while it's empty.
    TextBlock? keyPlaceholder;
    void KeyPlaceholder() { if (keyPlaceholder is { } h) h.Visibility = keyBox.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed; }
    TextBlock? notesKeyPlaceholder;

    /// The key of a custom service: optional on this computer and the local network.
    FrameworkElement CustomKey()
    {
        var saved = app.Key.Read();
        if (saved is { Length: > 0 } && !editingKey)
            return Ui.Row(8, Ui.Text(AIKey.Masked(saved), 13, Palette.Ink, wrap: false),
                Ui.Button(L("更换"), ChangeKey, height: 32),
                Ui.Button(L("删除"), () => { app.Key.Remove(); app.AIChanged(); }, height: 32));
        if (keyBox.Parent is Panel old) old.Children.Remove(keyBox);
        if (keyBox.Parent is Border oldBorder) oldBorder.Child = null;
        var typed = customFields.TryGetValue("base", out var b) ? b.Text : app.Settings.AiCustomBase;
        var hint = Ui.Text(AIProvider.IsNearby(typed) ? L("本机和局域网服务可不填") : "sk-…", 14, Palette.Tertiary, wrap: false);
        hint.IsHitTestVisible = false; hint.VerticalAlignment = VerticalAlignment.Center;
        keyPlaceholder = hint;
        KeyPlaceholder();
        Ui.StyleField(keyBox);
        var frame = Ui.FieldFrame(new Grid { Children = { keyBox, hint } }, keyBox);
        // Wide enough for the hint in English, Japanese and Korean ("Optional on this PC or your local network").
        frame.Width = 340; frame.Height = 34;
        return frame;
    }

    /// The notes' own key (另一个服务): empty, the key above is used; saved by 保存并检查, sent only
    /// to the notes' address. A refused one is framed red.
    FrameworkElement NotesKey()
    {
        var ling = app.Ling;
        var saved = ling.NotesHasOwnKey ? app.Key.Read(LingClient.NotesKeyName) : null;
        if (saved is { Length: > 0 } && !editingNotesKey)
            return Ui.Row(8, Ui.Text(AIKey.Masked(saved), 13, Palette.Ink, wrap: false),
                Ui.Button(L("更换"), () => { editingNotesKey = true; notesKeyBox.Clear(); Render(); notesKeyBox.Focus(); }, height: 32),
                Ui.Button(L("移除"), () => { ling.RemoveNotesKey(); editingNotesKey = false; app.AIChanged(); }, height: 32));
        if (notesKeyBox.Parent is Panel old) old.Children.Remove(notesKeyBox);
        var hint = Ui.Text(L("不填就用上面的 key"), 14, Palette.Tertiary, wrap: false);
        hint.IsHitTestVisible = false; hint.VerticalAlignment = VerticalAlignment.Center;
        hint.Visibility = notesKeyBox.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        notesKeyPlaceholder = hint;
        Ui.StyleField(notesKeyBox);
        var frame = Ui.FieldFrame(new Grid { Children = { notesKeyBox, hint } }, notesKeyBox);
        frame.Width = 340; frame.Height = 34;
        if (ling.Health.Notes?.Why is AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey) frame.BorderBrush = Palette.Danger;
        return frame;
    }

    /// 同传声音: a speech model (`/audio/speech`), its voice and address; else Windows speaks.
    FrameworkElement VoiceSection()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var s = app.Settings;
        var voiceModel = s.AiVoiceModels.GetValueOrDefault("custom", "").Trim();
        var host = c.VoiceBase is { } vb && Uri.TryCreate(vb, UriKind.Absolute, out var u) ? u.Host : ling.ServiceHost;
        var detail = voiceModel.Length == 0 ? L("没填，用 Windows 的声音")
            : string.Join(" · ", new[] { host, voiceModel, s.AiCustomVoice.Trim() }.Where(x => x.Length > 0));
        var last = ling.LastVoice;
        Brush dot = voiceModel.Length == 0 || last is null ? Palette.Toggle : last.Value.Ok ? Palette.Success : Palette.Danger;
        var trailing = voiceModel.Length == 0 ? L("本机") : last is { } l ? (l.Ok ? L("上次正常") : L("上次没出声")) : null;
        var header = SectionHeader("voice", L("同传声音"), detail, dot, trailing, last is { Ok: false } ? Palette.Danger : null);
        if (!open!.Contains("voice")) return header;
        return new StackPanel
        {
            Children =
            {
                header,
                Body(Line(L("需支持 /audio/speech；不填则同传用 Windows 的声音"), Palette.Tertiary),
                    Card(null, L("模型"), null, CustomField("voice", voiceModel, L("例如 kokoro"))),
                    Card(null, L("声音"), null, CustomField("voiceName", s.AiCustomVoice, L("例如 af_heart"))),
                    Card(null, L("地址"), null, CustomField("voiceBase", s.AiCustomVoiceBase, L("跟上面一样"))),
                    Card(null, "", null, SaveButton())),
            },
        };
    }

    /// 听对方: the hear model (it takes audio in: listening and 我说 both use it) and its own
    /// address if it runs elsewhere; the status is the check's hear step.
    FrameworkElement HearSection()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var s = app.Settings;
        var check = ling.Health;
        var state = check[AICheck.StepId.Hear];
        var detail = c.HearModel.Length == 0 ? L("还没填好") : string.Join(" · ", new[] { ling.HearHost, c.HearModel }.Where(x => x.Length > 0));
        Brush dot = c.HearModel.Length == 0 ? Palette.Toggle : state.Kind switch
        {
            AICheck.Kind.Ok => Palette.Success,
            AICheck.Kind.Busy => Palette.WarnIcon,
            AICheck.Kind.Fail => Palette.Danger,
            AICheck.Kind.Running => Palette.Live,
            _ => Palette.Toggle,
        };
        var trailing = state is { Kind: AICheck.Kind.Ok, Seconds: { } sec } ? LF("听 %@ 秒", Secs(sec)) : state.Kind == AICheck.Kind.Fail ? L("听不了声音") : null;
        var header = SectionHeader("hear", L("听对方"), detail, dot, trailing, state.Kind == AICheck.Kind.Fail ? Palette.Danger : null);
        if (!open!.Contains("hear")) return header;
        var parts = new List<FrameworkElement>
        {
            Line(L("要能输入音频：听对方和“我说”都用它"), Palette.Tertiary),
            Card(null, L("模型"), null, CustomField("hear", s.AiHearModels.GetValueOrDefault("custom", ""), L("例如 qwen3-omni"))),
            Card(null, L("地址"), null, CustomField("hearBase", s.AiCustomHearBase, L("跟上面一样"))),
        };
        if (check.Failure is { Step: AICheck.StepId.Hear } && check.Message(ling.ServiceLabel, ling.HearHost, c.TextModel, ling.HearName) is { } why)
            parts.Add(Line(why, Palette.Danger));
        parts.Add(Card(null, "", null, SaveButton()));
        return new StackPanel { Children = { header, Body([.. parts]) } };
    }

    FrameworkElement KeyCard()
    {
        var ling = app.Ling;
        var c = ling.Config;
        var p = c.Provider;
        var check = ling.Health;
        var key = ling.CurrentKey();
        var title = key is { Length: > 0 } ? AIKey.Masked(key) : key is not null ? L("本机服务，不用 key") : p.Id == "custom" ? L("还没填好") : L("还没填 API key");
        // One line under the key: what failed (the steps below say why), busy, or all passed in short.
        string? desc = null;
        Brush color = Palette.Secondary;
        if (key is not null)
        {
            if (AICheckView.Status(check) is { } status) { desc = status; color = check.IsRunning ? Palette.Secondary : Palette.Danger; }
            else if (check.IsBusy) { desc = LF("%@ 现在很忙", ling.ServiceName); color = Palette.WarnIcon; }
            else if (AICheckView.Summary(check) is { } passed) { desc = passed; color = Palette.Success; }
        }
        FrameworkElement control;
        if (editingKey || key is null)
        {
            if (keyBox.Parent is Panel old) old.Children.Remove(keyBox);
            if (keyBox.Parent is Border oldBorder) oldBorder.Child = null;
            var field = Ui.Field(keyBox); field.Width = 260; field.Height = 34;
            var buttons = new List<UIElement> { field, Ui.Button(L("保存并检查"), () => _ = SaveKey(), Ui.Kind.Primary, height: 34) };
            if (editingKey) buttons.Add(Ui.Button(L("取消"), () => { editingKey = false; keyHint = null; Render(); }, height: 34));
            control = Ui.Row(8, [.. buttons]);
        }
        else
        {
            var change = Ui.Button(L("更换"), ChangeKey, height: 32);
            var recheck = Ui.Button(check.IsRunning ? L("正在检查…") : L("重新检查"), () => _ = ling.Check(), height: 32);
            recheck.IsEnabled = !check.IsRunning;
            control = key.Length == 0 ? Ui.Row(8, change, recheck) : Ui.Row(8, change, Ui.Button(L("删除"), () => { app.Key.Remove(); app.AIChanged(); }, height: 32), recheck);
        }
        var card = Card(Icons.Key, title, desc, control);
        if (desc is not null && card is DockPanel dock && dock.Children.OfType<StackPanel>().LastOrDefault() is { Children.Count: > 1 } text && text.Children[1] is TextBlock line)
            line.Foreground = color;
        var rows = new List<FrameworkElement> { card };
        // A pasted key that belongs elsewhere, before it is saved: what it is, and where it fits.
        if (keyHint is { } kh)
        {
            var (hintText, service, pasted) = kh;
            var words = Ui.Text(hintText, 13, Palette.Danger);
            FrameworkElement hint = words;
            if (service is not null)
                hint = Ui.Spread(words, Ui.Button(LF("改用 %@", AIProvider.Named(service).Name), () => { keyHint = null; editingKey = false; keyBox.Clear(); app.SwitchService(service, pasted); }, Ui.Kind.Primary, height: 30));
            hint.Margin = new Thickness(0, 0, 0, 12);
            rows.Add(hint);
        }
        // Where it broke and the one thing that fixes it; all passed folds into the line above.
        if (key is not null && (check.IsRunning || check.Failure is not null || check.IsBusy || check.At is not null && !check.Passed))
            rows.Add(AICheckView.Steps(app, ChangeKey, recheckInStep: false));
        if (check.BalanceLine(ling.ServiceName) is { } low)
        {
            var strip = Ui.Spread(Ui.Text(low, 13, Palette.WarnIcon), Ui.Button(L("去充值"), () => AICheckView.Open(AICheckView.TopUp(p)), height: 30));
            rows.Add(new Border { Background = Palette.WarnBg, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 8, 8, 8), Margin = new Thickness(0, 4, 0, 12), Child = strip });
        }
        // Where to get one, while there is none.
        if (p.Site is { } site && key is null)
            rows.Add(Card(null, LF("打开 %@", c.Name), new Uri(site).Host, Ui.IconButton(Icons.OpenExternal, LF("打开 %@", c.Name), () => Process.Start(new ProcessStartInfo(site) { UseShellExecute = true }), Palette.Secondary, 32, 16)));
        return Group([.. rows]);
    }

    void ChangeKey() { editingKey = true; keyHint = null; keyBox.Clear(); Render(); keyBox.Focus(); }

    async Task SaveKey()
    {
        var s = app.Settings;
        if (s.AiProvider == "custom")
        {
            // The address and models typed so far, kept even before a key.
            string F(string name, string fallback) => customFields.TryGetValue(name, out var b) ? b.Text.Trim() : fallback;
            s.AiCustomBase = F("base", s.AiCustomBase);
            s.AiModels["custom"] = F("text", s.AiModels.GetValueOrDefault("custom", ""));
            s.AiHearModels["custom"] = F("hear", s.AiHearModels.GetValueOrDefault("custom", ""));
            s.AiVoiceModels["custom"] = F("voice", s.AiVoiceModels.GetValueOrDefault("custom", ""));
            s.AiCustomVoice = F("voiceName", s.AiCustomVoice);
            s.AiCustomVoiceBase = F("voiceBase", s.AiCustomVoiceBase);
            s.AiCustomHearBase = F("hearBase", s.AiCustomHearBase);
            s.AiCustomNotesBase = F("notesBase", s.AiCustomNotesBase);
            // The notes model typed by hand (no list): empty is the translation model.
            if (customFields.TryGetValue("notesModel", out var nm))
            {
                if (nm.Text.Trim().Length > 0) s.AiModels["custom.notes"] = nm.Text.Trim(); else s.AiModels.Remove("custom.notes");
            }
            s.Save();
            // Notes' own key (另一个服务): saved here too; it goes only to the notes' address.
            if (s.AiCustomNotesOwn && notesKeyBox.Password.Trim().Length > 0 && app.Ling.SaveNotesKey(notesKeyBox.Password))
            {
                notesKeyBox.Clear();
                editingNotesKey = false;
            }
        }
        var text = keyBox.Password.Trim();
        keyHint = null;
        // The prefix says whose key it is: a management key can't call models, and another
        // service's key goes there with one click (never a silent switch). A custom address may
        // well take an aggregator's key.
        if (s.AiProvider != "custom" && AICheck.Owner(text) is { } whose)
        {
            var (owner, management) = whose;
            if (management) { keyHint = (L("这是 ZenMux 的管理 key，不能用来调用模型。请粘贴 sk-payg 开头的 key。"), null, ""); Render(); return; }
            if (owner != s.AiProvider) { keyHint = (LF("这是 %@ 的 key。", AIProvider.Named(owner).Name), owner, text); Render(); return; }
        }
        // Ling's and the aggregators' keys start with sk-; a company gateway's may not.
        if (text.Length > 0 && (s.AiProvider == "custom" || text.StartsWith("sk-")))
        {
            if (!app.Key.Save(text)) return;
            keyBox.Clear();
        }
        else if (text.Length > 0) return;
        editingKey = false;
        app.AIChanged();
        Render();
        await Task.CompletedTask;
    }

    static FrameworkElement Keys(string combo)
    {
        return Ui.Shortcut(combo);
    }

    void Save() { app.Settings.Save(); app.SettingsChanged(); }

    static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }
}
