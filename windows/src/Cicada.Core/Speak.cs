using System.Globalization;
using System.Security.Cryptography;

namespace Cicada;

/// Where the room's voice goes: the virtual mic (VB-Cable's "CABLE Input"), or the speakers for a
/// preview. Takes 16-bit mono PCM at `rate` and returns once it has played.
public interface ISpeechSink
{
    /// Starts a sentence: PCM chunks follow, then End.
    void Begin(int rate);
    void Write(byte[] pcm);
    Task End();
    /// Whether there is somewhere to play: the virtual mic can go away between the press and the voice.
    bool Ready => true;
}

/// Windows' own voice, for when the AI service's can't speak: 16-bit mono PCM, or null.
public interface ISystemVoice
{
    Task<(byte[] pcm, int rate)?> Speak(string text, string language);
    /// Whether this PC has a voice for the language (Chinese Windows often has only Chinese ones).
    bool Has(string language);
}

/// A voice the room can hear: one of Ming's ("ming:…", through the Ling key), one of another
/// service's speech model ("cloud:…"), or Windows' own.
public sealed record VoiceOption(string Id, string Name, string Tags);

/// Which voices to offer for each language the room may hear, by the AI service in use: on Ling
/// Ming's hand-picked natural ones, as on the Mac (Voices.swift › VoiceCatalog); on another service
/// its speech model's voices, the same in every language, or none without a speech model; then
/// Windows' voice so there is always one.
public static class VoiceCatalog
{
    public const string SystemId = "system", MingPrefix = "ming:", CloudPrefix = "cloud:";

    public static string Key(string code) { var b = code.Split('-')[0]; return b.Length == 0 ? "en" : b; }

    /// Ming's `language_id` for languages that need it (zh and en work without).
    public static string? MingLanguage(string code) => Key(code) is "ja" or "ko" or "de" or "fr" or "es" ? Key(code) : null;

    /// The service's own voices for a language (Ming's on Ling).
    public static IReadOnlyList<VoiceOption> Cloud(string language, AIConfig config) =>
        config.IsLing ? Ming(language) : config.Voices.Select(v => new VoiceOption(CloudPrefix + v.Id, v.Id, v.Gender)).ToList();

    public static IReadOnlyList<VoiceOption> Ming(string language) => Key(language) switch
    {
        "en" => [new("ming:US_Emma", "Emma", "女 · 美式 · 自然对话"), new("ming:UK_George", "George", "男 · 英式 · 稳重"), new("ming:UK_Charlotte", "Charlotte", "女 · 英式 · 平稳")],
        "zh" => [new("ming:灵小雅", "小雅", "女 · 清亮 · 播报"), new("ming:灵小棠", "小棠", "女 · 温和 · 沉稳"), new("ming:灵小锋", "小锋", "男 · 温暖 · 亲切"), new("ming:灵卓然", "卓然", "男 · 沉着 · 清楚")],
        "ja" or "ko" or "de" or "fr" or "es" => [new("ming:US_Emma", "Emma", "女 · Ming"), new("ming:UK_George", "George", "男 · Ming")],
        _ => [],
    };

    /// The user's own voice (Voices.swift › cloneOption), offered with every language once recorded.
    public const string CloneId = "clone";
    public static readonly VoiceOption Clone = new(CloneId, "我自己的声音", "你的音色");

    /// `clone`: the user's recording exists and the service clones (Ling, with a working key).
    public static IReadOnlyList<VoiceOption> Options(string language, AIConfig config, bool windowsHasIt = true, bool clone = false) =>
        [.. Cloud(language, config), .. windowsHasIt ? [new VoiceOption(SystemId, "Windows", "本机")] : Array.Empty<VoiceOption>(), .. clone ? [Clone] : Array.Empty<VoiceOption>()];

    /// What a language uses until the user picks: the service's first voice once it can speak (or
    /// when Windows has none for the language), else Windows'.
    public static string DefaultId(string language, AIConfig config, bool speaks, bool windowsHasIt = true) =>
        (speaks || !windowsHasIt) && Cloud(language, config) is [var first, ..] ? first.Id : SystemId;

