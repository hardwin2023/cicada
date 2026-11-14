using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cicada;

/// Turns the key into bytes on disk and back. Windows uses DPAPI (the current user only); the
/// plain one is for the Mac-side CLI and tests.
public interface IKeyProtector
{
    string Tag { get; }
    byte[] Protect(byte[] data);
    byte[] Unprotect(byte[] data);
}

public sealed class PlainProtector : IKeyProtector
{
    public string Tag => "plain";
    public byte[] Protect(byte[] data) => data;
    public byte[] Unprotect(byte[] data) => data;
}

/// The user's AI keys, one file per service under the app folder, named as on the Mac
/// (`ling-api-key`, `ai-key-<service>`): never in settings, the registry, logs or exports. On
/// Windows each file holds DPAPI-sealed bytes, "dpapi:" + base64, readable only by this Windows
/// user. `service` says which one is in use, so switching services never deletes another's key;
/// `file` pins one file (the CLI reads the Mac app's in place).
public sealed class AIKey(IKeyProtector protector, string? file = null, Func<string>? service = null)
{
    readonly Func<string> service = service ?? (() => "ling");
    public string File_ => file ?? Paths.KeyFile(service());

    readonly Dictionary<string, string?> cache = [];
    readonly object gate = new();

    public string? Read() => ReadAt(File_);

    /// Another service's saved key, without switching to it (改用 Ling asks whether Ling has one).
    public string? Read(string service) => file is null ? ReadAt(Paths.KeyFile(service)) : null;

    string? ReadAt(string path)
    {
        lock (gate)
        {
            if (cache.TryGetValue(path, out var cached)) return cached;
            string? value = null;
            try
            {
                if (File.Exists(path))
                {
                    var text = File.ReadAllText(path).Trim();
                    if (text.StartsWith("dpapi:"))
                        text = Encoding.UTF8.GetString(protector.Unprotect(Convert.FromBase64String(text["dpapi:".Length..])));
                    value = text.Trim().Length == 0 ? null : text.Trim();
                }
            }
            catch (Exception e) { Log.Debug($"ai key: read failed {e.GetType().Name}"); }
            return cache[path] = value;
        }
    }

    public bool Save(string key) => SaveAt(File_, key);

    /// Another key file of this user's (a custom service's notes server, `custom-notes`).
    public bool Save(string key, string service) => file is null && SaveAt(Paths.KeyFile(service), key);

    bool SaveAt(string path, string key)
    {
        key = key.Trim();
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                var body = protector.Tag == "plain" ? key
                    : "dpapi:" + Convert.ToBase64String(protector.Protect(Encoding.UTF8.GetBytes(key)));
                File.WriteAllText(path, body);
                if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
                cache[path] = key;
                return true;
            }
            catch (Exception e)
            {
                Log.Debug($"ai key: save failed {e.GetType().Name}");
                return false;
            }
        }
    }

    /// Removes the key of the service in use only.
    public void Remove() => RemoveAt(File_);

    public void Remove(string service) { if (file is null) RemoveAt(Paths.KeyFile(service)); }

    void RemoveAt(string path)
    {
        lock (gate)
        {
            try { File.Delete(path); } catch { }
            cache[path] = null;
        }
    }

    /// Forget what was read: a file may have changed behind the app.
    public void Reload() { lock (gate) cache.Clear(); }

    /// "sk-••••••••••••3f9a" for display.
    public static string Masked(string key) => key.Length <= 8 ? "sk-…" : key[..3] + new string('•', 12) + key[^4..];
}

public enum Priority { Speak = 0, Translate = 1, Notes = 2 }

public enum KeyState { None, Unchecked, Checking, Ok, Invalid, Unreachable }

public sealed class LingException(LingException.Kind kind, int status = 0, double? retryAfter = null) : Exception(kind == Kind.Http ? $"http{status}" : kind.ToString())
{
    public enum Kind { NoKey, InvalidKey, RateLimited, Hijacked, Timeout, Http, Network, Parse }
    public Kind Failure { get; } = kind;
    /// The HTTP status for Kind.Http.
    public int Status { get; } = status;
    /// Seconds the service asked us to wait (a 429's Retry-After), when it said.
    public double? RetryAfter { get; } = retryAfter;
}

/// Time for LingClient's start gate; tests hand in one that moves on by itself.
public class GateClock
{
    public virtual DateTime UtcNow => DateTime.UtcNow;
    public virtual Task Delay(TimeSpan wait) => Task.Delay(wait);
}

/// The AI service: Ling (ant-ling.com) by default, or another OpenAI-compatible one (AIProviders.cs),
/// read from `config` on every call. One instance for the app. Request *starts* go through one gate
/// in priority order: Ling allows about 2 a second across every model (≥ 0.6 s apart, overlapping
/// is fine), the aggregators far more. Ling's gateway shapes every call (see Ling.swift): thinking
/// is always disabled, and the content goes in the system message with a fixed user instruction,
/// because a question-like user message gets a search essay back; such replies are dropped. The
/// other services get the same messages.
public sealed class LingClient
{
    public static readonly Uri Base = new(AIProvider.Ling.Base!);
    public const string DefaultModel = "Ling-3.1-flash";
    public const string AudioModel = "Ming-3.0-audio-flash";
    public const string VoiceModel = "Ming-3.0-tts-0.5B";
    // Search essays (Ling.swift), and the canned refusal some audio prompts get.
    static readonly string[] HijackPrefixes = ["根据现有检索证据", "暂未找到足够可靠的信息", "根据检索", "作为一个人工智能语言模型"];

