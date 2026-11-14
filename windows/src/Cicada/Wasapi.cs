using System.Runtime.InteropServices;

namespace Cicada.App;

/// Audio devices by name, and plain WASAPI capture and playback on them: the microphone (what I
/// say), the virtual cable's "CABLE Input" (what the meeting hears), the speakers (previews).
/// SystemAudioTap is the other half, the process loopback.
static class Endpoints
{
    public enum Flow { Render = 0, Capture = 1 }
    public sealed record Device(string Id, string Name, string Description);

    /// Active devices: Name is "扬声器 (Realtek…)", Description the short "CABLE Input".
    public static List<Device> All(Flow flow)
    {
        var list = new List<Device>();
        try
        {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            Marshal.ThrowExceptionForHR(e.EnumAudioEndpoints((int)flow, 1 /* ACTIVE */, out var all));
            all.GetCount(out var n);
            for (uint i = 0; i < n; i++)
            {
                all.Item(i, out var d);
                d.GetId(out var id);
                list.Add(new Device(id, Prop(d, 14) ?? id, Prop(d, 2) ?? ""));
            }
        }
        catch (Exception ex) { Log.Debug($"endpoints: list failed {ex.GetType().Name}"); }
        return list;
    }

    public static Device? Default(Flow flow)
    {
        try
        {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            if (e.GetDefaultAudioEndpoint((int)flow, 1 /* eMultimedia */, out var d) != 0) return null;
            d.GetId(out var id);
            return new Device(id, Prop(d, 14) ?? id, Prop(d, 2) ?? "");
        }
        catch { return null; }
    }

    /// The virtual cable's playback side, which meeting apps hear as the "CABLE Output" mic.
    public static Device? Cable() => All(Flow.Render).FirstOrDefault(d => d.Description == VirtualCable.InputName || d.Name.StartsWith(VirtualCable.InputName));
    public static Device? CableOutput() => All(Flow.Capture).FirstOrDefault(d => d.Description == VirtualCable.OutputName || d.Name.StartsWith(VirtualCable.OutputName));

    /// Any end of VB-Cable, "CABLE In 16ch" too (the pack installs it beside CABLE Input, and
    /// Windows can make it the default speaker as well).
    public static bool IsCable(Device d) =>
        d.Description is VirtualCable.InputName or VirtualCable.OutputName || d.Name.StartsWith(VirtualCable.InputName) || d.Name.StartsWith(VirtualCable.OutputName)
        || d.Name.Contains("VB-Audio Virtual Cable", StringComparison.OrdinalIgnoreCase);

    /// Every default (CableDefaults' "<flow>/<role>" keys): the playback and recording device for
    /// games and system sounds, for media and for calls.
    public static Dictionary<string, string> Defaults()
    {
        var map = new Dictionary<string, string>();
        try
        {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            foreach (var flow in new[] { Flow.Render, Flow.Capture })
                for (var role = 0; role < 3; role++)
                    if (e.GetDefaultAudioEndpoint((int)flow, role, out var d) == 0 && d.GetId(out var id) == 0) map[$"{(int)flow}/{role}"] = id;
        }
        catch (Exception ex) { Log.Debug($"endpoints: defaults failed {ex.GetType().Name}"); }
        return map;
    }

    /// Ids of the cable's two ends, for CableDefaults.
    public static HashSet<string> CableIds() => [.. All(Flow.Render).Concat(All(Flow.Capture)).Where(IsCable).Select(d => d.Id)];

    /// What the user hears through is the cable: they hear nothing.
    public static bool SpeakerIsCable() => Default(Flow.Render) is { } d && IsCable(d);

    /// Makes `id` the default for one role, as the Sound control panel does. IPolicyConfig isn't
    /// documented, but it is what Windows' own panel calls and has stayed put since Windows 7.
    public static bool SetDefault(string id, int role)
    {
        try
        {
            var policy = (IPolicyConfig)new PolicyConfigClient();
            var hr = policy.SetDefaultEndpoint(id, role);
            Marshal.ReleaseComObject(policy);
            return hr == 0;
        }
        catch (Exception ex) { Log.Debug($"endpoints: set default failed {ex.GetType().Name}"); return false; }
    }