    /// The voice chosen for a language, if it is still offered: a Ming voice saved before switching
    /// to ZenMux is not sent there, and "system" saved where Windows has no voice for the language
    /// (Chinese Windows often has only Chinese ones) left the voice blank and 试听 silent (#22). The
    /// user's own voice without its recording or without Ling falls back the same way, and comes
    /// back with them (AppModel.voiceID).
    public static string Chosen(AppSettings settings, string language, AIConfig config, bool speaks, bool windowsHasIt = true, bool clone = false) =>
        settings.SpeakVoices.TryGetValue(Key(language), out var id) && Options(language, config, windowsHasIt, clone).Any(v => v.Id == id) ? id : DefaultId(language, config, speaks, windowsHasIt);

    /// A short line to try a voice with, in the language it will speak.
    public static string Sample(string language) => Key(language) switch
    {
        "zh" => "谢谢大家。我们来看一下上线时间表，并确定谁负责麦克风测试。",
        "ja" => "皆さん、ありがとうございます。発売スケジュールを確認しましょう。",
        "ko" => "감사합니다. 출시 일정을 함께 확인해 보겠습니다.",
        "es" => "Gracias a todos. Revisemos el calendario de lanzamiento.",
        "fr" => "Merci à tous. Regardons ensemble le calendrier de lancement.",
        "de" => "Danke an alle. Schauen wir uns den Zeitplan für den Start an.",
        "pt" => "Obrigado a todos. Vamos ver o cronograma de lançamento.",
        _ => "Thanks everyone. Let's look at the launch timeline and decide who owns the microphone tests.",
    };
}

/// Hold to talk, the Mac's SpeakEngine: what I said (a 16 kHz WAV) → the AI service's hear model
/// (Ming on Ling) hears and translates it in one call → a voice speaks the translation into the virtual mic, so the meeting hears it in the
/// room's language. Never speaks anything untranslated: no translation, no sound.
public sealed class SpeakEngine
{
    public enum Phase { Idle, Recording, Translating, Speaking, Failed }

    readonly LingClient ling;
    readonly Translator translator;
    readonly SessionStore store;
    readonly AppSettings settings;
    readonly Func<string?> roomLanguage;
    readonly Func<(string id, DateTimeOffset startedAt)?> openMeeting;
    readonly ISystemVoice systemVoice;
    int lineCount;
    readonly SemaphoreSlim one = new(1, 1);

    public Phase State { get; private set; }
    /// What the bar shows: what I said, then what the room heard (or why nothing was sent).
    public string? Said { get; private set; }
    public string? Heard { get; private set; }
    public string? Problem { get; private set; }
    /// "ming", "cloud" (another service's speech model) or "system": how the last sentence was voiced.
    public string? LastVoice { get; private set; }
    public event Action? Changed;

    public SpeakEngine(LingClient ling, Translator translator, SessionStore store, AppSettings settings,
        Func<string?> roomLanguage, Func<(string id, DateTimeOffset startedAt)?> openMeeting, ISystemVoice systemVoice)
    {
        this.ling = ling; this.translator = translator; this.store = store; this.settings = settings;
        this.roomLanguage = roomLanguage; this.openMeeting = openMeeting; this.systemVoice = systemVoice;
    }

    /// The language I speak: the setting, else Windows'.
    public string MyLanguage => settings.SpeakFrom == "system" ? Languages.FromSystem(System.Globalization.CultureInfo.CurrentUICulture.Name) : settings.SpeakFrom;

    /// The room's language (SpeakEngine.swift › targetCode): the chosen one, else the language the
    /// other side has been speaking, else English; never my own.
    public string Target => TargetFor(settings.SpeakTo, roomLanguage(), MyLanguage);