    readonly AIKey key;
    readonly HttpClient http;
    readonly Func<AIConfig> config;
    /// The short form older callers read (Usable, the early stop of every request): derived from Health.
    public KeyState KeyState { get; private set; }
    public DateTimeOffset? RateLimitedAt { get; private set; }
    /// Step by step, where the service stands (AICheck). Swapped whole: requests report from worker threads.
    public AICheck Health { get { lock (healthGate) return health; } }
    AICheck health = new();
    readonly object healthGate = new();
    int checking;
    /// Which check is the newest: a check that started before a change (a model switched while
    /// one ran) finishes into nothing, so an old answer never lands over the new setting.
    int generation;
    /// How long the text model took in the last check that reached it.
    public double? Seconds => Health[AICheck.StepId.Text].Seconds;
    /// Whether the hear model takes audio: null until a check or a meeting found out.
    public bool? Hears => Health[AICheck.StepId.Hear] switch
    {
        { Kind: AICheck.Kind.Ok or AICheck.Kind.Busy } => true,
        { Kind: AICheck.Kind.Fail, Why: AICheck.Reason.Deaf } => false,
        _ => null,
    };
    /// The last time the room voice spoke (or failed to) through this service.
    public (bool Ok, DateTimeOffset At)? LastVoice { get; private set; }
    /// The service's models from `/models`, recommended first: all that chat, and those that hear.
    public IReadOnlyList<string> TextCatalog { get; private set; } = [];
    public IReadOnlyList<string> HearCatalog { get; private set; } = [];
    /// Every model id the service lists, and those it says take audio: whether the chosen ones still exist.
    HashSet<string>? listed, listedHearing;
    /// Reads this computer's proxy settings to word the "can't reach" hint (never used to connect).
    public Func<Task<AICheck.ProxyHint>>? ProxyHint { get; set; }
    /// Debug pipe only: the next checks end this way (screenshots of every state).
    public AICheck.Reason? SimulateCheck { get; set; }
    /// Debug pipe only: report this OpenRouter balance instead of the real one.
    public double? SimulateBalance { get; set; }
    public event Action? Changed;

    public LingClient(AIKey key, HttpMessageHandler? handler = null, Func<AIConfig>? config = null, GateClock? clock = null)
    {
        this.key = key;
        this.clock = clock ?? new GateClock();
        this.config = config ?? (() => AIConfig.Default);
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = Timeout.InfiniteTimeSpan; // per request below
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Cicada-Windows/0.1");
        KeyState = CurrentKey() is null ? KeyState.None : KeyState.Unchecked;
    }

    public AIConfig Config => config();
    public AIProvider Provider => Config.Provider;

    /// The key for the service in use. A custom service on this computer or the local network may need none: "".
    public string? CurrentKey()
    {
        var c = Config;
        var k = key.Read();
        if (k is null && c.Provider.Id == "custom" && c.Base is { } b && AIProvider.IsNearby(b)) return "";
        return k;
    }

    public bool HasKey => CurrentKey() is not null;

    /// The key file of a custom service's notes server (另一个服务), as on the Mac.
    public const string NotesKeyName = "custom-notes";

    /// The key notes are sent with: with 另一个服务, their own key file if there is one, else the
    /// translation key ("不填就用上面的 key").
    public string? NotesKey() => Config.NotesOwnService && key.Read(NotesKeyName) is { } own ? own : CurrentKey();

    /// Notes have a key file of their own (另一个服务 only).
    public bool NotesHasOwnKey => Config.NotesOwnService && key.Read(NotesKeyName) is not null;

    /// Notes' own key (另一个服务); the caller checks again (Controller.AIChanged).
    public bool SaveNotesKey(string raw) => raw.Trim().Length > 0 && key.Save(raw.Trim(), NotesKeyName);

    /// Notes go back to the translation key.
    public void RemoveNotesKey() => key.Remove(NotesKeyName);

    /// Notes' own server's text models from its `/models` (empty while notes share translation's address).
    public IReadOnlyList<string> NotesCatalog { get; private set; } = [];
    public bool Usable => HasKey && KeyState != KeyState.Invalid;
    /// Voices in the room from this service (else Windows' own voice speaks).
    public bool Speaks => Usable && Config.HasVoices;
    /// The user's own voice: only Ling clones.
    public bool Clones => Speaks && Config.Provider.Clones;
    /// Listening and 同声传译 can work: the hear model wasn't found to refuse audio.
    public bool CanHear => Usable && Hears != false && Config.HearModel.Length > 0;
    /// The addresses that refused `chat_template_kwargs` once (a custom service's text and hear
    /// models may be separate servers): left out there until settings change.
    readonly System.Collections.Concurrent.ConcurrentDictionary<string, bool> noTemplateKwargs = new();

    /// The key, the service or its models changed: forget what the last check found.
    public void KeyChanged()
    {
        key.Reload();
        noTemplateKwargs.Clear();
        Interlocked.Increment(ref generation);
        lock (healthGate) health = new AICheck();
        KeyState = CurrentKey() is null ? KeyState.None : KeyState.Unchecked;
        LastVoice = null;
        listed = listedHearing = null;
        TextCatalog = HearCatalog = NotesCatalog = [];
        Changed?.Invoke();
    }

    /// What messages call the service ("这个服务" for a custom address) and its host.
    public string ServiceName => Config.Provider.Id == "custom" ? Strings.L("这个服务") : Config.Name;
    public string ServiceHost => Host(Config.Base);
    /// Who a status line names: a custom service by its address, which says more than 这个服务
    /// and reads right in "The … key doesn't work".
    public string ServiceLabel => Config.Provider.Id == "custom" && ServiceHost.Length > 0 ? ServiceHost : ServiceName;
    /// Where the hear model is asked (a custom service's own address for it, else the service's).
    public string HearHost => Host(Config.HearBase ?? Config.Base);
    static string Host(string? b) => b is not null && Uri.TryCreate(b, UriKind.Absolute, out var u) ? u.Host : "";
    /// The hear model in messages; the service when none is named (a custom one not filled in).
    public string HearName => Config.HearModel.Length > 0 ? Config.HearModel : ServiceName;

