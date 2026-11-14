using System.Runtime.InteropServices;

namespace Cicada.App;

/// Everything the PC plays except Cicada itself: WASAPI process loopback with this process's tree
/// excluded (Windows 10 2004+), the counterpart of the Mac's Core Audio process tap. Asks Windows
/// for 16 kHz mono directly and falls back to 48 kHz stereo converted here. The capture thread
/// only hands buffers on; ListenEngine queues them.
sealed class SystemAudioTap : IAudioSource
{
    const string LoopbackDevice = "VAD\\Process_Loopback";
    const uint StreamLoopback = 0x00020000, StreamEventCallback = 0x00040000, AutoConvertPcm = 0x80000000, SrcDefaultQuality = 0x08000000;
    const uint BufferDiscontinuity = 0x1, BufferSilent = 0x2;

    Thread? thread;
    volatile bool running;
    /// Only Cicada's own sound instead of everything else: the onboarding's test sound, which the
    /// normal tap leaves out by design. Proves process loopback works on this PC all the same.
    public bool OnlySelf { get; init; }
    public event Action<short[]>? Samples;
    public event Action<string?>? Ended;

    public void Start()
    {
        running = true;
        thread = new Thread(Run) { IsBackground = true, Name = "SystemAudioTap", Priority = ThreadPriority.AboveNormal };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    public void Stop()
    {
        running = false;
        thread?.Join(1000);
    }

    /// A capture that breaks (the Windows Audio service restarting, a driver or a dock's audio
    /// resetting) opens again; only one that keeps failing ends listening, with its reason.
    void Run()
    {
        int failures = 0;
        while (true)
        {
            var started = DateTime.UtcNow;
            try { Capture(); Ended?.Invoke(null); return; }
            catch (Exception e)
            {
                Log.Debug($"tap: failed {e.GetType().Name} 0x{e.HResult:X8}");
                if (!running) { Ended?.Invoke(null); return; }
                failures = DateTime.UtcNow - started > TimeSpan.FromSeconds(10) ? 1 : failures + 1;
                if (failures > 5) { Ended?.Invoke(e.Message); return; }
                Thread.Sleep(300 * failures);
                if (!running) { Ended?.Invoke(null); return; }
                Log.Debug("tap: opening the capture again");
            }
        }
    }

    void Capture()
    {
        (int rate, int channels)[] tries = [(16000, 1), (48000, 2), (44100, 2)];
        IAudioClient? client = null;
        int rate = 0, channels = 0;
        foreach (var (r, c) in tries)
        {
            client = Activate();
            var fmt = WaveFormat.Pcm16(r, c);
            var p = Marshal.AllocHGlobal(Marshal.SizeOf<WaveFormat>());
            Marshal.StructureToPtr(fmt, p, false);
            // A 1 s buffer (100 ns units): a capture thread held up for a moment must not lose audio.
            int hr = client.Initialize(0, StreamLoopback | StreamEventCallback | AutoConvertPcm | SrcDefaultQuality, 10_000_000, 0, p, IntPtr.Zero);
            Marshal.FreeHGlobal(p);
            if (hr == 0) { rate = r; channels = c; break; }
            Log.Debug($"tap: {r} Hz x{c} refused 0x{hr:X8}");
            Marshal.ReleaseComObject(client);
            client = null;
        }
        if (client is null) throw new InvalidOperationException("no capture format accepted");
        Log.Debug($"tap: capturing {rate} Hz x{channels}");

        using var ready = new AutoResetEvent(false);
        Marshal.ThrowExceptionForHR(client.SetEventHandle(ready.SafeWaitHandle.DangerousGetHandle()));
        var iid = typeof(IAudioCaptureClient).GUID;
        Marshal.ThrowExceptionForHR(client.GetService(ref iid, out var service));
        var capture = (IAudioCaptureClient)service;
        Marshal.ThrowExceptionForHR(client.Start());
        try
        {
            // Loopback sends nothing while nothing plays, so we feed silence ourselves (LoopbackGap:
            // only after a second without a packet, or a late packet splits its sentence in two).
            var lastPacket = DateTime.UtcNow; var fedUntil = lastPacket;
            int gaps = 0;
            while (running)
            {
                if (!ready.WaitOne(100))
                {
                    var now = DateTime.UtcNow;
                    var silence = LoopbackGap.Silence((now - lastPacket).TotalSeconds, (now - fedUntil).TotalSeconds);
                    if (silence > 0)
                    {
                        Samples?.Invoke(new short[silence]);
                        fedUntil = now;
                    }
                    continue;
                }
                // How long packets stall here (a VM): a stall over LoopbackGap.Late puts a gap in a sentence.
                var waited = (DateTime.UtcNow - lastPacket).TotalMilliseconds;
                if (waited >= 300 && fedUntil == lastPacket) Log.Debug($"tap: packets late by {waited:F0} ms");
                // A failing call (the device invalidated, the audio service gone) must throw: ending the
                // loop quietly would feed silence for the rest of the meeting.
                while (true)
                {
                    Marshal.ThrowExceptionForHR(capture.GetNextPacketSize(out var packet));
                    if (packet == 0) break;
                    Marshal.ThrowExceptionForHR(capture.GetBuffer(out var data, out var frames, out var flags, out _, out _));
                    if ((flags & BufferDiscontinuity) != 0 && ++gaps % 50 == 1) Log.Debug($"tap: audio glitch ({gaps} so far)");
                    int count = (int)frames * channels;
                    var buf = new short[count];
                    if ((flags & BufferSilent) == 0) Marshal.Copy(data, buf, 0, count);
                    capture.ReleaseBuffer(frames);
                    Samples?.Invoke(channels == 1 && rate == 16000 ? buf : ToMono16k(buf, rate, channels));
                }
                lastPacket = fedUntil = DateTime.UtcNow;
            }
        }
        finally
        {
            client.Stop();
            Marshal.ReleaseComObject(capture);
            Marshal.ReleaseComObject(client);
        }
    }

    static short[] ToMono16k(short[] interleaved, int rate, int channels)
    {
        int frames = interleaved.Length / channels;
        var mono = new double[frames];
        for (int f = 0; f < frames; f++)
        {
            double sum = 0;
            for (int c = 0; c < channels; c++) sum += interleaved[f * channels + c];
            mono[f] = sum / channels;
        }
        return Wav.Resample(mono, rate);
    }

    IAudioClient Activate()
    {
        var p = new ActivationParams { ActivationType = 1, TargetProcessId = (uint)Environment.ProcessId, ProcessLoopbackMode = OnlySelf ? 0 /* include tree */ : 1 /* exclude tree */ };
        int size = Marshal.SizeOf<ActivationParams>();
        var blob = Marshal.AllocHGlobal(size);
        Marshal.StructureToPtr(p, blob, false);
        var variant = new PropVariantBlob { vt = 65, cbSize = (uint)size, pBlobData = blob };
        var handler = new Completion();
        var iid = typeof(IAudioClient).GUID;
        try
        {
            Marshal.ThrowExceptionForHR(ActivateAudioInterfaceAsync(LoopbackDevice, ref iid, ref variant, handler, out var op));
            if (!handler.Done.Wait(5000)) throw new TimeoutException("audio activation did not complete");
            Marshal.ThrowExceptionForHR(op.GetActivateResult(out var hr, out var iface));
            Marshal.ThrowExceptionForHR(hr);
            return (IAudioClient)iface;
        }
        finally { Marshal.FreeHGlobal(blob); }
    }

    [DllImport("Mmdevapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern int ActivateAudioInterfaceAsync(string path, ref Guid riid, ref PropVariantBlob activationParams,
        IActivateAudioInterfaceCompletionHandler handler, out IActivateAudioInterfaceAsyncOperation op);

    // Must be agile, or activation fails with E_ILLEGAL_METHOD_CALL.
    [ComVisible(true)]
    sealed class Completion : IActivateAudioInterfaceCompletionHandler, IAgileObject
    {
        public readonly ManualResetEventSlim Done = new(false);
        public int ActivateCompleted(IActivateAudioInterfaceAsyncOperation op) { Done.Set(); return 0; }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ActivationParams { public int ActivationType; public uint TargetProcessId; public int ProcessLoopbackMode; }

    [StructLayout(LayoutKind.Explicit)]
    struct PropVariantBlob
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public uint cbSize;
        [FieldOffset(16)] public IntPtr pBlobData;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    struct WaveFormat
    {
        public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec;
        public ushort nBlockAlign, wBitsPerSample, cbSize;
        public static WaveFormat Pcm16(int rate, int channels) => new()
        {
            wFormatTag = 1, nChannels = (ushort)channels, nSamplesPerSec = (uint)rate,
            nBlockAlign = (ushort)(channels * 2), nAvgBytesPerSec = (uint)(rate * channels * 2), wBitsPerSample = 16,
        };
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

    [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IActivateAudioInterfaceAsyncOperation
    {
        [PreserveSig] int GetActivateResult(out int hr, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IActivateAudioInterfaceCompletionHandler
    {
        [PreserveSig] int ActivateCompleted(IActivateAudioInterfaceAsyncOperation op);
    }

    [ComImport, Guid("94ea2b94-e9cc-49e0-c0ff-ee64ca8f5b90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAgileObject { }
}