    public static string TargetFor(string speakTo, string? room, string mine)
    {
        if (speakTo != "room") return speakTo;
        var r = room ?? "en";
        return VoiceCatalog.Key(r) == VoiceCatalog.Key(mine) ? (VoiceCatalog.Key(mine) == "en" ? "zh-CN" : "en") : r;
    }

    DateTimeOffset? pressedAt;
    double? pressedMono;
    /// When the computer's audio was loud, while listening (the echo check); null when not listening.
    public LoudnessLog? Echo { get; set; }
    /// Share of the press the computer may play through before it counts as echo (Linux's 0.5).
    public const double EchoShare = 0.5;

    /// Whether a press is dropped as the meeting's echo: only on the plain mic (SpeakEngine.swift's
    /// `pressPlain`). Through echo cancellation the meeting's voices are taken out of the mic, and
    /// what is left is me: dropping those presses lost everything said while the other side talked.
    public static bool EchoDrop(bool echoCancelled, double playedShare) => !echoCancelled && playedShare > EchoShare;

    public void BeginRecording()
    {
        pressedAt = DateTimeOffset.Now;
        pressedMono = Echo?.Now;
        State = Phase.Recording; Said = Heard = Problem = null;
        Changed?.Invoke();
    }

    public void Cancel()
    {
        if (State == Phase.Recording) { State = Phase.Idle; Changed?.Invoke(); }
    }

    /// One utterance: `wav` is 16 kHz mono. Returns what the room heard, or null if nothing was sent.
    /// `echoCancelled`: the press was heard through Windows' echo cancellation (`EchoCancel`).
    public async Task<string?> Speak(byte[] wav, ISpeechSink sink, bool echoCancelled = false)
    {
        await one.WaitAsync();
        try
        {
            var released = DateTime.UtcNow;
            // A press nobody spoke in: Ming hears 嗯 in the room's hush and the meeting would hear "Hmm."
            var measure = PressSpeech.Measure(wav);
            Log.Debug($"speak: press of {Math.Max(0, wav.Length - 44) / 32000.0:F1} s, {measure.Summary}");
            if (!measure.Spoken)
            {
                Log.Debug("speak: nothing said in the press, nothing sent");
                State = Phase.Idle; pressedAt = null;
                Changed?.Invoke();
                return null;
            }
            // The meeting playing through most of the press: what the mic heard is its echo as much
            // as me, and Ming would send the other side's words back to them (measured on the Mac).
            if (Echo is { } echo)
            {
                var share = echo.Fraction(pressedMono ?? echo.Now - wav.Length / 32000.0, echo.Now);
                if (EchoDrop(echoCancelled, share))
                {
                    Log.Debug($"speak: the computer played through {share * 100:F0}% of the press on the plain mic (echo), nothing sent");
                    return Fail(Strings.L("对方在说话时说的，没有说出去"));
                }
                if (share > EchoShare) Log.Debug($"speak: the computer played through {share * 100:F0}% of the press, heard with echo cancellation: sending");
            }
            var to = Target;
            State = Phase.Translating; Said = Heard = Problem = null;
            Changed?.Invoke();
            Heard? heard = null;
            try { heard = await translator.Hear(wav, to, MyLanguage, Priority.Speak); }
            catch (LingException e) { Log.Debug($"speak: hear failed {e.Message}"); return Fail(e.Failure is LingException.Kind.Network or LingException.Kind.Timeout ? (ling.Config.IsLing ? Strings.L("连不上 Ling，没有发出去") : Strings.LF("连不上 %@，没有发出去", ling.Config.Name)) : Strings.L("这句没翻译成 · 没有说出去")); }
            if (heard is null) return Fail(Strings.L("没听清，没有发出去"));
            if (PressSpeech.Filler(heard.Original))
            {
                Log.Debug("speak: only a filler heard, nothing sent");
                State = Phase.Idle; pressedAt = null;
                Changed?.Invoke();
                return null;
            }
            Said = heard.Original;
            var text = heard.Translation;
            // Ming didn't translate it: the text translator gets one try; failing that, silence.
            if (text is null && heard.Lang != to) text = await translator.Translate(heard.Original, heard.Lang, to, Translator.Kind.Sentence, Priority.Speak);
            if (string.IsNullOrWhiteSpace(text)) return Fail(Strings.L("这句没翻译成 · 没有说出去"));
            // The virtual mic went away during the press: no voice at all, and never the speakers.
            if (!sink.Ready) return Fail(Strings.L("没有虚拟麦克风 · 没有说出去"));
            var translatedAt = DateTime.UtcNow;
            Heard = text;
            State = Phase.Speaking;
            Changed?.Invoke();
            Record(heard, text, to, pressedAt ?? DateTimeOffset.Now.AddSeconds(-(wav.Length - 44) / 32000.0));
            pressedAt = null;
            var voiced = await Voice(text, to, sink);
            Log.Debug($"speak: {heard.Lang} → {to} via {LastVoice ?? "nothing"}, translated in {(translatedAt - released).TotalMilliseconds:F0} ms, voiced by {(DateTime.UtcNow - released).TotalMilliseconds:F0} ms");
            if (!voiced) return Fail(systemVoice.Has(to) ? Strings.L("没能发出声音") : Strings.L("这台电脑没有这种语言的声音，没有发出去"));
            State = Phase.Idle;
            Changed?.Invoke();
            return text;
        }
        finally { one.Release(); }
    }