    /// The cheapest requests that prove each step: Ling's tiny model, else one token from the text
    /// model; the others' hear model must take audio (half a second of silence), a custom service
    /// must return JSON (the notes need it), and the model list must still have both models.
    /// OpenRouter also tells the balance. Ling's Ming isn't asked: a meeting records how it hears.
    public async Task<(KeyState state, double seconds)> Check()
    {
        var started = DateTime.UtcNow;
        var c = Config;
        // Counted before anything else: a slower check still running (a custom service that thinks
        // for seconds) must not land on top of what this one finds, even "no key".
        var gen = Interlocked.Increment(ref generation);
        if (CurrentKey() is not { } k)
        {
            lock (healthGate) health = new AICheck();
            KeyState = KeyState.None;
            Changed?.Invoke();
            return (KeyState, 0);
        }
        Interlocked.Increment(ref checking);
        try
        {
            var r = new AICheck();
            r[AICheck.StepId.Reach] = AICheck.State.Running;
            lock (healthGate) health = r;
            KeyState = KeyState.Checking;
            Changed?.Invoke();
            r = new AICheck();
            if (SimulateCheck is { } sim) r = Simulated(sim);
            else if (c.Provider.Id == "custom" && c.Base is null) r.Fail(AICheck.StepId.Reach, AICheck.Reason.BadAddress, reached: false);
            else if (AICheck.Owner(k) is { Management: true }) r.Fail(AICheck.StepId.Key, AICheck.Reason.MgmtKey, reached: false);
            else await Probe(r, c, k, gen);
            await Finish(r, c, gen);
        }
        finally { Interlocked.Decrement(ref checking); }
        return (KeyState, (DateTime.UtcNow - started).TotalSeconds);
    }