    /// Back to a real speaker for every role (CableDefaults.Speaker): when nothing from before the
    /// install was remembered.
    public static bool RestoreSpeaker()
    {
        if (CableDefaults.Speaker(All(Flow.Render).Select(d => (d.Id, IsCable(d)))) is not { } id) { Log.Debug("cable: no other speaker"); return false; }
        var ok = Enumerable.Range(0, 3).All(role => SetDefault(id, role));
        Log.Debug($"cable: speaker restored {ok}");
        return ok && !SpeakerIsCable();
    }

    /// A microphone, never the cable's own output (that would be the room hearing itself).
    public static Device? Microphone()
    {
        var d = Default(Flow.Capture);
        if (d is not null && d.Description != VirtualCable.OutputName && !d.Name.StartsWith(VirtualCable.OutputName)) return d;
        return All(Flow.Capture).FirstOrDefault(x => x.Description != VirtualCable.OutputName && !x.Name.StartsWith(VirtualCable.OutputName));
    }

    /// 会议室: the microphone that hears the table (RoomMicPlan): the default, unless that is the
    /// virtual cable or a Bluetooth headset.
    public static Device? RoomMic()
    {
        var inputs = new List<(Device d, RoomMicPlan.Input plan)>();
        try
        {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            Marshal.ThrowExceptionForHR(e.EnumAudioEndpoints((int)Flow.Capture, 1 /* ACTIVE */, out var all));
            all.GetCount(out var n);
            for (uint i = 0; i < n; i++)
            {
                all.Item(i, out var d);
                d.GetId(out var id);
                var device = new Device(id, Prop(d, 14) ?? id, Prop(d, 2) ?? "");
                // PKEY_Device_EnumeratorName: BTHENUM, BTHHFENUM, BTHLEDEVICE for Bluetooth.
                var bus = Prop(d, 24) ?? "";
                var virtualCable = device.Description == VirtualCable.OutputName || device.Name.StartsWith(VirtualCable.OutputName);
                inputs.Add((device, new RoomMicPlan.Input(id, bus.StartsWith("BTH", StringComparison.OrdinalIgnoreCase), virtualCable)));
            }
        }
        catch (Exception ex) { Log.Debug($"endpoints: inputs failed {ex.GetType().Name}"); }
        var pick = RoomMicPlan.Pick(Default(Flow.Capture)?.Id, inputs.Select(i => i.plan).ToList());
        return inputs.FirstOrDefault(i => i.d.Id == pick).d;
    }

