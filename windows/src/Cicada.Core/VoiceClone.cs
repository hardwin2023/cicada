using System.Text;

namespace Cicada;

/// The recording Ming clones the user's voice from (Voices.swift › VoiceReference): `voice\reference.wav`
/// (16 kHz mono, 10–15 s) and `voice\reference.txt` (what it says, as Ming heard it) under the app's
/// folder, sealed with DPAPI like the keys. Never in a record, an export or the log; it leaves the
/// PC only inside a speech request to Ling.
public sealed class VoiceReference(IKeyProtector protector, string? folder = null)
{
    /// Shorter than the Mac's 8–30 s (#32): every cloned sentence sends the whole clip again, so a
    /// long one makes each sentence later. At 15 s the recording stops by itself.
    public const double MinSeconds = 10, MaxSeconds = 15;

    public string Folder => folder ?? Path.Combine(Paths.Root, "voice");
    public string AudioFile => Path.Combine(Folder, "reference.wav");
    public string TextFile => Path.Combine(Folder, "reference.txt");

    const string Sealed = "dpapi:";
    readonly object gate = new();
    (DateTime at, byte[]? wav, string? text)? cache;

    /// Fired when the recording is saved or removed.
    public event Action? Changed;

    public bool Exists => Load() is { wav: not null, text: { Length: > 0 } };
    public string? Text => Load().text;
    public byte[]? Wav => Load().wav;

    /// Seconds in the saved clip (16 kHz mono 16-bit after a 44-byte header).
    public double Duration => Wav is { } w ? Math.Max(0, w.Length - 44) / 32000.0 : 0;

    /// What Ming needs: the clip as a data URI and its transcript.
    public (string Audio, string Text)? Reference() =>
        Load() is { wav: { } w, text: { Length: > 0 } t } ? ("data:audio/wav;base64," + Convert.ToBase64String(w), t) : null;

    (byte[]? wav, string? text) Load()
    {
        lock (gate)
        {
            var at = File.Exists(AudioFile) ? File.GetLastWriteTimeUtc(AudioFile) : DateTime.MinValue;
            if (cache is { } c && c.at == at) return (c.wav, c.text);
            byte[]? wav = null; string? text = null;
            try
            {
                if (File.Exists(AudioFile) && File.Exists(TextFile))
                {
                    wav = Open(File.ReadAllText(AudioFile));
                    text = Open(File.ReadAllText(TextFile)) is { } t ? Encoding.UTF8.GetString(t).Trim() : null;
                }
            }
            catch (Exception e) { Log.Debug($"voice clone: read failed {e.GetType().Name}"); wav = null; text = null; }
            cache = (at, wav, text);
            return (wav, text);
        }
    }

    byte[]? Open(string body) =>
        body.StartsWith(Sealed) ? (protector.Tag == "plain" ? Convert.FromBase64String(body[Sealed.Length..]) : protector.Unprotect(Convert.FromBase64String(body[Sealed.Length..]))) : null;

    string Seal(byte[] data) => Sealed + Convert.ToBase64String(protector.Tag == "plain" ? data : protector.Protect(data));