    async Task Probe(AICheck r, AIConfig c, string k, int gen)
    {
        double Since(DateTime t) => (DateTime.UtcNow - t).TotalSeconds;
        void Failed(LingException e, AICheck.StepId step)
        {
            if (AICheck.Classify(e.Failure, e.Status, step, c.HearElsewhere) is not { } f) return;
            if (f.Why == AICheck.Reason.Busy) r.Busy(f.Step); else r.Fail(f.Step, f.Why, f.Code);
        }
        var t = DateTime.UtcNow;
        try
        {
            if (c.IsLing) await Chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens: 5, timeout: 10, model: "Ling-3.0-tiny");
            else if (c.Provider.Id != "custom") await Chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens: 5, timeout: 20);
            else
            {
                // A real sentence, the way a meeting translates: one token says nothing about a
                // model that thinks for six seconds before every answer.
                JsonNode? root = null;
                try
                {
                    await Chat("Translate the text into Simplified Chinese. Reply with the translation only.\n\nWe will ship the new version on Friday after the design review.",
                        "Translate.", Priority.Speak, maxTokens: 120, timeout: 30, reply: n => root = n);
                }
                // A reasoning parser that put the whole answer in reasoning_content: it answered, by thinking.
                catch (LingException e) when (e.Failure == LingException.Kind.Parse && AIConfig.Thought(root)) { }
                r.Translate = new AICheck.Speed(Since(t), AIConfig.Thought(root));
            }
            r.Pass(AICheck.StepId.Text, Since(t));
            if (c.NotesApart)
            {
                // Notes at their own model or server: their failure is theirs, translation goes on.
                r.Notes = AICheck.State.Running;
                lock (healthGate) { if (gen == generation) health = r.Clone(); }
                Changed?.Invoke();
                r.Notes = await CheckNotes(c);
            }
            else if (c.Provider.Id == "custom")
            {
                const string ask = "Reply with the JSON object {\"ok\": true}.";
                try { await Chat(ask, "Reply.", Priority.Speak, json: true, maxTokens: 20, timeout: 30, jsonFallback: false); }
                catch (LingException e) when (e.Failure == LingException.Kind.Http)
                {
                    // JSON mode refused (some hosts of a model do): meetings then ask without it, so
                    // what counts is whether the model still answers with a JSON object.
                    string? said = null;
                    try { said = await Chat(ask, "Reply.", Priority.Speak, maxTokens: 20, timeout: 30); } catch (LingException) { }
                    if (!AnswersJSON(said)) r.Fail(AICheck.StepId.Text, AICheck.Reason.NoJSON, e.Status);
                }
            }
        }
        catch (LingException e) { Failed(e, AICheck.StepId.Text); }
        catch (Exception) { r.Fail(AICheck.StepId.Reach, AICheck.Reason.Unreachable); }
        // The address and the key work: hearing is its own question (the text model may be the one gone).
        if (c.IsLing || r.Failure is { Step: AICheck.StepId.Reach or AICheck.StepId.Key }) return;
        if (c.HearModel.Length == 0) r.Fail(AICheck.StepId.Hear, AICheck.Reason.Deaf);
        else if (c.HearBase is null) r.Fail(AICheck.StepId.Hear, AICheck.Reason.BadAddress);
        else
        {
            t = DateTime.UtcNow;
            try
            {
                await Chat("Transcribe the audio.", "Reply with what is said, or NONE.", Priority.Speak, maxTokens: 10, timeout: 20,
                    model: c.HearModel, audio: Wav.Bytes(new short[8000]));
                r.Pass(AICheck.StepId.Hear, Since(t));
            }
            // A made-up answer to silence still came from a model that took the audio.
            catch (LingException e) when (e.Failure == LingException.Kind.Hijacked) { r.Pass(AICheck.StepId.Hear, Since(t)); }
            catch (LingException e) { Failed(e, AICheck.StepId.Hear); }
            catch (Exception) { }
        }
        await FetchCatalog();
        // A model the service no longer lists fails here, before a meeting finds out. On a custom
        // service, one a real sentence just went through exists whatever the list says (an alias,
        // a name typed by hand).
        var proven = c.Provider.Id == "custom" && r.Translate is not null;
        if (listed is { } ids && c.TextModel.Length > 0 && !proven && r[AICheck.StepId.Text].Kind != AICheck.Kind.Fail && !ids.Contains(c.TextModel))
            r.Fail(AICheck.StepId.Text, AICheck.Reason.NoModel);
        // The list is the text address's: it says nothing about a hear model served elsewhere.
        if (listedHearing is { } hearing && !c.HearElsewhere && c.HearModel.Length > 0 && r[AICheck.StepId.Hear].Kind != AICheck.Kind.Fail && !hearing.Contains(c.HearModel))
            r.Fail(AICheck.StepId.Hear, AICheck.Reason.Deaf);
        if (c.Provider.Id == "openrouter") r.Balance = AICheck.BalanceFrom(await GetText("key", k), await GetText("credits", k));
    }

    async Task Finish(AICheck r, AIConfig c, int gen)
    {
        if (gen != Volatile.Read(ref generation)) { Log.Debug($"ai {c.Provider.Id}: an older check -> {r.Summary}, dropped"); return; }
        if (r.Failure?.Why == AICheck.Reason.Unreachable && r.Proxy is null && ProxyHint is { } hint) r.Proxy = await hint();
        if (SimulateBalance is { } b) r.Balance = b;
        r.At = DateTimeOffset.Now;
        lock (healthGate) { if (gen != generation) return; health = r; }
        SyncKeyState();
        Log.Debug($"ai {c.Provider.Id}: check -> {r.Summary}");
        Changed?.Invoke();
    }

    /// A made-up result for `reason` (debug screenshots of every state).
    static AICheck Simulated(AICheck.Reason reason)
    {
        var r = new AICheck();
        switch (reason)
        {
            case AICheck.Reason.Busy: r.Pass(AICheck.StepId.Text, 1.2); r[AICheck.StepId.Text] = AICheck.State.Busy; r.Pass(AICheck.StepId.Hear, 0.9); break;
            case AICheck.Reason.Unreachable or AICheck.Reason.BadAddress: r.Fail(AICheck.StepId.Reach, reason, reached: false); break;
            case AICheck.Reason.InvalidKey: r.Fail(AICheck.StepId.Key, reason); break;
            case AICheck.Reason.NoCredit: r.Fail(AICheck.StepId.Key, reason, 402); break;
            case AICheck.Reason.MgmtKey: r.Fail(AICheck.StepId.Key, reason, reached: false); break;
            case AICheck.Reason.NoModel or AICheck.Reason.NoJSON: r.Fail(AICheck.StepId.Text, reason, 404); r.Pass(AICheck.StepId.Hear, 0.9); break;
            case AICheck.Reason.Deaf: r.Pass(AICheck.StepId.Text, 1.2); r.Fail(AICheck.StepId.Hear, reason, 400); break;
            default: r.Pass(AICheck.StepId.Text, 1.2); r.Fail(AICheck.StepId.Hear, reason, 503); break;
        }
        return r;
    }

    /// The short form older callers read: a refused key stops every request; a hear model that
    /// can't hear leaves the key good (notes and translation work).
    void SyncKeyState()
    {
        var h = Health;
        KeyState = !HasKey ? KeyState.None
            : h.IsRunning ? KeyState.Checking
            : h.Failure is { Why: AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey } ? KeyState.Invalid
            : h.Failure is { Step: AICheck.StepId.Reach or AICheck.StepId.Key } or { Why: AICheck.Reason.NoModel or AICheck.Reason.ServerError } ? KeyState.Unreachable
            : h.At is null ? KeyState.Unchecked
            : KeyState.Ok;
    }

    /// A real request (hearing, notes, translation) came back: keep the steps current without a
    /// check. One server error in a meeting isn't worth repainting the settings for, nor is the
    /// same good result again.
    void Observe(LingException? failure, double seconds, bool audio, bool notes = false)
    {
        if (!HasKey || Volatile.Read(ref checking) > 0 || SimulateCheck is not null) return;
        if (notes)
        {
            // Notes at their own model or server: theirs alone, translation's steps (and KeyState) are untouched.
            AICheck.State now;
            if (failure is not null)
            {
                if (AICheck.Classify(failure.Failure, failure.Status, AICheck.StepId.Text) is not { } f || f.Why == AICheck.Reason.ServerError) return;
                now = AICheck.State.Fail(f.Why, f.Code);
            }
            else now = AICheck.State.Ok(seconds);
            lock (healthGate)
            {
                if (health.Notes?.Kind == AICheck.Kind.Ok && now.Kind == AICheck.Kind.Ok) return;
                if (health.Notes is { } old && old with { Seconds = null } == now with { Seconds = null }) return;
                health = health.Clone();
                health.Notes = now;
            }
            Log.Debug($"ai: notes from a real request -> {health.Summary}");
            Changed?.Invoke();
            return;
        }
        var step = audio ? AICheck.StepId.Hear : AICheck.StepId.Text;
        AICheck r;
        bool wasUnreachable;
        lock (healthGate)
        {
            var old = health;
            r = old.Clone();
            if (failure is not null)
            {
                if (AICheck.Classify(failure.Failure, failure.Status, step, Config.HearElsewhere) is not { } f || f.Why == AICheck.Reason.ServerError) return;
                if (f.Why == AICheck.Reason.Busy) r.Busy(f.Step); else r.Fail(f.Step, f.Why, f.Code);
            }
            else r.Pass(step, seconds);
            r.At = DateTimeOffset.Now;
            r.Passive = true;
            if (r.SameSteps(old) && old.Passive) { old.At = r.At; return; }
            wasUnreachable = old.Failure?.Why == AICheck.Reason.Unreachable;
            if (r.Failure?.Why == AICheck.Reason.Unreachable) r.Proxy = old.Proxy;
            health = r;
        }
        SyncKeyState();
        Log.Debug($"ai: from a real request -> {r.Summary}");
        Changed?.Invoke();
        if (r.Failure?.Why == AICheck.Reason.Unreachable && !wasUnreachable && ProxyHint is { } hint)
            _ = Task.Run(async () =>
            {
                var p = await hint();
                lock (healthGate) { if (health.Failure?.Why != AICheck.Reason.Unreachable) return; health = health.Clone(); health.Proxy = p; }
                Changed?.Invoke();
            });
    }

    /// The network changed while the service was unreachable: look again (never on a timer).
    public void NetworkChanged()
    {
        var h = Health;
        if (!HasKey || h.Failure?.Why != AICheck.Reason.Unreachable || h.IsRunning) return;
        Log.Debug("ai: network changed while unreachable, checking again");
        _ = Check();
    }

    /// One click on 换成推荐的: the model that was wrong is the service's first recommended one now.
    /// Null when there is none (a custom service), or the chosen one is it already.
    public string? Recommended(AICheck.StepId step)
    {
        var c = Config;
        var (models, current) = step == AICheck.StepId.Hear ? (c.Provider.HearModels, c.HearModel) : (c.Provider.TextModels, c.TextModel);
        return models.FirstOrDefault()?.Id is { } id && id != current ? id : null;
    }

    /// One GET on the service's API (OpenRouter's key info and credits); null when it fails.
    async Task<string?> GetText(string path, string k, string? at = null)
    {
        if ((at ?? Config.Base) is not { } b) return null;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, new Uri(new Uri(b), path));
            if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            using var res = await http.SendAsync(req, cts.Token);
            return res.StatusCode == HttpStatusCode.OK ? await res.Content.ReadAsStringAsync(cts.Token) : null;
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException) { return null; }
    }

    /// The service's models, for the model menus. Quietly just the recommended ones when the
    /// service has no `/models`.
    public async Task FetchCatalog()
    {
        var c = Config;
        if (c.IsLing || CurrentKey() is not { } k || c.Base is null) return;
        if (await GetText("models", k) is not { } body) return;
        TextCatalog = AIProvider.Catalog(body, c.Provider.TextModels.Select(m => m.Id), hears: false);
        HearCatalog = AIProvider.Catalog(body, c.Provider.HearModels.Select(m => m.Id), hears: true);
        listed = AICheck.ListedModels(body);
        listedHearing = AICheck.ListedHearing(body);
        Log.Debug($"ai {c.Provider.Id}: {TextCatalog.Count} models, {HearCatalog.Count} hear");
        Changed?.Invoke();
    }

    /// Notes' own model or server (AIConfig.NotesApart): one JSON request the way a meeting's notes
    /// ask, sent straight (no gate, no retries: a check), then, at another address, its model list
    /// for the menu.
    async Task<AICheck.State> CheckNotes(AIConfig config)
    {
        if (config.NotesBadAddress) return AICheck.State.Fail(AICheck.Reason.BadAddress);
        var c = config.ForNotes;
        if (NotesKey() is not { } k || c.Base is not { } b) return AICheck.State.Fail(AICheck.Reason.InvalidKey);
        var url = new Uri(new Uri(b), "chat/completions");
        var body = new JsonObject
        {
            ["model"] = c.TextModel,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = "Reply with the JSON object {\"ok\": true}." },
                new JsonObject { ["role"] = "user", ["content"] = "Reply." }),
            ["stream"] = false,
        };
        c.Shape(body, 20, templateKwargs: !noTemplateKwargs.ContainsKey(b));
        body["response_format"] = new JsonObject { ["type"] = "json_object" };
        var asked = DateTime.UtcNow;
        AICheck.State result;
        try
        {
            await PostChat(url, body, b, k, 60, default);
            result = AICheck.State.Ok((DateTime.UtcNow - asked).TotalSeconds);
        }
        catch (LingException e) when (e.Failure == LingException.Kind.Http && e.Status is 400 or 422)
        {
            // JSON mode refused (some hosts of a model do): meetings then ask without it, so what
            // counts is whether the model still answers with a JSON object.
            body.Remove("response_format");
            string? said = null;
            try { said = Str((await PostChat(url, body, b, k, 60, default))["choices"]?[0]?["message"]?["content"]); } catch (LingException) { }
            result = AnswersJSON(said) ? AICheck.State.Ok((DateTime.UtcNow - asked).TotalSeconds) : AICheck.State.Fail(AICheck.Reason.NoJSON, e.Status);
        }
        catch (LingException e)
        {
            var f = AICheck.Classify(e.Failure, e.Status, AICheck.StepId.Text) ?? (AICheck.StepId.Text, AICheck.Reason.ServerError, null);
            result = AICheck.State.Fail(f.Why, f.Code);
        }
        catch (Exception) { result = AICheck.State.Fail(AICheck.Reason.Unreachable); }
        if (c.Base != config.Base) await FetchNotesCatalog();
        return result;
    }

    /// Notes' own address's text models, for its menu. Quietly empty when it has no `/models`.
    public async Task FetchNotesCatalog()
    {
        var c = Config;
        var b = c.ForNotes.Base;
        if (!c.NotesApart || b is null || b == c.Base || NotesKey() is not { } k) return;
        if (await GetText("models", k, b) is not { } body) return;
        NotesCatalog = AIProvider.Catalog(body, [], hears: false);
        Log.Debug($"ai notes: {NotesCatalog.Count} models");
        Changed?.Invoke();
    }

    /// One chat completion. `content` goes in the system message, `instruction` is the fixed user
    /// message, `audio` (a WAV) goes before it for the hear model. Notes and heard audio retry 429s
    /// with backoff (RetryWaits); the rest fail fast so the caller can fall back. `model` defaults to
    /// the service's text model. `patient` (the final notes) keeps retrying for about a minute. A 429
    /// holds every request start for a while (RateLimited), and a retry keeps its place in the
    /// queue, so lines stay in order. Audio goes to the hear model's address (a custom service's own
    /// one for it). `reply` sees the whole reply before its text is read (the check's thinking test).
    /// A JSON request refused with 400 is asked again without JSON mode unless `jsonFallback` is
    /// off (the check asks again itself). Notes (`notes`, by default the Notes priority) go to a
    /// custom service's notes model, address and key when they have their own (AIConfig.ForNotes);
    /// a live line's corrections ride at Notes priority but are translation's, as on the Mac.
    public async Task<string> Chat(string content, string instruction, Priority priority, bool json = false,
        int maxTokens = 1024, double timeout = 30, string? model = null, byte[]? audio = null, bool patient = false,
        CancellationToken cancel = default, Action<JsonNode>? reply = null, bool jsonFallback = true, bool? notes = null)
    {
        var all = Config;
        var notesSide = (notes ?? priority == Priority.Notes) && audio is null && all.NotesApart;
        // 另一个服务 at an address that can't be used: never fall back to translation's server with
        // the notes' key (the Mac does; the check already says the address is wrong).
        if (notesSide && all.NotesBadAddress) throw new LingException(LingException.Kind.NoKey);
        var c = notesSide ? all.ForNotes : all;
        var k = (notesSide ? NotesKey() : CurrentKey()) ?? throw new LingException(LingException.Kind.NoKey);
        // A refused notes key stops notes only; a refused translation key stops everything else.
        if (notesSide ? Health.Notes?.Why is AICheck.Reason.InvalidKey or AICheck.Reason.MgmtKey : KeyState == KeyState.Invalid)
            throw new LingException(LingException.Kind.InvalidKey);
        var b = audio is null ? c.Base : c.Provider.Id == "custom" ? c.HearBase : c.HearBase ?? c.Base;
        if (b is null) throw new LingException(LingException.Kind.NoKey);
        model ??= c.TextModel;
        JsonNode user = audio is null ? JsonValue.Create(instruction)! : new JsonArray(c.AudioPart(audio, model), new JsonObject { ["type"] = "text", ["text"] = instruction });
        var body = new JsonObject
        {
            ["model"] = model,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = content },
                new JsonObject { ["role"] = "user", ["content"] = user }),
            ["stream"] = false,
        };
        c.Shape(body, maxTokens, templateKwargs: !noTemplateKwargs.ContainsKey(b));
        if (json) body["response_format"] = new JsonObject { ["type"] = "json_object" };
        var url = new Uri(new Uri(b), "chat/completions");

        var waits = RetryWaits(priority, audio is not null, patient);
        var g = GateFor(b);
        long? ticket = null;
        for (int attempt = 1; ; attempt++)
        {
            var queued = DateTime.UtcNow;
            // One that wouldn't retry fails at once while the service is cooling down: its caller falls back.
            ticket = await Acquire(g, priority, c.Provider.Spacing, cancel, ticket, failIfPaused: waits.Length == 0);
            var started = DateTime.UtcNow;
            if ((started - queued).TotalSeconds > 1) Log.Debug($"ling: {priority} waited {(started - queued).TotalMilliseconds:F0} ms at the gate");
            try
            {
                JsonNode root;
                try { root = await PostChat(url, body, b, k, timeout, cancel); }
                catch (LingException e) when (jsonFallback && e.Failure == LingException.Kind.Http && e.Status == 400 && body.ContainsKey("response_format"))
                {
                    // Some hosts of a model refuse JSON mode (on OpenRouter, Novita for Ling 3.1 Flash)
                    // while the model answers JSON anyway: the prompt asks for it, the parsers find it.
                    Log.Debug($"ling: {priority} JSON mode refused (400), asking again without it");
                    body.Remove("response_format");
                    root = await PostChat(url, body, b, k, timeout, cancel);
                }
                reply?.Invoke(root);
                var choice = root["choices"]?[0];
                var text = Str(choice?["message"]?["content"]) ?? throw new LingException(LingException.Kind.Parse);
                var finish = Str(choice?["finish_reason"]);
                var trimmed = text.Trim();
                // Ling's search essays come without a finish reason; other services may simply omit it.
                if (finish is null && c.IsLing || HijackPrefixes.Any(trimmed.StartsWith))
                {
                    Log.Debug($"ling: {priority} search-style reply dropped");
                    throw new LingException(LingException.Kind.Hijacked);
                }
                var usage = root["usage"];
                Log.Debug($"ai {c.Provider.Id}: {priority} ok {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms tokens={usage?["prompt_tokens"]}/{usage?["completion_tokens"]}");
                if (RateLimitedAt is not null) { RateLimitedAt = null; Changed?.Invoke(); }
                Observe(null, (DateTime.UtcNow - started).TotalSeconds, audio is not null, notesSide);
                return trimmed;
            }
            catch (LingException e)
            {
                Observe(e, 0, audio is not null, notesSide);
                if (e.Failure != LingException.Kind.RateLimited) throw;
                var wait = RateLimited(g, waits.Length > 0 ? waits[Math.Min(attempt, waits.Length) - 1] : 1, e.RetryAfter);
                if (attempt > waits.Length || wait is null) { RateLimitedAt = DateTimeOffset.Now; Changed?.Invoke(); throw; }
                Log.Debug($"ling: {priority} 429, retry in {wait:F1} s");
            }
        }
    }

    /// Seconds before each retry of a 429 (Ling.swift › retryWaits). Notes can wait; the rest fail
    /// fast, except heard audio. A meeting's: on Windows a lost reply loses the words (on the Mac
    /// recognition is local and only the translation is lost), and Ling's 429s came in runs of up to
    /// ~10 s (two in a row lost about 2 lines a minute with one retry, 2026-11), so it keeps at it for
    /// about 15 s. What the user says (Speak) retries once: late into the room is worse than "try again".
    /// `patient` (the final notes) keeps at it for about a minute: a model limited upstream
    /// (OpenRouter's Ling 3.1 by DeepInfra, 2026-11) came back after ~15 s, and a meeting left
    /// without its notes is worse than notes a little late.
    public static double[] RetryWaits(Priority priority, bool audio = false, bool patient = false) =>
        priority == Priority.Notes ? (patient ? [1, 2, 4, 8, 16, 30] : [1, 2, 4])
        : audio ? (priority == Priority.Translate ? [1, 2, 4, 8] : [1]) : [];

    /// Longest Retry-After worth waiting for; longer is an outage, not a busy moment.
    public const double MaxPause = 30;

    /// After a 429: no request starts for `backoff` seconds, or as long as the service asked
    /// (Retry-After; Ling sends none), plus a little jitter. The queue waits at the gate instead of
    /// each request spending its retries on the same limit. Null when that is over MaxPause (the
    /// gate still holds for MaxPause).
    double? RateLimited(StartGate g, double backoff, double? retryAfter)
    {
        var wait = Math.Max(backoff, retryAfter ?? 0) + Random.Shared.NextDouble() * 0.5;
        lock (gate)
        {
            var until = clock.UtcNow.AddSeconds(Math.Min(wait, MaxPause));
            if (until > g.PausedUntil) g.PausedUntil = until;
        }
        return wait <= MaxPause ? wait : null;
    }

    /// A Retry-After header in seconds: a delay or a date. Null when there is none.
    public static double? RetryAfterSeconds(System.Net.Http.Headers.RetryConditionHeaderValue? value, DateTimeOffset now) =>
        value?.Delta is { } d ? Math.Max(0, d.TotalSeconds)
        : value?.Date is { } at ? Math.Max(0, (at - now).TotalSeconds)
        : null;

    /// The service's voice for `text`: raw 24 kHz mono 16-bit PCM, chunk by chunk as it arrives.
    /// On Ling, `voice` is Ming's and `languageId` its `language_id`, needed for ja, ko, de, fr and
    /// es (Ling.swift › speech); elsewhere the configured speech model, and a voice not in the
    /// service's list becomes its first. Replies come three ways and all are read: server-sent
    /// base64 chunks (Ling, ZenMux), raw PCM (OpenRouter), or one JSON `{"audio": <WAV>}`.
    /// `reference` (Ling only): a voice cloned from the user's recording (a WAV data URI and what it
    /// says) instead of `voice`; the whole clip goes with every sentence, so it waits longer.
    public async IAsyncEnumerable<byte[]> Speech(string text, string? voice, string? languageId = null,
        (string Audio, string Text)? reference = null,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancel = default)
    {
        var k = CurrentKey() ?? throw new LingException(LingException.Kind.NoKey);
        if (KeyState == KeyState.Invalid) throw new LingException(LingException.Kind.InvalidKey);
        var c = Config;
        if (!c.HasVoices) throw new LingException(LingException.Kind.NoKey);
        var body = SpeechBody(c, text, voice, languageId, reference);
        await Acquire(GateFor(c.VoiceBase), Priority.Speak, c.Provider.Spacing, cancel);
        var started = DateTime.UtcNow;
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(new Uri(c.VoiceBase!), "audio/speech"))
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        cts.CancelAfter(TimeSpan.FromSeconds(reference is not null && c.IsLing ? 30 : 20));
        HttpResponseMessage res;
        try { res = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token); }
        catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
        catch (HttpRequestException e) { Log.Debug($"ling: voice network error {e.HttpRequestError}"); throw new LingException(LingException.Kind.Network); }
        using (res)
        {
            switch (res.StatusCode)
            {
                case HttpStatusCode.OK: break;
                case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden:
                    Observe(new LingException(LingException.Kind.InvalidKey), 0, audio: false);
                    throw new LingException(LingException.Kind.InvalidKey);
                case HttpStatusCode.TooManyRequests: throw new LingException(LingException.Kind.RateLimited);
                default: Log.Debug($"ai {c.Provider.Id}: voice HTTP {(int)res.StatusCode}"); throw new LingException(LingException.Kind.Http, (int)res.StatusCode);
            }
            var kind = res.Content.Headers.ContentType?.MediaType ?? "";
            var stream = await res.Content.ReadAsStreamAsync(cts.Token);
            int chunks = 0;
            if (kind.Contains("event-stream") || c.IsLing)
            {
                using var reader = new StreamReader(stream);
                while (true)
                {
                    string? line;
                    try { line = await reader.ReadLineAsync(cts.Token); }
                    catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                    if (line is null) break;
                    var pcm = SpeechChunk(line, out var done);
                    if (done) break;
                    if (pcm is null) continue;
                    if (chunks++ == 0) Log.Debug($"ai {c.Provider.Id}: Speak first audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                    yield return pcm;
                }
            }
            else if (kind.Contains("json"))
            {
                string all;
                try { all = await new StreamReader(stream).ReadToEndAsync(cts.Token); }
                catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                byte[] wav;
                try { wav = Convert.FromBase64String(JsonNode.Parse(all)?["audio"]?.GetValue<string>() ?? throw new LingException(LingException.Kind.Parse)); }
                catch (Exception e) when (e is JsonException or FormatException or InvalidOperationException) { throw new LingException(LingException.Kind.Parse); }
                Log.Debug($"ai {c.Provider.Id}: Speak audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                yield return PcmFromWav(wav);
            }
            else
            {
                // Raw PCM: handed on in 0.1 s pieces at 24 kHz, so playback starts early. A read can
                // end mid-sample (OpenRouter's does): the odd byte waits for the next read, or every
                // sample after it would be split across two pieces.
                var buffer = new byte[4800];
                int held = 0;
                while (true)
                {
                    int n;
                    try { n = await stream.ReadAsync(buffer.AsMemory(held), cts.Token); }
                    catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                    if (n == 0) break;
                    n += held;
                    var even = n & ~1;
                    held = n - even;
                    if (even == 0) continue;
                    if (chunks++ == 0) Log.Debug($"ai {c.Provider.Id}: Speak first audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                    var piece = buffer[..even];
                    if (held > 0) buffer[0] = buffer[even];
                    yield return piece;
                }
            }
        }
    }

    /// The `/audio/speech` request (Ling.swift › speech): Ming's voice, or a clone of `reference`, on
    /// Ling; elsewhere the configured speech model with one of its voices.
    public static JsonObject SpeechBody(AIConfig c, string text, string? voice, string? languageId, (string Audio, string Text)? reference = null)
    {
        var body = new JsonObject { ["model"] = c.VoiceModel, ["input"] = text, ["response_format"] = "pcm" };
        if (c.IsLing)
        {
            if (reference is { } r) body["references"] = new JsonArray(new JsonObject { ["audio"] = r.Audio, ["text"] = r.Text });
            else body["voice"] = voice ?? "UK_Charlotte";
            body["sample_rate"] = 24000; body["stream"] = true; body["stream_format"] = "sse";
            if (languageId is not null) body["language_id"] = languageId;
        }
        else
        {
            // OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
            if (c.Provider.Id != "openrouter") body["stream"] = true;
            var ids = c.Voices.Select(v => v.Id).ToList();
            body["voice"] = voice is not null && ids.Contains(voice) ? voice : ids.FirstOrDefault() ?? c.CustomVoice ?? "Kore";
        }
        return body;
    }

    /// The room voice spoke through this service, or failed and Windows spoke instead (现在能用的 says which).
    public void VoiceSpoke(bool ok)
    {
        LastVoice = (ok, DateTimeOffset.Now);
        Changed?.Invoke();
    }

    /// One SSE line of a voice stream: the PCM it carries, or `done` at the end.
    public static byte[]? SpeechChunk(string line, out bool done)
    {
        done = false;
        if (!line.StartsWith("data:")) return null;
        JsonNode? obj;
        try { obj = JsonNode.Parse(line[5..]); } catch (JsonException) { return null; }
        if (obj is not JsonObject) return null;
        if (Str(obj["type"]) == "speech.audio.done") { done = true; return null; }
        if (Str(obj["audio"]) is not { Length: > 0 } b64) return null;
        try { return Convert.FromBase64String(b64); } catch (FormatException) { return null; }
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// The samples of a WAV (its `data` chunk); the bytes themselves when there's no header.
    public static byte[] PcmFromWav(byte[] wav)
    {
        if (wav.Length < 12 || Encoding.ASCII.GetString(wav, 0, 4) != "RIFF") return wav;
        int at = 12;
        while (at + 8 <= wav.Length)
        {
            int size = BitConverter.ToInt32(wav, at + 4);
            if (Encoding.ASCII.GetString(wav, at, 4) == "data") return wav[(at + 8)..Math.Min(wav.Length, at + 8 + size)];
            at += 8 + size + (size & 1);
        }
        return [];
    }

    /// A chat completion. A strict gateway answers 400 or 422 to a field it doesn't know: asked
    /// again without `chat_template_kwargs`, and not sent it again (to `b`) until settings change,
    /// but only when that request goes through (Ling.swift › postChat): a 400 for something else
    /// (no JSON mode) must not turn thinking back on for every translation.
    async Task<JsonNode> PostChat(Uri url, JsonObject body, string b, string k, double timeout, CancellationToken cancel)
    {
        try { return await Post(url, body.ToJsonString(), k, timeout, cancel); }
        catch (LingException e) when (e.Failure == LingException.Kind.Http && e.Status is 400 or 422 && body.ContainsKey("chat_template_kwargs"))
        {
            var plain = (JsonObject)body.DeepClone();
            plain.Remove("chat_template_kwargs");
            JsonNode root;
            try { root = await Post(url, plain.ToJsonString(), k, timeout, cancel); }
            catch (LingException) { throw e; }
            Log.Debug($"ai custom: chat_template_kwargs refused (HTTP {e.Status}), sent without it from now on");
            noTemplateKwargs[b] = true;
            return root;
        }
    }

    /// A chat reply's text holds a JSON object (a fence or a sentence around it is fine).
    public static bool AnswersJSON(string? text)
    {
        if (text is null) return false;
        int a = text.IndexOf('{'), z = text.LastIndexOf('}');
        if (a < 0 || z <= a) return false;
        try { return JsonNode.Parse(text[a..(z + 1)]) is JsonObject; } catch (JsonException) { return false; }
    }

    async Task<JsonNode> Post(Uri url, string payload, string k, double timeout, CancellationToken cancel)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        cts.CancelAfter(TimeSpan.FromSeconds(timeout));
        HttpResponseMessage res;
        try { res = await http.SendAsync(req, cts.Token); }
        catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
        catch (HttpRequestException e)
        {
            Log.Debug($"ling: network error {e.HttpRequestError}");
            throw new LingException(LingException.Kind.Network);
        }
        using (res)
        {
            switch (res.StatusCode)
            {
                case HttpStatusCode.OK: break;
                // Chat reports it to the check (Observe), which stops every request after it.
                case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden: throw new LingException(LingException.Kind.InvalidKey);
                case HttpStatusCode.TooManyRequests:
                    throw new LingException(LingException.Kind.RateLimited, 429, RetryAfterSeconds(res.Headers.RetryAfter, DateTimeOffset.UtcNow));
                default:
                    Log.Debug($"ling: HTTP {(int)res.StatusCode}");
                    throw new LingException(LingException.Kind.Http, (int)res.StatusCode);
            }
            try
            {
                var text = await res.Content.ReadAsStringAsync(cts.Token);
                return JsonNode.Parse(text) ?? throw new LingException(LingException.Kind.Parse);
            }
            catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
            catch (JsonException) { throw new LingException(LingException.Kind.Parse); }
        }
    }

    // Start gate: request starts ≥ the service's spacing apart, the most urgent waiting one first,
    // none while the server is cooling down after a 429. One per server (by host): notes or a hear
    // model on another server don't wait behind translation, and a 429 there doesn't hold it back.

    /// Tests only: overrides the service's spacing.
    public static double? Spacing { get; set; }
    readonly GateClock clock;
    /// Guards every StartGate and the shared ticket counter.
    readonly object gate = new();
    readonly Dictionary<string, StartGate> gates = [];
    long seq;

    sealed class StartGate
    {
        public DateTime LastStart = DateTime.MinValue;
        public DateTime PausedUntil = DateTime.MinValue;
        public readonly List<(Priority priority, long seq, TaskCompletionSource ready)> Waiting = [];
        public bool Pumping;
        public double Spacing = 0.6;
    }

    /// The gate of the server at `address` (its host; the service's when there is none).
    StartGate GateFor(string? address)
    {
        var host = Host(address ?? Config.Base);
        lock (gate)
        {
            if (!gates.TryGetValue(host, out var g)) gates[host] = g = new StartGate();
            return g;
        }
    }

    /// Waits for this request's turn to start. `ticket` is a retry's first one, which keeps its
    /// place ahead of requests queued after it. Returns the ticket.
    Task<long> Acquire(StartGate g, Priority priority, double serviceSpacing, CancellationToken cancel, long? ticket = null, bool failIfPaused = false)
    {
        lock (gate)
        {
            g.Spacing = Spacing ?? serviceSpacing;
            var now = clock.UtcNow;
            if (failIfPaused && g.PausedUntil > now) throw new LingException(LingException.Kind.RateLimited);
            var me = ticket ?? ++seq;
            if (g.Waiting.Count == 0 && !g.Pumping && Wait(g, now) <= Slack)
            {
                g.LastStart = now;
                return Task.FromResult(me);
            }
            var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            g.Waiting.Add((priority, me, ready));
            if (!g.Pumping) { g.Pumping = true; _ = Pump(g); }
            return ready.Task.WaitAsync(cancel).ContinueWith(t => { t.GetAwaiter().GetResult(); return me; }, TaskScheduler.Default);
        }
    }

    /// Close enough to go: a wait comes back a tick short (TimeSpan rounding).
    const double Slack = 0.001;

    /// Seconds until the next start may go (gate held).
    static double Wait(StartGate g, DateTime now) => Math.Max(g.Spacing - (now - g.LastStart).TotalSeconds, (g.PausedUntil - now).TotalSeconds);

    async Task Pump(StartGate g)
    {
        while (true)
        {
            double wait;
            lock (gate)
            {
                if (g.Waiting.Count == 0) { g.Pumping = false; return; }
                var now = clock.UtcNow;
                wait = Wait(g, now);
                if (wait <= Slack)
                {
                    var next = g.Waiting.MinBy(w => ((int)w.priority, w.seq));
                    g.Waiting.Remove(next);
                    g.LastStart = now;
                    next.ready.TrySetResult();
                    continue;
                }
            }
            await clock.Delay(TimeSpan.FromSeconds(wait));
        }
    }
}