    /// Something stopped the sentence before it got here (no mic, no virtual mic): say so on the bar.
    public void Report(string why) => Fail(why);

    string? Fail(string why)
    {
        State = Phase.Failed; Problem = why; pressedAt = null;
        Log.Debug($"speak: nothing sent ({why})");
        Changed?.Invoke();
        return null;
    }

    /// The sentence joins the meeting being listened to, as the Mac's "me" lines do.
    /// Timed from when I started speaking, like the other side's lines.
    void Record(Heard heard, string text, string to, DateTimeOffset spokeAt)
    {
        if (openMeeting() is not { } m) return;
        var line = new TranscriptLine
        {
            Id = $"m{++lineCount}", T = Math.Max(0, (spokeAt - m.startedAt).TotalSeconds), Speaker = "me",
            Src = heard.Original, Dst = text, SrcLang = heard.Lang, DstLang = to,
        };
        store.Append(m.id, line);
    }

    /// The user's recording for their own voice; null in tests that don't need it.
    public VoiceReference? Reference { get; set; }

    /// Whether the user's own voice can be used now: recorded, and Ling with a working key.
    public bool CloneReady => ling.Clones && Reference?.Exists == true;

    /// The voice a language uses now (the choice, or its fallback).
    public string ChosenVoice(string language) =>
        VoiceCatalog.Chosen(settings, language, ling.Config, ling.Speaks, systemVoice.Has(language), CloneReady);

    /// The service's voice (Ming's on Ling, or the user's own cloned from their recording), else
    /// Windows'. True once some sound went out.
    public async Task<bool> Voice(string text, string language, ISpeechSink sink)
    {
        var config = ling.Config;
        var id = ChosenVoice(language);
        var prefix = config.IsLing ? VoiceCatalog.MingPrefix : VoiceCatalog.CloudPrefix;
        var reference = id == VoiceCatalog.CloneId ? Reference?.Reference() : null;
        if ((id.StartsWith(prefix) || reference is not null) && ling.Speaks)
        {
            int chunks = 0;
            try
            {
                var voice = reference is null ? id[prefix.Length..] : null;
                await foreach (var pcm in ling.Speech(text, voice, config.IsLing ? VoiceCatalog.MingLanguage(language) : null, reference))
                {
                    if (chunks++ == 0) sink.Begin(24000);
                    sink.Write(pcm);
                }
            }
            catch (LingException e) { Log.Debug($"speak: {config.Provider.Id} {(reference is null ? "voice" : "cloned voice")} failed {e.Message}"); }
            ling.VoiceSpoke(chunks > 0);
            if (chunks > 0) { await sink.End(); LastVoice = reference is not null ? "clone" : config.IsLing ? "ming" : "cloud"; return true; }
        }
        var own = await systemVoice.Speak(text, language);
        if (own is not { } v || v.pcm.Length == 0) { LastVoice = null; return false; }
        sink.Begin(v.rate);
        sink.Write(v.pcm);
        await sink.End();
        LastVoice = "system";
        return true;
    }
}