    static string? Prop(IMMDevice d, int pid)
    {
        if (d.OpenPropertyStore(0, out var store) != 0) return null;
        var key = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = pid };
        if (store.GetValue(ref key, out var v) != 0) return null;
        var s = v.vt == 31 ? Marshal.PtrToStringUni(v.pointer) : null;
        PropVariantClear(ref v);
        return s;
    }

    internal static IAudioClient Activate(string id)
    {
        var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        Marshal.ThrowExceptionForHR(e.GetDevice(id, out var d));
        var iid = typeof(IAudioClient).GUID;
        Marshal.ThrowExceptionForHR(d.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out var o));
        return (IAudioClient)o;
    }

    internal static IntPtr Pcm16(int rate)
    {
        var p = Marshal.AllocHGlobal(18);
        var b = new byte[18];
        BitConverter.GetBytes((ushort)1).CopyTo(b, 0); BitConverter.GetBytes((ushort)1).CopyTo(b, 2);
        BitConverter.GetBytes(rate).CopyTo(b, 4); BitConverter.GetBytes(rate * 2).CopyTo(b, 8);
        BitConverter.GetBytes((ushort)2).CopyTo(b, 12); BitConverter.GetBytes((ushort)16).CopyTo(b, 14);
        Marshal.Copy(b, 0, p, 18);
        return p;
    }

    internal const uint AutoConvert = 0x80000000 | 0x08000000; // AUTOCONVERTPCM | SRC_DEFAULT_QUALITY

    // MARK: COM

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int Item(uint index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetAt(int index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")] class PolicyConfigClient { }

    /// Only SetDefaultEndpoint is called; the slots before it keep the vtable in order.
    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat(IntPtr a, IntPtr b);
        [PreserveSig] int GetDeviceFormat(IntPtr a, int b, IntPtr c);
        [PreserveSig] int ResetDeviceFormat(IntPtr a);
        [PreserveSig] int SetDeviceFormat(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int GetProcessingPeriod(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetProcessingPeriod(IntPtr a, IntPtr b);
        [PreserveSig] int GetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int SetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int GetPropertyValue(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int SetPropertyValue(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
        [PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
    }

    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public int pid; }
    [StructLayout(LayoutKind.Explicit, Size = 24)] struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr pointer; }
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant value);
}

[ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioClient
{
    [PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr sessionGuid);
    [PreserveSig] int GetBufferSize(out uint frames);
    [PreserveSig] int GetStreamLatency(out long latency);
    [PreserveSig] int GetCurrentPadding(out uint padding);
    [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
    [PreserveSig] int GetMixFormat(out IntPtr format);
    [PreserveSig] int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
    [PreserveSig] int Start();
    [PreserveSig] int Stop();
    [PreserveSig] int Reset();
    [PreserveSig] int SetEventHandle(IntPtr handle);
    [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
}

[ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioCaptureClient
{
    [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
    [PreserveSig] int ReleaseBuffer(uint frames);
    [PreserveSig] int GetNextPacketSize(out uint frames);
}

[ComImport, Guid("F294ACFC-3146-4483-A7BF-ADDCA7C260E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioRenderClient
{
    [PreserveSig] int GetBuffer(uint frames, out IntPtr data);
    [PreserveSig] int ReleaseBuffer(uint frames, uint flags);
}

/// Records one device at 16 kHz mono (Windows converts) until Stop: the mic while the key is held,
/// or CABLE Output in tests (what the meeting would hear).
sealed class DeviceRecorder
{
    readonly string id;
    readonly List<short> samples = [];
    Thread? thread;
    volatile bool running;
    public string? Error { get; private set; }
    /// The last packet's peak, 0–1 (scaled as the Mac's recorder meter): for a level bar.
    public volatile float Level;

    public DeviceRecorder(string id) { this.id = id; }

    public void Start()
    {
        running = true;
        var ready = new ManualResetEventSlim();
        thread = new Thread(() => Run(ready)) { IsBackground = true, Name = "DeviceRecorder" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
        ready.Wait(2000);
    }

    public short[] Stop()
    {
        running = false;
        thread?.Join(1500);
        lock (samples) return [.. samples];
    }

    void Run(ManualResetEventSlim ready)
    {
        IAudioClient? client = null;
        try
        {
            client = Endpoints.Activate(id);
            var fmt = Endpoints.Pcm16(16000);
            int hr = client.Initialize(0, Endpoints.AutoConvert, 2_000_000, 0, fmt, IntPtr.Zero);
            Marshal.FreeHGlobal(fmt);
            Marshal.ThrowExceptionForHR(hr);
            var iid = typeof(IAudioCaptureClient).GUID;
            Marshal.ThrowExceptionForHR(client.GetService(ref iid, out var s));
            var cap = (IAudioCaptureClient)s;
            Marshal.ThrowExceptionForHR(client.Start());
            ready.Set();
            while (running)
            {
                Thread.Sleep(10);
                while (cap.GetNextPacketSize(out var n) == 0 && n > 0)
                {
                    if (cap.GetBuffer(out var data, out var frames, out var flags, out _, out _) != 0) break;
                    var buf = new short[frames];
                    if ((flags & 0x2) == 0) Marshal.Copy(data, buf, 0, (int)frames);
                    cap.ReleaseBuffer(frames);
                    int peak = 0;
                    foreach (var v in buf) peak = Math.Max(peak, Math.Abs((int)v));
                    Level = Math.Min(1f, peak / 32768f * 2.5f);
                    lock (samples) samples.AddRange(buf);
                }
            }
            client.Stop();
        }
        catch (Exception e)
        {
            // 0x80070005: Windows' microphone privacy switch is off for desktop apps.
            Error = e.HResult == unchecked((int)0x80070005) ? "denied" : e.GetType().Name;
            Log.Debug($"recorder: failed 0x{e.HResult:X8}");
            ready.Set();
        }
        finally { if (client is not null) Marshal.ReleaseComObject(client); }
    }
}

/// Plays a sentence on one device: the virtual cable for the room, the speakers for a preview.
/// Chunks are queued as they stream in and played as soon as the first arrives; End waits for the
/// last sample to be heard.
sealed class DeviceSpeaker : ISpeechSink
{
    readonly Func<Endpoints.Device?> device;
    readonly Queue<byte[]> queue = new();
    Thread? thread;
    volatile bool ending, stopped;
    TaskCompletionSource? done;
    int rate;
    public string? DeviceName { get; private set; }
    /// The device was there but wouldn't play (or vanished): nothing, or not all, was heard.
    public bool Failed { get; private set; }
    public bool Stopped => stopped;

    public DeviceSpeaker(Func<Endpoints.Device?> device) { this.device = device; }

    public bool Ready => device() is not null;

    /// 试听's 停止: what is queued is dropped and End returns; later chunks are ignored.
    public void Stop()
    {
        stopped = true; ending = true;
        lock (queue) queue.Clear();
    }

    public void Begin(int rate)
    {
        this.rate = rate;
        ending = stopped;
        lock (queue) queue.Clear();
        done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (stopped) { done.TrySetResult(); return; }
        var d = device();
        DeviceName = d?.Name;
        if (d is null) { Log.Debug("speaker: no device"); Failed = true; done.TrySetResult(); return; }
        thread = new Thread(() => Run(d.Id)) { IsBackground = true, Name = "DeviceSpeaker" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    public void Write(byte[] pcm) { if (!stopped) lock (queue) queue.Enqueue(pcm); }

    public Task End() { ending = true; return done?.Task ?? Task.CompletedTask; }

    void Run(string id)
    {
        IAudioClient? client = null;
        try
        {
            client = Endpoints.Activate(id);
            var fmt = Endpoints.Pcm16(rate);
            int hr = client.Initialize(0, Endpoints.AutoConvert, 2_000_000, 0, fmt, IntPtr.Zero);
            Marshal.FreeHGlobal(fmt);
            Marshal.ThrowExceptionForHR(hr);
            client.GetBufferSize(out var size);
            var iid = typeof(IAudioRenderClient).GUID;
            Marshal.ThrowExceptionForHR(client.GetService(ref iid, out var s));
            var render = (IAudioRenderClient)s;
            byte[] pending = [];
            int offset = 0;
            bool started = false;
            while (!stopped)
            {
                client.GetCurrentPadding(out var padding);
                var room = (int)(size - padding);
                if (offset >= pending.Length)
                {
                    lock (queue) { if (queue.Count > 0) { pending = queue.Dequeue(); offset = 0; } }
                }
                // Half a sample left over can't be played: without this the loop spun on it forever,
                // End never returned and the talk key stayed on 正在说给对方听….
                if (pending.Length - offset == 1) offset = pending.Length;
                if (offset < pending.Length && room > 0)
                {
                    int frames = Math.Min(room, (pending.Length - offset) / 2);
                    if (render.GetBuffer((uint)frames, out var data) != 0) { Thread.Sleep(10); continue; }
                    Marshal.Copy(pending, offset, data, frames * 2);
                    render.ReleaseBuffer((uint)frames, 0);
                    offset += frames * 2;
                    if (!started) { Marshal.ThrowExceptionForHR(client.Start()); started = true; }
                    continue;
                }
                bool empty; lock (queue) empty = queue.Count == 0;
                if (ending && empty && offset >= pending.Length && padding == 0) break;
                Thread.Sleep(10);
            }
            client.Stop();
        }
        catch (Exception e) { Log.Debug($"speaker: failed 0x{e.HResult:X8}"); Failed = true; }
        finally
        {
            if (client is not null) Marshal.ReleaseComObject(client);
            done?.TrySetResult();
        }
    }
}