    public void Save(byte[] wav, string text)
    {
        lock (gate)
        {
            Directory.CreateDirectory(Folder);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(Folder, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            File.WriteAllText(TextFile, Seal(Encoding.UTF8.GetBytes(text.Trim())));
            File.WriteAllText(AudioFile, Seal(wav));
            if (!OperatingSystem.IsWindows())
                foreach (var f in new[] { AudioFile, TextFile }) File.SetUnixFileMode(f, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            cache = null;
            slow = null;
        }
        Changed?.Invoke();
    }

    public void Remove()
    {
        lock (gate)
        {
            try { if (Directory.Exists(Folder)) Directory.Delete(Folder, true); } catch (Exception e) { Log.Debug($"voice clone: remove failed {e.GetType().Name}"); }
            cache = null;
            slow = null;
        }
        Changed?.Invoke();
    }

    (DateTime at, bool slow)? slow;

    /// The saved recording is read too slowly (worked out once per recording).
    public bool SavedIsSlow
    {
        get
        {
            var at = File.Exists(AudioFile) ? File.GetLastWriteTimeUtc(AudioFile) : DateTime.MinValue;
            if (slow is { } s && s.at == at) return s.slow;
            var result = Load() is { wav: { } w, text: { } t } && VoicePace.Pace(t, VoicePace.Samples(w), 16000) is { } p && VoicePace.IsSlow(t, p);
            slow = (at, result);
            return result;
        }
    }
}

/// How fast a recording is read (Voices.swift › VoiceReference's pace): Ming copies the clip's pace
/// into every sentence, so a recital at 1.7 characters a second made each sentence about 4× as long.
public static class VoicePace
{
    /// Characters (Chinese, Japanese, Korean) or words a second below which the clone is too slow
    /// for a meeting; an ordinary pace gives 3.5–5 and 2.3–3.
    public const double SlowCharacters = 2.5, SlowWords = 1.6;

    public static double? Pace(string text, float[] samples, double sampleRate)
    {
        var units = Tokens(text).Count;
        if (units == 0 || SpeechSpan(samples, sampleRate) is not { } span || span <= 0.5) return null;
        return units / span;
    }

    public static bool IsSlow(string text, double pace)
    {
        var tokens = Tokens(text);
        var characters = tokens.Count(t => t.Any(IsCjk));
        return pace < (characters * 2 >= tokens.Count ? SlowCharacters : SlowWords);
    }

    /// Seconds from the first to the last 20 ms window within 35 dB of the loudest one.
    public static double? SpeechSpan(float[] samples, double sampleRate)
    {
        var size = Math.Max(1, (int)(sampleRate * 0.02));
        var levels = new List<float>();
        for (var i = 0; i < samples.Length; i += size)
        {
            var end = Math.Min(samples.Length, i + size);
            float sum = 0;
            for (var k = i; k < end; k++) sum += samples[k] * samples[k];
            levels.Add(MathF.Sqrt(sum / (end - i)));
        }
        if (levels.Count == 0) return null;
        var loudest = levels.Max();
        if (loudest <= 0.003f) return null;
        var floor = loudest * 0.0178f;
        var first = levels.FindIndex(l => l >= floor);
        var last = levels.FindLastIndex(l => l >= floor);
        return (last - first + 1) * (double)size / sampleRate;
    }

    /// Words, and each CJK character on its own (SpeakTest.swift › SpeakScore.tokens).
    public static List<string> Tokens(string text)
    {
        var out_ = new List<string>();
        var word = new StringBuilder();
        void Flush() { if (word.Length > 0) { out_.Add(word.ToString().ToLowerInvariant()); word.Clear(); } }
        foreach (var ch in text)
        {
            if (IsCjk(ch)) { Flush(); out_.Add(ch.ToString()); }
            else if (char.IsLetterOrDigit(ch) || ch == '\'' || ch == '’') word.Append(ch == '’' ? '\'' : ch);
            else Flush();
        }
        Flush();
        return out_;
    }

    public static bool IsCjk(char c) => c is (>= '぀' and <= 'ヿ') or (>= '㐀' and <= '䶿') or (>= '一' and <= '鿿') or (>= '가' and <= '힯') or (>= '豈' and <= '﫿');

    /// A 16-bit mono WAV (or bare PCM) as samples in −1…1.
    public static float[] Samples(byte[] wav)
    {
        var start = wav.Length >= 44 && wav[0] == 'R' && wav[1] == 'I' ? 44 : 0;
        var n = (wav.Length - start) / 2;
        var out_ = new float[n];
        for (var i = 0; i < n; i++) out_[i] = BitConverter.ToInt16(wav, start + i * 2) / 32768f;
        return out_;
    }
}

/// What a recording for the clone comes to (the Mac's VoiceRecorder.finish): ready with its
/// transcript, or why not. Kept apart from the microphone so it can be tested.
public static class VoiceCloneCheck
{
    public enum Outcome { Ready, TooShort, NotHeard, Slow }

    public static async Task<(Outcome outcome, string text)> Check(byte[] wav, Func<byte[], Task<string?>> transcribe)
    {
        var seconds = Math.Max(0, wav.Length - 44) / 32000.0;
        if (seconds < VoiceReference.MinSeconds) return (Outcome.TooShort, "");
        string? text = null;
        try { text = await transcribe(wav); } catch (LingException e) { Log.Debug($"voice clone: hearing failed {e.Message}"); }
        text = text?.Trim() ?? "";
        if (text.Length < 6) return (Outcome.NotHeard, text);
        var pace = VoicePace.Pace(text, VoicePace.Samples(wav), 16000);
        Log.Debug($"voice clone: {text.Length} chars, {seconds:F1} s, pace {(pace is { } p ? p.ToString("F1", System.Globalization.CultureInfo.InvariantCulture) : "-")}/s");
        if (pace is { } q && VoicePace.IsSlow(text, q)) return (Outcome.Slow, text);
        return (Outcome.Ready, text);
    }

    /// The passage to read, in the user's own language (Voices.swift › VoiceReference.passage).
    public static string Passage(string language) => VoiceCatalog.Key(language) switch
    {
        "zh" => "大家好，我是这次会议的主持人。今天我们主要讨论新产品的上线计划，包括时间安排、测试范围和市场推广。请大家先看一下屏幕上的议程。",
        "ja" => "皆さん、こんにちは。今日の会議では、新製品の発売計画について話し合います。スケジュール、テストの範囲、そしてマーケティングについて順番に確認しましょう。",
        _ => "Hello everyone, thanks for joining. Today we'll walk through the launch plan for the new product: the schedule, what we still need to test, and how we'll tell people about it. Let's start with the agenda on the screen.",
    };
}