/// VB-Cable, the virtual mic: downloaded from VB-Audio when the user asks, never bundled, and run
/// only if it is the exact package checked here (as BlackHole is on the Mac).
public static class VirtualCable
{
    public const string PackageUrl = "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip";
    public const string PackageSha256 = "b950e39f01af1d04ea623c8f6d8eb9b6ea5c477c637295fabf20631c85116bfb";
    /// The render endpoint the app writes to, and the capture one meeting apps pick as the mic.
    public const string InputName = "CABLE Input", OutputName = "CABLE Output";

    public static bool Verify(byte[] package) => Convert.ToHexString(SHA256.HashData(package)).Equals(PackageSha256, StringComparison.OrdinalIgnoreCase);
}

/// Windows can make a freshly installed VB-Cable the default speaker (and mic): then everything the
/// computer plays goes into the cable and the user hears nothing. A user took that for Cicada
/// breaking their sound and nearly uninstalled it. Keys are "<flow>/<role>" (render 0, capture 1;
/// console 0, multimedia 1, communications 2), values the endpoint ids.
public static class CableDefaults
{
    /// The defaults to set back after the install: each one the cable took from a real device.
    public static List<(string Key, string Id)> Restore(IReadOnlyDictionary<string, string> before, IReadOnlyDictionary<string, string> after, Func<string, bool> isCable) =>
        after.Where(a => isCable(a.Value) && before.TryGetValue(a.Key, out var b) && !isCable(b))
            .Select(a => (a.Key, before[a.Key])).OrderBy(r => r.Key, StringComparer.Ordinal).ToList();

    /// A speaker to go back to when nothing was remembered (installed before this, or outside
    /// Cicada): the first that isn't the cable.
    public static string? Speaker(IEnumerable<(string Id, bool Cable)> speakers) => speakers.FirstOrDefault(s => !s.Cable).Id;

    /// The startup notification, once while the cable holds the speaker: someone who routes sound
    /// into it on purpose hears about it once; it comes back only after the speaker was real again.
    public static bool ShouldNotify(bool speakerIsCable, bool notified) => speakerIsCable && !notified;
}

/// Whether anyone spoke during a press of the talk key (PressSpeech in SpeakEngine.swift, same
/// numbers): 0.3 s of 30 ms frames over three times the press's own quiet (its quietest tenth),
/// between -44 and -36 dBFS. A silent press came back from Ming as "嗯。" and went out as "Hmm.";
/// a result that is only fillers isn't sent either.
public static class PressSpeech
{
    const int Frame = 480;
    const double Needed = 0.3;

    /// What the check saw (PressSpeech.Measure on the Mac): seconds over the line, the press's quiet
    /// and the line (RMS, 0–1). Logged per press: echo left after cancellation raises the quiet,
    /// and a line held at its −36 dBFS cap is how a soft voice over the meeting gets dropped.
    public readonly record struct Result(double Voiced, double Floor, double Line)
    {
        public bool Spoken => Voiced >= Needed;
        public string Summary => $"voiced {Voiced.ToString("F2", CultureInfo.InvariantCulture)} s, quiet {Db(Floor)} dBFS, line {Db(Line)} dBFS";
        static string Db(double v) => v > 0 ? (20 * Math.Log10(v)).ToString("F0", CultureInfo.InvariantCulture) : "-inf";
    }

    /// `wav`: 16 kHz mono 16-bit, with or without its 44-byte header.
    public static bool Spoken(byte[] wav) => Measure(wav).Spoken;

