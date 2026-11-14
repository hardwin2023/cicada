// Unit tests for Cicada.Core: `scripts/test.sh` (or `dotnet run --project tests/Cicada.Tests`).
// Each test is a method below; a failed Check throws and the runner reports it. No network:
// LingClient runs against a fake handler.
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Cicada;

Environment.SetEnvironmentVariable("CICADA_HOME", Path.Combine(Path.GetTempPath(), "cicada-tests-" + Environment.ProcessId));
Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
int passed = 0, failed = 0;
foreach (var m in typeof(Tests).GetMethods(BindingFlags.Public | BindingFlags.Static).OrderBy(m => m.MetadataToken))
{
    try
    {
        if (m.Invoke(null, null) is Task t) await t;
        passed++;
    }
    catch (Exception e)
    {
        failed++;
        var inner = e is TargetInvocationException { InnerException: { } i } ? i : e;
        Console.WriteLine($"FAIL {m.Name}: {inner.Message}");
    }
}
try { Directory.Delete(Paths.Root, true); } catch { }
Console.WriteLine($"{passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;

static class Tests
{
    static void Check(bool ok, string what) { if (!ok) throw new Exception(what); }
    static void Equal<T>(T expected, T actual, string what)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"{what}: expected «{expected}», got «{actual}»");
    }

    // MARK: the installer

    public static void SetupDecidesFromWhereItRuns()
    {
        const string home = @"C:\Users\a\AppData\Local\Programs\Cicada\Cicada.exe";
        const string download = @"C:\Users\a\Downloads\Cicada-1.1.0-Windows-x64.exe";
        Equal(SetupPlan.Step.Run, SetupPlan.Decide(false, home, home, "1.4.0", "1.4.0"), "the installed copy just runs");
        Equal(SetupPlan.Step.Run, SetupPlan.Decide(false, @"c:\users\A\appdata\local\programs\cicada\CICADA.EXE", home, "1.4.0", "1.4.0"), "paths compare without case");
        Equal(SetupPlan.Step.Run, SetupPlan.Decide(true, download, home, null, "1.4.0"), "a dev build never installs");
        Equal(SetupPlan.Step.Install, SetupPlan.Decide(false, download, home, null, "1.4.0"), "nothing installed: install");
        Equal(SetupPlan.Step.Upgrade, SetupPlan.Decide(false, download, home, "1.3.9", "1.4.0"), "older installed: upgrade");
        Equal(SetupPlan.Step.Open, SetupPlan.Decide(false, download, home, "1.4.0", "1.4.0"), "same version: open it");
        Equal(SetupPlan.Step.Open, SetupPlan.Decide(false, download, home, "1.10.0", "1.9.0"), "never downgrade");
        Equal("知了", SetupPlan.ShortcutName("zh-Hans"), "Chinese shortcut");
        Equal("Cicada", SetupPlan.ShortcutName("ja"), "other languages");
    }

    public static void StringsLoadFromAReader()
    {
        var files = new Dictionary<string, string> { ["en.lproj/Localizable.strings"] = "\"知了\" = \"Cicada\";", ["en.lproj/Windows.strings"] = "\"安装\" = \"Install\";" };
        try
        {
            Strings.Load(p => files.GetValueOrDefault(p), "en");
            Equal("Cicada", Strings.L("知了"), "the Mac table");
            Equal("Install", Strings.L("安装"), "the Windows table over it");
        }
        finally { Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans"); }
    }

    // MARK: 结束会议 (the Mac's MeetingEndTests, case for case)

    static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
    static readonly Dictionary<string, string> Zoom = new() { ["zoom.exe"] = "Zoom" };
    static readonly Dictionary<string, string> NoCalls = [];
    static MeetingEndWatch Watch(MeetingEndWatch.Silence silence = MeetingEndWatch.Silence.Prompt, bool followApps = true) =>
        new(new MeetingEndWatch.Config(FollowApps: followApps, Silence: silence), T0);
    static DateTimeOffset At(double s) => T0.AddSeconds(s);

    public static void HangUpEndsAfterTheGrace()
    {
        var w = Watch();
        Equal(null, w.Tick(At(10), Zoom, true), "in a call");
        Equal(null, w.Tick(At(20), NoCalls, true), "hung up");
        Equal(new MeetingEndWatch.Pending(MeetingEndWatch.Reason.AppLeft("Zoom"), At(50)), w.Waiting, "the grace");
        Equal(null, w.Tick(At(49), NoCalls, true), "still in the grace");
        Equal(MeetingEndWatch.Reason.AppLeft("Zoom"), w.Tick(At(50), NoCalls, true), "ends");
    }

    public static void RejoiningWithinTheGraceKeepsGoing()
    {
        var w = Watch();
        w.Tick(At(10), Zoom, true); w.Tick(At(20), NoCalls, true);
        Equal(null, w.Tick(At(30), Zoom, true), "rejoined");
        Equal(null, w.Waiting, "nothing pending");
    }

    public static void SpeechDoesNotCancelAHangUp()
    {
        var w = Watch();
        w.Tick(At(10), Zoom, true); w.Tick(At(20), NoCalls, true);
        w.Heard(At(25));
        Equal(MeetingEndWatch.Reason.AppLeft("Zoom"), w.Tick(At(50), NoCalls, true), "the next video would talk over it");
    }

    public static void KeepGoingForgetsTheHangUp()
    {
        var w = Watch();
        w.Tick(At(10), Zoom, true); w.Tick(At(20), NoCalls, true);
        w.KeepGoing(At(30));
        Equal(null, w.Tick(At(100), NoCalls, true), "kept going");
        Equal(null, w.Waiting, "nothing pending");
    }

    public static void SilencePromptsThenEnds()
    {
        var w = Watch();
        w.Heard(At(5));
        Equal(null, w.Tick(At(604), NoCalls, true), "not yet");
        Equal(null, w.Waiting, "no prompt yet");
        Equal(null, w.Tick(At(605), NoCalls, true), "the prompt");
        Equal(new MeetingEndWatch.Pending(MeetingEndWatch.Reason.SilenceEnd, At(665)), w.Waiting, "a countdown");
        Equal(MeetingEndWatch.Reason.SilenceEnd, w.Tick(At(665), NoCalls, true), "ends");
    }

    public static void WordsCancelTheSilencePrompt()
    {
        var w = Watch();
        w.Tick(At(600), NoCalls, true);
        Equal("silence", w.Waiting?.Reason.Kind, "prompted");
        w.Heard(At(620));
        Equal(null, w.Waiting, "words cancel it");
        Equal(null, w.Tick(At(700), NoCalls, true), "and it starts over");
    }

    public static void SilenceEndModeEndsAtOnceAndOffNever()
    {
        Equal(MeetingEndWatch.Reason.SilenceEnd, Watch(MeetingEndWatch.Silence.End).Tick(At(600), NoCalls, true), "end");
        var off = Watch(MeetingEndWatch.Silence.Off);
        Equal(null, off.Tick(At(99_999), NoCalls, true), "off");
        Equal(null, off.Waiting, "off: nothing pending");
    }

    public static void SilenceDoesNotCountDuringACall()
    {
        var w = Watch();
        Equal(null, w.Tick(At(5_000), Zoom, true), "a muted call");
        Equal(null, w.Waiting, "no prompt in a call");
        var plain = Watch(followApps: false);
        Equal(null, plain.Tick(At(600), Zoom, true), "not following apps");
        Equal("silence", plain.Waiting?.Reason.Kind, "then a call says nothing");
    }

    public static void NothingSaidStopsQuietlyAfterTheSilence()
    {
        var w = Watch();
        Equal(null, w.Tick(At(599), NoCalls, false), "not yet");
        Equal(MeetingEndWatch.Reason.Nobody, w.Tick(At(600), NoCalls, false), "stops");
        Equal(null, w.Waiting, "no countdown");
        Equal(MeetingEndWatch.Reason.Nobody, Watch(MeetingEndWatch.Silence.End).Tick(At(600), NoCalls, false), "end mode too");
        Equal(null, Watch(MeetingEndWatch.Silence.Off).Tick(At(5_000), NoCalls, false), "off keeps listening");
        Equal(null, Watch().Tick(At(5_000), Zoom, false), "a muted webinar keeps listening");
    }

    public static void NothingSaidKeepsListening()
    {
        var w = Watch();
        w.Tick(At(10), Zoom, false);
        Equal(null, w.Tick(At(500), NoCalls, false), "a call that ended before anyone spoke");
        Equal(null, w.Waiting, "nothing pending");
        w.Heard(At(5_001));
        Equal(null, w.Tick(At(5_002), NoCalls, true), "is forgotten once someone does");
        Equal(null, w.Waiting, "still nothing pending");
    }

    public static void MicUseCountsOnlyMeetingAppsWithTheMicOpen()
    {
        var calls = MicUse.Calls([
            ("C:#Program Files#Zoom#bin#Zoom.exe", 0), ("C:#Users#me#AppData#Roaming#Zoom#bin#Zoom.exe", 0),
            ("C:#Program Files (x86)#Tencent#WeMeet#wemeetapp.exe", 133_000_000_000), // used earlier, closed now
            ("C:#Program Files#Google#Chrome#Application#chrome.exe", 0),               // a browser isn't a meeting app
            ("MSTeams_8wekyb3d8bbwe", 0),
            ("C:#Program Files (x86)#WXWork#WXWork.exe", 0),
        ]);
        Equal("Teams=msteams,Zoom=zoom.exe,企业微信=wxwork.exe", string.Join(",", calls.OrderBy(p => p.Value).Select(p => $"{p.Value}={p.Key}")), "meeting apps reading a mic");
        Equal(0, MicUse.Calls([]).Count, "none");
    }

    public static void WordsFireOnNewAndGrownLinesOnly()
    {
        var store = new SessionStore();
        var id = store.Begin().Id;
        int heard = 0;
        store.Words += w => { if (w == id) heard++; };
        store.Append(id, new TranscriptLine { Id = "h1-1", Src = "so we will", Dst = "所以我们会", SrcLang = "en", DstLang = "zh-CN" });
        store.Append(id, new TranscriptLine { Id = "m1", Speaker = "me", Src = "好的", Dst = "OK", SrcLang = "zh-CN", DstLang = "en" });
        store.Replace(id, new TranscriptLine { Id = "h1-1", Src = "so we will", Dst = "所以我们将", SrcLang = "en", DstLang = "zh-CN" });
        Equal(2, heard, "a retranslation isn't speech");
        store.Replace(id, new TranscriptLine { Id = "h1-1", Src = "so we will ship", Dst = "所以我们会发布", SrcLang = "en", DstLang = "zh-CN" });
        Equal(3, heard, "a half sentence that grew is");
        store.Delete(id);
    }

    // MARK: Records

    public static void SessionJsonMatchesTheMac()
    {
        var s = new Session
        {
            Id = "20261103-101611", Title = "会议 11月3日 10:16", HasAudio = false,
            StartedAt = DateTimeOffset.Parse("2026-11-03T15:16:11Z"),
            Lines = [new TranscriptLine { Id = "h1-1", T = 2.7636849899291995, Src = "你好/世界", SrcLang = "zh-CN", DstLang = "en", Via = "room", Voice = 1 }],
        };
        var json = Json.Write(s);
        Check(json.Contains("\"startedAt\": \"2026-11-03T15:16:11Z\""), "dates are whole-second ISO-8601 UTC");
        Check(json.Contains("你好/世界"), "Chinese and slashes are written as they are");
        Check(!json.Contains("\"dst\""), "nil optionals are left out");
        Check(!json.Contains("endedAt") && !json.Contains("notes"), "absent fields stay absent");
        Check(json.Contains("2.7636849899291995"), "doubles keep full precision");
        var keys = JsonNode.Parse(json)!.AsObject().Select(p => p.Key).ToList();
        Check(keys.SequenceEqual(keys.Order(StringComparer.Ordinal)), "keys are sorted like the Mac's");
        var lineKeys = JsonNode.Parse(json)!["lines"]![0]!.AsObject().Select(p => p.Key).ToList();
        Check(lineKeys.SequenceEqual(lineKeys.Order(StringComparer.Ordinal)), "line keys are sorted");
    }

    public static void ReadsAMacRecord()
    {
        const string mac = """
        {
          "endedAt" : "2026-11-02T15:24:12Z",
          "hasAudio" : true,
          "id" : "20261102-101639",
          "lines" : [
            {
              "dst" : "Hello",
              "dstLang" : "en",
              "id" : "h1-1",
              "speaker" : "them",
              "src" : "你好",
              "srcLang" : "zh-CN",
              "t" : 2.5,
              "voice" : 1
            },
            {
              "dstLang" : "en",
              "id" : "h1000001-1000001",
              "speaker" : "them",
              "src" : "对",
              "srcLang" : "zh-CN",
              "t" : 3,
              "via" : "room"
            }
          ],
          "notes" : {
            "conclusions" : [ ], "covered" : 1, "final" : true, "summary" : "总结",
            "terms" : [ { "heard" : [ ], "name" : "鸟哥", "note" : "分享者" } ],
            "title" : "标题", "todos" : [ { "owner" : "你", "support" : 3, "t" : 202.4, "text" : "记录" } ],
            "topics" : [ { "pointTimes" : [ 12.4, null ], "points" : [ "a", "b" ], "start" : 0, "summary" : "s", "title" : "t" } ],
            "updatedAt" : "2026-11-02T15:24:40Z"
          },
          "startedAt" : "2026-11-02T15:16:39Z",
          "title" : "会议 11月2日 10:16",
          "voiceNames" : { "1" : "Emma" }
        }
        """;
        var s = Json.Read<Session>(mac)!;
        Equal(2, s.Lines.Count, "lines");
        Equal(1, s.Lines[0].Voice, "voice");
        Equal("room", s.Lines[1].Via, "via");
        Equal(null, s.Lines[0].Via, "no via for the computer's audio");
        Equal("Emma", s.VoiceNames!["1"], "voice names");
        Equal(12.4, s.Notes!.Topics[0].PointTime(0), "point time");
        Equal(null, s.Notes!.Topics[0].PointTime(1), "missing point time");
        Check(JsonNode.DeepEquals(JsonNode.Parse(mac), JsonNode.Parse(Json.Write(s))), "written back unchanged");
    }

    /// 改正听错的词: a Mac record whose lines carry fixes reads and writes back byte for byte in
    /// value, and the line shows (and exports) the fixed words while `src` stays what was heard.
    public static void KeepsTheMacsFixes()
    {
        const string mac = """
        {
          "hasAudio" : false,
          "id" : "20261107-013000",
          "lines" : [
            {
              "dst" : "Recently Curve raised it; Morpho too.",
              "dstLang" : "en",
              "fixes" : [
                { "ask" : true, "from" : "开布特", "to" : "Curve" },
                { "from" : "莫拉", "to" : "Morpho" },
                { "from" : "质压", "off" : true, "to" : "质押" },
                { "from" : "Morpho", "to" : "Monad", "user" : true }
              ],
              "id" : "h1-1",
              "speaker" : "them",
              "src" : "最近那个开布特提了，莫拉也是，质压",
              "srcLang" : "zh-CN",
              "t" : 1.5
            },
            { "dstLang" : "en", "id" : "h2-2", "speaker" : "them", "src" : "好的", "srcLang" : "zh-CN", "t" : 4 }
          ],
          "startedAt" : "2026-11-07T06:30:00Z",
          "title" : "会议 11月7日 01:30"
        }
        """;
        var s = Json.Read<Session>(mac)!;
        var l = s.Lines[0];
        Equal(4, l.Fixes!.Count, "fixes read");
        Equal(true, l.Fixes[0].Ask, "ask");
        Equal(null, l.Fixes[1].Ask, "absent flags stay null");
        Equal("最近那个开布特提了，Monad也是，质压", l.Shown, "applied fixes in, the user's last; waiting and refused ones out");
        Equal("最近那个开布特提了，莫拉也是，质压", l.Src, "src is what was heard");
        Equal(null, s.Lines[1].Fixes, "a line without fixes");
        Check(JsonNode.DeepEquals(JsonNode.Parse(mac), JsonNode.Parse(Json.Write(s))), "written back unchanged");
        var written = Json.Write(s);
        var keys = JsonNode.Parse(written)!["lines"]![0]!.AsObject().Select(p => p.Key).ToList();
        Check(keys.SequenceEqual(keys.Order(StringComparer.Ordinal)), "line keys sorted with fixes");
        var fixKeys = JsonNode.Parse(written)!["lines"]![0]!["fixes"]![2]!.AsObject().Select(p => p.Key).ToList();
        Equal("from,off,to", string.Join(",", fixKeys), "fix keys sorted, false flags left out");
        Check(!JsonNode.Parse(written)!["lines"]![1]!.AsObject().ContainsKey("fixes"), "no fixes key without fixes");
        Check(SessionStore.Markdown(s).Contains("Monad也是"), "the export uses the shown text");
        Check(!SessionStore.Markdown(s).Contains("莫拉"), "not the heard one");
    }

    public static void ARetranslationKeepsTheLinesFixes()
    {
        var store = new SessionStore();
        var id = store.Begin().Id;
        store.Append(id, new TranscriptLine { Id = "h1-1", Src = "但质压这种", SrcLang = "zh-CN", DstLang = "en" });
        store.SetFixes(id, "h1-1", [new LineFix("质压", "质押")]);
        store.Replace(id, new TranscriptLine { Id = "h1-1", Src = "但质压这种", Dst = "but staking", SrcLang = "zh-CN", DstLang = "en" });
        Equal("但质押这种", store.Get(id)!.Lines[0].Shown, "fixes kept through Replace");
        store.SetFixes(id, "h1-1", []);
        Equal(null, store.Get(id)!.Lines[0].Fixes, "none is absent");
        store.Delete(id);
    }

    public static void StoreSavesAndDropsEmptyMeetings()
    {
        var store = new SessionStore();
        var empty = store.Begin(DateTimeOffset.Parse("2026-01-01T01:00:00Z"));
        store.End(empty.Id);
        Check(store.Get(empty.Id) is null && !Directory.Exists(Path.Combine(Paths.Sessions, empty.Id)), "an empty meeting is removed");
        var s = store.Begin(DateTimeOffset.Parse("2026-01-01T02:00:00Z"));
        store.Append(s.Id, new TranscriptLine { Id = "h1-1", Src = "hi", SrcLang = "en", DstLang = "zh-CN" });
        store.End(s.Id);
        var file = Path.Combine(Paths.Sessions, s.Id, "session.json");
        Check(File.Exists(file), "record written on end");
        Equal(1, Json.Read<Session>(File.ReadAllText(file))!.Lines.Count, "line saved");
        Check(new SessionStore().Get(s.Id) is not null, "loaded again");
        Check(s.Title.StartsWith("会议 "), "default title is the Mac's Chinese form");
    }

    public static void DisplayTitle()
    {
        var s = new Session { Title = "会议 1月1日 10:00", StartedAt = DateTimeOffset.Now, Notes = new MeetingNotes { Title = "路线评审", Summary = "x" } };
        Check(SessionStore.DisplayTitle(s).EndsWith(" 路线评审"), "notes' name after the date");
        s.Renamed = true; s.Title = "我的会";
        Equal("我的会", SessionStore.DisplayTitle(s), "the user's title wins");
        Check(SessionStore.Markdown(s).Split('\n')[0].TrimEnd() == "# 我的会", "the export is headed by the shown title");
    }

    public static void ExportMarksTalkKeyLinesAsInterpreted()
    {
        // TranscriptExport.speakerName on the Mac: a "me" line was said with the talk key (同传).
        var s = new Session { Title = "会议 1月1日 10:00", StartedAt = DateTimeOffset.Now, Lines =
            [new TranscriptLine { Id = "h1-1", T = 1, Src = "Can we ship?", Dst = "能发布吗？", SrcLang = "en", DstLang = "zh-CN" },
             new TranscriptLine { Id = "m1", T = 5, Speaker = "me", Src = "可以", Dst = "Yes", SrcLang = "zh-CN", DstLang = "en" }] };
        var md = SessionStore.Markdown(s);
        Check(md.Contains("你 · 同传： 可以"), "my line says it was interpreted");
        Check(md.Split('\n').Count(x => x.Contains("同传")) == 1, "only my line");
    }

    public static void KeepsTheMacsImportAndRoomFields()
    {
        // A Mac record of an imported room recording (a line by the room mic), plus a key no version knows yet.
        const string mac = """
        {"endedAt":"2026-01-01T02:10:00Z","futureKey":{"a":[1,2]},"hasAudio":true,"id":"20260101-100000","importing":false,"lines":[{"dstLang":"en","id":"h1-1","speaker":"them","src":"你好","srcLang":"zh-CN","t":2.5,"via":"room"}],"room":true,"sourceFile":"周会.m4a","sourcePath":"/Users/x/周会.m4a","startedAt":"2026-01-01T02:00:00Z","title":"会议 1月1日 10:00"}
        """;
        var s = Json.Read<Session>(mac)!;
        Equal(true, s.Room, "room");
        Equal("room", s.Lines[0].Via, "a line the room mic heard");
        Equal("周会.m4a", s.SourceFile, "sourceFile");
        Check(JsonNode.DeepEquals(JsonNode.Parse(mac), JsonNode.Parse(Json.Write(s))), "written back with every key: " + Json.Write(s));
    }

    // MARK: 保存会议录音

    /// Records what it is given; the "file" is a list of samples, and Rewrap copies the partial file.
    sealed class FakeAudio : IAudioFiles
    {
        public readonly List<short> Samples = [];
        public bool Closed;
        public readonly List<(string from, string to, double? until)> Rewraps = [];
        public IAudioWriter? Open(string path) { File.WriteAllBytes(path, [0xFF, 0xF1]); return new Writer(this); }
        public bool Rewrap(string from, string to, double? until) { Rewraps.Add((from, to, until)); File.Copy(from, to, true); return true; }
        sealed class Writer(FakeAudio a) : IAudioWriter
        {
            public void Write(ReadOnlySpan<short> pcm) { lock (a.Samples) a.Samples.AddRange(pcm.ToArray()); }
            public void Close() => a.Closed = true;
        }
    }

    /// Loopback as it really is: sound while something plays, nothing at all in between.
    sealed class GappySource(params (double seconds, bool sound)[] parts) : IAudioSource
    {
        public event Action<short[]>? Samples;
        public event Action<string?>? Ended;
        public void Start() => Task.Run(async () =>
        {
            foreach (var (seconds, sound) in parts)
            {
                if (!sound) { await Task.Delay(TimeSpan.FromSeconds(seconds)); continue; }
                for (int i = 0; i < seconds * 10; i++) { Samples?.Invoke(Tone(0.1, 0.002)); await Task.Delay(100); }
            }
            Ended?.Invoke(null);
        });
        public void Stop() { }
    }

    static short Loudest(List<short> pcm, double from, double to)
    {
        short m = 0;
        for (int i = (int)(from * 16000); i < Math.Min(pcm.Count, (int)(to * 16000)); i++) m = Math.Max(m, Math.Abs(pcm[i]));
        return m;
    }

    /// 电脑和会议室: the room mic goes into the meeting's one recording at its place on the clock (#19).
    public static void TheRoomIsMixedIntoTheRecordingWhereItWasHeard()
    {
        var audio = new FakeAudio();
        var mix = new RoomMix(audio.Open(Path.Combine(Path.GetTempPath(), $"mix-{Guid.NewGuid()}.aac"))!);
        for (int i = 0; i < 30; i++) // 3 s of the PC at 1000; the room at 500 from 1 s to 2 s, half a second late
        {
            mix.Write(Enumerable.Repeat((short)1000, 1600).ToArray());
            if (i >= 15 && i < 25) mix.Room(Enumerable.Repeat((short)500, 1600).ToArray(), (i - 5) * 1600);
        }
        mix.Write(Enumerable.Repeat((short)30000, 1600).ToArray());
        mix.Room(Enumerable.Repeat((short)30000, 1600).ToArray(), 3 * 16000);
        mix.Room(Enumerable.Repeat((short)30000, 1600).ToArray(), 4 * 16000); // after the PC's last sample
        mix.Close();
        Check(audio.Closed, "closed");
        Equal(4 * 16000 + 1600, audio.Samples.Count, "the PC's 3.1 s, then silence up to the room's last words");
        Equal((short)1000, Loudest(audio.Samples, 0, 1), "the PC alone");
        Equal((short)1500, audio.Samples.Skip(16000).Take(16000).Min(), "both, every sample of that second");
        Equal((short)1000, Loudest(audio.Samples, 2, 3), "the PC alone again");
        Equal(short.MaxValue, audio.Samples[3 * 16000], "loud on loud clips instead of wrapping");
        Equal((short)0, Loudest(audio.Samples, 3.2, 4), "nothing between");
        Equal((short)30000, audio.Samples[^1], "the room after the PC ended");
    }

    public static async Task BothSidesOfAMeetingGoIntoItsRecording()
    {
        var ling = Client(new Fake(_ => Reply("{}")));
        var audio = new FakeAudio();
        var store = new SessionStore { Audio = audio };
        var settings = new AppSettings { Target = "zh-CN", SpeakerVoices = false };
        var main = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), settings);
        var room = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), settings, roomSide: true);
        var pc = new GappySource((0.5, true), (2.5, false));
        var mic = new GappySource((2.0, true)); // a mic sends all the time, quiet or not
        var ended = new TaskCompletionSource();
        pc.Ended += _ => ended.TrySetResult();
        main.Start(pc);
        room.Join(mic, main.SessionId!, store.Get(main.SessionId!)!.StartedAt, main.Mix);
        await ended.Task;
        await room.Stop();
        await main.Stop();
        Check(audio.Closed, "closed when the meeting ends");
        Check(Loudest(audio.Samples, 1.0, 1.8) > 0, "the room's sound, after the PC's ended, is in the recording");
    }

    public static void SilenceGoesInOnlyOnceTheStreamIsASecondBehind()
    {
        Equal(0, Recording.Behind(0.5, 0, 1600), "a packet a little late: nothing");
        Equal(0, Recording.Behind(2.0, 16000, 1600), "0.9 s behind: still nothing");
        Equal(24000, Recording.Behind(2.6, 16000, 1600), "1.5 s behind after 1.1 s of audio: 1.5 s of silence");
        Equal(0, Recording.Behind(1.0, 64000, 1600), "ahead of the clock: nothing");
    }

    public static async Task TheRecordingKeepsTheMeetingsClock()
    {
        // 0.5 s of sound, 2.5 s of nothing (loopback while the PC is silent), 0.5 s of sound.
        var fake = new Fake(_ => Reply("{}"));
        var ling = Client(fake);
        var store = new SessionStore { Audio = new FakeAudio() };
        var audio = (FakeAudio)store.Audio;
        var engine = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), new AppSettings { Target = "zh-CN", SpeakerVoices = false });
        var source = new GappySource((0.5, true), (2.5, false), (0.5, true));
        var ended = new TaskCompletionSource();
        source.Ended += _ => ended.TrySetResult();
        engine.Start(source);
        var id = engine.SessionId!;
        Check(File.Exists(Recording.Partial(Recording.SystemAudio(id))), "written as system.aac while live");
        await ended.Task;
        var wall = (DateTimeOffset.Now - store.Get(id)!.StartedAt).TotalSeconds;
        await engine.Stop();
        Check(audio.Closed, "closed when the meeting ends");
        var recorded = audio.Samples.Count / 16000.0;
        Check(recorded > wall - 1.1 && recorded < wall + 0.2, $"the recording ({recorded:F2} s) is as long as the meeting ({wall:F2} s)");

        var off = new SessionStore { Audio = new FakeAudio() };
        var quiet = new ListenEngine(ling, new Translator(ling), off, new NotesEngine(ling, off), new AppSettings { RecordAudio = false });
        quiet.Start(new GappySource((0.2, true)));
        Check(!File.Exists(Recording.Partial(Recording.SystemAudio(quiet.SessionId!))), "保存会议录音 off: no file");
        await quiet.Stop();
    }

    public static async Task EndingAMeetingFinishesItsRecording()
    {
        var audio = new FakeAudio();
        var store = new SessionStore { Audio = audio };
        var s = store.Begin(DateTimeOffset.Parse("2026-02-01T02:00:00Z"));
        store.Append(s.Id, new TranscriptLine { Id = "h1-1", Src = "hi", SrcLang = "en", DstLang = "zh-CN", T = 3 });
        var m4a = Recording.SystemAudio(s.Id);
        Directory.CreateDirectory(Path.GetDirectoryName(m4a)!);
        File.WriteAllBytes(Recording.Partial(m4a), [1]);
        store.End(s.Id, DateTimeOffset.Parse("2026-02-01T02:10:00Z"));
        Check(store.Get(s.Id)!.HasAudio, "hasAudio once a recording exists");
        for (int i = 0; i < 50 && !File.Exists(m4a); i++) await Task.Delay(20);
        Check(File.Exists(m4a) && !File.Exists(Recording.Partial(m4a)), "rewrapped into system.m4a, the partial file gone");
        Equal(600.0, audio.Rewraps[0].until, "a meeting that ended by itself is cut where it ended");
        Equal(m4a, Recording.Playable(store.Get(s.Id)!), "it plays");

        // A meeting the app didn't get to close: finished at the next launch.
        var t = store.Begin(DateTimeOffset.Parse("2026-02-02T02:00:00Z"));
        store.Append(t.Id, new TranscriptLine { Id = "h1-1", Src = "hi", SrcLang = "en", DstLang = "zh-CN" });
        store.Flush();
        File.WriteAllBytes(Recording.Partial(Recording.SystemAudio(t.Id)), [1]);
        var later = new SessionStore { Audio = audio };
        later.FinishLeftovers();
        for (int i = 0; i < 50 && !File.Exists(Recording.SystemAudio(t.Id)); i++) await Task.Delay(20);
        Check(later.Get(t.Id)!.HasAudio && File.Exists(Recording.SystemAudio(t.Id)), "a crash's recording is kept");
        Equal(null, Recording.Playable(new Session { Id = "20990101-000000" }), "no file: nothing to play");
    }

    public static void AdtsFramesAreSplitAndACutOneDropped()
    {
        // Two AAC-LC 16 kHz mono frames of 10 and 12 bytes (7-byte headers), then half a third.
        static byte[] Frame(int payload)
        {
            int length = 7 + payload;
            var f = new byte[length];
            f[0] = 0xFF; f[1] = 0xF1; f[2] = (1 << 6) | (8 << 2); f[3] = (byte)((1 << 6) | (length >> 11));
            f[4] = (byte)(length >> 3); f[5] = (byte)((length & 7) << 5 | 0x1F); f[6] = 0xFC;
            for (int i = 7; i < length; i++) f[i] = (byte)i;
            return f;
        }
        byte[] file = [.. Frame(3), .. Frame(5), .. Frame(9)[..8]];
        var config = Adts.Read(file)!;
        Equal(16000, config.Rate, "rate");
        Equal(1, config.Channels, "mono");
        Equal("14-08", BitConverter.ToString(config.SpecificConfig), "AudioSpecificConfig of AAC-LC 16 kHz mono");
        var frames = Adts.Frames(file);
        Equal(2, frames.Count, "the cut-off frame is left out");
        Equal(new Adts.Frame(7, 3), frames[0], "payload without the header");
        Equal(new Adts.Frame(17, 5), frames[1], "second frame");
    }

    // MARK: 会议室

    public static void RoomMicSkipsTheCableAndHeadsets()
    {
        RoomMicPlan.Input usb = new("usb"), headset = new("bt", Bluetooth: true), cable = new("cable", Virtual: true);
        Equal("usb", RoomMicPlan.Pick("usb", [headset, usb]), "the default");
        Equal("usb", RoomMicPlan.Pick("bt", [headset, usb]), "a headset hears the wearer, not the table");
        Equal("usb", RoomMicPlan.Pick("cable", [cable, usb]), "never the virtual cable");
        Equal("bt", RoomMicPlan.Pick("cable", [cable, headset]), "a headset when nothing else is left");
        Equal(null, RoomMicPlan.Pick(null, [cable]), "no microphone");
    }

    public static void RoomSpeechLineFollowsTheNoise()
    {
        var gate = new VoiceGate();
        Equal(0.004, gate.Threshold, "before the room is known");
        // Half a minute of a fan at 0.003 with a voice at 0.02 now and then.
        for (int i = 0; i < 30 * 33; i++) gate.Voiced(i % 10 == 0 ? 0.02 : 0.003, 0.03);
        Check(Math.Abs(gate.Threshold - 0.006) < 1e-9, $"twice the room's noise, got {gate.Threshold}");
        Check(gate.Voiced(0.008, 0.03), "a quiet voice across the table");
        Check(!gate.Voiced(0.004, 0.03), "the fan");
        var loud = new VoiceGate();
        for (int i = 0; i < 200; i++) loud.Voiced(0.5, 0.03);
        Equal(VoiceGate.Fixed, loud.Threshold, "never above the computer's line");
    }

    public static void ARoomMicHearsQuietSpeechTheFixedLineMisses()
    {
        // A voice at -48 dBFS (0.004 RMS) over a quieter floor: under the fixed 0.01 line.
        var rng = new Random(1);
        short[] Noise(double seconds, double rms) => Enumerable.Range(0, (int)(seconds * Segmenter.Rate)).Select(_ => (short)((rng.NextDouble() * 2 - 1) * rms * 1.7 * 32768)).ToArray();
        short[] Voice(double seconds, double rms) => Enumerable.Range(0, (int)(seconds * Segmenter.Rate)).Select(i => (short)(Math.Sin(i * 0.05) * Math.Sin(i * 0.0007) * rms * 2 * 32768)).ToArray();
        int Count(Segmenter s) { int n = 0; s.Emitted += _ => n++; s.Feed(Noise(5, 0.0008)); s.Feed(Voice(1.5, 0.004)); s.Feed(Noise(2, 0.0008)); s.Flush(); return n; }
        Equal(0, Count(new Segmenter()), "the computer's line hears nothing");
        Equal(1, Count(new Segmenter(new VoiceGate())), "the room's line hears the sentence");
    }

    public static void ARoomMeetingIsMarked()
    {
        var store = new SessionStore();
        var s = store.Begin(DateTimeOffset.Parse("2026-01-02T02:00:00Z"));
        store.MarkRoom(s.Id);
        Equal(true, store.Get(s.Id)!.Room, "room");
        store.Delete(s.Id);
        Equal(ListenSource.System, ListenSource.Parse("mac"), "an unknown value is the computer's audio");
        Equal(ListenSource.Both, ListenSource.Parse("both"), "both");
    }

    public static void RenameLikeTheMac()
    {
        var store = new SessionStore();
        var id = store.Begin(DateTimeOffset.Parse("2026-01-02T02:00:00Z")).Id;
        store.Append(id, new TranscriptLine { Id = "h1-1", Src = "hi", SrcLang = "en", DstLang = "zh-CN" });
        store.SetNotes(id, new MeetingNotes { Title = "路线评审", Summary = "x" });
        var shown = SessionStore.DisplayTitle(store.Get(id)!);
        store.Rename(id, " " + shown + " ");
        Equal(null, store.Get(id)!.Renamed, "saving the shown title unchanged isn't a rename");
        store.SetNotes(id, new MeetingNotes { Title = "预算", Summary = "y" });
        Check(SessionStore.DisplayTitle(store.Get(id)!).EndsWith(" 预算"), "so a later name from the notes still shows");
        store.Rename(id, "我的会");
        Equal(true, store.Get(id)!.Renamed, "renamed");
        store.Rename(id, "  ");
        Equal(false, store.Get(id)!.Renamed, "an empty title goes back to the automatic one");
        Check(SessionStore.DisplayTitle(store.Get(id)!).EndsWith(" 预算"), "the notes' name again");
        store.Delete(id);
    }

    public static void MeetingCutShortEndsAfterItsLastLine()
    {
        var start = DateTimeOffset.Parse("2026-01-03T02:00:00Z");
        var dir = Path.Combine(Paths.Sessions, "20260103-crash");
        Directory.CreateDirectory(dir);
        var s = new Session { Id = "20260103-crash", Title = "会议", StartedAt = start, Lines = [new() { Id = "h1-1", Src = "a", T = 3 }, new() { Id = "h1-2", Src = "b", T = 70 }] };
        File.WriteAllText(Path.Combine(dir, "session.json"), Json.Write(s));
        var store = new SessionStore();
        Equal(start.AddSeconds(75), store.Get(s.Id)!.EndedAt, "last line + 5 s");
        store.Delete(s.Id);
    }

    // MARK: Hearing

    public static void ParsesMingReplies()
    {
        var h = Translator.ParseHeard("LANG: en\nORIGINAL: Hello there.\nTRANSLATION: 你好。", "zh-CN", null)!;
        Equal("en", h.Lang, "lang"); Equal("Hello there.", h.Original, "original"); Equal("你好。", h.Translation, "translation");
        Equal(null, Translator.ParseHeard("作为一个人工智能语言模型，这个问题超出我目前的学习范围了", "zh-CN", null), "no labelled lines");
        Equal(null, Translator.ParseHeard("LANG: en\nORIGINAL: NONE\nTRANSLATION: 无", "zh-CN", null), "no speech");
        Equal(null, Translator.ParseHeard("LANG: en\nORIGINAL: ...\nTRANSLATION: …", "zh-CN", null), "punctuation only");
        var same = Translator.ParseHeard("LANG: zh\nORIGINAL: 好的\nTRANSLATION: OK", "zh-CN", "en")!;
        Equal("zh-CN", same.Lang, "zh normalized"); Equal("好的", same.Translation, "already in the target: kept as is");
        var wrong = Translator.ParseHeard("LANG: en\nORIGINAL: Hi\nTRANSLATION: Hi again", "zh-CN", null)!;
        Equal(null, wrong.Translation, "a translation not in Chinese is dropped for the text translator");
        Equal("ja", Translator.ParseHeard("lang: ja-JP\noriginal: はい\ntranslation: 是", "zh-CN", null)!.Lang, "labels in any case");
    }

    // Same cases as the Android and Linux ports' noise tests.
    public static void DropsNoise()
    {
        foreach (var o in new[] { "嗯。", "Mm.", "uh, um", "呃呃呃呃呃", "嗯，嗯，嗯，嗯，嗯，嗯，嗯，嗯，嗯，嗯，嗯，嗯。", string.Concat(Enumerable.Repeat("滴答", 50)),
                                  "hmmmm", "うーん", "음…", "喂？", "No no no no no no",
                         "（无语音内容）", "[Music]", "♪♪", "这段音频是一段旋律，没有说话声。", "There is no speech in this audio." })
            Check(Translator.IsNoise(o), $"noise: {o}");
        foreach (var o in new[] { "嗯，好的。", "OK.", "Oh no, it crashed.", "对", "对对对", "谢谢谢谢", "喂喂，能听到吗？", "No, no, no.",
                                  "えーと、来週の件ですが", "あの人です", "Okay, let's move on to the quarterly numbers.", "（笑）好的" })
            Check(!Translator.IsNoise(o), $"kept: {o}");
        var spoken = "我们今天讨论一下这个季度的数字和下个季度的计划安排";
        Check(Translator.IsNoise(spoken, 1.0), "more than anyone says in a second");
        Check(!Translator.IsNoise(spoken, 4.0), "said in four seconds");
        Equal(null, Translator.ParseHeard("LANG: zh-CN\nORIGINAL: 嗯，嗯，嗯，嗯，嗯，嗯。\nTRANSLATION: 嗯，嗯，嗯，嗯，嗯，嗯。", "zh-CN", null), "hold music");
        Equal(800, Translator.HearTokens(0), "unknown length"); Equal(380, Translator.HearTokens(8), "a full segment");
        Equal(800, Translator.HearTokens(30), "capped");
    }

    public static void NormalizesLanguages()
    {
        Equal("zh-CN", Languages.Normalize("zh-Hans", "en"), "zh-Hans");
        Equal("zh-TW", Languages.Normalize("zh-TW", "en"), "zh-TW");
        Equal("zh-CN", Languages.Normalize("cmn", "en"), "cmn");
        Equal("en", Languages.Normalize("en-US", "ja"), "en-US");
        Equal("ja", Languages.Normalize("", "ja"), "empty falls back");
        Equal("zh-TW", Languages.FromSystem("zh-Hant-HK"), "system zh-Hant");
        Equal("zh-CN", Languages.FromSystem("zh-CN"), "system zh-CN");
        Equal("en", Languages.FromSystem("en-GB"), "system en");
        Equal("Simplified Chinese", Languages.EnglishName("zh-CN"), "english name");
        Equal("Japanese", Languages.EnglishName("ja"), "english name ja");
        Equal("01:05", Languages.Clock(65.9), "clock"); Equal("1:00:01", Languages.Clock(3601), "clock hours");
    }

    public static void CleansTranslations()
    {
        Equal("你好", Translator.CleanTranslation("Translation: 你好", "zh-CN"), "label stripped");
        Equal("你好", Translator.CleanTranslation("“你好”", "zh-CN"), "wrapping quotes");
        Equal("Hello", Translator.CleanTranslation("Here is the translation:\nHello", "en"), "remark line dropped");
        Equal(null, Translator.CleanTranslation("请提供需要翻译的字幕内容", "en"), "a request for input is not a translation");
        Equal(null, Translator.CleanTranslation("Hello", "zh-CN"), "wrong script");
        Equal(null, Translator.CleanTranslation("翻译。", "zh-CN"), "the instruction translated, not the subtitle");
        Equal(null, Translator.CleanTranslation("Translate.", "en"), "the instruction translated, in English");
        Equal("好的，翻译。", Translator.CleanTranslation("好的，翻译。", "zh-CN"), "a sentence about translating is kept");
        Equal("Done.", Translator.CleanTranslation("<think>x</think>Done.", "en"), "leaked reasoning");
    }

    /// While the check says the service is unreachable, a sentence doesn't wait on its timeout
    /// every time: one in 15 s still tries it, the rest go straight to Google.
    public static async Task AnUnreachableServiceIsTriedOnceIn15Seconds()
    {
        var fake = new Fake(_ => Reply("你好"));
        var ling = Client(fake);
        var translator = new Translator(ling, new Fake(_ => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)));
        Equal("你好", await translator.Translate("Hello", "en", "zh-CN", Translator.Kind.Sentence), "a healthy service translates");
        ling.SimulateCheck = AICheck.Reason.Unreachable;
        await ling.Check();
        await translator.Translate("Hello", "en", "zh-CN", Translator.Kind.Sentence);
        await translator.Translate("Hello", "en", "zh-CN", Translator.Kind.Sentence);
        Equal(2, fake.Calls.Count, "one try while unreachable, the next sentence skips it");
        ling.SimulateCheck = AICheck.Reason.Deaf;
        await ling.Check();
        await translator.Translate("Hello", "en", "zh-CN", Translator.Kind.Sentence);
        Equal(3, fake.Calls.Count, "tried again once the check says it answers");
    }

    public static void JoinsCutSentences()
    {
        var last = new TranscriptLine { Src = "We finished the migration and", SrcLang = "en" };
        Check(ListenEngine.Continues(last, 0.2, new Heard("en", "the error rate dropped.", null)), "mid-sentence cut joins");
        Check(!ListenEngine.Continues(last, 1.5, new Heard("en", "next", null)), "a long gap doesn't");
        Check(!ListenEngine.Continues(new TranscriptLine { Src = "Done.", SrcLang = "en" }, 0.1, new Heard("en", "Next", null)), "after a full stop doesn't");
        Check(!ListenEngine.Continues(last, 0.1, new Heard("ja", "はい", null)), "another language doesn't");
        Equal("我们完成了迁移", ListenEngine.Join("我们完成了", "迁移", "zh-CN"), "CJK joins without a space");
        Equal("a b", ListenEngine.Join("a ", " b", "en"), "others with one space");
    }

    // MARK: Segmenter

    /// A 300 Hz tone that swells and fades four times a second like syllables; steady when not, or
    /// rising and falling by `wobble` twice a second like a fan.
    static short[] Tone(double seconds, double amp = 0.3, bool syllables = true, double wobble = 0) =>
        Enumerable.Range(0, (int)(seconds * 16000)).Select(i => (short)(Math.Sin(2 * Math.PI * 300 * i / 16000)
            * (syllables ? 0.55 + 0.45 * Math.Sin(2 * Math.PI * 4 * i / 16000) : 1 + wobble * Math.Sin(2 * Math.PI * 0.5 * i / 16000))
            * amp * 32767)).ToArray();
    static short[] Silence(double seconds) => new short[(int)(seconds * 16000)];
    /// Typing: a key click every 0.2 s, 6 ms of decaying crackle peaking near -12 dBFS (scripts/vad-clips.py).
    static short[] Keys(double seconds)
    {
        var x = Silence(seconds);
        for (int at = 1600; at < x.Length - 96; at += 3200)
            for (int k = 0; k < 96; k++) x[at + k] = (short)(0.25 * Math.Exp(-k / 24.0) * (k % 2 == 1 ? 1 : -1) * 32767);
        return x;
    }
    /// A sine at `freq` that swells and fades four times a second like syllables.
    static short[] Hz(double freq, double seconds, double amp) =>
        Enumerable.Range(0, (int)(seconds * 16000)).Select(i => (short)(Math.Sin(2 * Math.PI * freq * i / 16000)
            * (0.55 + 0.45 * Math.Sin(2 * Math.PI * 4 * i / 16000)) * amp * 32767)).ToArray();
    /// One word on its own ("Thanks."): a 300 Hz tone that swells from nothing and fades back.
    static short[] Word(double seconds, double amp)
    {
        int n = (int)(seconds * 16000);
        return Enumerable.Range(0, n).Select(i => (short)(Math.Sin(2 * Math.PI * 300 * i / 16000) * Math.Pow(Math.Sin(Math.PI * i / n), 2) * amp * 32767)).ToArray();
    }

    /// A 7 kHz tone faded in and out over 0.3 s: crosses zero like a hiss, swells like a word.
    static short[] Hiss(double seconds, double amp)
    {
        int n = (int)(seconds * 16000);
        return Enumerable.Range(0, n).Select(i => (short)(Math.Sin(2 * Math.PI * 7000 * i / 16000) * Math.Min(1, Math.Min(i / 4800.0, (n - i) / 4800.0)) * amp * 32767)).ToArray();
    }

    static List<Segment> Cut(params short[][] parts)
    {
        var seg = new Segmenter();
        var list = new List<Segment>();
        seg.Emitted += list.Add;
        foreach (var p in parts) for (int i = 0; i < p.Length; i += 1600) seg.Feed(p.AsSpan(i, Math.Min(1600, p.Length - i)));
        seg.Flush();
        return list;
    }

    public static void SegmentsOnPauses()
    {
        var list = Cut(Silence(0.5), Tone(2), Silence(1), Tone(1.5), Silence(1));
        Equal(2, list.Count, "two stretches");
        Check(Math.Abs(list[0].Start - 0.35) < 0.05, $"starts just before the speech (pre-roll), got {list[0].Start}");
        Check(Math.Abs(list[1].Start - 3.35) < 0.05, $"second start, got {list[1].Start}");
        Check(list[0].Seconds is > 2.1 and < 2.4, $"length with lead-in and tail, got {list[0].Seconds}");
    }

    public static void CutsLongSpeechAtItsQuietestMoment()
    {
        // 7 s of speech, a 0.3 s dip (shorter than a pause), 4 s more: one cut, at the dip.
        var list = Cut(Tone(7), Tone(0.3, 0.004), Tone(4), Silence(1));
        Equal(2, list.Count, "split in two");
        Check(list[0].Seconds is > 6.9 and < 7.4, $"cut inside the dip, got {list[0].Seconds}");
        Check(list.All(s => s.Seconds <= 8.0), "no segment over 8 s");
        Check(Math.Abs(list[1].Start - (list[0].Start + list[0].Seconds)) < 0.001, "the rest carries on without a gap");
    }

    public static void KeyClicksAreNotSpeech()
    {
        var list = Cut(Tone(2), Keys(1.5), Tone(1.5), Silence(1));
        Equal(2, list.Count, "clicks in a pause don't hold it open");
        Check(Math.Abs(list[1].Start - 3.35) < 0.06, $"second start, got {list[1].Start}");
        Equal(0, Cut(Silence(0.5), Keys(3), Silence(1)).Count, "typing alone makes no segment");
    }

    public static void IgnoresClicks()
    {
        Equal(0, Cut(Silence(1), Tone(0.1), Silence(1)).Count, "under 0.25 s of sound is not speech");
        Equal(0, Cut(Tone(3, 0.002)).Count, "below the gate is silence");
        Equal(0, Cut(Tone(3, 0.02, syllables: false), Silence(1)).Count, "a steady hum over the gate is not speech");
        Equal(1, Cut(Tone(3), Silence(1)).Count, "speech, which rises and falls, is");
        Equal(1, Cut(Tone(3, 0.03), Silence(1)).Count, "quiet speech, whose dips fall below the gate, is too");
        Equal(1, Cut(Tone(3, 0.022), Silence(1)).Count, "a voice whose loudest frames barely clear the gate dips far between syllables");
        Equal(0, Cut(Tone(4, 0.016, syllables: false, wobble: 0.3), Silence(1)).Count, "a hum at the gate that slowly rises and falls doesn't");
        Equal(1, Cut(Silence(1), Word(0.4, 0.028), Silence(1)).Count, "a quiet word on its own, 0.2 s over the gate");
        Equal(1, Cut(Silence(1), Word(1.2, 0.022), Silence(1)).Count, "one smooth run of voice on its own, no dips inside");
        Equal(1, Cut(Silence(1), Tone(0.5, 0.022, syllables: false), Tone(0.15, 0.0025, syllables: false), Silence(1)).Count,
            "a quiet word whose fade (an \"s\", a breath) falls under gate / 4 still swells: a meeting's quiet opening line");
        // Wherever the 30 ms frames fall (a few ms more lead-in), a quiet phrase with brief dips between
        // its words stays a word, and a hum or a faded hiss in silence stays out.
        short[] Flat(double s, double a) => Tone(s, a, syllables: false);
        short[] phrase = [.. Flat(0.35, 0.022), .. Flat(0.04, 0.0055), .. Flat(0.4, 0.022), .. Flat(0.04, 0.0055), .. Flat(0.35, 0.022), .. Flat(0.06, 0.0025)];
        for (int ms = 0; ms < 30; ms += 2)
        {
            var lead = Silence(1.0 + ms / 1000.0);
            Equal(1, Cut(lead, phrase, Silence(1)).Count, $"a quiet phrase with dips, {ms} ms more lead-in");
            Equal(0, Cut(lead, Flat(1, 0.03), Silence(1)).Count, $"a short hum, {ms} ms more lead-in");
            Equal(0, Cut(lead, Hiss(1, 0.03), Silence(1)).Count, $"a faded hiss, {ms} ms more lead-in");
        }
        Equal(0, Cut(Silence(1), Tone(1, 0.03, syllables: false), Silence(1)).Count, "a short hum in silence doesn't swell and fade");
        Equal(0, Cut(Silence(1), Word(0.15, 0.3), Silence(1)).Count, "nor is a knock a word");
        Equal(0, Cut(Silence(1), Hz(12, 3, 0.1), Silence(1)).Count, "rumble far under 100 Hz is no voice however it swells");
        Equal(1, Cut(Silence(1), Hz(100, 3, 0.3), Silence(1)).Count, "a voice as low as 100 Hz stays");
    }

    public static void LateLoopbackPacketsDontSplitASentence()
    {
        // A VM held packets back for 0.3-0.7 s: silence went in front of them and lines split
        // mid-phrase. The tap now waits a second before it calls a stall silence.
        Equal(0, LoopbackGap.Silence(0.3, 0.3), "a 300 ms stall is no silence");
        Equal(0, LoopbackGap.Silence(0.9, 0.9), "nor is a 900 ms one");
        Equal(16000, LoopbackGap.Silence(1.0, 1.0), "a second of nothing is: all of it goes in");
        Equal(1600, LoopbackGap.Silence(1.1, 0.1), "then what has passed since");
        // The segmenter fed like the tap: speech, a 0.3 s break between words, a 0.5 s stall.
        var whole = Cut(Tone(2), Silence(0.3), Tone(2), Silence(1));
        Equal(1, whole.Count, "one sentence");
        var stalled = Cut(Tone(2), Silence(0.3), new short[LoopbackGap.Silence(0.5, 0.5)], Tone(2), Silence(1));
        Equal(1, stalled.Count, "still one after a late packet");
        var old = Cut(Tone(2), Silence(0.3), Silence(0.5), Tone(2), Silence(1));
        Equal(2, old.Count, "with 300 ms it was split in two");
    }

    public static void WavRoundTrip()
    {
        var pcm = Tone(0.5);
        var path = Path.Combine(Path.GetTempPath(), $"cicada-test-{Environment.ProcessId}.wav");
        File.WriteAllBytes(path, Wav.Bytes(pcm));
        Check(Wav.Read(path).SequenceEqual(pcm), "16 kHz mono reads back exactly");
        File.Delete(path);
        Equal(16000, Wav.Resample(new double[48000], 48000).Length, "48 kHz to 16 kHz");
    }

    // MARK: Notes

    public static void ParsesNotes()
    {
        const string reply = """
        ```json
        {"title": "“发布评审”", "summary": "讨论发布。",
         "topics": [{"start": 0, "title": "进展", "summary": "一句", "points": [{"text": "迁移完成", "evidence": ["L2"]}, "旧格式要点", {"text": "", "evidence": []}],
                     "fishbone": {"question": "为何延期", "branches": [{"label": "测试", "detail": "x", "t": 3, "evidence": ["L1"]}, {"label": "设计", "detail": "y", "evidence": ["L9"]}]}}],
         "conclusions": [{"text": "周五上线", "evidence": ["L1", "L2", "L99"]}],
         "todos": [{"text": "发说明", "owner": "", "evidence": ["L2"]}],
         "terms": [{"name": "Stripe", "note": "支付", "heard": ["Stripe", "Strip"]}]}
        ```
        """;
        var n = NotesEngine.Parse(reply, [1.0, 5.0], 0)!;
        Equal("发布评审", n.Title, "title quotes trimmed");
        Equal(2, n.Topics[0].Points.Count, "empty points dropped, plain strings kept");
        Equal(5.0, n.Topics[0].PointTime(0), "point time from evidence");
        Equal(null, n.Topics[0].PointTime(1), "no evidence, no time");
        Equal(2, n.Topics[0].Fishbone!.Branches.Count, "fishbone kept");
        Equal(0, n.Topics[0].Fishbone!.Branches[1].Support, "evidence beyond the transcript doesn't count");
        Equal(2, n.Conclusions[0].Support, "support counts real lines");
        Equal(null, n.Todos[0].Owner, "empty owner is none");
        Equal("Strip", string.Join(",", n.Terms[0].Heard), "the correct spelling isn't a mishearing");
        Equal(null, NotesEngine.Parse("not json", [], 0), "garbage");
        Equal(null, NotesEngine.Parse("{}", [], 0), "empty notes");
    }

    public static void TopicStartsAtItsFirstCitedLine()
    {
        double[] times = [5, 11, 49, 180];
        var raw = "{\"summary\":\"s\",\"topics\":[{\"start\":289,\"title\":\"发布说明\",\"points\":[{\"text\":\"发给设计组\",\"evidence\":[\"L3\"]}]},{\"start\":999,\"title\":\"别的\",\"points\":[\"x\"]}]}";
        var n = NotesEngine.Parse(raw, times, 0)!;
        Equal(49.0, n.Topics[0].Start, "the cited line's time, not the model's 289");
        Equal(180.0, n.Topics[1].Start, "never after the last line");
        var late = NotesEngine.Parse("{\"summary\":\"s\",\"topics\":[{\"start\":5,\"title\":\"整场\",\"points\":[{\"text\":\"p\",\"evidence\":[\"L4\"]}]}]}", times, 0)!;
        Equal(180.0, late.Topics[0].Start, "the cited lines win over the model's start, as on the Mac");
    }

    public static void KeepsEarliestTimes()
    {
        var old = new MeetingNotes { Topics = [new NoteTopic { Title = "t", Points = ["a"], PointTimes = [3] }], Todos = [new NoteItem { Text = "x", T = 2 }] };
        var next = new MeetingNotes { Topics = [new NoteTopic { Title = "t", Points = ["a", "b"], PointTimes = [9, null] }], Todos = [new NoteItem { Text = "x", T = 8 }] };
        NotesEngine.CarryTimes(old, next);
        Equal(3.0, next.Topics[0].PointTime(0), "a point keeps when it was first heard");
        Equal(2.0, next.Todos[0].T, "to-dos too");
    }

    /// A heard form only a fix wrote ("platform" for 平台) isn't one: it would teach the translator
    /// and the next fix the same mistake.
    public static void NotesTermsKeepOnlyFormsTheRecognizerWrote()
    {
        var l = new TranscriptLine { Id = "a", Speaker = "them", Src = "我们 twoty 平台", SrcLang = "zh-CN", DstLang = "en", Fixes = [new LineFix("平台", "platform")] };
        var terms = new List<NoteTerm> { new() { Name = "X平台", Note = "n", Heard = ["Xplatform", "platform", "Twoty"] } };
        Equal("Twoty", string.Join("|", NotesEngine.HeardAsSaid(terms, [l]).First().Heard), "heard forms");
    }

    public static void NotesAndExportNameSpeakersLikeTheMac()
    {
        // Two voices, five substantive lines each: 说话人 1 (voice 7) and 说话人 2 (voice 9).
        var lines = Enumerable.Range(0, 10).Select(i => new TranscriptLine { Id = $"h{i}-1", T = i * 10, Src = $"we will ship line {i}", Voice = i % 2 == 0 ? 7 : 9, SrcLang = "en", DstLang = "zh-CN" }).ToList();
        var s = new Session { Title = "会议 1月1日 10:00", StartedAt = DateTimeOffset.Now, Lines = lines,
            VoiceNames = new() { ["7"] = "George" }, VoiceGuesses = new() { ["9"] = new VoiceGuess { Name = "Anna" } } };
        var names = SpeakerLabels.Names(s);
        Equal("George,Anna", $"{names[1]},{names[2]}", "the user's name, else Ling's guess");
        var p = NotesEngine.Prompt(new MeetingNotes(), lines, 0, "English", final: true, names);
        Check(p.Contains("[L1 00:00 George]") && p.Contains("[L2 00:10 Anna]"), "named in the notes prompt");
        Check(SessionStore.Markdown(s).Contains("George："), "and in the export");
        try
        {
            SpeakerLabels.Voices = false;
            Check(NotesEngine.Prompt(new MeetingNotes(), lines, 0, "English", final: true).Contains("[L1 00:00 对方]"), "说话人识别 off: no speakers in the notes");
            var md = SessionStore.Markdown(s);
            Check(!md.Contains("George") && !md.Contains("说话人"), "nor in the export");
        }
        finally { SpeakerLabels.Voices = true; }
    }

    public static void NotesPromptIsTheMacs()
    {
        var lines = new List<TranscriptLine> { new() { T = 1, Src = "你好", Speaker = "them" }, new() { T = 65, Src = "我来说", Speaker = "me" } };
        var p = NotesEngine.Prompt(new MeetingNotes(), lines, 0, "Simplified Chinese", final: false);
        Check(p.StartsWith("You keep notes for a meeting that is still going on. Update them with the new lines.\nWrite the notes in Simplified Chinese. Return JSON only.\n"), "opening");
        Check(p.Contains("[L1 00:01 对方] 你好\n[L2 01:05 你] 我来说"), "transcript lines");
        Check(p.Contains("These are the first lines: make one topic."), "first update");
        Check(p.EndsWith("No markdown, no text outside the JSON."), "ending");
        var f = NotesEngine.Prompt(new MeetingNotes(), lines, 0, "English", final: true);
        Check(f.Contains("This meeting ran 01:04: use at most 1 topic."), "final topic limit");
        Check(p.Contains("at most 8 in total") && f.Contains("at most 8 in total"), "with nothing frozen, live and final say the Mac's 8");
        Check(p.Contains("never append to it"), "topic summaries stay one sentence");
        var log = "对方展示AI眼镜后觉得是完全新的体验，提议可以出发回去。" + string.Concat(Enumerable.Repeat("最新对方又补充了一些内容，", 20));
        Equal("对方展示AI眼镜后觉得是完全新的体验，提议可以出发回去。", NotesEngine.Shortened(log), "a runaway summary is cut to its first sentence");
        Equal(NotesEngine.TopicSummaryLimit + 1, NotesEngine.Shortened(new string('长', 200)).Length, "or to the limit");
        Check(NotesEngine.Written(new MeetingNotes { Summary = "讨论发布 Stripe" }, "Simplified Chinese"), "Chinese notes");
        Check(!NotesEngine.Written(new MeetingNotes { Summary = "We talked" }, "Simplified Chinese"), "English isn't Chinese");
    }

    static NoteTopic Topic(double start, string title, List<string>? points = null) =>
        new() { Start = start, Title = title, Summary = "s", Points = points ?? ["p"] };

    static List<TranscriptLine> TenSecondLines(int n) =>
        Enumerable.Range(0, n).Select(i => new TranscriptLine { Id = $"l{i}", T = i * 10, Speaker = "them", Src = $"line {i}", SrcLang = "zh-CN", DstLang = "en" }).ToList();

    static string Titles(IEnumerable<NoteTopic> topics) => string.Join(",", topics.Select(t => t.Title));

    public static void LiveNotesKeepFrozenTopicsAndTakeTheReplysTail()
    {
        var old = Enumerable.Range(0, 5).Select(i => Topic(i * 100, $"t{i}")).ToList();
        // The model echoed everything, renamed the current topic and added one.
        var reply = new List<NoteTopic> { Topic(0, "t0"), Topic(100, "t1 改"), Topic(300, "t3"), Topic(400, "t4 改"), Topic(500, "t5") };
        Equal("t0,t1,t2,t3,t4 改,t5", Titles(NotesEngine.Merge(old, 3, reply)), "frozen kept, the reply's tail after them");
        // The first update over many lines: nothing to echo, so every topic is the model's own.
        var own = Enumerable.Range(0, 5).Select(i => Topic(i * 100, $"t{i}")).ToList();
        Equal(Titles(own), Titles(NotesEngine.Merge([], 0, own)), "nothing frozen keeps every topic");
        Equal(Titles(own), Titles(NotesEngine.Merge([Topic(0, "t0")], 0, own)), "nothing frozen, with old topics");
        var abc = new List<NoteTopic> { Topic(0, "a"), Topic(100, "b"), Topic(200, "c") };
        Equal("a,b,c", Titles(NotesEngine.Merge(abc, 1, [])), "an empty reply keeps the topics");
        Equal("a,b,c", Titles(NotesEngine.Merge(abc, 1, [Topic(0, "a")])), "a reply echoing only frozen topics too");
        static List<NoteTerm> Terms(string names) => [.. names.Split(',').Select(n => new NoteTerm { Name = n })];
        Equal("A,B,C,D", string.Join(",", NoteTerm.KeepingOrder(Terms("A,B,C"), Terms("C,D,A,B")).Select(t => t.Name)), "terms keep their place, new ones after");
        Equal("B,E,D", string.Join(",", NoteTerm.KeepingOrder(Terms("A,B,C"), Terms("E,B,D")).Select(t => t.Name)), "dropped terms leave, new ones keep the reply's order");
    }

    public static void FullLiveNotesJoinTheShortestSettledPair()
    {
        // Twelve topics, t3 and t4 the shortest neighbours (t3 to t5 is 100 s): a new topic
        // still starts, and those two become one.
        double[] starts = [0, 100, 200, 300, 330, 400, 600, 700, 800, 900, 1000, 1100];
        var old = starts.Select((s, i) => Topic(s, $"t{i}", [$"a{i}", $"b{i}", $"c{i}"])).ToList();
        var merged = NotesEngine.Merge(old, 10, [Topic(1000, "t10"), Topic(1100, "t11"), Topic(1200, "t12")]);
        Equal(NotesEngine.LiveMaxTopics, merged.Count, "still at most 12");
        Equal("t12", merged[^1].Title, "the newest topic starts");
        Equal("t3 / t4", merged[3].Title, "the shortest pair joined");
        Equal(300.0, merged[3].Start, "from the first one's start");
        Equal("a3,b3,a4,b4", string.Join(",", merged[3].Points), "points from each");
        Equal("s s", merged[3].Summary, "both summaries");
        var t = Topic(0, "t0");
        t.Summary = "对方展示AI眼镜后觉得是完全新的体验，提议可以出发回去。" + string.Concat(Enumerable.Repeat("最新对方又补充了一些内容，", 20));
        Equal("对方展示AI眼镜后觉得是完全新的体验，提议可以出发回去。", NotesEngine.Merge([], 0, [t])[0].Summary, "merge cuts a runaway summary");
        Equal("short", NotesEngine.Shortened("short"), "a short summary stays");
    }

    public static void LivePromptSendsOnlyTheLatestTopics()
    {
        var notes = new MeetingNotes { Summary = "summary", Topics = [Topic(0, "最早的话题"), Topic(100, "第二个话题"), Topic(200, "当前话题")], Covered = 20 };
        var p = NotesEngine.Prompt(notes, TenSecondLines(24), 20, "Simplified Chinese", final: false, frozen: 1);
        var json = p.Split("Current notes")[1].Split("\n\n")[0];
        Check(p.Contains("Earlier topics") && p.Contains("- 00:00 最早的话题: s"), "frozen topics listed");
        Check(p.Contains("returning only the topics in the current notes"), "the frozen topics rule");
        Check(!json.Contains("最早的话题") && json.Contains("第二个话题") && json.Contains("当前话题"), "only the latest in the JSON");
        Check(!NotesEngine.Prompt(notes, TenSecondLines(24), 20, "Simplified Chinese", final: false).Contains("Earlier topics"), "a full rewrite has nothing frozen");
        var eight = new MeetingNotes { Summary = "summary", Topics = Enumerable.Range(0, 8).Select(i => Topic(i * 10, $"t{i}")).ToList(), Covered = 20 };
        var e = NotesEngine.Prompt(eight, TenSecondLines(24), 20, "English", final: false, frozen: 6);
        Check(!e.Contains("do not start a new topic") && e.Contains("never append to it"), "one-sentence summaries");
    }

    public static void LongMeetingsSplitByTime()
    {
        // A line every 10 s: 90 min stays whole, 4 h becomes four parts of an hour.
        var whole = NotesEngine.Parts(TenSecondLines(540));
        Check(whole.Count == 1 && whole[0].Equals(0..540), "90 minutes stays whole");
        var four = NotesEngine.Parts(TenSecondLines(1440));
        Equal(4, four.Count, "4 hours in four parts");
        Check(four[0].Start.Value == 0 && four[^1].End.Value == 1440, "covering every line");
        Check(four.Zip(four.Skip(1)).All(x => x.First.End.Value == x.Second.Start.Value), "back to back");
        Equal(0, NotesEngine.Parts([]).Count, "no lines, no parts");
        var ten = Enumerable.Range(0, 10).Select(i => Topic(i * 300, $"t{i}")).ToList();
        var kept = NotesEngine.Thinned(ten, 4, 3000);
        Equal(4, kept.Count, "a part's topics thinned to four");
        Equal(0.0, kept[0].Start, "from the first");
        Check(ten.All(t => kept.Any(k => k.Title.Split(" / ").Contains(t.Title))), "every topic joined, none dropped");
        Equal("0", string.Join(",", NotesEngine.Thinned(ten, 1, 3000).Select(t => t.Start)), "one");
        Equal(3, NotesEngine.Thinned(ten.Take(3).ToList(), 4, 3000).Count, "fewer than asked stay");
        // A 2.5-hour meeting's last part, asked for 2 topics, came back with 3: the budget topic's
        // end as its own. Kept first and last, the budget topic at 125 min was lost.
        var part = new List<NoteTopic> { Topic(6000, "营销发布安排", ["a"]), Topic(7500, "预算评审", ["b"]), Topic(8982, "预算评审（续）", ["c"]) };
        var two = NotesEngine.Thinned(part, 2, 8990);
        Equal("营销发布安排,预算评审", Titles(two), "the topic kept over its continuation");
        Equal("6000,7500", string.Join(",", two.Select(t => t.Start)), "at its own start");
        Equal("b,c", string.Join(",", two[1].Points), "with the continuation's points");
        var other = new List<NoteTopic> { Topic(6000, "营销发布安排"), Topic(7500, "预算评审"), Topic(8982, "收尾") };
        Equal("6000,7500", string.Join(",", NotesEngine.Thinned(other, 2, 8990).Select(t => t.Start)), "a stub joins the topic it ends");
        Equal("Budget review", NotesEngine.Subject("Budget review (cont.)"), "subject without the bracket");
        Equal("(续)", NotesEngine.Subject("(续)"), "a bracket alone stays");
    }

    public static void PartPromptKeepsLineNumbers()
    {
        var all = TenSecondLines(720);
        var p = NotesEngine.Prompt(new MeetingNotes(), all.Take(480).ToList(), 240, "English", final: true, part: (2, 3));
        Check(p.Contains("part 2 of 3"), "which part");
        Check(p.Contains("[L241 40:00 对方] line 240") && !p.Contains("[L238 "), "the transcript's own line numbers");
        Check(p.Contains("This part ran 39:50"), "the part's length");
        // Each of three parts gets two of the eight topics.
        Check(p.Contains("use at most 2 topics"), "the part's share of the topics");
        var merge = NotesEngine.MergePrompt(["{\"summary\":\"a\"}", "{\"summary\":\"b\"}"], all, "English", voices: false);
        Check(merge.Contains("Part 2 of 2:\n{\"summary\":\"b\"}"), "the parts' notes");
        Check(merge.Contains("Return the full notes as one JSON object") && merge.Contains("\"topics\": []"), "the format, topics kept in code");
    }

    public static void TopicStartsWhenItsLinesWereSaid()
    {
        var times = Enumerable.Range(0, 100).Select(i => i * 60.0).ToList();
        var raw = """
        {"summary": "s", "topics": [
          {"start": 1380, "title": "late", "summary": "s", "points": [{"text": "a", "evidence": ["L86"]}, {"text": "b", "evidence": ["L52"]}], "evidence": ["L60"]},
          {"start": 300, "title": "no evidence", "summary": "s", "points": ["c"]}]}
        """;
        var n = NotesEngine.Parse(raw, times, 0)!;
        Equal("3060,300", string.Join(",", n.Topics.Select(t => t.Start)), "the earliest cited line, else the model's start");
    }

    // MARK: Strings

    /// The notes store a to-do's owner as the transcript's Chinese label; it shows and exports in the UI language.
    public static void TodoOwnersShowInTheUILanguage()
    {
        var res = Path.Combine(AppContext.BaseDirectory, "Resources");
        try
        {
            Strings.Load(res, "en");
            Equal("Them", new NoteItem { Owner = "对方" }.OwnerShown, "them");
            Equal("You", new NoteItem { Owner = "你" }.OwnerShown, "you");
            Equal("Speaker 2", new NoteItem { Owner = "说话人2" }.OwnerShown, "speaker");
            Equal("Alice", new NoteItem { Owner = "Alice" }.OwnerShown, "a name stays");
            var s = new Session { Notes = new MeetingNotes { Summary = "s", Todos = [new NoteItem { Text = "Send the deck", Owner = "对方" }] } };
            Check(SessionStore.Markdown(s).Contains("- [ ] Send the deck (Them)"), "export: " + SessionStore.Markdown(s));
            Equal("Misheard words fixed: 3", Strings.LF("改了 %lld 处听错的词", 3), "banner");
            Strings.Load(res, "zh-Hans");
            Equal("发资料（对方）", new NoteItem { Text = "发资料", Owner = "对方" }.WithOwner, "Chinese");
        }
        finally { Strings.Load(res, "zh-Hans"); }
    }

    public static void LoadsTheMacsTranslations()
    {
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "en");
        Equal("Live notes", Strings.L("实时纪要"), "an English string");
        Equal("没有这条", Strings.L("没有这条"), "missing keys show the Chinese");
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
        Equal("实时纪要", Strings.L("实时纪要"), "Chinese is the key");
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "en");
        var s = new Session { Title = "会议 11月4日 10:27", StartedAt = new DateTimeOffset(2026, 11, 4, 10, 27, 0, TimeSpan.Zero) };
        Check(!SessionStore.DisplayTitle(s).Contains('月'), "English dates whatever Windows' language: " + SessionStore.DisplayTitle(s));
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
        var t = Strings.Parse("/* c */\n\"a \\\"b\\\"\" = \"x\\ny\";\n// line\n\"%@ 分钟\" = \"%@ min\";");
        Equal("x\ny", t["a \"b\""], "escapes");
        Equal("%@ min", t["%@ 分钟"], "placeholders kept");
        Equal("3 分钟", Strings.LF("%@ 分钟", 3), "LF fills %@");
        Equal("正在下载 1.3.0：59%", Strings.LF("正在下载 %@：%lld%%", "1.3.0", 59), "%% is one percent sign");
        Equal("1 句", Strings.LF("%lld 句", 1), "Chinese has no plural forms");
    }

    public static void PluralsFromTheMacsStringsdict()
    {
        var res = Path.Combine(AppContext.BaseDirectory, "Resources");
        try
        {
            Strings.Load(res, "en");
            Equal("1 line", Strings.LF("%lld 句", 1), "one");
            Equal("2 lines", Strings.LF("%lld 句", 2), "other");
            Equal("0 lines", Strings.LF("%lld 句", 0), "zero is other in English");
            Equal("Heard 1 line", Strings.LF("已听到 %lld 句", 1), "text around the plural");
            Equal("12:00 · 1 line", Strings.LF("%@ · %lld 句", "12:00", 1), "positional %2$#@n@ after %1$@");
            Equal("Recorded 03:15 · 1 line. Ending stops listening and writes the full notes.",
                  Strings.LF("已记录 %@ · %lld 句。结束后停止收听，并整理一份完整版纪要。", "03:15", 1), "the end-meeting question");
            Equal("1 point", Strings.LF("%lld 条要点", 1L), "a long counts too");
            Equal("Live notes", Strings.L("实时纪要"), "plain strings still load");
            Strings.Load(res, "ja");
            Equal("1文", Strings.LF("%lld 句", 1), "no stringsdict: the .strings value");
            var p = Strings.ParsePlurals("<?xml version=\"1.0\"?>\n<!DOCTYPE plist>\n<plist version=\"1.0\"><dict><key>a &amp; b</key><dict>" +
                "<key>NSStringLocalizedFormatKey</key><string>%#@x@ &lt;</string><key>x</key><dict><key>one</key><string>%lld y</string>" +
                "<key>other</key><string>%lld ys</string></dict></dict></dict></plist>");
            Equal("%#@x@ <", p["a & b"].Format, "entities");
            Equal("%lld ys", p["a & b"].Forms["x"]["other"], "forms");
        }
        finally { Strings.Load(res, "zh-Hans"); }
    }

    // MARK: Ling

    sealed class Fake(Func<string, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public readonly List<(DateTime at, string body)> Calls = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var body = await request.Content!.ReadAsStringAsync(cancel);
            lock (Calls) Calls.Add((DateTime.UtcNow, body));
            return respond(body);
        }
    }

    static HttpResponseMessage Reply(string content, string? finish = "stop") => new(HttpStatusCode.OK)
    {
        Content = new StringContent(new JsonObject
        {
            ["choices"] = new JsonArray(new JsonObject { ["message"] = new JsonObject { ["content"] = content }, ["finish_reason"] = finish }),
            ["usage"] = new JsonObject { ["prompt_tokens"] = 1, ["completion_tokens"] = 1 },
        }.ToJsonString()),
    };

    static LingClient Client(Fake fake, GateClock? clock = null)
    {
        var key = new AIKey(new PlainProtector());
        key.Save("sk-test-0000000000");
        return new LingClient(key, fake, clock: clock);
    }

    /// The start gate's time, moved on by each wait instead of waiting (one request at a time).
    sealed class FakeClock : GateClock
    {
        public DateTime Now = new(2026, 11, 5, 12, 0, 0, DateTimeKind.Utc);
        public readonly DateTime Start = new(2026, 11, 5, 12, 0, 0, DateTimeKind.Utc);
        public readonly List<double> Waits = [];
        public override DateTime UtcNow => Now;
        public override Task Delay(TimeSpan wait) { Waits.Add(wait.TotalSeconds); Now += wait; return Task.CompletedTask; }
    }

    static HttpResponseMessage Busy(string? retryAfter = null)
    {
        var r = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
        if (retryAfter is not null) r.Headers.TryAddWithoutValidation("Retry-After", retryAfter);
        return r;
    }

    public static async Task LingRequestShape()
    {
        var fake = new Fake(_ => Reply("ok"));
        var ling = Client(fake);
        await ling.Chat("the content", "Translate.", Priority.Translate, model: LingClient.AudioModel, audio: [1, 2, 3]);
        var body = JsonNode.Parse(fake.Calls[0].body)!;
        Equal("disabled", body["thinking"]!["type"]!.GetValue<string>(), "thinking disabled");
        Equal("system", body["messages"]![0]!["role"]!.GetValue<string>(), "content in the system message");
        Equal("the content", body["messages"]![0]!["content"]!.GetValue<string>(), "content");
        Equal("audio_url", body["messages"]![1]!["content"]![0]!["type"]!.GetValue<string>(), "audio first");
        Equal("data:audio/wav;base64,AQID", body["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>(), "WAV as a data URL");
        Equal("Translate.", body["messages"]![1]!["content"]![1]!["text"]!.GetValue<string>(), "fixed instruction last");
    }

    public static async Task LingDropsHijackedAndRefusedReplies()
    {
        foreach (var (reply, finish) in new[] { ("根据现有检索证据，……", "stop"), ("作为一个人工智能语言模型，这个问题超出……", "stop"), ("fine", (string?)null) })
        {
            var ling = Client(new Fake(_ => Reply(reply, finish)));
            try { await ling.Chat("c", "i", Priority.Translate); throw new Exception($"accepted «{reply}»"); }
            catch (LingException e) { Equal(LingException.Kind.Hijacked, e.Failure, "dropped as hijacked"); }
        }
    }

    public static async Task LingHeardAudioRidesOutARunOf429s()
    {
        // Ling's 429s come in runs (two in a row lost a line with one retry): heard audio backs off
        // 1, 2, 4 s and gets through; text translation fails at once so the caller can fall back.
        int calls = 0;
        var clock = new FakeClock();
        var fake = new Fake(_ => Interlocked.Increment(ref calls) <= 3 ? Busy() : Reply("LANG: en\nORIGINAL: Hi.\nTRANSLATION: 嗨。"));
        var reply = await Client(fake, clock).Chat("c", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]);
        Check(reply.Contains("ORIGINAL: Hi."), "the fourth attempt answered");
        Equal(4, calls, "three retries");
        Equal(3, clock.Waits.Count, "a wait before each");
        double[] backoff = [1, 2, 4];
        for (int i = 0; i < 3; i++) Check(clock.Waits[i] >= backoff[i] && clock.Waits[i] <= backoff[i] + 0.5, $"backoff {string.Join(",", clock.Waits)}");
        var text = Client(new Fake(_ => Busy()), new FakeClock());
        try { await text.Chat("c", "i", Priority.Translate); throw new Exception("text translation retried"); }
        catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "text fails fast"); }
    }

    public static async Task LingHeardAudioIsLostOnlyAfterAnOutage()
    {
        var clock = new FakeClock();
        var fake = new Fake(_ => Busy());
        var ling = Client(fake, clock);
        try { await ling.Chat("c", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]); throw new Exception("no failure"); }
        catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "rate limited in the end"); }
        Equal(5, fake.Calls.Count, "the first try and four retries");
        Check((clock.Now - clock.Start).TotalSeconds >= 15, $"about 15 s of trying, got {(clock.Now - clock.Start).TotalSeconds}");
        Check(ling.RateLimitedAt is not null, "reported busy");
    }

    public static async Task LingWaitsAsLongAsRetryAfterAsks()
    {
        int calls = 0;
        var clock = new FakeClock();
        var fake = new Fake(_ => Interlocked.Increment(ref calls) == 1 ? Busy("5") : Reply("ok"));
        Equal("ok", await Client(fake, clock).Chat("c", "i", Priority.Notes), "answered after the wait");
        Check(clock.Waits[0] is >= 5 and <= 5.5, $"waited as asked, got {clock.Waits[0]}");
        // Asked to wait minutes: an outage, so the line goes now rather than after it.
        var outage = new Fake(_ => Busy("120"));
        try { await Client(outage, new FakeClock()).Chat("c", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]); throw new Exception("waited"); }
        catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "given up"); }
        Equal(1, outage.Calls.Count, "no retry into an outage");
        var now = new DateTimeOffset(2026, 11, 5, 12, 0, 0, TimeSpan.Zero);
        Equal(3.0, LingClient.RetryAfterSeconds(new(TimeSpan.FromSeconds(3)), now), "a delay");
        Equal(7.0, LingClient.RetryAfterSeconds(new(now.AddSeconds(7)), now), "a date");
        Equal(null, LingClient.RetryAfterSeconds(null, now), "none");
    }

    public static async Task LingA429HoldsEveryStartWhileTheServiceCoolsDown()
    {
        int calls = 0;
        var clock = new FakeClock();
        var fake = new Fake(_ => Interlocked.Increment(ref calls) == 1 ? Busy() : Reply("notes"));
        var ling = Client(fake, clock);
        try { await ling.Chat("first", "i", Priority.Translate); } catch (LingException) { }
        // A translation that wouldn't retry fails at once, without spending a request on the limit…
        try { await ling.Chat("second", "i", Priority.Translate); throw new Exception("sent during the pause"); }
        catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "busy"); }
        Equal(1, fake.Calls.Count, "nothing sent");
        // …and one that would waits at the gate until the pause is over, then goes.
        Equal("notes", await ling.Chat("notes", "i", Priority.Notes), "notes after the pause");
        Check(clock.Waits.Sum() is >= 1 and <= 1.5, $"held for the pause, got {string.Join(",", clock.Waits)}");
    }

    public static async Task LingARetriedLineKeepsItsPlaceInTheQueue()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0.05;
        try
        {
            int first = 0;
            var fake = new Fake(b => b.Contains("\"content\":\"a\"") && Interlocked.Increment(ref first) == 1 ? Busy() : Reply("ok"));
            var ling = Client(fake);
            var a = ling.Chat("a", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]);
            await Task.Delay(200);
            var b = ling.Chat("b", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]);
            await Task.WhenAll(a, b);
            var order = fake.Calls.Select(c => JsonNode.Parse(c.body)!["messages"]![0]!["content"]!.GetValue<string>()).ToList();
            Equal("a,a,b", string.Join(",", order), "the retry goes first");
            Check((fake.Calls[2].at - fake.Calls[0].at).TotalSeconds >= 1.0, "b waited out the pause");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task LingMarksABadKey()
    {
        var ling = Client(new Fake(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized)));
        try { await ling.Chat("c", "i", Priority.Translate); } catch (LingException e) { Equal(LingException.Kind.InvalidKey, e.Failure, "401"); }
        Equal(KeyState.Invalid, ling.KeyState, "key state");
        Check(!ling.Usable, "no longer usable");
    }

    public static async Task LingGateSpacesStartsAndServesPriorityFirst()
    {
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.2;
        try
        {
            var fake = new Fake(_ => Reply("ok"));
            var ling = Client(fake);
            var first = ling.Chat("first", "i", Priority.Notes);
            await Task.Delay(20);
            // Queued while the gate is closed: the translation goes before the earlier notes call.
            var notes = ling.Chat("notes", "i", Priority.Notes);
            await Task.Delay(20);
            var translate = ling.Chat("translate", "i", Priority.Translate);
            await Task.WhenAll(first, notes, translate);
            var order = fake.Calls.Select(c => JsonNode.Parse(c.body)!["messages"]![0]!["content"]!.GetValue<string>()).ToList();
            Equal("first,translate,notes", string.Join(",", order), "priority order");
            for (int i = 1; i < fake.Calls.Count; i++)
                Check((fake.Calls[i].at - fake.Calls[i - 1].at).TotalSeconds >= 0.18, "starts spaced");
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: Voices

    public static void FbankMatchesKaldi()
    {
        var x = new short[19200];
        for (int t = 0; t < x.Length; t++)
            x[t] = (short)Math.Round(8000 * Math.Sin(2 * Math.PI * 220 * t / 16000) + 3000 * Math.Sin(2 * Math.PI * 1375 * t / 16000) + 1500 * Math.Sin(2 * Math.PI * 3100 * t / 16000 * (1 + t / 19200.0)));
        var f = Fbank.Features(x)!;
        var fx = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "fbank.json")))!;
        Equal(fx["frames"]!.GetValue<int>() * Fbank.Bins, f.Length, "frame count");
        foreach (var (row, values) in fx["rows"]!.AsObject())
        {
            int r = int.Parse(row);
            var want = values!.AsArray().Select(v => v!.GetValue<double>()).ToArray();
            var worst = Enumerable.Range(0, Fbank.Bins).Max(b => Math.Abs(f[r * Fbank.Bins + b] - want[b]));
            Check(worst < 2e-3, $"row {r} off by {worst:F5} from numpy/Kaldi");
        }
        Check(Fbank.Features(new short[4000]) is null, "under 0.5 s gives no voiceprint");
    }

    static float[] Unit(params float[] v) { var n = MathF.Sqrt(v.Sum(x => x * x)); return v.Select(x => x / n).ToArray(); }

    public static void ClustersVoicesAsTheMacDoes()
    {
        var c = new VoiceClusterer();
        Check(c.Label(Unit(1, 0, 0), 1.0) is null, "a short first line starts no voice");
        Equal(0, c.Label(Unit(1, 0, 0), 3.0), "a long one does");
        Equal(0, c.Label(Unit(0.9f, 0.3f, 0), 1.0), "a similar line joins it, even short");
        Equal(1, c.Label(Unit(0, 1, 0), 2.5), "a long unlike line is a new voice");
        Check(c.Label(Unit(0, 0, 1), 1.0) is null, "a short unlike line stays 对方");
    }

    public static void NumbersVoicesOnceTwoHaveSaidEnough()
    {
        TranscriptLine L(int i, int? v, string text = "we should ship it") => new() { Id = $"h{i}", Speaker = "them", Src = text, Voice = v };
        var lines = new List<TranscriptLine>();
        for (int i = 0; i < 5; i++) lines.Add(L(i, 7));
        Equal(0, SpeakerLabels.Numbers(lines).Count, "one voice alone: still 对方");
        for (int i = 5; i < 9; i++) lines.Add(L(i, 3));
        lines.Add(L(9, 3, "yeah"));
        Equal(0, SpeakerLabels.Numbers(lines).Count, "\"yeah\" doesn't count towards a name");
        lines.Add(L(10, 3, "我们下周一定上线"));
        var n = SpeakerLabels.Numbers(lines);
        Check(n["h0"] == 1 && n["h10"] == 2 && !n.ContainsKey("h20"), "numbers in the order voices got there");
    }

    sealed class FakePrint(Func<short[], float[]?> f) : IVoiceprint { public float[]? Embed(short[] s) => f(s); }

    // MARK: 电脑和会议室

    static EchoMatch.Heard H(string t, double s, double e) => new(t, s, e);

    public static void TheRoomsCopyOfARemoteSentenceIsAnEcho()
    {
        // EchoMatchTests on the Mac, case for case.
        List<EchoMatch.Heard> online = [H("Revenue grew by 12%, mostly from the new region.", 10, 14)];
        Check(EchoMatch.IsEcho(H("revenue grew by 12% mostly from new region", 10.3, 14.2), online), "heard worse, a word lost");
        Check(!EchoMatch.IsEcho(H("I think we should check the numbers for Europe first", 11, 15), online), "room speech is kept");
        Check(!EchoMatch.IsEcho(H("我觉得应该先看一下欧洲的情况", 11, 15), online), "room speech in Chinese is kept");
        Check(EchoMatch.IsEcho(H("这个季度的数据收入增长了百分之十二", 0.8, 4), [H("我们先看一下这个季度的数据。", 0, 2), H("收入增长了百分之十二，主要来自新的市场。", 2.2, 5)]), "cut differently");
        Check(!EchoMatch.IsEcho(H("can everyone hear me okay", 20, 22), [H("Can everyone hear me okay?", 0, 2)]), "the same words long after");
        Check(EchoMatch.IsEcho(H("ok", 5.2, 5.6), [H("OK.", 5, 5.5)]) && !EchoMatch.IsEcho(H("no", 5.2, 5.6), [H("OK.", 5, 5.5)]), "short lines only exactly");
    }

    public static void EchoGateClosesForTheHang()
    {
        double now = 100;
        var g = new EchoGate(() => now);
        Check(!g.Closed, "open");
        g.Hold();
        now = 100.3; Check(g.Closed, "closed just after loud audio");
        now = 100 + EchoGate.Hang + 0.01; Check(!g.Closed, "open after the hang");
        var echo = new EchoFilter(g);
        Check(echo.Quiet(H("x", 104, 105)), "nothing played around a later line");
        Check(!echo.Quiet(H("x", 101, 102)), "the computer played just before");
        var pump = new Pump();
        var room = new GatedSource(pump) { Silenced = () => g.Closed };
        short[]? got = null;
        room.Samples += b => got = b;
        pump.Push([100, -100]);
        Check(got is [100, -100], "the room passes while the computer is quiet");
        g.Hold();
        pump.Push([100, -100]);
        Check(got is [0, 0], "silence while the gate is closed");
        now += 1; room.Muted = true;
        pump.Push([100, -100]);
        Check(got is [0, 0], "silence while you hold the talk key");
    }

    public static void EchoGateOnlyForSpeechThatReachesTheMic()
    {
        double now = 0;
        var g = new EchoGate(() => now);
        // Music: loud, and no words for EchoGate.Music seconds.
        for (; now < EchoGate.Music - 1; now += 0.1) g.Hold();
        Check(g.Closed && !g.PlayingMusic, "no words yet: still taken for speech");
        for (; now < EchoGate.Music + 1; now += 0.1) g.Hold();
        Check(g.PlayingMusic, "no words for long: music");
        now += EchoGate.Hang + 0.01; g.Hold(); now += 0.01;
        Check(!g.Closed, "music doesn't close the gate");
        g.HeardWords(); g.Hold(); now += 0.1;
        Check(g.Closed, "words close it again");

        // Headphones: the room mic stays at its floor while the computer plays.
        now = 1000;
        var h = new EchoGate(() => now);
        Check(h.Echo, "echo until measured");
        for (var t = 0; t < 60; t++) { h.Hold(); now += 0.05; h.RoomLevel(0.001, 0.1); now += 0.05; }
        for (var t = 0; t < 60; t++) { now += 0.1; h.RoomLevel(0.001, 0.1); }
        Check(!h.Echo, "no echo measured with headphones");
        h.Hold(); now += 0.1;
        Check(!h.Closed, "the room stays open with headphones");
        // Speakers: the mic hears the computer.
        now += 100;
        for (var t = 0; t < 60; t++) { h.Hold(); now += 0.05; h.RoomLevel(0.03, 0.1); now += 0.05; }
        for (var t = 0; t < 60; t++) { now += 0.1; h.RoomLevel(0.001, 0.1); }
        Check(h.Echo, "echo again once the speakers reach the mic");
        Check(EchoGate.Ratio([(0.001, 1)], [(0.001, 10)]) is null, "not enough to tell");
    }

    sealed class Pump : IAudioSource
    {
        public event Action<short[]>? Samples;
        public event Action<string?>? Ended { add { } remove { } }
        public void Push(short[] b) => Samples?.Invoke(b);
        public void Start() { }
        public void Stop() { }
    }

    public static void PlacesShowOnlyWhenBothWereHeard()
    {
        TranscriptLine L(string id, string speaker = "them", string? via = null) => new() { Id = id, Speaker = speaker, Via = via };
        Check(!Places.HeardBoth([L("a"), L("b")]), "the computer alone");
        Check(!Places.HeardBoth([L("a", via: "room"), L("b", "me")]), "my own lines aren't the computer's");
        Check(Places.HeardBoth([L("a", via: "room"), L("b")]), "both");
        var starts = Places.Starts([L("a"), L("b"), L("c", via: "room"), L("d", "me"), L("e", via: "room"), L("f")]);
        Check(starts.SetEquals(["a", "c", "e", "f"]), "a change of place starts a run: " + string.Join(",", starts));
    }

    public static async Task TheRoomSideDropsTheSpeakersAndKeepsTheTable()
    {
        // The computer plays one sentence; the room mic hears it again from the speakers, then
        // someone at the table says something else.
        const string remote = "LANG: en\nORIGINAL: Revenue grew by 12%, mostly from the new region.\nTRANSLATION: 收入增长了 12%，主要来自新区域。";
        const string table = "LANG: en\nORIGINAL: I think we should check the numbers for Europe first\nTRANSLATION: 我觉得应该先看欧洲的数字";
        var fake = new Fake(body =>
        {
            if (!body.Contains("Ming-3.0-audio-flash")) return Reply("{}");
            var url = JsonNode.Parse(body)!["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>();
            return Reply(url.Length < 140_000 ? remote : table);
        });
        var old = LingClient.Spacing; LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var settings = new AppSettings { Target = "zh-CN", SpeakerVoices = false };
            var notes = new NotesEngine(ling, store);
            var main = new ListenEngine(ling, new Translator(ling), store, notes, settings);
            var room = new ListenEngine(ling, new Translator(ling), store, notes, settings, roomSide: true);
            var echo = new EchoFilter(new EchoGate());
            main.Echo = echo; room.Echo = echo;
            string Wave(string name, short[] pcm)
            {
                var path = Path.Combine(Path.GetTempPath(), $"cicada-{name}-{Environment.ProcessId}.wav");
                File.WriteAllBytes(path, Wav.Bytes(pcm));
                return path;
            }
            var computer = new FileAudioSource(Wave("computer", [.. Tone(2), .. Silence(1)]), speed: 0);
            var mic = new FileAudioSource(Wave("mic", [.. Tone(2, 0.05), .. Silence(1), .. Tone(4, 0.05), .. Silence(1)]), speed: 0);
            var done = new TaskCompletionSource[] { new(), new() };
            computer.Ended += _ => done[0].TrySetResult();
            mic.Ended += _ => done[1].TrySetResult();
            main.Start(computer);
            var started = store.Get(main.SessionId!)!.StartedAt;
            room.Join(mic, main.SessionId!, started);
            await Task.WhenAll(done[0].Task, done[1].Task);
            await Task.Delay(TimeSpan.FromSeconds(EchoMatch.Hold + 1.5));
            await room.Stop();
            await main.Stop();
            var s = store.Get(main.SessionId!)!;
            var theirs = s.Lines.Where(l => l.Via == "room").ToList();
            Equal(1, s.Lines.Count(l => l.Via is null), "the computer's line");
            Equal(1, theirs.Count, "the speakers' copy dropped, the table kept: " + string.Join(" | ", s.Lines.Select(l => $"{l.Via}:{l.Src}")));
            Check(theirs[0].Src.Contains("Europe") && theirs[0].Id.StartsWith("h1000001-100000"), "the table's line, in the room's ids: " + theirs[0].Id);
            Equal(true, s.Room, "a room meeting");
            Check(Places.HeardBoth(s.Lines), "heard both");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task NeverJoinsTwoVoices()
    {
        // Two halves of one "sentence" (no full stop, 0.4 s apart) in two different voices.
        var fake = new Fake(body =>
        {
            if (!body.Contains("Ming-3.0-audio-flash")) return Reply("{}");
            var url = JsonNode.Parse(body)!["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>();
            return Reply(url.Length < 110_000 ? "LANG: en\nORIGINAL: so what we need\nTRANSLATION: 所以我们需要" : "LANG: en\nORIGINAL: is a plan for Monday\nTRANSLATION: 周一的计划");
        });
        var old = LingClient.Spacing; LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var engine = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), new AppSettings { Target = "zh-CN" })
            {
                // Told apart by length: the first stretch is 2.5 s, the second 3 s.
                Voiceprint = new FakePrint(s => s.Length < 50_000 ? Unit(1, 0, 0) : Unit(0, 1, 0)),
            };
            var path = Path.Combine(Path.GetTempPath(), $"cicada-voices-{Environment.ProcessId}.wav");
            File.WriteAllBytes(path, Wav.Bytes([.. Tone(2.5), .. Silence(0.7), .. Tone(3), .. Silence(1)]));
            var src = new FileAudioSource(path, speed: 0);
            var ended = new TaskCompletionSource();
            src.Ended += _ => ended.TrySetResult();
            engine.Start(src);
            await ended.Task;
            await Task.Delay(100);
            await engine.Stop();
            var lines = store.All().First().Lines;
            Equal(2, lines.Count, "two voices, two lines (not joined)");
            Check(lines[0].Voice == 0 && lines[1].Voice == 1, "each with its voice");
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: Speaking

    sealed class Sink : ISpeechSink
    {
        public int Rate; public readonly List<byte[]> Chunks = [];
        public void Begin(int rate) => Rate = rate;
        public void Write(byte[] pcm) => Chunks.Add(pcm);
        public Task End() => Task.CompletedTask;
        public bool Ready { get; init; } = true;
    }

    sealed class NoVoice : ISystemVoice
    {
        public int Calls;
        public Task<(byte[] pcm, int rate)?> Speak(string text, string language) { Calls++; return Task.FromResult<(byte[], int)?>((new byte[480], 16000)); }
        public bool Has(string language) => true;
    }

    public static void ParsesMingVoiceStream()
    {
        var pcm = LingClient.SpeechChunk("data:{\"type\":\"speech.audio.delta\",\"audio\":\"AQIDBA==\"}", out var done);
        Check(!done && pcm is { Length: 4 } && pcm[3] == 4, "a delta carries its PCM");
        LingClient.SpeechChunk("data:{\"type\":\"speech.audio.done\"}", out done);
        Check(done, "done ends the stream");
        Check(LingClient.SpeechChunk(": keep-alive", out _) is null && LingClient.SpeechChunk("data:{oops", out _) is null, "noise is skipped");
    }

    public static void PicksTheRoomsLanguage()
    {
        Equal("en", SpeakEngine.TargetFor("room", "en", "zh-CN"), "the language the other side speaks");
        Equal("en", SpeakEngine.TargetFor("room", null, "zh-CN"), "English before anyone spoke");
        Equal("en", SpeakEngine.TargetFor("room", "zh-CN", "zh-CN"), "never my own language");
        Equal("zh-CN", SpeakEngine.TargetFor("room", "en", "en"), "an English speaker in an English room gets Chinese");
        Equal("ja", SpeakEngine.TargetFor("ja", "en", "zh-CN"), "a chosen language wins");
    }

    public static void ChecksTheVirtualCablePackage()
    {
        Check(!VirtualCable.Verify("not the package"u8.ToArray()), "anything else is refused");
        Equal(64, VirtualCable.PackageSha256.Length, "a full SHA-256 is pinned");
    }

    public static void GivesTheSpeakerBackAfterTheCableInstall()
    {
        static bool cable(string id) => id.StartsWith("cable");
        var before = new Dictionary<string, string> { ["0/0"] = "realtek", ["0/1"] = "realtek", ["0/2"] = "headset", ["1/0"] = "mic", ["1/2"] = "cable-out" };
        var after = new Dictionary<string, string> { ["0/0"] = "cable-in", ["0/1"] = "cable-in", ["0/2"] = "headset", ["1/0"] = "cable-out", ["1/1"] = "cable-out", ["1/2"] = "cable-out" };
        var back = CableDefaults.Restore(before, after, cable);
        Equal("0/0=realtek 0/1=realtek 1/0=mic", string.Join(" ", back.Select(r => $"{r.Key}={r.Id}")),
            "only the defaults the cable took from a real device; one already on the cable, or unknown before, stays");
        Equal(0, CableDefaults.Restore(before, before, cable).Count, "nothing changed, nothing to do");
        Equal("realtek", CableDefaults.Speaker([("cable-in", true), ("realtek", false)]), "the first real speaker");
        Equal(null, CableDefaults.Speaker([("cable-in", true)]), "no real speaker");
        Check(CableDefaults.ShouldNotify(true, false), "told once");
        Check(!CableDefaults.ShouldNotify(true, true), "not again while it stays on the cable");
        Check(!CableDefaults.ShouldNotify(false, false), "a real speaker: nothing to say");
    }

    static SpeakEngine Speaker(LingClient ling, NoVoice voice, AppSettings? settings = null) =>
        new(ling, new Translator(ling, new Fake(_ => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable))), new SessionStore(), settings ?? new AppSettings(), () => "en", () => null, voice);

    public static async Task SpeaksTheTranslationNeverTheOriginal()
    {
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.01;
        try
        {
            // Ming hears and translates; Ming's voice streams two chunks.
            var spoken = new List<string>();
            var fake = new Fake(body =>
            {
                if (body.Contains(LingClient.AudioModel)) return Reply("LANG: zh-CN\nORIGINAL: 我们周三能测完吗？\nTRANSLATION: Can we finish testing by Wednesday?");
                if (body.Contains(LingClient.VoiceModel))
                {
                    lock (spoken) spoken.Add(JsonNode.Parse(body)!["input"]!.GetValue<string>());
                    return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("data:{\"type\":\"speech.audio.delta\",\"audio\":\"AAABAA==\"}\n\ndata:{\"type\":\"speech.audio.delta\",\"audio\":\"AgADAA==\"}\n\ndata:{\"type\":\"speech.audio.done\"}\n\n") };
                }
                return Reply("x");
            });
            var voice = new NoVoice();
            var sink = new Sink();
            var engine = Speaker(Client(fake), voice, new AppSettings { SpeakFrom = "zh-CN" });
            var heard = await engine.Speak(Wav.Bytes(Tone(1)), sink);
            Equal("Can we finish testing by Wednesday?", heard, "the room hears the translation");
            Equal("Can we finish testing by Wednesday?", spoken.Single(), "and only it is voiced");
            Check(sink.Rate == 24000 && sink.Chunks.Count == 2, "Ming's 24 kHz stream reaches the virtual mic");
            Equal("ming", engine.LastVoice, "voiced by Ming");

            // No translation (Ming echoes the original, Ling and Google fail): nothing reaches the room.
            var echo = new Fake(body => body.Contains(LingClient.AudioModel)
                ? Reply("LANG: zh-CN\nORIGINAL: 我们周三能测完吗？\nTRANSLATION: 我们周三能测完吗？")
                : new HttpResponseMessage(HttpStatusCode.InternalServerError));
            var quiet = new Sink();
            var voice2 = new NoVoice();
            var e2 = Speaker(Client(echo), voice2, new AppSettings { SpeakFrom = "zh-CN" });
            Check(await e2.Speak(Wav.Bytes(Tone(1)), quiet) is null, "no translation, nothing said");
            Check(quiet.Chunks.Count == 0 && voice2.Calls == 0 && e2.State == SpeakEngine.Phase.Failed, "and no voice at all");

            // The virtual mic went away during the press: nothing is played anywhere (never the speakers).
            var gone = new Sink { Ready = false };
            var voice3 = new NoVoice();
            var e3 = Speaker(Client(fake), voice3, new AppSettings { SpeakFrom = "zh-CN" });
            Check(await e3.Speak(Wav.Bytes(Tone(1)), gone) is null, "no virtual mic, nothing said");
            Check(gone.Chunks.Count == 0 && voice3.Calls == 0 && e3.State == SpeakEngine.Phase.Failed, "and no voice at all");
            Equal("没有虚拟麦克风 · 没有说出去", e3.Problem, "the bar says why");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task SilencesFillersAndEchoAreNotSent()
    {
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.01;
        try
        {
            var asked = 0;
            var reply = "LANG: zh-CN\nORIGINAL: 嗯。\nTRANSLATION: Hmm.";
            var fake = new Fake(body =>
            {
                if (body.Contains(LingClient.AudioModel)) { Interlocked.Increment(ref asked); return Reply(reply); }
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("data:{\"type\":\"speech.audio.done\"}\n\n") };
            });
            var engine = Speaker(Client(fake), new NoVoice(), new AppSettings { SpeakFrom = "zh-CN" });
            // A press nobody spoke in: not even sent to the service.
            Check(await engine.Speak(Wav.Bytes(new short[16000 * 3]), new Sink()) is null && asked == 0, "a silent press sends nothing");
            Check(engine.State == SpeakEngine.Phase.Idle && engine.Problem is null, "and says nothing about it");
            // Ming heard only 嗯: nothing goes out.
            Check(await engine.Speak(Wav.Bytes(Tone(1)), new Sink()) is null && asked == 1, "a filler alone isn't sent");
            // The computer played through the press: its echo, not me.
            double now = 0;
            var log = new LoudnessLog(() => now);
            engine.Echo = log;
            engine.BeginRecording();
            for (var i = 0; i < 30; i++) { log.Add(true); now += 0.1; }
            Check(await engine.Speak(Wav.Bytes(Tone(1)), new Sink()) is null && asked == 1, "pressed while the meeting played: not sent");
            Equal(Strings.L("对方在说话时说的，没有说出去"), engine.Problem, "and the bar says why");
            // The same press through Windows' echo cancellation: the meeting is taken out, I am sent.
            reply = "LANG: zh-CN\nORIGINAL: 我们周三能测完吗？\nTRANSLATION: Can we finish testing by Wednesday?";
            engine.BeginRecording();
            for (var i = 0; i < 30; i++) { log.Add(true); now += 0.1; }
            Equal("Can we finish testing by Wednesday?", await engine.Speak(Wav.Bytes(Tone(1)), new Sink(), echoCancelled: true), "pressed while the meeting played, echo cancelled: sent");
            Check(asked == 2 && engine.Problem is null, "and heard by the service");
            // Echo cancellation doesn't let a silent press through.
            engine.BeginRecording();
            for (var i = 0; i < 30; i++) { log.Add(true); now += 0.1; }
            Check(await engine.Speak(Wav.Bytes(new short[16000 * 3]), new Sink(), echoCancelled: true) is null && asked == 2, "a silent press still sends nothing");
        }
        finally { LingClient.Spacing = old; }
        Check(PressSpeech.Filler("嗯嗯。") && PressSpeech.Filler("Um, uh...") && !PressSpeech.Filler("嗯，好的。") && !PressSpeech.Filler("OK."), "fillers");
        Check(PressSpeech.Filler("翻译结果：") && PressSpeech.Filler("Translation:") && !PressSpeech.Filler("我想补充三点：价格、时间和人手。"), "a bare heading is no sentence");
    }

    public static void EchoIsDroppedOnlyFromThePlainMic()
    {
        Check(SpeakEngine.EchoDrop(false, 0.51), "plain mic, meeting over half the press: dropped");
        Check(!SpeakEngine.EchoDrop(false, 0.5), "half exactly: kept, as before");
        Check(!SpeakEngine.EchoDrop(true, 1.0), "echo cancelled: never dropped as echo");
        var aec = EchoCancel.Effect;
        var ns = new Guid("6f64adbf-8211-11e2-8c70-2c27d7f001fa");
        Check(!EchoCancel.InEffect(null), "no effects list (Windows 10): plain");
        Check(!EchoCancel.InEffect([]), "nothing listed: plain");
        Check(!EchoCancel.InEffect([new(ns, false, true)]), "noise suppression alone isn't echo cancellation");
        Check(!EchoCancel.InEffect([new(aec, false, false)]), "AEC listed but off: plain");
        Check(EchoCancel.InEffect([new(ns, false, true), new(aec, false, true)]), "AEC on: cancelled");
        Check(EchoCancel.CanTurnOn([new(aec, true, false)]) && !EchoCancel.CanTurnOn([new(aec, false, false)]) && !EchoCancel.CanTurnOn([new(aec, true, true)]), "only an AEC that is off and may be set is turned on");
        var m = PressSpeech.Measure(Wav.Bytes(Tone(1)));
        Check(m.Spoken && m.Summary.StartsWith("voiced ") && m.Summary.Contains("dBFS"), $"the press measure is logged: {m.Summary}");
        Check(!PressSpeech.Measure(Wav.Bytes(new short[100])).Spoken, "too short to measure");
    }

    public static async Task WhatISayGoesAheadOfTheMeeting()
    {
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.2;
        try
        {
            var fake = new Fake(body => body.Contains(LingClient.AudioModel)
                ? Reply("LANG: zh-CN\nORIGINAL: 好的\nTRANSLATION: OK")
                : body.Contains(LingClient.VoiceModel) ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("data:{\"type\":\"speech.audio.done\"}\n\n") } : Reply("ok"));
            var ling = Client(fake);
            var first = ling.Chat("meeting 1", "i", Priority.Translate);
            await Task.Delay(20);
            var queued = ling.Chat("meeting 2", "i", Priority.Translate);
            await Task.Delay(20);
            var said = Speaker(ling, new NoVoice(), new AppSettings { SpeakFrom = "zh-CN" }).Speak(Wav.Bytes(Tone(1)), new Sink());
            await Task.WhenAll(first, queued, (Task)said);
            var order = fake.Calls.Select(c => c.body.Contains(LingClient.AudioModel) ? "hear" : c.body.Contains("meeting 2") ? "meeting 2" : c.body.Contains("meeting 1") ? "meeting 1" : "other").ToList();
            Equal("meeting 1,hear,meeting 2", string.Join(",", order.Where(o => o != "other")), "my words jump the queue");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ListenEngineEndToEndWithAFakeMing()
    {
        // Two stretches of "speech", told apart by length (1 s, then 1.6 s); the fake Ming
        // answers the first one slower, and lines still come out in order.
        var fake = new Fake(body =>
        {
            if (body.Contains("Ming-3.0-audio-flash"))
            {
                var url = JsonNode.Parse(body)!["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>();
                bool first = url.Length < 60_000; // base64 of ~1.3 s at 32 kB/s, with lead-in and tail
                if (first) Thread.Sleep(400);
                return Reply(first ? "LANG: en\nORIGINAL: First one.\nTRANSLATION: 第一句。" : "LANG: en\nORIGINAL: Second one.\nTRANSLATION: 第二句。");
            }
            return Reply("{}");
        });
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var notes = new NotesEngine(ling, store);
            var engine = new ListenEngine(ling, new Translator(ling), store, notes, new AppSettings { Target = "zh-CN" });
            var path = Path.Combine(Path.GetTempPath(), $"cicada-e2e-{Environment.ProcessId}.wav");
            File.WriteAllBytes(path, Wav.Bytes([.. Tone(1), .. Silence(1), .. Tone(1.6), .. Silence(1)]));
            var src = new FileAudioSource(path, speed: 0);
            var ended = new TaskCompletionSource();
            src.Ended += _ => ended.TrySetResult();
            engine.Start(src);
            await ended.Task;
            await Task.Delay(100);
            await engine.Stop();
            var s = store.Get(engine.SessionId!)!;
            Equal("First one.|Second one.", string.Join("|", s.Lines.Select(l => l.Src)), "in segment order");
            Equal("第一句。", s.Lines[0].Dst, "translation from the same call");
            Equal("h1-1", s.Lines[0].Id, "Mac-style ids");
            Check(s.EndedAt is not null, "ended");
            File.Delete(path);
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: Updates (the Mac's UpdateCheckerTests)

    static string Rel(string tag, params string[] assets) =>
        $$"""{"tag_name":"{{tag}}","html_url":"https://example.com/{{tag}}","assets":[{{string.Join(",", assets.Select(a => $$"""{"name":"{{a}}","browser_download_url":"https://example.com/{{a}}","size":1048576}"""))}}]}""";

    public static void UpdateVersionsCompareByNumber()
    {
        Check(UpdateChecker.IsNewer("2.10.0", "2.9.1"), "2.10 > 2.9");
        Check(UpdateChecker.IsNewer("1.4.1", "1.4"), "1.4.1 > 1.4");
        Check(!UpdateChecker.IsNewer("1.4.0", "1.4"), "1.4.0 = 1.4");
        Check(!UpdateChecker.IsNewer("1.3.9", "1.4.0"), "older");
    }

    public static void UpdateNotifiesOncePerVersionWhenIdle()
    {
        Check(UpdateChecker.ShouldNotify("1.1.0", null, false), "first time");
        Check(UpdateChecker.ShouldNotify("1.2.0", "1.1.0", false), "a newer version");
        Check(!UpdateChecker.ShouldNotify("1.1.0", "1.1.0", false), "already told");
        Check(!UpdateChecker.ShouldNotify("1.1.0", null, true), "held while listening");
        Equal("ab12", UpdateChecker.ChecksumFor("ff00  Cicada-1.1.0-Windows-ARM64.exe\nAB12 *Cicada-1.1.0-Windows-x64.exe\n", "Cicada-1.1.0-Windows-x64.exe"), "sha256sum line");
        Equal(null, UpdateChecker.ChecksumFor("ff00  Cicada-1.1.0-Windows-ARM64.exe", "Cicada-1.1.0-Windows-x64.exe"), "other file");
    }

    /// The in-app download: the installer is kept only when it matches checksums.txt.
    public static async Task UpdateDownloadChecksTheInstaller()
    {
        var dir = Directory.CreateTempSubdirectory("cicada-upd-").FullName;
        var exe = Path.Combine(dir, "Cicada-1.1.0-Windows-x64.exe");
        File.WriteAllText(exe, "installer");
        var sha = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(exe)));
        File.WriteAllText(Path.Combine(dir, "checksums.txt"), $"{sha}  Cicada-1.1.0-Windows-x64.exe\n");
        File.WriteAllText(Path.Combine(dir, "bad.txt"), "0000  Cicada-1.1.0-Windows-x64.exe\n");
        var checker = new UpdateChecker(null, _ => { });
        var u = new UpdateChecker.Update("1.1.0", "https://example.com", null, 9, new Uri(exe).AbsoluteUri, new Uri(Path.Combine(dir, "checksums.txt")).AbsoluteUri);
        var got = await checker.Download(u);
        Equal("installer", File.ReadAllText(got), "downloaded copy");
        Check(got != exe && Path.GetFileName(got) == "Cicada-1.1.0-Windows-x64.exe", "into its own folder, same name");
        try { await checker.Download(u with { Checksums = new Uri(Path.Combine(dir, "bad.txt")).AbsoluteUri }); throw new Exception("bad checksum accepted"); }
        catch (UpdateChecker.Failure f) { Equal("下载的文件校验不通过", f.Key, "bad checksum refused"); }
        try { await checker.Download(u with { Setup = null }); throw new Exception("zip-only accepted"); }
        catch (UpdateChecker.Failure f) { Equal("这个版本没有可安装的文件", f.Key, "nothing to install"); }
        UpdateChecker.CleanDownloads(Path.GetDirectoryName(Path.GetDirectoryName(got)));
        Check(!File.Exists(got), "left-over installer removed");
    }

    /// A release served over HTTP: checksums.txt, then the installer through `body`.
    sealed class Release(byte[] installer, Func<byte[], Stream> body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var name = Path.GetFileName(request.RequestUri!.LocalPath);
            HttpContent content = name == "checksums.txt"
                ? new StringContent($"{Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(installer))}  Cicada-1.3.0-Windows-x64.exe\n")
                : new StreamContent(body(installer));
            if (name != "checksums.txt") content.Headers.ContentLength = installer.Length;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        }
    }

    /// Sends `data` in `chunk`-sized pieces, then (when `stallAt` is reached) nothing at all.
    sealed class Trickle(byte[] data, int chunk, long stallAt = long.MaxValue) : Stream
    {
        long at;
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancel = default)
        {
            if (at >= stallAt) { await Task.Delay(Timeout.Infinite, cancel); }
            var n = (int)Math.Min(Math.Min(chunk, buffer.Length), data.Length - at);
            data.AsMemory((int)at, n).CopyTo(buffer);
            at += n;
            await Task.Yield();
            return n;
        }
        public override int Read(byte[] buffer, int offset, int count) => ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
        public override bool CanRead => true; public override bool CanSeek => false; public override bool CanWrite => false;
        public override long Length => data.Length; public override long Position { get => at; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long o, SeekOrigin s) => throw new NotSupportedException();
        public override void SetLength(long v) => throw new NotSupportedException();
        public override void Write(byte[] b, int o, int c) => throw new NotSupportedException();
    }

    /// A slow download keeps going and reports progress up to 100 %; one that stops sending fails
    /// after the stall limit, not after a fixed total time.
    public static async Task UpdateDownloadFailsOnAStallNotOnSlowness()
    {
        var installer = new byte[300_000];
        Random.Shared.NextBytes(installer);
        var u = new UpdateChecker.Update("1.3.0", "https://example.com", null, installer.Length,
            "https://example.com/Cicada-1.3.0-Windows-x64.exe", "https://example.com/checksums.txt");
        var progress = new List<double>();
        var slow = new UpdateChecker(null, _ => { }, new Release(installer, d => new Trickle(d, 1000))) { Stall = TimeSpan.FromMilliseconds(500) };
        var got = await slow.Download(u, progress.Add);
        Check(File.ReadAllBytes(got).AsSpan().SequenceEqual(installer), "whole file written");
        Equal(1.0, progress[^1], "progress reaches 100 %");
        Check(progress.Count <= 101, "whole percents only");
        UpdateChecker.CleanDownloads(Path.GetDirectoryName(Path.GetDirectoryName(got)));

        var stuck = new UpdateChecker(null, _ => { }, new Release(installer, d => new Trickle(d, 1000, stallAt: 100_000))) { Stall = TimeSpan.FromMilliseconds(300) };
        var t = DateTime.UtcNow;
        try { await stuck.Download(u); throw new Exception("a stalled download succeeded"); }
        catch (UpdateChecker.Failure f) { Equal("下载失败", f.Key, "stall reported as a failed download"); }
        Check((DateTime.UtcNow - t).TotalSeconds < 5, "fails soon after the stall");
    }

    /// The system proxy watch: polled from the first unreachable result; a change made while a
    /// check runs is still acted on once that check ends unreachable; a reachable result stops it.
    public static void ProxyWatchKeepsAChangeMadeDuringACheck()
    {
        var w = new ProxyWatch();
        var proxy = "1|10.0.2.2:7890|";
        Check(!w.Update(false, false, () => proxy), "reachable: not polled");
        Check(!w.Update(false, true, () => proxy), "a check from a good state: not polled");
        Check(w.Update(true, false, () => proxy), "unreachable: polled");
        Check(!w.Changed(proxy, false), "same settings");
        Check(w.Update(false, true, () => proxy), "kept through the next check");
        proxy = "0||";
        Check(!w.Changed(proxy, true), "not while the check runs");
        Check(w.Update(true, false, () => proxy), "the check ended unreachable");
        Check(w.Changed(proxy, false), "the change made during it now counts");
        Check(!w.Changed(proxy, false), "once");
        Check(!w.Update(false, false, () => proxy), "reachable: stopped");
        Check(!w.Changed("1|x|", false), "stopped means no changes reported");
    }

    public static void UpdateSkipsReleasesWithoutAWindowsZip()
    {
        var list = UpdateChecker.Decode($"[{Rel("v1.6.0", "Cicada-1.6.0-macOS-AppleSilicon.zip")},{Rel("v1.5.0", "Cicada-1.5.0-Windows-x64.zip", "Cicada-1.5.0-Windows-ARM64.zip")}]")!;
        var u = UpdateChecker.NewestWindows(list, "x64")!;
        Equal("1.5.0", u.Version, "newest with a Windows zip");
        Equal("https://example.com/Cicada-1.5.0-Windows-x64.zip", u.Zip, "this PC's zip");
        Equal(1048576L, u.Size, "size");
        Equal("https://example.com/Cicada-1.5.0-Windows-ARM64.zip", UpdateChecker.NewestWindows(list, "ARM64")!.Zip, "ARM zip");
    }

    public static void UpdateOnArmFallsBackToX64AndSkipsDrafts()
    {
        var draft = Rel("v2.0.0", "Cicada-2.0.0-Windows-x64.zip").Replace("\"tag_name\"", "\"draft\":true,\"tag_name\"");
        var list = UpdateChecker.Decode($"[{draft},{Rel("v1.5.0", "Cicada-1.5.0-Windows-x64.zip")}]")!;
        var u = UpdateChecker.NewestWindows(list, "ARM64")!;
        Equal("1.5.0", u.Version, "draft skipped");
        Equal("https://example.com/Cicada-1.5.0-Windows-x64.zip", u.Zip, "x64 on ARM");
        Equal(1, UpdateChecker.Decode(Rel("v1.5.0"))!.Count, "a single release");
        Equal(null, UpdateChecker.Decode("{\"message\":\"Not Found\"}"), "GitHub's 404");
        Equal(null, UpdateChecker.Decode("<html>"), "not JSON");
        // A release with the installer: it's what to download, on each architecture.
        var withSetup = UpdateChecker.Decode("""
            [{"tag_name":"v1.6.0","html_url":"https://example.com/r","assets":[
              {"name":"Cicada-1.6.0-Windows-x64.zip","browser_download_url":"https://example.com/z","size":5},
              {"name":"Cicada-1.6.0-Windows-x64.exe","browser_download_url":"https://example.com/setup","size":7},
              {"name":"Cicada-1.6.0-Windows-ARM64.exe","browser_download_url":"https://example.com/setup-arm","size":8}]},
             {"tag_name":"v1.7.0","html_url":"https://example.com/r2","assets":[
              {"name":"Cicada-1.7.0-Windows-x64.exe","browser_download_url":"https://example.com/setup2","size":9}]}]
            """)!;
        var x = UpdateChecker.NewestWindows(withSetup, "x64")!;
        Equal("1.7.0", x.Version, "a release with only the installer counts");
        Equal("https://example.com/setup2", x.Download, "the installer is the download");
        var older = UpdateChecker.NewestWindows(withSetup.Take(1), "ARM64")!;
        Equal("https://example.com/setup-arm", older.Download, "ARM's installer");
        Equal(8L, older.Size, "its size");
        // 1.1.0's installer names still count, so a release carrying only those is found too.
        var legacy = UpdateChecker.Decode("""
            [{"tag_name":"v1.1.0","html_url":"https://example.com/r","assets":[
              {"name":"Cicada-Setup.exe","browser_download_url":"https://example.com/old","size":3},
              {"name":"Cicada-Setup-arm64.exe","browser_download_url":"https://example.com/old-arm","size":4}]}]
            """)!;
        Equal("https://example.com/old", UpdateChecker.NewestWindows(legacy, "x64")!.Download, "1.1.0's x64 name");
        Equal("https://example.com/old-arm", UpdateChecker.NewestWindows(legacy, "ARM64")!.Download, "1.1.0's ARM name");
    }

    public static void UpdateDueAfterTheAge()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        Check(UpdateChecker.Due(null, now, UpdateChecker.Every), "never checked");
        Check(!UpdateChecker.Due(now.AddHours(-1), now, UpdateChecker.Every), "an hour ago");
        Check(UpdateChecker.Due(now.AddHours(-4), now, UpdateChecker.Every), "4 hours ago");
        Check(UpdateChecker.Due(now.AddHours(2), now, UpdateChecker.Every), "clock set back");
    }

    public static async Task UpdateCheckReadsAFeedFile()
    {
        var file = Path.Combine(Path.GetTempPath(), $"cicada-feed-{Environment.ProcessId}.json");
        File.WriteAllText(file, $"[{Rel("v9.0.0", "Cicada-9.0.0-Windows-x64.zip", "Cicada-9.0.0-Windows-ARM64.zip")}]");
        DateTimeOffset? saved = null;
        var c = new UpdateChecker(null, at => saved = at) { Feed = file, Current = "1.0.0" };
        try
        {
            Check(await c.Check(), "reached");
            Equal("9.0.0", c.Available?.Version, "found");
            Check(saved is not null && c.LastChecked == saved, "remembered");
            c.Current = "9.0.0";
            await c.Check();
            Equal(null, c.Available, "up to date");
            c.Feed = file + ".missing";
            Check(!await c.Check(), "unreachable");
        }
        finally { File.Delete(file); }
    }

    // MARK: AI 服务 (other services than Ling: linux/tests/test_providers.py, case for case)

    /// Answers every request with `respond(url, body)` and records where each went.
    sealed class Service(Func<string, string, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public readonly List<(string url, string body)> Sent = [];
        /// The key each request carried ("Bearer …"), in the order of Sent.
        public readonly List<string?> Auth = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancel);
            var url = request.RequestUri!.ToString();
            lock (Sent) { Sent.Add((url, body)); Auth.Add(request.Headers.Authorization?.ToString()); }
            return respond(url, body);
        }
    }

    static (LingClient ling, AppSettings settings) Using(Service fake, string provider = "zenmux", string? key = "sk-test-0000000000", AppSettings? s = null)
    {
        s ??= new AppSettings();
        s.AiProvider = provider;
        var k = new AIKey(new PlainProtector(), service: () => s.AiProvider);
        k.Remove();
        if (key is not null) k.Save(key);
        return (new LingClient(k, fake, s.AIConfig), s);
    }

    static HttpResponseMessage Status(int code, string body = "{}") => new((HttpStatusCode)code) { Content = new StringContent(body) };

    public static void ServicesDefaultToTheirRecommendedModels()
    {
        var c = new AppSettings { AiProvider = "zenmux" }.AIConfig();
        Equal("https://zenmux.ai/api/v1/", c.Base, "base");
        Equal("qwen/qwen3.8-omni-flash", c.HearModel, "hear");
        Equal("inclusionai/ling-3.0-flash", c.TextModel, "text");
        Equal("google/gemini-3.8-flash-tts", c.VoiceModel, "voice");
        var ling = new AppSettings().AIConfig();
        Equal(("Ming-3.0-audio-flash", "Ling-3.1-flash"), (ling.HearModel, ling.TextModel), "Ling");
        Equal("Ling-3.0-flash", new AppSettings { Model = "Ling-3.0-flash" }.AIConfig().TextModel, "Ling keeps its own key");
        Equal("ling", AIProvider.Named("openai").Id, "OpenAI isn't offered: Ling");
        Equal(0.6, AIProvider.Ling.Spacing, "Ling's gate");
        Equal(0.1, AIProvider.ZenMux.Spacing, "the aggregators'");
    }

    public static void ChosenModelsAndACustomService()
    {
        var s = new AppSettings { AiProvider = "openrouter", AiHearModels = { ["openrouter"] = "google/gemini-3.1-flash-lite" } };
        Equal("google/gemini-3.1-flash-lite", s.AIConfig().HearModel, "chosen hear model");
        s = new AppSettings { AiProvider = "custom", AiCustomBase = "localhost:11434/v1", AiModels = { ["custom"] = "qwen3:14b" } };
        var c = s.AIConfig();
        Equal("http://localhost:11434/v1/", c.Base, "local address");
        Equal("", c.HearModel, "no hear model yet");
        Check(!c.HasVoices, "no voices without a speech model");
        s.AiVoiceModels["custom"] = "kokoro"; s.AiCustomVoice = "af_heart";
        Equal(("kokoro", "http://localhost:11434/v1/"), (s.AIConfig().VoiceModel, s.AIConfig().VoiceBase), "speech model on the same address");
        Equal("af_heart", s.AIConfig().Voices.Single().Id, "the one voice named");
    }

    public static void CustomAddress()
    {
        Equal("https://api.example.com/v1/", AIProvider.CustomBase("api.example.com/v1"), "https by default");
        Equal("http://127.0.0.1:1234/v1/", AIProvider.CustomBase("127.0.0.1:1234/v1"), "http on this computer");
        Equal(null, AIProvider.CustomBase("http://api.example.com/v1"), "http only on this computer");
        Equal(null, AIProvider.CustomBase(" "), "nothing");
    }

    public static void TheLocalNetworkMayUsePlainHttp()
    {
        foreach (var ok in new[] { "http://192.168.1.20:8000/v1", "10.0.0.5:8000/v1", "http://172.20.1.1/v1", "http://100.101.102.103:8000/v1",
                     "http://169.254.3.4/v1", "http://gpu.local:30000/v1", "http://GPU.LOCAL/v1", "http://[fd12:3456::1]:8000/v1", "http://[fe80::1]/v1", "http://[::1]:8000/v1" })
            Check(AIProvider.CustomBase(ok)?.StartsWith("http://") == true, ok);
        foreach (var no in new[] { "http://172.32.0.1/v1", "http://172.15.0.1/v1", "http://100.128.0.1/v1", "http://100.63.0.1/v1", "http://8.8.8.8/v1",
                     "http://192.169.1.1/v1", "http://gpu.example.com/v1", "http://10.0.0.5.evil.com/v1", "http://[2001:db8::1]/v1" })
            Equal(null, AIProvider.CustomBase(no), no);
        Equal("http://192.168.1.20:8000/v1/", AIProvider.CustomBase("192.168.1.20:8000/v1"), "no scheme on the local network: http");
        Equal("https://10.0.0.5.evil.com/v1/", AIProvider.CustomBase("10.0.0.5.evil.com/v1"), "a name that looks like one: https");
        Check(AIProvider.IsNearby("http://192.168.1.20:8000/v1/") && !AIProvider.IsLocal("http://192.168.1.20:8000/v1/"), "nearby but not this computer");
        var (ling, s) = Using(new Service((_, _) => Reply("ok")), "custom", key: null, new AppSettings { AiCustomBase = "http://192.168.1.20:8000/v1" });
        Equal("", ling.CurrentKey(), "a service on the local network needs no key");
    }

    public static void ACustomHearModelMayHaveItsOwnAddress()
    {
        var s = new AppSettings { AiProvider = "custom", AiCustomBase = "http://192.168.1.20:8000/v1", AiHearModels = { ["custom"] = "qwen3-omni" } };
        Equal("http://192.168.1.20:8000/v1/", s.AIConfig().HearBase, "empty: the text model's address");
        Check(!s.AIConfig().HearElsewhere, "same address");
        s.AiCustomHearBase = "192.168.1.21:8001/v1";
        Equal("http://192.168.1.21:8001/v1/", s.AIConfig().HearBase, "its own");
        Check(s.AIConfig().HearElsewhere, "elsewhere");
        s.AiCustomHearBase = "http://example.com/v1";
        Equal(null, s.AIConfig().HearBase, "http off the local network is no address");
        Equal("https://zenmux.ai/api/v1/", new AppSettings { AiProvider = "zenmux" }.AIConfig().HearBase, "other services: theirs");
        Equal("https://api.ant-ling.com/v1/", new AppSettings().AIConfig().HearBase, "Ling");
        // Not reaching a hear server of its own says nothing about the text address.
        Equal((AICheck.StepId.Hear, AICheck.Reason.Unreachable, (int?)null), AICheck.Classify(LingException.Kind.Network, 0, AICheck.StepId.Hear, hearElsewhere: true), "hear elsewhere");
        Equal((AICheck.StepId.Reach, AICheck.Reason.Unreachable, (int?)null), AICheck.Classify(LingException.Kind.Timeout, 0, AICheck.StepId.Hear), "same address");
    }

    public static void ACustomServiceIsAskedNotToThink()
    {
        var c = new AppSettings { AiProvider = "custom", AiCustomBase = "https://x.example/v1" }.AIConfig();
        var body = new JsonObject();
        c.Shape(body, 50);
        Equal("{\"enable_thinking\":false}", body["chat_template_kwargs"]?.ToJsonString(), "Qwen3 on vLLM / SGLang / llama.cpp");
        var plain = new JsonObject();
        c.Shape(plain, 50, templateKwargs: false);
        Check(plain["chat_template_kwargs"] is null, "left out for a server that refused it");
        var zen = new JsonObject();
        new AppSettings { AiProvider = "zenmux" }.AIConfig().Shape(zen, 50);
        Check(zen["chat_template_kwargs"] is null, "only a custom service");
    }

    public static void AThinkingModelIsSeenFromItsReply()
    {
        static JsonNode R(string message, string? usage = null) => JsonNode.Parse($"{{\"choices\":[{{\"message\":{message}}}]{(usage is null ? "" : ",\"usage\":" + usage)}}}")!;
        Check(!AIConfig.Thought(R("{\"content\":\"周五发布。\"}")), "a plain answer");
        Check(AIConfig.Thought(R("{\"content\":\"周五发布。\",\"reasoning_content\":\"The user wants…\"}")), "reasoning_content");
        Check(AIConfig.Thought(R("{\"content\":null,\"reasoning_content\":\"周五发布。\"}")), "the answer in reasoning_content");
        Check(AIConfig.Thought(R("{\"content\":\"周五发布。\",\"reasoning\":\"hmm\"}")), "reasoning");
        Check(AIConfig.Thought(R("{\"content\":\"<think>hmm</think>周五发布。\"}")), "<think>");
        Check(AIConfig.Thought(R("{\"content\":\"周五发布。\"}", "{\"completion_tokens_details\":{\"reasoning_tokens\":212}}")), "reasoning tokens");
        Check(!AIConfig.Thought(R("{\"content\":\"周五发布。\",\"reasoning_content\":\"  \"}", "{\"completion_tokens_details\":{\"reasoning_tokens\":0}}")), "blank and zero");
        Check(!AIConfig.Thought(null), "no reply");
        Check(!new AICheck.Speed(0.4, false).Slow && new AICheck.Speed(0.4, true).Slow && new AICheck.Speed(3.0, false).Slow, "slow: thinks, or 3 s and more");
    }

    public static async Task ACustomCheckTranslatesASentenceAndRetriesWithoutKwargs()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            // A strict gateway refuses chat_template_kwargs; the model thinks, its answer in reasoning_content.
            var fake = new Service((url, body) =>
                body.Contains("chat_template_kwargs") ? Status(400)
                : url.EndsWith("/models") ? Status(404)
                : body.Contains("input_audio") ? Reply("NONE")
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"choices\":[{\"message\":{\"content\":null,\"reasoning_content\":\"我们将在周五发布。\"},\"finish_reason\":\"stop\"}]}") });
            var (ling, s) = Using(fake, "custom", key: null, new AppSettings
            {
                AiCustomBase = "http://192.168.1.20:8000/v1", AiCustomHearBase = "http://192.168.1.21:8001/v1",
                AiModels = { ["custom"] = "qwen3" }, AiHearModels = { ["custom"] = "qwen3-omni" },
            });
            await ling.Check();
            var first = fake.Sent[0];
            Check(first.url == "http://192.168.1.20:8000/v1/chat/completions" && first.body.Contains("chat_template_kwargs") && first.body.Contains("design review"), "a real sentence, thinking off");
            Check(!fake.Sent[1].body.Contains("chat_template_kwargs") && fake.Sent[1].body.Contains("design review"), "asked again without it");
            const string text = "http://192.168.1.20:8000/v1/chat/completions", hear = "http://192.168.1.21:8001/v1/chat/completions";
            Check(fake.Sent.Skip(2).Where(x => x.url == text).All(x => !x.body.Contains("chat_template_kwargs")), "and not sent it again");
            var heard = fake.Sent.Where(x => x.url == hear).ToList();
            Check(heard.Count == 2 && heard[0].body.Contains("input_audio") && heard[0].body.Contains("chat_template_kwargs") && !heard[1].body.Contains("chat_template_kwargs"),
                "the hear model at its own address, which refused it on its own");
            Check(ling.Health.Translate is { Thinks: true } && ling.Health.Slow, ling.Health.Summary);
            Check(ling.Health.SlowLine()!.Contains("先思考"), "says why");
            Check(ling.Health.SlowLine()!.Contains("Google"), "and that Google stands in");
            Check(ling.Health.SlowLine(googleOff: true) is { } only && only.Contains("先思考") && only.Contains("不等它了") && !only.Contains("Google"),
                "语音和文字只发给你的服务: no Google to fall back on");
            Equal(AICheck.Kind.Ok, ling.Health[AICheck.StepId.Hear].Kind, "hears");
            ling.KeyChanged();
            fake.Sent.Clear();
            try { await ling.Chat("x", "Translate.", Priority.Translate); } catch (LingException) { } // its answer is all reasoning
            Check(fake.Sent[0].body.Contains("chat_template_kwargs"), "settings changed: tried again");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ARefusalForSomethingElseKeepsThinkingOff()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            // No JSON mode on this server (OpenRouter's Novita for Ling 3.1 Flash): 400 with or
            // without the kwargs. Asked again without JSON mode.
            var fake = new Service((url, body) => body.Contains("response_format") ? Status(400) : Reply("好"));
            var (ling, _) = Using(fake, "custom", key: null, new AppSettings { AiCustomBase = "http://192.168.1.20:8000/v1", AiModels = { ["custom"] = "m" } });
            Equal("好", await ling.Chat("x", "Notes.", Priority.Translate, json: true), "answered without JSON mode");
            var last = fake.Sent[^1].body;
            Check(!last.Contains("response_format") && last.Contains("chat_template_kwargs"), "thinking stays off");
            await ling.Chat("y", "Translate.", Priority.Translate);
            Check(fake.Sent[^1].body.Contains("chat_template_kwargs"), "and is not dropped for later requests");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ACheckPassesAModelThatAnswersJSONWithoutJSONMode()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var s = new AppSettings { AiCustomBase = "http://192.168.1.20:8000/v1", AiModels = { ["custom"] = "m" }, AiHearModels = { ["custom"] = "m" } };
            var fake = new Service((url, body) => url.EndsWith("/models") ? Status(404) : body.Contains("response_format") ? Status(400)
                : body.Contains("JSON object") ? Reply("```json\n{\"ok\": true}\n```") : Reply("周五发布。"));
            var (ling, _) = Using(fake, "custom", key: null, s);
            await ling.Check();
            Check(ling.Health[AICheck.StepId.Text].Kind == AICheck.Kind.Ok && ling.Health.Failure?.Why != AICheck.Reason.NoJSON, ling.Health.Summary);
            // One that can't answer JSON at all still fails.
            var plain = new Service((url, body) => url.EndsWith("/models") ? Status(404) : body.Contains("response_format") ? Status(400) : Reply("ok"));
            var (other, _) = Using(plain, "custom", key: null, s);
            await other.Check();
            Equal(AICheck.Reason.NoJSON, other.Health.Failure?.Why, "no JSON either way");
            Equal(400, other.Health.Failure?.Code, "the refusal's code");
        }
        finally { LingClient.Spacing = old; }
    }

    public static void AJSONObjectInPlainTextCountsAsJSON()
    {
        Check(LingClient.AnswersJSON("{\"ok\": true}"), "bare");
        Check(LingClient.AnswersJSON("```json\n{\"ok\": true}\n```"), "fenced");
        Check(LingClient.AnswersJSON("Sure: {\"ok\": true}."), "in a sentence");
        Check(!LingClient.AnswersJSON("ok") && !LingClient.AnswersJSON("[1]") && !LingClient.AnswersJSON("} {") && !LingClient.AnswersJSON(null), "none");
    }

    public static void NotesTakeJSONOutOfAFence()
    {
        var n = NotesEngine.Parse("```json\n{\"summary\": \"周五发布\", \"topics\": []}\n```", [0.0], 0);
        Check(n is not null, "fenced notes parse");
    }

    // 语音和文字只发给你的服务 (issue #15; the Mac's GoogleOffTests): Google is never asked.

    public static void CustomOnlyActsWithTheCustomServiceAlone()
    {
        var s = new AppSettings { AiProvider = "custom", AiCustomOnly = true };
        Check(s.GoogleOff, "on with the custom service");
        s.AiProvider = "zenmux";
        Check(!s.GoogleOff && s.AiCustomOnly, "kept but inert with another service");
        Check(Json.Write(new AppSettings { AiCustomOnly = true }).Contains("\"aiCustomOnly\": true"), "the Mac's key");
        Check(Json.Read<AppSettings>("{\"aiCustomOnly\":true}")!.AiCustomOnly, "read back");
    }

    public static async Task WithGoogleOffPartialTextGoesNowhere()
    {
        var google = new Service((_, _) => Status(200, "[[[\"周五\",\"Friday\"]]]"));
        var service = new Service((_, _) => Reply("我们周五发布。"));
        var (ling, _) = Using(service);
        var t = new Translator(ling, google) { GoogleOff = true };
        for (var i = 0; i < 3; i++) Equal(null, await t.Translate("We ship on Friday", "en", "zh-CN", Translator.Kind.Draft), "the original shows");
        Check(google.Sent.Count == 0 && service.Sent.Count == 0, "neither Google nor the service sees a draft");
        Check(!t.SentencesUntranslated, "a draft says nothing about sentences");
    }

    public static async Task WithGoogleOffSentencesGoToTheServiceOnly()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var google = new Service((_, _) => Status(200, "[[[\"谷歌的译文\",\"x\"]]]"));
            var up = false;
            var service = new Service((_, _) => up ? Reply("我们周五发布。") : Status(400, "{\"error\":{\"message\":\"bad\"}}"));
            var (ling, _) = Using(service);
            var t = new Translator(ling, google) { GoogleOff = true };
            var changes = 0;
            t.Changed += () => changes++;
            Equal(null, await t.Translate("We ship on Friday.", "en", "zh-CN", Translator.Kind.Sentence), "the service failed: the original only");
            Check(service.Sent.Count > 0, "the service was asked");
            Equal(0, google.Sent.Count, "Google never was");
            Check(t.SentencesUntranslated && changes == 1, "the notes window is told");
            up = true;
            Equal("我们周五发布。", await t.Translate("We ship on Friday.", "en", "zh-CN", Translator.Kind.Sentence), "the service answers again");
            Check(!t.SentencesUntranslated && changes == 2, "and the notice goes");
            Equal(0, google.Sent.Count, "still no Google");

            // Off again: Google stands in as before.
            t.GoogleOff = false;
            up = false;
            Equal("谷歌的译文", await t.Translate("We ship on Friday.", "en", "zh-CN", Translator.Kind.Sentence), "Google once more");
            Equal(1, google.Sent.Count, "one request to Google");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task FlippingGoogleOffClearsAGoogleBackoff()
    {
        var google = new Service((_, _) => Status(429));
        var (ling, _) = Using(new Service((_, _) => Reply("x")), key: null);
        var t = new Translator(ling, google);
        Equal(null, await t.Translate("Hello", "en", "zh-CN", Translator.Kind.Draft), "rate-limited");
        Equal(null, await t.Translate("Hello", "en", "zh-CN", Translator.Kind.Draft), "backing off");
        Equal(1, google.Sent.Count, "the second waits out the backoff");
        t.GoogleOff = true;
        t.GoogleOff = false;
        await t.Translate("Hello", "en", "zh-CN", Translator.Kind.Draft);
        Equal(2, google.Sent.Count, "the backoff went with the flip");
    }

    public static async Task AHearServerRefusingKwargsLeavesTheTextServerAlone()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var fake = new Service((url, body) => url.Contains(":8001/") && body.Contains("chat_template_kwargs") ? Status(422) : url.EndsWith("/models") ? Status(404) : Reply("周五发布。"));
            var (ling, _) = Using(fake, "custom", key: null, new AppSettings
            {
                AiCustomBase = "http://192.168.1.20:8000/v1", AiCustomHearBase = "http://192.168.1.21:8001/v1",
                AiModels = { ["custom"] = "qwen3" }, AiHearModels = { ["custom"] = "qwen3-omni" },
            });
            await ling.Check();
            Equal(AICheck.Kind.Ok, ling.Health[AICheck.StepId.Hear].Kind, "heard on the retry");
            fake.Sent.Clear();
            await ling.Chat("x", "Translate.", Priority.Translate);
            Check(fake.Sent.Single().body.Contains("chat_template_kwargs"), "the text server still gets it");
            Check(ling.Health.Translate is { Thinks: false } && !ling.Health.Slow, ling.Health.Summary);
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: Notes apart (LingTests.swift › Notes apart)

    /// A custom service whose notes use "big"; with `own`, at notes.example with 另一个服务.
    static (LingClient ling, AppSettings settings, Service fake) NotesClient(bool own, Func<string, string, HttpResponseMessage> respond, string? notesKey = null, GateClock? clock = null)
    {
        var s = new AppSettings
        {
            AiProvider = "custom", AiCustomBase = "https://main.example/v1", AiModels = { ["custom"] = "mt", ["custom.notes"] = "big" },
            AiCustomNotesOwn = own, AiCustomNotesBase = own ? "https://notes.example/v1" : "",
        };
        var k = new AIKey(new PlainProtector(), service: () => s.AiProvider);
        k.Remove(); k.Remove(LingClient.NotesKeyName);
        k.Save("sk-main-1111111111");
        if (notesKey is not null) k.Save(notesKey, LingClient.NotesKeyName);
        var fake = new Service(respond);
        return (new LingClient(k, fake, s.AIConfig, clock), s, fake);
    }

    public static async Task NotesGoToTheirModelAndServerTranslationStays()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, _, fake) = NotesClient(true, (_, _) => Reply("{}"), notesKey: "sk-notes-222222222");
            await ling.Chat("x", "Notes.", Priority.Notes, json: true);
            await ling.Chat("y", "Translate.", Priority.Translate);
            Equal("big,mt", string.Join(",", fake.Sent.Select(x => JsonNode.Parse(x.body)!["model"]!.GetValue<string>())), "models");
            Equal("https://notes.example/v1/chat/completions,https://main.example/v1/chat/completions", string.Join(",", fake.Sent.Select(x => x.url)), "servers");
            Equal("Bearer sk-notes-222222222,Bearer sk-main-1111111111", string.Join(",", fake.Auth), "keys");
            // A live line's corrections ride at Notes priority but are translation's.
            await ling.Chat("z", "JSON only.", Priority.Notes, notes: false);
            Check(fake.Sent[^1].url.StartsWith("https://main.example/") && fake.Auth[^1] == "Bearer sk-main-1111111111", "corrections stay with translation");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task NotesWithoutTheirOwnKeyUseTheTranslationKey()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, _, fake) = NotesClient(true, (_, _) => Reply("{}"));
            await ling.Chat("x", "Notes.", Priority.Notes);
            Equal("Bearer sk-main-1111111111", fake.Auth[0], "不填就用上面的 key");
            Check(!ling.NotesHasOwnKey, "no key of their own");
            // The same service, another model: same address and key, even with a notes key file left over.
            var (same, _, f2) = NotesClient(false, (_, _) => Reply("{}"), notesKey: "sk-notes-222222222");
            await same.Chat("x", "Notes.", Priority.Notes);
            Check(f2.Sent[0].url.StartsWith("https://main.example/") && f2.Auth[0] == "Bearer sk-main-1111111111", "same service: its key");
            Equal("big", JsonNode.Parse(f2.Sent[0].body)!["model"]!.GetValue<string>(), "the notes model");
            Check(!same.NotesHasOwnKey, "同一个服务 has no key of its own");
            // 另一个服务 at an http address on the internet: notes aren't sent anywhere else instead.
            var (bad, s3, f3) = NotesClient(true, (_, _) => Reply("{}"), notesKey: "sk-notes-222222222");
            s3.AiCustomNotesBase = "http://notes.example/v1";
            try { await bad.Chat("x", "Notes.", Priority.Notes); Check(false, "not sent"); } catch (LingException) { }
            Equal(0, f3.Sent.Count, "nothing sent with a bad notes address");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ARefusedNotesKeyLeavesTranslationWorking()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, _, _) = NotesClient(true, (_, body) => body.Contains("\"big\"") ? Status(401) : Reply("好"));
            try { await ling.Chat("x", "Notes.", Priority.Notes); Check(false, "notes refused"); }
            catch (LingException e) { Equal(LingException.Kind.InvalidKey, e.Failure, "refused"); }
            Check(ling.KeyState != KeyState.Invalid, "translation's key isn't marked bad");
            Equal(AICheck.Reason.InvalidKey, ling.Health.Notes?.Why, "the notes' result says so");
            Check(ling.Health.Failure is null, "translation's steps untouched");
            Equal("好", await ling.Chat("y", "Translate.", Priority.Translate), "translation still works");
            Equal("%@ 不认上面的 key，给它单独填一个。".Replace("%@", "notes.example"), ling.Health.NotesLine("notes.example", "big", sharedKey: true), "wants a key of its own");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ANotesServerBusyDoesNotHoldTranslationBack()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var clock = new FakeClock();
            var (ling, _, fake) = NotesClient(true, (url, _) => url.Contains("notes.example") ? Busy("20") : Reply("好"), clock: clock);
            try { await ling.Chat("x", "Notes.", Priority.Notes); Check(false, "busy"); }
            catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "notes gave up"); }
            Check(clock.Now > clock.Start, "notes waited at their own gate");
            // A translation fails at once while its server cools down; this one isn't.
            Equal("好", await ling.Chat("y", "Translate.", Priority.Translate), "translation's gate isn't paused");
            Check(ling.Health.Failure is null && !ling.Health.NotesFailed, "busy is no failure: " + ling.Health.Summary);
        }
        finally { LingClient.Spacing = old; }
    }

    public static void NotesFallBackToTranslationUntilSet()
    {
        const string b = "https://main.example/v1/";
        var plain = new AIConfig(AIProvider.Custom, b, "mt", "");
        Check(!plain.NotesApart && plain.ForNotes == plain, "nothing set: translation's");
        var model = new AIConfig(AIProvider.Custom, b, "mt", "", NotesModel: "big");
        Check(model.NotesApart && model.ForNotes.TextModel == "big" && model.ForNotes.Base == b, "another model, same address");
        // Only the custom service splits.
        var ling = new AIConfig(AIProvider.Ling, AIProvider.Ling.Base, "x", "", NotesModel: "big");
        Check(!ling.NotesApart && ling.ForNotes.TextModel == "x", "Ling doesn't");
        // From settings: the translation model named again is no model of its own; 另一个服务 off keeps
        // the address but doesn't use it; an http address on the internet can't be used.
        var s = new AppSettings { AiProvider = "custom", AiCustomBase = "https://main.example/v1", AiModels = { ["custom"] = "mt", ["custom.notes"] = "mt" } };
        Check(!s.AIConfig().NotesApart, "same model: not apart");
        s.AiCustomNotesBase = "https://notes.example/v1";
        Check(!s.AIConfig().NotesApart && s.AIConfig().ForNotes.Base == b, "同一个服务: the address is kept, not used");
        s.AiCustomNotesOwn = true;
        Equal("https://notes.example/v1/", s.AIConfig().ForNotes.Base, "另一个服务");
        Equal("mt", s.AIConfig().ForNotes.TextModel, "with the translation model");
        s.AiCustomNotesBase = "http://notes.example/v1";
        Check(s.AIConfig().NotesBadAddress && s.AIConfig().ForNotes.Base == b, "http to the internet");
        s.AiCustomNotesBase = "";
        Check(s.AIConfig().NotesApart && s.AIConfig().ForNotes.Base == b && !s.AIConfig().NotesBadAddress, "另一个服务, no address: the same one, its own key");
    }

    public static async Task ACheckTestsNotesApartWithoutFailingTranslation()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            // The notes model is gone from the notes server; translation's model, typed by hand, isn't listed but answers.
            var (ling, _, fake) = NotesClient(true, (url, body) =>
                url == "https://main.example/v1/models" ? Status(200, "{\"data\":[{\"id\":\"other\"}]}")
                : url == "https://notes.example/v1/models" ? Status(200, "{\"data\":[{\"id\":\"n1\"},{\"id\":\"n2\"}]}")
                : url.StartsWith("https://notes.example/") ? Status(404)
                : Reply("周五发布。"), notesKey: "sk-notes-222222222");
            await ling.Check();
            var h = ling.Health;
            Check(h[AICheck.StepId.Text].Kind == AICheck.Kind.Ok && h.Failure?.Step == AICheck.StepId.Hear, "translation passes (no hear model here): " + h.Summary);
            Equal(AICheck.Reason.NoModel, h.Notes?.Why, "the notes fail on their own: " + h.Summary);
            Check(h.NotesFailed && h.Summary.Contains("notes=fail(noModel 404)"), h.Summary);
            Equal("n1,n2", string.Join(",", ling.NotesCatalog), "the notes server's models, for its menu");
            Check(!fake.Sent.Any(x => x.url == "https://main.example/v1/chat/completions" && x.body.Contains("JSON object")), "no JSON test against translation");
            Equal(KeyState.Ok, ling.KeyState, "translation's key is fine");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ANoKeyCheckOutranksAnOlderSlowOne()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var gate = new TaskCompletionSource();
            var fake = new Service((_, _) => { gate.Task.Wait(); return Reply("周五发布。"); });
            var (ling, s) = Using(fake, "custom", key: null, new AppSettings { AiCustomBase = "http://localhost:8000/v1", AiModels = { ["custom"] = "m" } });
            var slow = Task.Run(ling.Check);
            while (fake.Sent.Count == 0) await Task.Delay(5);
            s.AiCustomBase = "https://api.example.com/v1"; // remote now, and no key
            await ling.Check();
            gate.SetResult();
            await slow;
            Equal(KeyState.None, ling.KeyState, "the newer \"no key\" stays");
            Check(ling.Health.At is null, "the older check dropped");
        }
        finally { LingClient.Spacing = old; }
    }

    public static void SettingsKeepTheServiceAcrossARestart()
    {
        new AppSettings { AiProvider = "zenmux", AiHearModels = { ["zenmux"] = "bytedance/doubao-seed-2.0-mini" } }.Save();
        var back = AppSettings.Load();
        Equal("zenmux", back.AiProvider, "service");
        Equal("bytedance/doubao-seed-2.0-mini", back.AIConfig().HearModel, "hear model");
        var json = File.ReadAllText(Paths.Settings);
        Check(json.Contains("\"aiProvider\"") && json.Contains("\"aiHearModels\""), "the Mac's key names");
        File.Delete(Paths.Settings);
    }

    public static void EachServiceTurnsThinkingOffItsOwnWay()
    {
        foreach (var (id, key, value) in new[] { ("ling", "thinking", "{\"type\":\"disabled\"}"), ("zenmux", "reasoning", "{\"enabled\":false}"), ("openrouter", "reasoning", "{\"enabled\":false}") })
        {
            var body = new JsonObject();
            new AppSettings { AiProvider = id }.AIConfig().Shape(body, 100);
            Equal(value, body[key]!.ToJsonString(), id);
            Equal(100, body["max_tokens"]!.GetValue<int>(), "max_tokens");
        }
        var custom = new JsonObject();
        new AppSettings { AiProvider = "custom", AiCustomBase = "https://x.example/v1" }.AIConfig().Shape(custom, 5);
        Check(custom["reasoning"] is null && custom["thinking"] is null && custom["temperature"]!.GetValue<double>() == 0.2, "custom: neither");
    }

    public static void AudioGoesInTheFormEachModelTakes()
    {
        byte[] wav = [1, 2, 3];
        Equal("{\"type\":\"audio_url\",\"audio_url\":{\"url\":\"data:audio/wav;base64,AQID\"}}", new AppSettings().AIConfig().AudioPart(wav, "Ming-3.0-audio-flash").ToJsonString(), "Ming");
        var zen = new AppSettings { AiProvider = "zenmux" }.AIConfig();
        Equal("{\"type\":\"input_audio\",\"input_audio\":{\"data\":\"AQID\",\"format\":\"wav\"}}", zen.AudioPart(wav, "google/gemini-3.1-flash-lite").ToJsonString(), "input_audio");
        Equal("data:audio/wav;base64,AQID", zen.AudioPart(wav, "qwen/qwen3.8-omni-flash")["input_audio"]!["data"]!.GetValue<string>(), "Qwen wants a data URL");
    }

    public static void CatalogListsChatModelsAndThoseThatHear()
    {
        const string data = """
        {"data": [
          {"id": "qwen/qwen3.8-omni-flash", "input_modalities": ["text", "image", "audio", "video"], "output_modalities": ["text"]},
          {"id": "x/asr-only", "input_modalities": ["audio"], "output_modalities": ["text"]},
          {"id": "x/text-model", "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]}},
          {"id": "x/tts", "input_modalities": ["text"], "output_modalities": ["audio"]},
          {"id": "x/embed-1"},
          {"id": "google/gemini-3.1-flash-lite:batch", "input_modalities": ["audio", "text"], "output_modalities": ["text"]}
        ]}
        """;
        Equal("rec/one,qwen/qwen3.8-omni-flash", string.Join(",", AIProvider.Catalog(data, ["rec/one"], hears: true)), "hear");
        Equal("qwen/qwen3.8-omni-flash,x/text-model", string.Join(",", AIProvider.Catalog(data, [], hears: false)), "text");
        Equal(0, AIProvider.Catalog("not json", [], hears: false).Count, "no /models");
    }

    public static void OneKeyFilePerService()
    {
        var s = new AppSettings();
        var k = new AIKey(new PlainProtector(), service: () => s.AiProvider);
        k.Save("sk-ling-000000000");
        s.AiProvider = "zenmux";
        Equal(null, k.Read(), "ZenMux has none yet");
        k.Save("sk-zen-0000000000");
        Check(k.File_.EndsWith("ai-key-zenmux"), "named as on the Mac");
        if (!OperatingSystem.IsWindows()) Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(k.File_), "0600");
        s.AiProvider = "ling";
        Equal("sk-ling-000000000", k.Read(), "switching back keeps Ling's");
        s.Save();
        Check(!File.ReadAllText(Paths.Settings).Contains("sk-"), "never in settings");
        k.Remove(); s.AiProvider = "zenmux"; k.Remove(); File.Delete(Paths.Settings);
    }

    public static void ALocalCustomServiceNeedsNoKey()
    {
        var (ling, s) = Using(new Service((_, _) => Reply("ok")), "custom", key: null,
            new AppSettings { AiCustomBase = "localhost:11434/v1", AiModels = { ["custom"] = "qwen3:14b" } });
        Equal("", ling.CurrentKey(), "no key needed");
        Check(ling.HasKey, "has one, in effect");
        s.AiCustomBase = "https://api.example.com/v1";
        Check(!ling.HasKey, "a remote one needs a key");
    }

    public static async Task RequestsGoToTheServiceInItsShape()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var fake = new Service((_, _) => Reply("LANG: en\nORIGINAL: Hi.\nTRANSLATION: 嗨。", finish: null));
            var (ling, _) = Using(fake);
            // No finish reason: Ling's search essays come without one, other services may just omit it.
            var r = await ling.Chat("c", "i", Priority.Translate, model: "qwen/qwen3.8-omni-flash", audio: [1]);
            Check(r.Contains("ORIGINAL: Hi."), "kept without a finish reason");
            Equal("https://zenmux.ai/api/v1/chat/completions", fake.Sent[0].url, "the service's address");
            var b = JsonNode.Parse(fake.Sent[0].body)!;
            Equal(false, b["reasoning"]!["enabled"]!.GetValue<bool>(), "reasoning off");
            Check(b["thinking"] is null, "no Ling-only fields");
            Equal("input_audio", b["messages"]![1]!["content"]![0]!["type"]!.GetValue<string>(), "input_audio");
            await ling.Chat("c", "i", Priority.Translate);
            Equal("inclusionai/ling-3.0-flash", JsonNode.Parse(fake.Sent[1].body)!["model"]!.GetValue<string>(), "text calls use the text model");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task CheckFindsAHearModelThatRefusesAudio()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, s) = Using(new Service((url, body) =>
                url.EndsWith("models") ? Status(200, "{\"data\":[{\"id\":\"inclusionai/ling-3.0-flash\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}]}")
                : body.Contains("input_audio") ? Status(400) : Reply("OK")),
                s: new AppSettings { AiHearModels = { ["zenmux"] = "x/text-only" } });
            var (state, _) = await ling.Check();
            Equal(KeyState.Ok, state, "the key is good");
            Equal(false, ling.Hears, "but the model can't hear");
            Equal("reach=ok key=ok text=ok(0.0s) hear=fail(deaf 400)", Regex.Replace(ling.Health.Summary, @"\d+\.\ds", "0.0s"), "the hear step failed");
            Check(!ling.CanHear && ling.Usable, "notes and translation still work");
            Check(ling.TextCatalog.Contains("inclusionai/ling-3.0-flash"), "catalog fetched after a good check");
            Equal("qwen/qwen3.8-omni-flash", ling.Recommended(AICheck.StepId.Hear), "换成推荐的");
            s.AiHearModels.Clear();
            ling.KeyChanged();
            Equal(null, ling.Hears, "a new model is asked again");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task CheckSaysWhy()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, _) = Using(new Service((_, _) => Status(401)));
            Equal(KeyState.Invalid, (await ling.Check()).state, "401");
            Equal("reach=ok key=fail(invalidKey) text=skipped hear=skipped", ling.Health.Summary, "401 stops at the key");
            (ling, _) = Using(new Service((url, body) => body.Contains("input_audio") || url.EndsWith("models") ? Status(200, "{\"data\":[]}") : Status(404)));
            await ling.Check();
            Equal(AICheck.Reason.NoModel, ling.Health.Failure?.Why, "a 404 on the text model");
            Equal("ZenMux 上找不到 inclusionai/ling-3.0-flash 这个模型。", ling.Health.Message(ling.ServiceName, ling.ServiceHost, ling.Config.TextModel, ling.HearName), "names the service and the model");
            (ling, _) = Using(new Service((_, _) => throw new HttpRequestException("no route")));
            ling.ProxyHint = () => Task.FromResult(new AICheck.ProxyHint(AICheck.ProxyKind.AppRunning, 7890));
            await ling.Check();
            Equal("reach=fail(unreachable) key=skipped text=skipped hear=skipped proxy=appRunning(7890)", ling.Health.Summary, "a network error stops at reach, with the proxy");
            (ling, _) = Using(new Service((url, _) => url.EndsWith("models") ? Status(404) : Status(429)));
            await ling.Check();
            Check(ling.Health.Passed && ling.Health.IsBusy && !ling.Health.NeedsUser, "429 passes as busy");
            (ling, _) = Using(new Service((_, _) => Reply("ok")), key: "sk-mgmt-0000");
            await ling.Check();
            Equal("reach=untested key=fail(mgmtKey) text=skipped hear=skipped", ling.Health.Summary, "a management key isn't sent");
            (ling, _) = Using(new Service((_, _) => Reply("ok")), "openrouter", key: null);
            Equal(KeyState.None, ling.KeyState, "no key");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task CheckFindsModelsGoneFromTheList()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            // ZenMux lists modalities at the top level: the text model is gone, and the hear model doesn't take audio.
            var (ling, _) = Using(new Service((url, _) => url.EndsWith("models")
                ? Status(200, "{\"data\":[{\"id\":\"qwen/qwen3.8-flash\",\"input_modalities\":[\"text\"]},{\"id\":\"qwen/qwen3.8-omni-flash\",\"input_modalities\":[\"text\"]},{\"id\":\"a/ears\",\"input_modalities\":[\"audio\",\"text\"]}]}")
                : Reply("OK")));
            await ling.Check();
            Equal(AICheck.Kind.Fail, ling.Health[AICheck.StepId.Text].Kind, "the text model is gone");
            Equal(AICheck.Reason.Deaf, ling.Health[AICheck.StepId.Hear].Why, "the hear model isn't listed as hearing");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task CheckReadsOpenRouterBalance()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, _) = Using(new Service((url, _) =>
                url.EndsWith("/key") ? Status(200, "{\"data\":{\"limit_remaining\":0.3}}")
                : url.EndsWith("/credits") ? Status(200, "{\"data\":{\"total_credits\":10,\"total_usage\":3}}")
                : url.EndsWith("models") ? Status(404) : Reply("OK")), "openrouter");
            await ling.Check();
            Equal(0.3, ling.Health.Balance, "the key's limit is the smaller");
            Check(ling.Health.Passed && ling.Health.NeedsUser, "passed, but low");
            Equal("OpenRouter 余额快用完了（还剩 $0.30）", ling.Health.BalanceLine("OpenRouter"), "balance line");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task RealRequestsKeepTheStepsCurrent()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            int status = 200;
            var (ling, _) = Using(new Service((url, body) => status == 200 ? Reply("OK") : Status(status)));
            await ling.Chat("c", "i", Priority.Translate);
            Equal("reach=ok key=ok text=ok(0.0s) hear=untested passive", Regex.Replace(ling.Health.Summary, @"\d+\.\ds", "0.0s"), "a translation proves the text model");
            status = 404;
            try { await ling.Chat("c", "i", Priority.Translate, model: ling.Config.HearModel, audio: [1]); } catch (LingException) { }
            Equal(AICheck.Reason.Deaf, ling.Health.Failure?.Why, "a 404 on audio is the hear model, never the text model");
            Equal(AICheck.Kind.Ok, ling.Health[AICheck.StepId.Text].Kind, "the text model stays proven");
            status = 200;
            await ling.Chat("c", "i", Priority.Translate, model: ling.Config.HearModel, audio: [1]);
            Equal(null, ling.Health.Failure, "heard again: clear");
            int changes = 0;
            ling.Changed += () => changes++;
            await ling.Chat("c", "i", Priority.Translate);
            await ling.Chat("c", "i", Priority.Translate);
            Equal(0, changes, "the same good result again changes nothing");
            status = 503;
            try { await ling.Chat("c", "i", Priority.Translate); } catch (LingException) { }
            Equal(null, ling.Health.Failure, "one server error in a meeting is left alone");
            status = 401;
            try { await ling.Chat("c", "i", Priority.Translate); } catch (LingException) { }
            Equal(KeyState.Invalid, ling.KeyState, "a refused key stops every request");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task AnOlderCheckNeverLandsOverANewerOne()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var (ling, s) = Using(new Service((url, body) =>
            {
                if (body.Contains("slow/gone")) { Thread.Sleep(400); return Status(404); }
                return url.EndsWith("models") ? Status(404) : Reply("OK");
            }), s: new AppSettings { AiModels = { ["zenmux"] = "slow/gone" } });
            var first = ling.Check();
            await Task.Delay(50);
            s.AiModels["zenmux"] = "fast/here";
            ling.KeyChanged();
            await ling.Check();
            await first;
            Equal(null, ling.Health.Failure, "the model chosen since is the one checked");
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: AI 服务检查 (the Mac's AICheckTests, case for case, plus hearing)

    public static void EachFailureStopsAtItsStep()
    {
        static string C(LingException.Kind k, int status, AICheck.StepId at) => AICheck.Classify(k, status, at)?.ToString() ?? "null";
        Equal("(Reach, Unreachable, )", C(LingException.Kind.Network, 0, AICheck.StepId.Text), "network");
        Equal("(Reach, Unreachable, )", C(LingException.Kind.Timeout, 0, AICheck.StepId.Key), "timeout");
        Equal("(Key, InvalidKey, )", C(LingException.Kind.InvalidKey, 0, AICheck.StepId.Text), "401");
        Equal("(Key, NoCredit, 402)", C(LingException.Kind.Http, 402, AICheck.StepId.Text), "402");
        Equal("(Text, NoModel, 404)", C(LingException.Kind.Http, 404, AICheck.StepId.Text), "404");
        Equal("(Text, NoModel, 400)", C(LingException.Kind.Http, 400, AICheck.StepId.Text), "400");
        Equal("(Text, Busy, )", C(LingException.Kind.RateLimited, 0, AICheck.StepId.Text), "429");
        Equal("(Key, ServerError, 503)", C(LingException.Kind.Http, 503, AICheck.StepId.Key), "5xx");
        Equal("null", C(LingException.Kind.Hijacked, 0, AICheck.StepId.Text), "hijacked says nothing");
        foreach (var code in new[] { 400, 404, 415, 422 })
            Equal($"(Hear, Deaf, {code})", C(LingException.Kind.Http, code, AICheck.StepId.Hear), $"{code} on audio");
        Equal("(Hear, Busy, )", C(LingException.Kind.RateLimited, 0, AICheck.StepId.Hear), "429 on audio");
    }

    public static void AFailedStepSkipsTheRestAndAReplyProvesTheOnesBefore()
    {
        var c = new AICheck();
        c.Fail(AICheck.StepId.Key, AICheck.Reason.InvalidKey);
        Equal("reach=ok key=fail(invalidKey) text=skipped hear=skipped", c.Summary, "key");
        Equal(AICheck.StepId.Key, c.Failure?.Step, "failure");
        var m = new AICheck();
        m.Fail(AICheck.StepId.Key, AICheck.Reason.MgmtKey, reached: false);
        Equal(AICheck.Kind.Untested, m[AICheck.StepId.Reach].Kind, "nothing sent");
        // Hearing doesn't need the text model, nor the other way round.
        var t = new AICheck();
        t.Fail(AICheck.StepId.Text, AICheck.Reason.NoModel, 404);
        Equal("reach=ok key=ok text=fail(noModel 404) hear=untested", t.Summary, "text");
        var h = new AICheck();
        h.Fail(AICheck.StepId.Hear, AICheck.Reason.Deaf, 400);
        Equal("reach=ok key=ok text=untested hear=fail(deaf 400)", h.Summary, "hear");
    }

    public static void ASuccessClearsAnEarlierFailure()
    {
        var c = new AICheck();
        c.Fail(AICheck.StepId.Reach, AICheck.Reason.Unreachable);
        c.Proxy = new AICheck.ProxyHint(AICheck.ProxyKind.None);
        c.Pass(AICheck.StepId.Text, 1.5);
        Equal(null, c.Failure, "cleared");
        Equal("reach=ok key=ok text=ok(1.5s) hear=untested", c.Summary, "a chat proves reach, key and text");
        Equal(null, c.Proxy, "proxy hint gone");
    }

    public static void BusyPassesAndNeedsNobody()
    {
        var c = new AICheck();
        c.Busy(AICheck.StepId.Text);
        c.At = DateTimeOffset.Now;
        Check(c.Passed && c.IsBusy && !c.NeedsUser, "busy passes");
        Equal("ZenMux 现在很忙，key 没问题。开会时会自动重试。", c.Message("ZenMux", "zenmux.ai", "m", "h"), "busy words");
    }

    public static void OnlyWhatTheUserMustFixShowsBeyondThePanel()
    {
        var blocking = new[] { AICheck.Reason.InvalidKey, AICheck.Reason.MgmtKey, AICheck.Reason.NoCredit, AICheck.Reason.NoModel, AICheck.Reason.BadAddress, AICheck.Reason.NoJSON, AICheck.Reason.Deaf };
        foreach (var why in Enum.GetValues<AICheck.Reason>())
            Equal(blocking.Contains(why), AICheck.Blocks(why), $"{why}");
        var key = new AICheck();
        key.Fail(AICheck.StepId.Key, AICheck.Reason.InvalidKey);
        Check(key.Blocking, "a bad key");
        var away = new AICheck();
        away.Fail(AICheck.StepId.Reach, AICheck.Reason.Unreachable);
        Check(!away.Blocking && away.NeedsUser, "unreachable: the panel says so, no dot");
        var low = new AICheck { Balance = 0.3 };
        Check(!low.Blocking && low.NeedsUser, "a low balance still works: no dot");
        Check(!new AICheck().Blocking, "nothing known");
    }

    public static void KeyPrefixesTellWhoseKeyItIs()
    {
        Equal(("openrouter", false), AICheck.Owner("sk-or-v1-abc"), "OpenRouter");
        Equal(("zenmux", false), AICheck.Owner(" sk-payg-abc\n"), "ZenMux");
        Equal(("zenmux", true), AICheck.Owner("sk-mgmt-abc"), "management");
        Equal(null, AICheck.Owner("sk-abc"), "nothing to tell");
    }

    public static void BalanceIsTheSmallerOfKeyLimitAndCredits()
    {
        const string key = "{\"data\":{\"limit_remaining\":1.72}}", credits = "{\"data\":{\"total_credits\":10.0,\"total_usage\":3.92}}";
        Equal(1.72, AICheck.BalanceFrom(key, credits), "both");
        Check(Math.Abs(AICheck.BalanceFrom("{\"data\":{\"limit_remaining\":null}}", credits)!.Value - 6.08) < 0.001, "no key limit: credits");
        Equal(1.72, AICheck.BalanceFrom(key, null), "key only");
        Equal(null, AICheck.BalanceFrom(null, null), "nothing");
        var c = new AICheck { Balance = 0.3 };
        Check(c.IsLowBalance && c.NeedsUser, "low");
    }

    public static void ListedModelsReadsEveryID()
    {
        var ids = AICheck.ListedModels("{\"data\":[{\"id\":\"inclusionai/ling-3.0-flash\"},{\"id\":\"qwen/qwen3.8-flash\"}]}");
        Equal("inclusionai/ling-3.0-flash,qwen/qwen3.8-flash", string.Join(",", ids!.Order()), "ids");
        Equal(null, AICheck.ListedModels("{}"), "no data");
        Equal(null, AICheck.ListedModels("{\"data\":[]}"), "empty");
        // OpenRouter says modalities under architecture; a list that says nothing proves nothing about hearing.
        var hearing = AICheck.ListedHearing("{\"data\":[{\"id\":\"a\",\"architecture\":{\"input_modalities\":[\"text\",\"audio\"]}},{\"id\":\"b\",\"architecture\":{\"input_modalities\":[\"text\"]}}]}");
        Equal("a", string.Join(",", hearing!), "hearing");
        Equal(null, AICheck.ListedHearing("{\"data\":[{\"id\":\"a\"}]}"), "nothing said");
    }

    public static void MessagesNameTheServiceAndTheProxyHintFollowsTheProxy()
    {
        var c = new AICheck();
        c.Fail(AICheck.StepId.Reach, AICheck.Reason.Unreachable);
        Equal("这台电脑访问不到 zenmux.ai。", c.Message("ZenMux", "zenmux.ai", "m", "h"), "unreachable");
        Equal(null, c.ProxyLine("ZenMux", "zenmux.ai"), "no hint yet");
        c.Proxy = new AICheck.ProxyHint(AICheck.ProxyKind.AppRunning, 7890);
        Check(c.ProxyLine("ZenMux", "zenmux.ai")!.Contains("7890"), "port, not 7,890");
        c.Proxy = new AICheck.ProxyHint(AICheck.ProxyKind.SystemOn);
        Check(c.ProxyLine("ZenMux", "zenmux.ai")!.Contains("zenmux.ai"), "system on names the host");
        c.Proxy = new AICheck.ProxyHint(AICheck.ProxyKind.None);
        Check(c.ProxyLine("ZenMux", "zenmux.ai")!.Contains("ZenMux"), "none names the service");
        var m = new AICheck();
        m.Fail(AICheck.StepId.Text, AICheck.Reason.NoModel, 404);
        Check(m.Message("ZenMux", "zenmux.ai", "x/y", "h")!.Contains("x/y"), "model named");
        var d = new AICheck();
        d.Fail(AICheck.StepId.Hear, AICheck.Reason.Deaf, 400);
        Equal("qwen3:14b 听不了声音。", d.Message("ZenMux", "zenmux.ai", "m", "qwen3:14b"), "deaf names the hear model");
        Check(d.NeedsUser, "deaf needs the user");
    }

    public static async Task ProxyProbeReadsTheSystemThenThePorts()
    {
        Equal(AICheck.ProxyKind.SystemOn, (await ProxyProbe.Hint(() => true)).Kind, "system proxy on");
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try { Check(await ProxyProbe.Listening(((IPEndPoint)listener.LocalEndpoint).Port), "something listens"); }
        finally { listener.Stop(); }
    }

    static async Task<string> Joined(IAsyncEnumerable<byte[]> chunks)
    {
        var all = new List<byte>();
        await foreach (var c in chunks) all.AddRange(c);
        return string.Join(",", all);
    }

    public static async Task SpeechFromEachService()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            // ZenMux: server-sent base64, with `stream`.
            var sse = new Service((_, _) => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("data: {\"audio\":\"AQACAA==\"}\n\ndata: {\"type\":\"speech.audio.done\"}\n\n", System.Text.Encoding.UTF8, "text/event-stream"),
            });
            var (ling, _) = Using(sse);
            Equal("1,0,2,0", await Joined(ling.Speech("Hello", "Puck", "ja")), "SSE chunks");
            var b = JsonNode.Parse(sse.Sent[0].body)!;
            Equal("https://zenmux.ai/api/v1/audio/speech", sse.Sent[0].url, "speech address");
            Equal(("google/gemini-3.8-flash-tts", "Puck", true), (b["model"]!.GetValue<string>(), b["voice"]!.GetValue<string>(), b["stream"]!.GetValue<bool>()), "body");
            Check(b["language_id"] is null, "language_id is Ming's only");
            // A voice that isn't this service's (a Ming name left in settings) becomes its first one.
            await Joined(ling.Speech("Hello", "US_Emma"));
            Equal("Kore", JsonNode.Parse(sse.Sent[1].body)!["voice"]!.GetValue<string>(), "first voice");
            // OpenRouter streams the PCM bytes themselves, without `stream`.
            var raw = new Service((_, _) => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([5, 0, 6, 0]) { Headers = { ContentType = new("audio/pcm") } } });
            (ling, _) = Using(raw, "openrouter");
            Equal("5,0,6,0", await Joined(ling.Speech("Hi", null)), "raw PCM");
            Check(JsonNode.Parse(raw.Sent[0].body)!["stream"] is null, "no stream for OpenRouter");
            // One JSON with a WAV in it.
            var wav = Wav.Bytes([7, 8], 24000);
            var one = new Service((_, _) => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent($"{{\"audio\":\"{Convert.ToBase64String(wav)}\"}}", System.Text.Encoding.UTF8, "application/json") });
            (ling, _) = Using(one, "custom", s: new AppSettings { AiCustomBase = "https://x.example/v1", AiModels = { ["custom"] = "m" }, AiVoiceModels = { ["custom"] = "kokoro" }, AiCustomVoice = "af_heart" });
            Equal("7,0,8,0", await Joined(ling.Speech("Hi", "af_heart")), "JSON WAV");
            Equal("7,0,8,0", string.Join(",", LingClient.PcmFromWav(wav)), "the data chunk");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task NoVoiceModelMeansWindowsSpeaks()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var settings = new AppSettings { AiCustomBase = "https://x.example/v1", AiModels = { ["custom"] = "m" }, SpeakVoices = { ["en"] = "ming:US_Emma" } };
            var fake = new Service((_, _) => Reply("ok"));
            var (ling, _) = Using(fake, "custom", s: settings);
            Check(!ling.Speaks, "no speech model, no service voice");
            var voice = new NoVoice();
            var engine = new SpeakEngine(ling, new Translator(ling), new SessionStore(), settings, () => "en", () => null, voice);
            Check(await engine.Voice("Hello", "en", new Sink()), "something was said");
            Equal("system", engine.LastVoice, "by Windows");
            Check(fake.Sent.Count == 0, "the old Ming voice went nowhere");
            Equal(VoiceCatalog.SystemId, VoiceCatalog.Options("en", ling.Config).Single().Id, "Windows is the only choice");
        }
        finally { LingClient.Spacing = old; }
    }

    public static void VoicesFollowTheService()
    {
        var zen = new AppSettings { AiProvider = "zenmux" }.AIConfig();
        Equal("cloud:Kore,cloud:Aoede,cloud:Charon,cloud:Puck,system", string.Join(",", VoiceCatalog.Options("ja", zen).Select(v => v.Id)), "Gemini's voices in every language, then Windows'");
        Equal("cloud:Kore", VoiceCatalog.DefaultId("en", zen, speaks: true), "the service's first");
        Equal("system", VoiceCatalog.DefaultId("en", zen, speaks: false), "Windows' until it can speak");
        var settings = new AppSettings { SpeakVoices = { ["en"] = "ming:US_Emma" } };
        Equal("cloud:Kore", VoiceCatalog.Chosen(settings, "en", zen, true), "a Ming voice isn't sent to ZenMux");
        Equal("ming:US_Emma", VoiceCatalog.Chosen(settings, "en", new AppSettings().AIConfig(), true), "and is used again on Ling");
        // #22: Windows' voice saved for a language this PC has no voice for.
        var system = new AppSettings { SpeakVoices = { ["en"] = "system" } };
        var ling = new AppSettings().AIConfig();
        Equal("system", VoiceCatalog.Chosen(system, "en", ling, true, windowsHasIt: true), "kept where Windows has it");
        Equal("ming:US_Emma", VoiceCatalog.Chosen(system, "en", ling, true, windowsHasIt: false), "the service's voice where it doesn't");
        Equal("ming:US_Emma", VoiceCatalog.Chosen(system, "en", ling, false, windowsHasIt: false), "even before the service is checked");
    }

    // MARK: 我自己的声音

    public static void KeepsTheOwnVoiceRecordingSealed()
    {
        var folder = Path.Combine(Paths.Root, "voice-test");
        var r = new VoiceReference(new FlipProtector(), folder);
        Check(!r.Exists && r.Reference() is null, "nothing recorded yet");
        var wav = Wav.Bytes(new short[16000 * 12]);
        int changes = 0;
        r.Changed += () => changes++;
        r.Save(wav, " 大家好，我是这次会议的主持人。 ");
        Check(r.Exists, "saved");
        Equal(12.0, r.Duration, "its length");
        Equal("大家好，我是这次会议的主持人。", r.Text, "its words, trimmed");
        Check(!File.ReadAllText(r.AudioFile).Contains("RIFF") && File.ReadAllText(r.AudioFile).StartsWith("dpapi:"), "sealed on disk, not a plain WAV");
        Check(!File.ReadAllText(r.TextFile).Contains("主持人"), "the words too");
        var (audio, text) = r.Reference()!.Value;
        Check(audio.StartsWith("data:audio/wav;base64,") && Convert.FromBase64String(audio[22..]).SequenceEqual(wav), "Ming gets the WAV back as a data URI");
        Equal("大家好，我是这次会议的主持人。", text, "with what it says");
        Equal(true, new VoiceReference(new FlipProtector(), folder).Exists, "read back by a fresh instance");
        r.Remove();
        Check(!r.Exists && !Directory.Exists(folder), "删除 takes the folder");
        Equal(2, changes, "saved and removed are announced");
    }

    sealed class FlipProtector : IKeyProtector
    {
        public string Tag => "flip";
        public byte[] Protect(byte[] data) => data.Select(b => (byte)~b).ToArray();
        public byte[] Unprotect(byte[] data) => data.Select(b => (byte)~b).ToArray();
    }

    public static void SendsTheOwnVoiceAsAReference()
    {
        var ling = new AppSettings().AIConfig();
        var cloned = LingClient.SpeechBody(ling, "Hello", "US_Emma", "ja", ("data:audio/wav;base64,AAAA", "大家好"));
        var refs = cloned["references"]!.AsArray();
        Equal(1, refs.Count, "one reference");
        Equal(("data:audio/wav;base64,AAAA", "大家好"), (refs[0]!["audio"]!.GetValue<string>(), refs[0]!["text"]!.GetValue<string>()), "the clip and its words");
        Check(cloned["voice"] is null, "no built-in voice beside it");
        Equal("ja", cloned["language_id"]!.GetValue<string>(), "language_id still sent");
        Check(cloned["stream"]!.GetValue<bool>() && cloned["sample_rate"]!.GetValue<int>() == 24000, "streamed as Ming's other voices");
        var plain = LingClient.SpeechBody(ling, "Hello", "US_Emma", null);
        Check(plain["references"] is null && plain["voice"]!.GetValue<string>() == "US_Emma", "a built-in voice sends no reference");
        var zen = LingClient.SpeechBody(new AppSettings { AiProvider = "zenmux" }.AIConfig(), "Hello", null, null, ("data:x", "y"));
        Check(zen["references"] is null, "only Ling clones");
    }

    public static void OwnVoiceFallsBackWithoutItsRecordingOrLing()
    {
        var ling = new AppSettings().AIConfig();
        var zen = new AppSettings { AiProvider = "zenmux" }.AIConfig();
        var s = new AppSettings { SpeakVoices = { ["en"] = "clone" } };
        Equal("ming:US_Emma,ming:UK_George,ming:UK_Charlotte,system,clone", string.Join(",", VoiceCatalog.Options("en", ling, clone: true).Select(v => v.Id)), "offered last, once recorded");
        Check(!VoiceCatalog.Options("en", ling).Any(v => v.Id == "clone"), "not before");
        Equal("clone", VoiceCatalog.Chosen(s, "en", ling, true, clone: true), "used when recorded on Ling");
        Equal("ming:US_Emma", VoiceCatalog.Chosen(s, "en", ling, true, clone: false), "the default without the recording");
        Equal("cloud:Kore", VoiceCatalog.Chosen(s, "en", zen, true, clone: false), "and on another service");
        Check(AIProvider.Ling.Clones && !AIProvider.ZenMux.Clones && !AIProvider.OpenRouter.Clones && !AIProvider.Custom.Clones, "only Ling clones");
    }

    public static async Task SpeaksInTheOwnVoiceAndFallsBackToWindows()
    {
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        var folder = Path.Combine(Paths.Root, "voice-engine-test");
        try
        {
            var sse = new Service((_, _) => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("data: {\"audio\":\"AQACAA==\"}\n\ndata: {\"type\":\"speech.audio.done\"}\n\n", System.Text.Encoding.UTF8, "text/event-stream"),
            });
            var (ling, s) = Using(sse, "ling");
            s.SpeakVoices["ja"] = "clone";
            var reference = new VoiceReference(new PlainProtector(), folder);
            var voice = new NoVoice();
            var engine = new SpeakEngine(ling, new Translator(ling), new SessionStore(), s, () => "ja", () => null, voice);
            // Not recorded: Ming's default voice for Japanese.
            Check(await engine.Voice("こんにちは", "ja", new Sink()), "spoken");
            Equal("ming", engine.LastVoice, "Ming's own voice before the recording");
            engine.Reference = reference;
            reference.Save(Wav.Bytes(new short[16000 * 11]), "大家好，我是主持人。");
            Check(engine.CloneReady, "ready with Ling and a recording");
            Check(await engine.Voice("こんにちは", "ja", new Sink()), "spoken");
            Equal("clone", engine.LastVoice, "in the user's own voice");
            var body = JsonNode.Parse(sse.Sent[^1].body)!;
            Check(body["references"] is JsonArray { Count: 1 } && body["voice"] is null, "the recording went with it");
            Equal("ja", body["language_id"]!.GetValue<string>(), "with Ming's language");
            // Ling failing: Windows speaks the translation instead (never the original).
            var down = new Service((_, _) => new HttpResponseMessage(HttpStatusCode.InternalServerError));
            var (ling2, s2) = Using(down, "ling");
            s2.SpeakVoices["ja"] = "clone";
            var engine2 = new SpeakEngine(ling2, new Translator(ling2), new SessionStore(), s2, () => "ja", () => null, voice) { Reference = reference };
            Check(await engine2.Voice("こんにちは", "ja", new Sink()), "still spoken");
            Equal("system", engine2.LastVoice, "by Windows");
        }
        finally { LingClient.Spacing = old; try { Directory.Delete(folder, true); } catch { } }
    }

    public static void TellsASlowRecordingApart()
    {
        // 21 characters read over 4 s of sound (a second of silence each side): an ordinary pace.
        var samples = new float[16000 * 6];
        for (var i = 16000; i < 16000 * 5; i++) samples[i] = (float)Math.Sin(i * 0.05) * 0.3f;
        var text = "大家好我是这次会议的主持人今天我们讨论计划";
        var pace = VoicePace.Pace(text, samples, 16000)!.Value;
        Check(Math.Abs(pace - 5.25) < 0.1, $"characters over the speech, not the silence ({pace})");
        Check(!VoicePace.IsSlow(text, pace), "not slow");
        Check(VoicePace.IsSlow(text, 1.7), "a recital at 1.7 a second is");
        Check(!VoicePace.IsSlow("hello everyone thanks for joining", 2.0) && VoicePace.IsSlow("hello everyone thanks for joining", 1.5), "words for English");
        Equal(null, VoicePace.SpeechSpan(new float[16000], 16000), "silence has no span");
        Equal("hello,it's,大,家", string.Join(",", VoicePace.Tokens("Hello, it’s 大家!")), "tokens as the Mac's");
    }

    public static async Task ChecksARecordingBeforeKeepingIt()
    {
        static byte[] Spoken(double seconds)
        {
            var pcm = new short[(int)(16000 * seconds)];
            for (var i = 8000; i < pcm.Length - 8000; i++) pcm[i] = (short)(Math.Sin(i * 0.05) * 9000);
            return Wav.Bytes(pcm);
        }
        var passage = VoiceCloneCheck.Passage("zh-CN")[..40];
        Equal(VoiceCloneCheck.Outcome.TooShort, (await VoiceCloneCheck.Check(Spoken(9), _ => Task.FromResult<string?>(passage))).outcome, "under 10 s");
        Equal(VoiceCloneCheck.Outcome.NotHeard, (await VoiceCloneCheck.Check(Spoken(12), _ => Task.FromResult<string?>("嗯"))).outcome, "nothing recognisable");
        Equal(VoiceCloneCheck.Outcome.NotHeard, (await VoiceCloneCheck.Check(Spoken(12), _ => throw new LingException(LingException.Kind.Network))).outcome, "the hearing failed");
        Equal(VoiceCloneCheck.Outcome.Slow, (await VoiceCloneCheck.Check(Spoken(14), _ => Task.FromResult<string?>("大家好我是主持人今天讨论"))).outcome, "12 characters in 13 s");
        var (ok, text) = await VoiceCloneCheck.Check(Spoken(12), _ => Task.FromResult<string?>(" " + passage + " "));
        Equal((VoiceCloneCheck.Outcome.Ready, passage), (ok, text), "an ordinary reading is kept with its words");
    }

    public static async Task HearingGoesToTheChosenHearModel()
    {
        Equal(12.0, Translator.HearTimeout(new AppSettings().AIConfig()), "Ming's timeout");
        Equal(20.0, Translator.HearTimeout(new AppSettings { AiProvider = "zenmux" }.AIConfig()), "the others'");
        var old = LingClient.Spacing; LingClient.Spacing = 0;
        try
        {
            var fake = new Service((_, _) => Reply("LANG: en\nORIGINAL: We ship on Friday.\nTRANSLATION: 我们周五发布。"));
            var (ling, _) = Using(fake, s: new AppSettings { AiHearModels = { ["zenmux"] = "bytedance/doubao-seed-2.0-mini" } });
            var heard = await new Translator(ling).Hear(Wav.Bytes(Tone(1)), "zh-CN", null);
            Equal("我们周五发布。", heard?.Translation, "heard");
            Equal("bytedance/doubao-seed-2.0-mini", JsonNode.Parse(fake.Sent[0].body)!["model"]!.GetValue<string>(), "model");
        }
        finally { LingClient.Spacing = old; }
    }

    public static void ProblemsNameTheService()
    {
        Check(ListenEngine.Words(LingException.Kind.Http, 400, "ZenMux").Settings, "a hear model that refuses audio is fixed in settings");
        Check(ListenEngine.Words(LingException.Kind.Network, 0, "ZenMux").Body.Contains("ZenMux"), "named");
        // One status line: subtitles and notes both wait, since the service hears the meeting here.
        Equal((null, "字幕和纪要等 Ling 恢复 · 连上后自动继续", false), ListenEngine.Words(LingException.Kind.Timeout, 0, "Ling"), "unreachable is one line");
        Check(!ListenEngine.Words(LingException.Kind.Http, 400, "Ling").Settings, "Ling's 400 is the network bar");
        // A gateway's 502 in front of the server: the service erring, not the network, nothing in settings.
        Equal((null, "ZenMux 暂时出错（HTTP 502），稍后再试。", false), ListenEngine.Words(LingException.Kind.Http, 502, "ZenMux"), "a 5xx is the service's trouble");
        Equal("Ling 暂时出错（HTTP 503），稍后再试。", ListenEngine.Words(LingException.Kind.Http, 503, "Ling").Body, "Ling's too");
    }

    public static async Task ServerErrorsInARowAreSaidAndClearOnTheNextLine()
    {
        // Every stretch answered 502 by a gateway: no subtitles, so from the third in a row the bar
        // says the service is erring; the next stretch heard clears it. Two blips say nothing.
        var calls = 0;
        var seen = new List<(LingException.Kind? kind, int status, int calls)>();
        var fake = new Fake(body =>
        {
            if (!body.Contains("Ming-3.0-audio-flash")) return Reply("{}");
            return Interlocked.Increment(ref calls) <= 3 ? new HttpResponseMessage(HttpStatusCode.BadGateway)
                : Reply("LANG: en\nORIGINAL: Back again.\nTRANSLATION: 回来了。");
        });
        var old = LingClient.Spacing; LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var engine = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), new AppSettings { Target = "zh-CN" });
            engine.Changed += () => { lock (seen) seen.Add((engine.Problem, engine.ProblemStatus, Volatile.Read(ref calls))); };
            var path = Path.Combine(Path.GetTempPath(), $"cicada-502-{Environment.ProcessId}.wav");
            short[] stretches = [.. Tone(1), .. Silence(3), .. Tone(1), .. Silence(3), .. Tone(1), .. Silence(3), .. Tone(1), .. Silence(3)];
            File.WriteAllBytes(path, Wav.Bytes(stretches));
            // Four times real time: each reply is back before the next stretch goes, as in a meeting.
            var src = new FileAudioSource(path, speed: 4);
            var ended = new TaskCompletionSource();
            src.Ended += _ => ended.TrySetResult();
            engine.Start(src);
            await ended.Task;
            await Task.Delay(300);
            await engine.Stop();
            Equal(4, calls, "four stretches sent");
            List<(LingException.Kind? kind, int status, int calls)> shown;
            lock (seen) shown = seen.Where(p => p.kind is not null).ToList();
            Check(shown.Count > 0 && shown.All(p => p.kind == LingException.Kind.Http && p.status == 502), "three 502s in a row are said");
            Check(shown.All(p => p.calls >= 3), "not after one or two");
            Equal(null, engine.Problem, "the next stretch heard clears it");
            Equal("Back again.", store.Get(engine.SessionId!)!.Lines.Single().Src, "and its line is there");
        }
        finally { LingClient.Spacing = old; }
    }

    public static void FinalNotesKeepRetryingForAboutAMinute()
    {
        Check(LingClient.RetryWaits(Priority.Translate).Length == 0, "translation fails fast");
        Check(LingClient.RetryWaits(Priority.Translate, audio: true).SequenceEqual(new double[] { 1, 2, 4, 8 }), "heard audio rides out about 15 s");
        Check(LingClient.RetryWaits(Priority.Speak, audio: true).SequenceEqual(new double[] { 1 }), "what I say retries once");
        Check(LingClient.RetryWaits(Priority.Notes).SequenceEqual(new double[] { 1, 2, 4 }), "live notes as before");
        var patient = LingClient.RetryWaits(Priority.Notes, patient: true).Sum();
        Check(patient is >= 50 and <= 70, $"final notes wait about a minute ({patient} s)");
    }

    public static void AClockIsNotSpeech()
    {
        foreach (var madeUp in new[] { "00:00", "00:00.", "1:02:03" }) Check(Translator.IsNoise(madeUp, 1.2), madeUp);
        foreach (var said in new[] { "Hello.", "3 点", "15%", "好的" }) Check(!Translator.IsNoise(said, 1.2), said);
    }

    // MARK: 改正听错的词 (the Mac's CorrectionTests, VocabularyTests and LiveFixesTests, case for case;
    // cases from a 21-minute meeting recording, a DeFi team's weekly)

    static Correction.Verdict Verdict(string from, string to, double c, (string, string)[]? known = null, (string, string)[]? rejected = null) =>
        Correction.Decide(new Correction.Edit(from, to, c), (a, b) => (known ?? []).Contains((a, b)), (a, b) => (rejected ?? []).Contains((a, b)));

    public static void FixSoundAlikeChineseIsApplied()
    {
        Equal(Correction.Verdict.Apply, Verdict("解除质压", "解除质押", 0.9), "质压");
        Check(Verdict("跳便是", "跳变", 0.9) != Correction.Verdict.Apply, "a word dropped: not a sound fix");
        Equal(Correction.Verdict.Apply, Verdict("两个代笔", "两个代币", 0.9), "代笔");
        Equal(Correction.Verdict.Apply, Verdict("管理房", "管理方", 0.9), "管理房");
        Equal(Correction.Verdict.Apply, Verdict("追压", "质押", 0.85), "追压");
        // Only the changed part is compared: 花/概 share nothing, though the phrase around them does.
        Equal(Correction.Verdict.Drop, Verdict("花了大花", "花了大概", 0.85), "花/概");
        Equal(Correction.Verdict.Apply, Verdict("FFT制押", "FFT质押", 0.9), "FFT制押");
    }

    public static void FixConfidentButUnlikeSoundIsDropped()
    {
        Equal(Correction.Verdict.Drop, Verdict("快销", "区块", 0.85), "快销");
        Equal(Correction.Verdict.Drop, Verdict("苍蝇", "方向", 0.85), "苍蝇");
        Equal(Correction.Verdict.Drop, Verdict("机录", "机会", 0.8), "机录");
    }

    public static void FixLowConfidenceIsDropped() => Equal(Correction.Verdict.Drop, Verdict("质压", "质押", 0.5), "low");

    public static void FixSpellingNeedsHighConfidence()
    {
        Equal(Correction.Verdict.Apply, Verdict("cransfer", "transfer", 0.85), "near spelling");
        Equal(Correction.Verdict.Drop, Verdict("cransfer", "transfer", 0.7), "not sure enough");
        Equal(Correction.Verdict.Drop, Verdict("bos", "BOS", 0.9), "case only");
    }

    public static void FixNewNamesAreAsked()
    {
        Equal(Correction.Verdict.Ask, Verdict("莫拉", "Morpho", 0.85), "莫拉");
        Equal(Correction.Verdict.Ask, Verdict("开布特", "Curve", 0.8), "开布特");
        Equal(Correction.Verdict.Ask, Verdict("Ero", "Euler", 0.85), "Ero");
        Equal(Correction.Verdict.Drop, Verdict("莫纳", "Morpho", 0.7), "莫纳");
    }

    /// A learned "S平 → X平" never reaches into "iOS平台"; on its own it still applies.
    public static void FixLearnedWordsStayWhole()
    {
        Check(Correction.WordIn("S平", "iOS平台很好") < 0, "inside iOS");
        Check(Correction.WordIn("A工", "DATA工具") < 0, "inside DATA");
        Check(Correction.WordIn("S平", "在S平台上") >= 0, "on its own");
        Check(Correction.WordIn("S平", "iOS平台和S平台") >= 0, "the second one");
        Check(Correction.WordIn("莫拉", "解释这个莫拉的") >= 0, "Chinese edges");
        Equal("iOS平台和X平台", Correction.Apply([new("S平", "X平")], "iOS平台和S平台").Text, "applied to the whole one");
    }

    /// A translation isn't a misheard name: one 对 to "X平台 → X platform" taught 平台 → platform.
    public static void FixTranslationsAreNotAsked()
    {
        Equal(Correction.Verdict.Drop, Verdict("X平台", "X platform", 0.9), "X平台");
        Equal(Correction.Verdict.Drop, Verdict("平台", "platform", 0.95), "平台");
        Equal(Correction.Verdict.Drop, Verdict("respons", "responsible", 0.85), "respons");
        Equal(Correction.Verdict.Ask, Verdict("GPT四", "GPT4", 0.85), "GPT四");
        Check(Correction.Translation("平台", "platform"), "a translation");
        Check(!Correction.Translation("莫拉", "Morpho"), "a name");
    }

    public static void FixConfirmedHeardFormIsApplied()
    {
        Equal(Correction.Verdict.Apply, Verdict("莫拉", "Morpho", 0.5, known: [("莫拉", "Morpho")]), "known");
        Equal(Correction.Verdict.Apply, Verdict("解释这个莫拉的", "解释这个Morpho的", 0.5, known: [("莫拉", "Morpho")]), "known core");
    }

    public static void FixRejectedIsDropped()
    {
        Equal(Correction.Verdict.Drop, Verdict("质压", "质押", 0.95, rejected: [("质压", "质押")]), "rejected");
        Equal(Correction.Verdict.Drop, Verdict("莫拉", "Morpho", 0.95, known: [("莫拉", "Morpho")], rejected: [("莫拉", "Morpho")]), "rejected beats known");
    }

    public static void FixCoreDropsSharedEnds()
    {
        Equal(("质压", "质押"), Correction.Core("解除质压", "解除质押"), "shared ends");
        Equal(("Un450P三", "Uniswap V3"), Correction.Core("Un450P三", "Uniswap V3"), "a Latin word stays whole");
        Equal(("莫拉", "Morpho"), Correction.Core("解释这个莫拉的", "解释这个Morpho的"), "name");
        Equal(("cransfer", "transfer"), Correction.Core("找了cransfer记录", "找了transfer记录"), "spelling");
        // A Chinese change next to a Latin word leaves the word out.
        Equal(("制押", "质押"), Correction.Core("FFT制押", "FFT质押"), "beside a Latin word");
    }

    public static void FixPinyinFromTheTable()
    {
        Equal("zhi|ya", string.Join("|", Correction.Pinyin("质押")), "质押");
        Check(Correction.SoundsAlike("质压", "质押") && !Correction.SoundsAlike("苍蝇", "方向"), "sound-alike");
        Check(Correction.Han("质押") && !Correction.Han("FFT") && !Correction.Han("质，"), "han");
    }

    public static void FixApplyReplacesAndMarks()
    {
        List<LineFix> fixes = [new("莫拉", "Morpho"), new("质压", "质押"), new("开布特", "Curve", ask: true), new("ropax", "RoPax", off: true)];
        var (text, marks) = Correction.Apply(fixes, "解释这个莫拉的，质压和开布特，ropax");
        Equal("解释这个Morpho的，质押和开布特，ropax", text, "applied");
        Equal("Morpho|质押", string.Join("|", marks.Select(m => text.Substring(m.Start, m.Length))), "marks");
        var (t2, m2) = Correction.Apply([new("质压", "质押"), new("莫拉", "Morpho")], "莫拉说质压");
        Equal("Morpho说质押", t2, "later fix shifts");
        Equal("Morpho|质押", string.Join("|", m2.Select(m => t2.Substring(m.Start, m.Length))), "earlier marks kept");
        // The words went away (the line was heard again differently): nothing breaks.
        Equal("解释这个摩托的", Correction.Apply([new("莫拉", "Morpho")], "解释这个摩托的").Text, "skipped");
    }

    public static void FixParseReply()
    {
        const string reply = """
        {"translation": "I explained Morpho.", "fixes": [{"from": "莫拉", "to": "Morpho", "confidence": 0.85},
         {"from": "不在原文", "to": "x", "confidence": 0.9}]}
        """;
        var p = Correction.Parse(reply, "解释这个莫拉的。");
        Equal("I explained Morpho.", p?.Translation, "translation");
        Equal(new Correction.Edit("莫拉", "Morpho", 0.85), p?.Edits.Single(), "only the words in the subtitle");
        Check(Correction.Parse("I explained Mora.", "x") is null, "not JSON");
        Equal("Hi", Correction.Parse("```json\n{\"translation\": \"Hi\"}\n```", "x")?.Translation, "fenced");
    }

    public static void FixMergeKeepsRefusals()
    {
        List<LineFix> old = [new("莫拉", "Morpho", off: true), new("质压", "质押")];
        List<LineFix> fresh = [new("莫拉", "Morpho"), new("寻检", "巡检")];
        Check(Correction.Merge(old, fresh).SequenceEqual([new LineFix("莫拉", "Morpho", off: true), new LineFix("寻检", "巡检")]), "refusal kept, guess replaced");
        List<LineFix> mine = [new("跑好的", "跑跑的"), new("开布特", "Curve", user: true)];
        Check(Correction.Merge(mine, []).SequenceEqual([new LineFix("开布特", "Curve", user: true)]), "the recheck takes back a guess, not the user's yes");
        Check(Correction.Merge(mine, [new("开布特", "Cobalt")]).SequenceEqual([new LineFix("开布特", "Curve", user: true)]), "nor overrides the user's word");
    }

    public static void FixUserEditOnTopOfAFix()
    {
        List<LineFix> fixes = [new("莫纳", "Morpho")];
        const string src = "扩展到这个莫纳的 Link";
        var shown = Correction.Apply(fixes, src).Text;
        var e = Correction.UserEdit(shown, "扩展到这个Monad的 Link", src, fixes);
        Equal(new LineFix("Morpho", "Monad", user: true), e?.Fix, "edit of a fix");
        Equal("莫纳", e?.Heard, "heard as");
        Equal("扩展到这个Monad的 Link", Correction.Apply([.. fixes, e!.Value.Fix], src).Text, "applied last");
        Equal("木娜", Correction.UserEdit("我木娜找了一个", "我在 Monad 找了一个", "我木娜找了一个", [])?.Heard, "a plain heard word");
        Check(Correction.UserEdit("a", " a ", "a", []) is null, "unchanged");
    }

    public static void FixAddedWordStaysOnItsLineAndNeverMatchesPunctuation()
    {
        // "now" added before the full stop: the fix is the last word, unique in the line, not ".".
        const string line = "Great, let's lock that in.";
        var e = Correction.UserEdit(line, "Great, let's lock that in now.", line, []);
        Equal("in", e?.Fix.From, "from");
        Equal("in now", e?.Fix.To, "to");
        Equal(false, e?.Swap, "added, not swapped");
        Equal("Great, let's lock that in now.", Correction.Apply([e!.Value.Fix], line).Text, "applied");
        // A word added at the start.
        var s = Correction.UserEdit(line, "OK Great, let's lock that in.", line, []);
        Equal("Great", s?.Fix.From, "start from");
        Equal("OK Great", s?.Fix.To, "start to");
        Equal(false, s?.Swap, "start swap");
        // A word that appears twice: grown until the span is unique.
        var t = Correction.UserEdit("in the room in the hall", "in the room inside the hall", "in the room in the hall", []);
        Equal("in the room inside the hall", Correction.Apply([t!.Value.Fix], "in the room in the hall").Text, "unique span");
        // Chinese: an inserted word takes its neighbour.
        var c = Correction.UserEdit("好的我来看一下", "好的OK我来看一下", "好的我来看一下", []);
        Equal("好的OK我来看一下", c is { } cc ? Correction.Apply([cc.Fix], "好的我来看一下").Text : null, "Chinese insert");
        Equal(false, c?.Swap, "Chinese swap");
        // A real swap is still a swap.
        Equal(true, Correction.UserEdit("我木娜找了", "我Monad找了", "我木娜找了", [])?.Swap, "swap");
    }

    public static void FixLabelNamesAnAddedWordWhole()
    {
        Equal(("in", "in now"), Correction.Label(new LineFix("in", "in now", user: true)), "added at the end");
        Equal(("Great", "OK Great"), Correction.Label(new LineFix("Great", "OK Great", user: true)), "added at the start");
        Equal(("质压", "质押"), Correction.Label(new LineFix("解除质压", "解除质押")), "a swap: the changed words");
    }

    public static void FixDroppedWordKeepsBothSidesOfTheFix()
    {
        const string line = "Great, let's lock that in now.";
        var e = Correction.UserEdit(line, "Great, let's lock that in.", line, []);
        Check(e is { } x && x.Fix.From.Length > 0 && x.Fix.To.Length > 0, $"both sides: {e?.Fix.From} → {e?.Fix.To}");
        Equal("Great, let's lock that in.", Correction.Apply([e!.Value.Fix], line).Text, "applied");
        var l = Correction.Label(e.Value.Fix);
        Check(l.From.Length > 0 && l.To.Length > 0, $"label: {l.From} → {l.To}");
    }

    public static void FixesEditRevertEditRevertGoesBack()
    {
        var (fx, store, id) = FixSetup("Great, let's lock that in.", "Design signs off by Friday.");
        for (int i = 0; i < 2; i++)
        {
            fx.Edit("l0", id, "Great, let's lock that in now.", everywhere: true, remember: true);
            Equal("Great, let's lock that in now.", FixLine(store, id, "l0").Shown, $"edited {i}");
            var f = FixLine(store, id, "l0").Fixes!.First(x => x.Applied);
            fx.Revert(f, "l0", id);
            Equal("Great, let's lock that in.", FixLine(store, id, "l0").Shown, $"reverted {i}");
        }
        Equal(1, FixLine(store, id, "l0").Fixes!.Count, "one fix");
        Equal(null, FixLine(store, id, "l1").Fixes, "other line untouched");
    }

    public static void FixesRevertNamesAnAddedWordWhole()
    {
        var (fx, store, id) = FixSetup("Great, let's lock that in.");
        fx.Edit("l0", id, "Great, let's lock that in now.", everywhere: false, remember: false);
        fx.Revert(FixLine(store, id, "l0").Fixes![0], "l0", id);
        Equal("Great, let's lock that in.", FixLine(store, id, "l0").Shown, "reverted");
        Check(fx.Toast?.Text.Contains("已改回 in，") == true, "toast: " + fx.Toast?.Text);
    }

    public static void FixesAddedWordEditStaysOnItsLine()
    {
        var (fx, store, id) = FixSetup("Great, let's lock that in.", "Done.");
        Equal(1, fx.SameHeard("l0", id, "Great, let's lock that in now.")?.Count, "one line");
        Equal(1, fx.Edit("l0", id, "Great, let's lock that in now.", everywhere: true, remember: true), "changed");
        Equal("Done.", FixLine(store, id, "l1").Shown, "the full stop elsewhere untouched");
        Equal(0, fx.Vocabulary.Terms.Count, "nothing taught");
        Check(fx.Toast?.Text.Contains("in → in now") == true, "the toast shows the span it changed: " + fx.Toast?.Text);
    }

    public static void NumberedIntegerPlaceholders()
    {
        var files = new Dictionary<string, string> { ["en.lproj/Localizable.strings"] = "\"整场听成 %@ 的 %lld 处都改\" = \"All %2$lld places heard as %1$@ in this meeting\";" };
        try
        {
            Strings.Load(p => files.GetValueOrDefault(p), "en");
            Equal("All 2 places heard as 木娜 in this meeting", Strings.LF("整场听成 %@ 的 %lld 处都改", "木娜", 2), "positional");
        }
        finally { Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans"); }
    }

    public static void VocabAYesNeverTeachesATranslation()
    {
        var v = new Vocabulary(null);
        v.Confirm("平台", "platform");
        Equal(0, v.Terms.Count, "a yes in a meeting");
        v.Confirm("平台", "platform", source: "user");
        Check(v.Knows("平台", "platform"), "the user's own");
    }

    public static void VocabImportLinesWithHeardForms()
    {
        var v = new Vocabulary(null);
        var r = v.Import("Uniswap V3\nMorpho = 莫拉、莫法\n\n" + new string('长', 41) + "\n巡检=寻检,巡练");
        Equal("added=3 updated=0 skipped=[4]", r.ToString(), "result");
        Check(v.Knows("莫法", "morpho"), "case-free word");
        Equal("寻检|巡练", string.Join("|", v.Terms.First(t => t.Word == "巡检").Heard), "heard forms");
    }

    public static void VocabSameWordWhateverWidthOrCase()
    {
        var v = new Vocabulary(null);
        v.Import("Aave");
        var r = v.Import("ＡＡＶＥ = 阿韦");
        Check(r.Updated == 1 && r.Added == 0, "updated");
        Equal(1, v.Terms.Count, "one word");
        Check(v.Knows("阿韦", "Aave"), "known");
    }

    public static void VocabConfirmAndForget()
    {
        var v = new Vocabulary(null);
        v.Confirm("开布特", "Curve");
        Check(v.Terms is [{ Word: "Curve", Heard: ["开布特"], Source: "live" }], "confirmed");
        v.Forget("开布特", "Curve");
        Check(!v.Knows("开布特", "Curve"), "forgotten");
    }

    public static void VocabPromptPutsRecentFirst()
    {
        var v = new Vocabulary(null);
        v.Import("A\nB = b");
        v.Use("B", DateTimeOffset.FromUnixTimeSeconds(100));
        Equal("B (heard as b)|A", string.Join("|", v.PromptLines()), "recent first");
    }

    public static void VocabSavesAndLoadsTheMacsFile()
    {
        var path = Path.Combine(Path.GetTempPath(), $"vocab-{Guid.NewGuid()}.json");
        try
        {
            var v = new Vocabulary(path);
            v.Import("Morpho = 莫拉");
            v.Use("Morpho", DateTimeOffset.Parse("2026-11-07T06:30:00Z"));
            Check(new Vocabulary(path).Knows("莫拉", "Morpho"), "loaded");
            var keys = JsonNode.Parse(File.ReadAllText(path))![0]!.AsObject().Select(p => p.Key);
            Equal("fixes,heard,source,used,word", string.Join(",", keys), "the Mac's keys, sorted");
            Check(File.ReadAllText(path).Contains("\"used\": \"2026-11-07T06:30:00Z\""), "ISO-8601 dates");
            const string mac = """[ { "fixes" : 2, "heard" : [ "开布特" ], "source" : "live", "used" : "2026-11-07T06:30:00Z", "word" : "Curve" } ]""";
            File.WriteAllText(path, mac);
            var m = new Vocabulary(path);
            Check(m.Knows("开布特", "Curve") && m.Terms[0].Fixes == 2, "reads the Mac's file");
        }
        finally { File.Delete(path); }
    }

    public static void VocabRenameKeepsHeardFormsAndMerges()
    {
        var v = new Vocabulary(null);
        v.Import("Morfo = 莫拉\nMorpho = 莫法");
        v.Rename("Morfo", "Morpho");
        Equal(1, v.Terms.Count, "merged");
        Check(v.Knows("莫拉", "Morpho") && v.Knows("莫法", "Morpho"), "both heard forms");
    }

    public static void VocabEditsThatArentAWordForAWordTeachNothing()
    {
        var v = new Vocabulary(null);
        v.Confirm("持。", "讲。");
        Check(v.Knows("持", "讲"), "trimmed of the full stop");
        v.Confirm("我来", "OK我来", "user");
        v.Confirm("然后，", "然后");
        Equal("讲", string.Join(",", v.Terms.Select(t => t.Word)), "words around the heard ones teach nothing");
        v.Confirm("木娜", "Monad", "user");
        v.Confirm("Uni斯图 V三", "Uniswap V3");
        Check(v.Knows("木娜", "Monad") && v.Knows("Uni斯图 V三", "Uniswap V3"), "a word for a word is learned");
    }

    public static void FixesEditThatIsntAWordForAWordStillAppliesButTeachesNothing()
    {
        var (fx, store, id) = FixSetup("我来", "我来吧");
        fx.Edit("l0", id, "OK我来", everywhere: true, remember: true);
        Equal("OK我来", FixLine(store, id, "l0").Shown, "applied");
        Equal(0, fx.Vocabulary.Terms.Count, "nothing taught");
        Check(fx.Toast?.Text.Contains("记进词表") == false, "the toast doesn't say it was saved: " + fx.Toast?.Text);
    }

    public static void VocabOwnersAndPreview()
    {
        var v = new Vocabulary(null);
        v.Import("Morpho = 莫拉");
        Equal("Morpho", string.Join(",", v.Owners("莫拉", "Mora")), "owner");
        Equal(0, v.Owners("莫拉", "Morpho").Count, "not its own");
        Equal("added=1 updated=1 skipped=[3]", v.Preview("Morpho = 莫法\nPendle\n" + new string('长', 41)).ToString(), "preview");
        Equal(1, v.Terms.Count, "preview changes nothing");
    }

    static (LiveFixes fx, SessionStore store, string id) FixSetup(params string[] lines)
    {
        var store = new SessionStore();
        var id = store.Begin(DateTimeOffset.Now.AddDays(-Random.Shared.Next(1, 100000))).Id;
        for (int i = 0; i < lines.Length; i++)
            store.Append(id, new TranscriptLine { Id = $"l{i}", T = i, Src = lines[i], SrcLang = "zh-CN", DstLang = "en" });
        return (new LiveFixes(store, new Vocabulary(null), new AppSettings { FixMisheard = true, AskNames = true }), store, id);
    }

    static TranscriptLine FixLine(SessionStore store, string id, string l) => store.Get(id)!.Lines.First(x => x.Id == l);

    public static void FixesRecheckTakesBackAGuessButKeepsTheUsersYes()
    {
        var (fx, store, id) = FixSetup("最近那个开布特提了，这个是跑好的测试");
        fx.Received(id, "l0", [new("开布特", "Curve", 0.9), new("跑好的", "跑跑的", 0.9)]);
        Check(FixLine(store, id, "l0").Shown.Contains("跑跑的"), "sound-alike applied");
        fx.Answer(fx.Pending(id)[0].Fix, true, id);
        Equal("最近那个Curve提了，这个是跑跑的测试", FixLine(store, id, "l0").Shown, "yes");
        // The second pass, with the lines after it in view, proposes nothing.
        fx.Received(id, "l0", []);
        Equal("最近那个Curve提了，这个是跑好的测试", FixLine(store, id, "l0").Shown, "guess taken back, yes kept");
    }

    public static void FixesConfirmedHeardFormsApplyWithoutTheService()
    {
        var (fx, store, id) = FixSetup("扩展到这个莫拉的链", "单个的拉不改");
        fx.Vocabulary.Confirm("莫拉", "Morpho");
        fx.ApplyKnown(id, "l0");
        fx.ApplyKnown(id, "l1");
        Equal("扩展到这个Morpho的链", FixLine(store, id, "l0").Shown, "known");
        Equal(null, FixLine(store, id, "l1").Fixes, "one character never");
    }

    public static void FixesEditEverywhereTeachesTheListAndUndoPutsItBack()
    {
        var (fx, store, id) = FixSetup("我木娜找了一个", "木娜那边也有", "别的");
        Equal(2, fx.SameHeard("l0", id, "我Monad找了一个")?.Count, "same heard");
        Equal(2, fx.Edit("l0", id, "我Monad找了一个", everywhere: true, remember: true), "changed");
        Equal("Monad那边也有", FixLine(store, id, "l1").Shown, "everywhere");
        Check(fx.Vocabulary.Knows("木娜", "Monad"), "taught");
        Check(fx.Toast?.Text.Contains("Monad") == true, "toast");
        // A later pass can't override what the user wrote.
        fx.Received(id, "l1", [new("木娜", "Mona", 0.95)]);
        Equal("Monad那边也有", FixLine(store, id, "l1").Shown, "user wins");
        fx.Undo();
        Equal("我木娜找了一个", FixLine(store, id, "l0").Shown, "undone");
        Check(!fx.Vocabulary.Knows("木娜", "Monad"), "list undone");
    }

    public static void FixesOneOffEditDoesNotTeachTheList()
    {
        var (fx, store, id) = FixSetup("我木娜找了一个", "木娜那边也有");
        fx.Edit("l0", id, "我Monad找了一个", everywhere: false, remember: true);
        Equal("木娜那边也有", FixLine(store, id, "l1").Shown, "other line untouched");
        Equal(0, fx.Vocabulary.Terms.Count, "nothing taught");
    }

    public static void FixesLaterTakesItOffTheCardButKeepsItWaiting()
    {
        var (fx, _, id) = FixSetup("最近那个开布特提了");
        fx.Received(id, "l0", [new("开布特", "Curve", 0.9)]);
        var a = fx.Asking(id)!.Value;
        fx.Later(a.Fix, id);
        Check(fx.Asking(id) is null, "off the card");
        Equal(1, fx.Pending(id).Count, "still waiting");
        fx.Undo();
        Check(fx.Asking(id) is not null, "back on the card");
    }

    public static void FixesRevertStaysRevertedThroughTheRecheck()
    {
        var (fx, store, id) = FixSetup("但质压这种");
        fx.Received(id, "l0", [new("质压", "质押", 0.9)]);
        fx.Revert(FixLine(store, id, "l0").Fixes![0], "l0", id);
        fx.Received(id, "l0", [new("质压", "质押", 0.9)]);
        Equal("但质压这种", FixLine(store, id, "l0").Shown, "stays reverted");
    }

    public static void FixesYesFixesTheRestOfTheMeetingAtOnce()
    {
        var (fx, store, id) = FixSetup("最近那个开布特提了", "开布特那边也说了");
        fx.Received(id, "l0", [new("开布特", "Curve", 0.9)]);
        fx.Answer(fx.Pending(id)[0].Fix, true, id);
        Equal("Curve那边也说了", FixLine(store, id, "l1").Shown, "the other line follows at once");
        fx.Undo();
        Equal("开布特那边也说了", FixLine(store, id, "l1").Shown, "undo takes it back");
    }

    public static void FixesOffLeavesLinesAsHeard()
    {
        var (fx, store, id) = FixSetup("但质压这种");
        var off = new LiveFixes(store, fx.Vocabulary, new AppSettings { FixMisheard = false });
        Check(off.Context(id, "l0") is null, "no context: the request is the plain translation");
        off.Received(id, "l0", [new("质压", "质押", 0.9)]);
        Equal(null, FixLine(store, id, "l0").Fixes, "nothing fixed");
    }

    /// A finished line goes to the AI service again with fixes asked for, in one request with the
    /// Mac's prompt and no JSON mode; its translation (of the sentence as fixed) replaces Ming's.
    public static async Task FixesRideOnTheSentencesTranslation()
    {
        var fake = new Fake(body =>
        {
            if (body.Contains("Ming-3.0-audio-flash")) return Reply("LANG: zh-CN\nORIGINAL: 我们讨论解除质压的事。\nTRANSLATION: We discussed unpledging.");
            if (body.Contains("point out words the speech recognizer got wrong"))
                return Reply("{\"translation\": \"We discussed releasing the staking.\", \"fixes\": [{\"from\": \"质压\", \"to\": \"质押\", \"confidence\": 0.9}]}");
            return Reply("{}");
        });
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var settings = new AppSettings { Target = "en" };
            var engine = new ListenEngine(ling, new Translator(ling), store, new NotesEngine(ling, store), settings)
            {
                Fixes = new LiveFixes(store, new Vocabulary(null), settings),
            };
            var path = Path.Combine(Path.GetTempPath(), $"cicada-fix-{Environment.ProcessId}.wav");
            File.WriteAllBytes(path, Wav.Bytes([.. Tone(1.2), .. Silence(1)]));
            var src = new FileAudioSource(path, speed: 0);
            var ended = new TaskCompletionSource();
            src.Ended += _ => ended.TrySetResult();
            engine.Start(src);
            await ended.Task;
            for (int i = 0; i < 50 && store.Get(engine.SessionId!)!.Lines.FirstOrDefault()?.Fixes is null; i++) await Task.Delay(50);
            await engine.Stop();
            var l = store.Get(engine.SessionId!)!.Lines[0];
            Equal("我们讨论解除质压的事。", l.Src, "heard");
            Equal("我们讨论解除质押的事。", l.Shown, "fixed");
            Equal("We discussed releasing the staking.", l.Dst, "the fixed sentence's translation");
            string fixing;
            lock (fake.Calls) fixing = fake.Calls.Select(c => c.body).First(b => b.Contains("point out words"));
            Check(!fixing.Contains("response_format"), "no JSON mode");
            Check(JsonNode.Parse(fixing)!.ToJsonString(new System.Text.Json.JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping })
                .Contains("Subtitle: 我们讨论解除质压的事。"), "the heard sentence");
            File.Delete(path);
        }
        finally { LingClient.Spacing = old; }
    }

    // MARK: 分享… (the Mac's ShareTests, case for case: Tests/fixtures/share is the contract)

    static Session ShareSession() =>
        Json.Read<Session>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "share", "session.json")))!;

    public static void ShareFixtureBytes()
    {
        var want = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "share", "share-doc.json")).Trim();
        Equal(want, ShareProjection.Encode(ShareProjection.Doc(ShareSession(), ShareScope.Full, names: false)), "the Mac's bytes");
    }

    public static void ShareNothingPrivateLeaves()
    {
        var text = ShareProjection.Encode(ShareProjection.Doc(ShareSession(), ShareScope.Full, names: false));
        foreach (var secret in new[] { "/Users/someone", "Emma", "Kenji", "Emmer", "Sure, Emma", "hasAudio", "room", "voice" })
            Check(!text.Contains(secret), secret);
    }

    public static void ShareNamesWhenAsked()
    {
        var d = ShareProjection.Doc(ShareSession(), ShareScope.Full, names: true);
        Equal("Emma", d.Notes!.Todos[0].Owner, "todo owner");
        Equal("Emma", d.Notes!.Terms[0].Name, "term");
        Equal(null, d.Notes!.Conclusions[0].Owner, "conclusions never have one");
    }

    public static void ShareNotesOnlyAndRemoved()
    {
        var s = ShareSession();
        Equal(0, ShareProjection.Doc(s, ShareScope.Notes, false).Lines.Count, "notes only");
        var d = ShareProjection.Doc(s, ShareScope.Full, false, new HashSet<int> { 3 }, dropNotes: true);
        Check(d.Lines.Count == 3 && d.Notes is null && d.Hidden == 2, "removed lines and notes counted");
        Check(!ShareProjection.Encode(d).Contains("\"notes\""), "no notes key");
    }

    public static void ShareSpeakerNumbersWithoutNames()
    {
        var s = ShareSession();
        s.Lines = [.. Enumerable.Range(0, 10).Select(i => new TranscriptLine
        {
            Id = $"v{i}", T = i, Speaker = "them", Src = $"this is line number {i}", Dst = $"第 {i} 句话", SrcLang = "en", DstLang = "zh", Voice = i % 2 == 0 ? 3 : 7,
        })];
        Equal("说话人 1,说话人 2", string.Join(",", ShareProjection.Doc(s, ShareScope.Full, false).Lines.Select(l => l.Who).Distinct().Order()), "numbers");
        Equal("Emma,Kenji", string.Join(",", ShareProjection.Doc(s, ShareScope.Full, true).Lines.Select(l => l.Who).Distinct().Order()), "names");
    }

    public static void ShareCopiesOneMessage()
    {
        var now = new DateTimeOffset(2026, 11, 8, 10, 0, 0, TimeSpan.Zero);
        var r = new ShareRecord { Url = "https://cicada.indaloop.app/s/abc", Password = "k7m2p9", ExpiresAt = now.AddDays(7).AddSeconds(-3) };
        Equal("「周会」会议记录\nhttps://cicada.indaloop.app/s/abc\n密码：k7m2p9（7 天内有效）", r.Message("周会", now), "Chinese, with a password");
        var open = new ShareRecord { Url = r.Url, ExpiresAt = now.AddDays(365) };
        Equal("「周会」会议记录\nhttps://cicada.indaloop.app/s/abc\n1 年内有效", open.Message("周会", now), "no password, a year");
        Equal(7, new ShareRecord { ExpiresAt = now.AddDays(7).AddSeconds(2) }.DaysLeft(now), "a clock a little behind the server's still says 7");
        Equal(7, new ShareRecord { ExpiresAt = now.AddDays(6.5) }.DaysLeft(now), "part of a day counts");
        Equal(1, new ShareRecord { ExpiresAt = now.AddMinutes(10) }.DaysLeft(now), "never 0");
        var res = Path.Combine(AppContext.BaseDirectory, "Resources");
        try
        {
            Strings.Load(res, "en");
            Equal("Meeting record: Weekly\nhttps://cicada.indaloop.app/s/abc\nPassword: k7m2p9 (valid for 7 days)", r.Message("Weekly", now), "English");
            Strings.Load(res, "ja");
            Equal("パスワード：k7m2p9（7 日間有効）", r.Message("x", now).Split('\n')[2], "Japanese");
        }
        finally { Strings.Load(res, "zh-Hans"); }
    }

    public static void ShareRoundsAndLanguages()
    {
        var s = ShareSession();
        s.Lines = [
            new TranscriptLine { Id = "a", T = 0.25, Src = "x", Dst = "x", SrcLang = "ja-JP", DstLang = "zh-Hans" },
            new TranscriptLine { Id = "b", T = 0.35, Src = "y", Dst = "", SrcLang = "en-US", DstLang = "zh" },
            new TranscriptLine { Id = "c", T = 1.05, Src = "z", Dst = "zz", SrcLang = "en", DstLang = "zh-CN" },
        ];
        var d = ShareProjection.Doc(s, ShareScope.Full, false);
        Equal("0.3,0.4,1.1", string.Join(",", d.Lines.Select(l => l.T.ToString(System.Globalization.CultureInfo.InvariantCulture))), "half away from zero");
        Check(d.Lines[0].Dst is null && d.Lines[1].Dst is null, "dst left out when empty or the same");
        Equal("en,zh", string.Join(",", d.Langs), "most lines by base code");
        Equal("\"a\\\"b\\\\c\\nd/e\"", ShareProjection.Encode(d with { Title = "a\"b\\c\nd/e" }).Split("\"title\":")[^1].Split(",\"v\"")[0], "escapes as Swift");
    }

    public static void SharePasswordVerifier()
    {
        var salt = Enumerable.Repeat((byte)1, 16).ToArray();
        var v = SharePassword.Verifier("ruby-41-lake", salt, 1000);
        Equal("eab69fcd00a0517794c156495dd76ad1fbfb036ea03df3d59a68a33519009c81", Convert.ToHexStringLower(v), "the browser's PBKDF2");
        Check(!v.SequenceEqual(SharePassword.Verifier("ruby-41-laka", salt, 1000)), "another password");
        Equal(3, SharePassword.Make().Split('-').Length, "word-NN-word");
    }

    public static void ShareBlockedHitsMapBack()
    {
        var hits = new[] { new ShareHit("lines", 2, 3, ["credential"]), new ShareHit("notes", null, null, ["personal"]) };
        Equal("4,5", string.Join(",", ShareHit.RecordLines(hits, [0, 1, 4, 5, 6]).Order()), "sent lines back to the record's");
    }

    public static void Ed25519Rfc8032()
    {
        (string sk, string pk, string msg, string sig)[] vectors =
        [
            ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
             "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
            ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
             "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
            ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
             "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
        ];
        foreach (var (sk, pk, msg, sig) in vectors)
        {
            var seed = Convert.FromHexString(sk);
            var m = Convert.FromHexString(msg);
            Equal(pk, Convert.ToHexStringLower(Ed25519.PublicKey(seed)), "public key");
            Equal(sig, Convert.ToHexStringLower(Ed25519.Sign(seed, m)), "signature");
            Check(Ed25519.Verify(Convert.FromHexString(pk), m, Convert.FromHexString(sig)), "verifies");
            var bad = Convert.FromHexString(sig); bad[5] ^= 1;
            Check(!Ed25519.Verify(Convert.FromHexString(pk), m, bad), "a changed signature doesn't");
        }
    }

    static byte[] UnB64Url(string s) => Convert.FromBase64String(s.Replace('-', '+').Replace('_', '/').PadRight((s.Length + 3) / 4 * 4, '='));

    /// Answers the share service's routes and checks each signed request as server/src/auth.js does.
    sealed class ShareServer(Func<HttpRequestMessage, string, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public readonly List<string> Seen = [];
        public byte[]? Pub;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken cancel)
        {
            var body = r.Content is null ? "" : await r.Content.ReadAsStringAsync(cancel);
            var path = r.RequestUri!.PathAndQuery;
            if (path == "/api/v1/devices")
            {
                var j = JsonNode.Parse(body)!;
                Pub = UnB64Url(j["key"]!.GetValue<string>());
                var h = System.Security.Cryptography.SHA256.HashData([.. Pub, .. UnB64Url(j["pow"]!.GetValue<string>())]);
                Check(h[0] == 0 && h[1] == 0 && h[2] < 16, "proof of work");
                Check(j["platform"]!.GetValue<string>() == "windows", "platform");
            }
            else
            {
                string H(string k) => r.Headers.TryGetValues("X-Cicada-" + k, out var v) ? v.First() : "";
                var message = $"{r.Method.Method}\n{path}\n{H("Time")}\n{H("Nonce")}\n{Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(body)))}";
                Check(Ed25519.Verify(Pub!, Encoding.UTF8.GetBytes(message), UnB64Url(H("Signature"))), "signed " + path);
                Check(Regex.IsMatch(H("Nonce"), "^[A-Za-z0-9_-]{16,64}$"), "nonce");
            }
            Check(r.Headers.GetValues("X-Cicada-Client").First() == "windows/9.9.9", "client header");
            lock (Seen) Seen.Add($"{r.Method.Method} {path}");
            return respond(r, body);
        }
    }

    public static async Task ShareClientSignsAndStores()
    {
        var folder = Path.Combine(Paths.Root, "share-test");
        bool forgotten = true;
        var server = new ShareServer((r, body) =>
        {
            var path = r.RequestUri!.AbsolutePath;
            if (path == "/api/v1/devices") return Status(201, "{\"device\":\"0123456789abcdef0123456789abcdef\"}");
            if (path == "/api/v1/shares" && r.Method == HttpMethod.Post)
            {
                // The first signed call finds the device forgotten: the client registers again once.
                if (forgotten) { forgotten = false; return Status(401, "{\"code\":\"unknown_device\"}"); }
                var j = JsonNode.Parse(body)!;
                Check(r.Headers.GetValues("Idempotency-Key").First().StartsWith("20261106-140000-"), "idempotency key");
                if (j["scope"]!.GetValue<string>() == "full")
                    return Status(422, "{\"code\":\"blocked\",\"hits\":[{\"part\":\"lines\",\"from\":1,\"to\":1,\"questions\":[\"credential\"]}]}");
                Check(j["password"]!["iter"]!.GetValue<int>() == 210000, "iterations");
                Check(j["doc"]!["lines"]!.AsArray().Count == 0 && j["doc"]!["notes"] is not null, "notes only");
                return Status(201, "{\"id\":\"AAAAAAAAAAAAAAAAAAAAAA\",\"url\":\"https://x/s/AAAAAAAAAAAAAAAAAAAAAA\",\"token\":\"tok\",\"expiresAt\":1900000000}");
            }
            if (r.Method == HttpMethod.Get) return Status(200, "{\"shares\":[{\"id\":\"AAAAAAAAAAAAAAAAAAAAAA\",\"expiresAt\":1900000000,\"state\":\"live\",\"views\":3}]}");
            if (r.Method == HttpMethod.Delete)
            {
                Check(r.Headers.Authorization?.ToString() == "Bearer tok", "manage token");
                return new HttpResponseMessage(HttpStatusCode.NoContent);
            }
            return Status(404, "{\"code\":\"not_found\"}");
        });
        var client = new ShareClient(new PlainProtector(), "windows", "9.9.9", server, folder);
        var s = ShareSession();
        var shared = await client.Share(s, new ShareOptions { Password = "ruby-41-lake" }) as ShareOutcome.Shared;
        Check(shared is not null, "shared");
        Equal(2, server.Seen.Count(x => x == "POST /api/v1/devices"), "registered again after unknown_device");
        Equal("tok", client.Store.Read(s.Id)!.Token, "token kept");
        Equal("ruby-41-lake", client.Store.Read(s.Id)!.Password, "password kept");
        if (!OperatingSystem.IsWindows())
            Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(Path.Combine(folder, "Shares", s.Id + ".json")), "0600");
        Equal(3, (await client.StatsOf(["AAAAAAAAAAAAAAAAAAAAAA"]))["AAAAAAAAAAAAAAAAAAAAAA"].Views, "views");
        var blocked = await client.Share(s, new ShareOptions { Scope = ShareScope.Full }) as ShareOutcome.Blocked;
        Equal("1", string.Join(",", ShareHit.RecordLines(blocked!.Hits, blocked.Kept)), "blocked line");
        Check(await client.Revoke(shared!.Record, s.Id), "revoked");
        Equal(null, client.Store.Read(s.Id), "forgotten after revoke");
        Equal(2, server.Seen.Count(x => x == "POST /api/v1/devices"), "the device file is reused");
    }

    // MARK: 存到文件夹 (Tests/fixtures/folder-export is the contract, as in the Mac's FolderExportTests)

    static string FolderFixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "folder-export", name));
    static Session FolderSession() => Json.Read<Session>(FolderFixture("session.json"))!;
    static JsonNode FolderCases() => JsonNode.Parse(FolderFixture("cases.json"))!;
    static TimeZoneInfo FolderZone() => TimeZoneInfo.FindSystemTimeZoneById((string)FolderCases()["timeZone"]!);
    static IEnumerable<(string, string)> Pairs(string key) => FolderCases()[key]!.AsArray().Select(p => ((string)p![0]!, (string)p[1]!));

    public static void FolderExportFrontmatterBytes()
    {
        var got = FolderExportFormat.Frontmatter(FolderSession(), FolderZone());
        Equal(FolderFixture("frontmatter.md"), got, "frontmatter bytes");
        Check(!got.Contains('\r'), "\\n line ends on Windows too");
    }

    public static void FolderExportFileName()
    {
        var stem = FolderExportFormat.Stem(FolderSession(), FolderZone());
        Equal((string)FolderCases()["fileName"]!, FolderExportFormat.FileName(stem, _ => false), "file name");
    }

    public static void FolderExportNames()
    {
        foreach (var (name, want) in Pairs("names")) Equal(want, FolderExportFormat.SafeName(name), $"safe name of «{name}»");
        foreach (var (title, want) in Pairs("stems"))
        {
            var s = FolderSession();
            s.Title = title;
            Equal(want, FolderExportFormat.Stem(s, FolderZone()), $"stem of «{title}»");
        }
        foreach (var (text, want) in Pairs("escapes")) Equal(want, FolderExportFormat.Quote(text), $"quote of «{text}»");
        foreach (var c in FolderCases()["collisions"]!.AsArray())
        {
            var taken = c!["taken"]!.AsArray().Select(t => (string)t!).ToList();
            Equal((string)c["want"]!, FolderExportFormat.FileName((string)c["stem"]!, taken.Contains), $"collision with {taken.Count} taken");
        }
    }

    /// The name: the user's title, else the notes', else the imported file's, never the display title.
    public static void FolderExportNamePrecedence()
    {
        var s = FolderSession();
        s.Renamed = false;
        s.Title = SessionStore.DefaultTitle(s.StartedAt);
        Equal("产品路线评审", FolderExportFormat.Name(s), "the notes' title");
        s.Notes = null;
        Equal("", FolderExportFormat.Name(s), "nothing");
        s.SourceFile = "Weekly sync.m4a";
        Equal("Weekly sync", FolderExportFormat.Name(s), "the file's name");
        Check(FolderExportFormat.Frontmatter(s).Contains("source: \"file\"\nnotes: \"none\""), "an imported file without notes");
        s.Renamed = null;
        s.Title = "会议 11月6日 14:00";
        Equal("Weekly sync", FolderExportFormat.Name(s), "an older record's default title isn't a name");
    }

    public static void FolderExportPaths()
    {
        var json = """{"vaults":{"a":{"path":"C:\\v\\old","ts":1},"b":{"path":"C:\\v\\new","ts":5,"open":true},"c":{"path":"D:\\gone","ts":9}}}""";
        var vaults = FolderExportFormat.ObsidianVaults(json, p => p != @"D:\gone");
        Equal(@"C:\v\new|C:\v\old", string.Join("|", vaults), "newest first, only ones that exist");
        Equal(0, FolderExportFormat.ObsidianVaults("not json").Count, "unreadable");
        Equal(@"C:\v\new", FolderExportFormat.Vault(@"c:\V\New\Cicada", vaults), "inside a vault, ignoring case");
        Equal(null, FolderExportFormat.Vault(@"C:\v\newer\Cicada", vaults), "a neighbour isn't inside");
        Equal("Documents › Cicada", FolderExportFormat.ShortPath(@"C:\Users\a\Documents\Cicada\"), "parent › folder");
        Equal("D: › Cicada", FolderExportFormat.ShortPath(@"D:\Cicada"), "a drive's top folder");
        Equal("文档 › Cicada", FolderExportFormat.ShortPath(@"C:\Users\a\Documents\Cicada", p => p.EndsWith("Documents") ? "文档" : null), "Explorer's names");
        Equal(@"D:\", FolderExportFormat.Parent(@"D:\Cicada"), "the drive is the parent");
        string[] roots = [@"C:\Users\a\OneDrive\Documents", @"C:\Users\a\Desktop"];
        Check(FolderExportFormat.Protected(@"C:\Users\a\OneDrive\Documents\Cicada", roots), "Documents is protected");
        Check(!FolderExportFormat.Protected(@"C:\Users\a\Notes\Cicada", roots), "elsewhere isn't");
    }

    public static async Task FolderExportWrites()
    {
        var dir = Path.Combine(Path.GetTempPath(), "cicada-export-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(dir, "Cicada");
        Directory.CreateDirectory(dir);
        try
        {
            var store = new SessionStore();
            var s = store.Begin(new DateTimeOffset(2026, 11, 6, 14, 0, 0, TimeSpan.Zero));
            store.Append(s.Id, new TranscriptLine { Id = "l1", Src = "Hello", SrcLang = "en", Dst = "你好", DstLang = "zh", T = 3 });
            store.End(s.Id, s.StartedAt.AddMinutes(30));
            store.Rename(s.Id, "周会");
            var settings = new AppSettings();
            var index = Path.Combine(dir, "FolderExport.json");
            var ex = new FolderExporter(store, settings, index) { Delay = TimeSpan.FromMilliseconds(20) };
            var stem = FolderExportFormat.Stem(store.Get(s.Id)!);
            // A file Cicada didn't write is never overwritten.
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, stem + ".md"), "mine");
            ex.Choose(folder);
            await ex.Idle();
            Equal(null, ex.Trouble, "the folder can be written");
            Check(ex.Unwritten.Any(x => x.Id == s.Id), "an earlier meeting waits for 也存一份");
            ex.WriteAll();
            await ex.Idle();
            Equal(stem + " 2.md", Path.GetFileName(ex.FileFor(s.Id)), "the taken name gets 2");
            Equal("mine", File.ReadAllText(Path.Combine(folder, stem + ".md")), "the user's file stays");
            var text = File.ReadAllText(ex.FileFor(s.Id)!);
            Check(text.StartsWith("---\ncicada: 1\n") && text.Contains("title: \"周会\""), "frontmatter, then the body");
            Check(!Directory.GetFiles(folder, ".cicada*").Any(), "no temporary or check file left");
            Check(Json.Read<FolderExporter.Index>(File.ReadAllText(index))!.Files.ContainsKey(s.Id), "the index keeps it");
            // A new name moves the file.
            store.Rename(s.Id, "周会改");
            store.Flush();
            ex.Saved(s.Id);
            await Task.Delay(200);
            await ex.Idle();
            var moved = ex.FileFor(s.Id)!;
            Check(Path.GetFileName(moved).EndsWith("周会改.md"), "renamed: " + Path.GetFileName(moved));
            Check(!File.Exists(Path.Combine(folder, stem + " 2.md")), "the old file went");
            // Unchanged content isn't written again.
            var at = File.GetLastWriteTimeUtc(moved);
            ex.Saved(s.Id);
            await Task.Delay(200);
            await ex.Idle();
            Equal(at, File.GetLastWriteTimeUtc(moved), "unchanged");
            // Deleting the record leaves its file.
            ex.Deleted(s.Id);
            Check(File.Exists(moved), "the file stays");
            store.Delete(s.Id);
            // A folder whose parent is gone isn't made.
            ex.Choose(Path.Combine(dir, "gone", "Cicada"));
            await ex.Idle();
            Equal(FolderExporter.Kind.Missing, ex.Trouble?.Kind, "missing");
            Check(!Directory.Exists(Path.Combine(dir, "gone")), "nothing made");
        }
        finally { try { Directory.Delete(dir, true); } catch { } }
    }

    // MARK: the talk key (#22: keyboards without right Ctrl)

    public static void TalkKeyChoices()
    {
        Equal("rcontrol", new AppSettings().TalkKey, "right Ctrl by default");
        Equal(0xA3, TalkKey.Named(null).Vk, "no name is right Ctrl");
        Equal(0xA3, TalkKey.Named("nonsense").Vk, "an unknown name is right Ctrl");
        Equal("f13", TalkKey.Choose(0x7C).Key?.Name, "F13 can be one");
        Equal("capslock", TalkKey.Choose(0x14).Key?.Name, "Caps Lock can be one");
        Equal("lcontrol", TalkKey.Choose(0xA2).Key?.Name, "left Ctrl can be one");
        Check(TalkKey.Choose(0x41).Key is null && TalkKey.Choose(0x41).Refused is not null, "a letter is refused");
        Check(TalkKey.Choose(0x20).Key is null, "space is refused");
        Check(TalkKey.Choose(0xA5).Key is null, "right Alt is refused (AltGr, window menus)");
        Check(TalkKey.Choose(0x5B).Key is null, "the Windows key is refused");
        Check(TalkKey.All.Where(k => k.Modifier).All(k => k.Name.EndsWith("control") || k.Name.EndsWith("shift")), "only Ctrl and Shift pass through to other apps");
        Equal(TalkKey.All.Count, TalkKey.All.Select(k => k.Vk).Distinct().Count(), "one key per code");
        foreach (var k in TalkKey.All) Equal(k, TalkKey.Named(k.Name), $"{k.Name} round-trips");
        var s = Json.Read<AppSettings>(Json.Write(new AppSettings { TalkKey = "f13" }))!;
        Equal("f13", s.TalkKey, "kept in settings");
        Equal("rcontrol", Json.Read<AppSettings>("{}")!.TalkKey, "settings from before it are right Ctrl");
    }
}