    public static Result Measure(byte[] wav)
    {
        var start = wav.Length >= 44 && wav[0] == 'R' && wav[1] == 'I' ? 44 : 0;
        var n = (wav.Length - start) / 2;
        if (n < Frame) return new(0, 0, 0);
        var levels = new List<double>();
        for (var i = 0; i + Frame <= n; i += Frame)
        {
            double sum = 0;
            for (var k = i; k < i + Frame; k++) { double v = BitConverter.ToInt16(wav, start + k * 2) / 32768.0; sum += v * v; }
            levels.Add(Math.Sqrt(sum / Frame));
        }
        var floor = levels.Order().ElementAt(levels.Count / 10);
        var line = Math.Min(0.016, Math.Max(0.0063, floor * 3));
        return new(levels.Count(l => l >= line) * Frame / 16000.0, floor, line);
    }

    static readonly HashSet<string> Fillers = ["嗯", "啊", "呃", "哦", "唔", "额", "噢", "哎", "um", "uh", "hmm", "hm", "mm", "mhm", "ah", "oh", "er", "えー", "あの", "음", "어"];

    /// Nothing but fillers (嗯, 啊, um, hmm…), whatever the punctuation.
    public static bool Filler(string text)
    {
        // A heading with nothing after it ("翻译结果：", "Translation:"): the model's answer to noise, not a sentence.
        var trimmed = text.Trim();
        if (trimmed.Length is > 0 and <= 12 && (trimmed.EndsWith(':') || trimmed.EndsWith('：'))) return true;
        var words = System.Text.RegularExpressions.Regex.Split(text.ToLowerInvariant(), @"[^\p{L}]+").Where(w => w.Length > 0).ToList();
        return words.Count == 0 || words.All(w => Fillers.Contains(w) || (w.Length > 1 && w.Distinct().Count() == 1 && Fillers.Contains(w[0].ToString())));
    }
}

/// When the computer's audio was loud: (time, loud) per buffer of the listening side, the last
/// minute (Linux's LoudnessLog). Read by the talk key's echo check.
public sealed class LoudnessLog(Func<double>? clock = null)
{
    readonly Func<double> clock = clock ?? (() => Environment.TickCount64 / 1000.0);
    readonly Queue<(double t, bool loud)> log = new();
    public double Now => clock();

    public void Add(bool loud)
    {
        var now = Now;
        lock (log)
        {
            log.Enqueue((now, loud));
            while (log.Count > 0 && log.Peek().t < now - 60) log.Dequeue();
        }
    }

    /// Share of the buffers between `start` and `end` that were loud (0 with none).
    public double Fraction(double start, double end)
    {
        lock (log)
        {
            var span = log.Where(b => b.t >= start && b.t <= end).ToList();
            return span.Count == 0 ? 0 : span.Count(b => b.loud) / (double)span.Count;
        }
    }
}

/// Whether Windows' echo cancellation works on the talk key's mic. A capture stream opened in the
/// communications category gets the endpoint's AEC when its driver (or Windows 11's Voice Clarity)
/// has one, and from build 22000 the stream lists its effects. Only an AEC listed as on counts: not
/// knowing (Windows 10, a driver that lists nothing) is the plain mic, because sending the meeting's
/// own words back to it is the worse mistake.
public static class EchoCancel
{
    /// AUDIO_EFFECT_TYPE_ACOUSTIC_ECHO_CANCELLATION (ksmedia.h).
    public static readonly Guid Effect = new("6f64adbe-8211-11e2-8c70-2c27d7f001fa");

    public readonly record struct AudioEffect(Guid Id, bool CanSetState, bool On);

    /// `effects`: the stream's list, null when Windows has none to give.
    public static bool InEffect(IReadOnlyList<AudioEffect>? effects) => effects?.Any(e => e.Id == Effect && e.On) ?? false;

    /// Listed but off, and the app may turn it on: worth asking for before the press starts.
    public static bool CanTurnOn(IReadOnlyList<AudioEffect>? effects) => effects?.Any(e => e.Id == Effect && !e.On && e.CanSetState) ?? false;
}
