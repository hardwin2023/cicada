using System.Runtime.InteropServices;
using System.Windows.Interop;
using Microsoft.Win32;

namespace Cicada.App;

/// Ctrl+Alt+L anywhere: start or end listening. A message-only window receives WM_HOTKEY.
sealed class Hotkey : IDisposable
{
    public const string Label = "Ctrl+Alt+L";
    const int Id = 0xC1CA, WmHotkey = 0x0312;
    const uint ModAlt = 0x1, ModControl = 0x2, ModNoRepeat = 0x4000, VkL = 0x4C;
    readonly HwndSource source;
    readonly Action pressed;
    /// False when another app already holds the combination (Settings says so).
    public bool Registered { get; }

    public Hotkey(Action pressed)
    {
        this.pressed = pressed;
        source = new HwndSource(new HwndSourceParameters("CicadaHotkey") { ParentWindow = new IntPtr(-3) /* HWND_MESSAGE */, Width = 0, Height = 0 });
        source.AddHook(Hook);
        Registered = RegisterHotKey(source.Handle, Id, ModControl | ModAlt | ModNoRepeat, VkL);
        Log.Debug($"hotkey: {(Registered ? "registered" : "taken")} {Label}");
    }

    IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && wParam.ToInt32() == Id) { handled = true; pressed(); }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (Registered) UnregisterHotKey(source.Handle, Id);
        source.Dispose();
    }

    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}

/// 开机时启动知了: the per-user Run key, so no admin rights. The dev build has its own entry.
static class AutoStart
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    static string Name => Paths.Dev ? "Cicada Dev" : "Cicada";
    // --background: started with Windows, so stay in the tray; opened by hand, the main window shows.
    static string Command(string exe) => $"\"{exe}\" --background" + (Paths.Dev ? " --dev" : "");

    /// Rewrites an entry made before --background existed, which would open the main window at sign-in.
    public static void Refresh()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            var exe = Environment.ProcessPath ?? "";
            if (k?.GetValue(Name) is string v && v.StartsWith($"\"{exe}\"", StringComparison.OrdinalIgnoreCase) && v != Command(exe)) { k.SetValue(Name, Command(exe)); Log.Debug("autostart: command updated"); }
        }
        catch (Exception e) { Log.Debug($"autostart: refresh failed {e.GetType().Name}"); }
    }

    public static bool Enabled
    {
        get
        {
            try { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue(Name) is string; }
            catch { return false; }
        }
        set => Set(Environment.ProcessPath ?? "", value);
    }

    /// The installer sets it for the copy it put in place, not for itself in Downloads.
    public static void Set(string exe, bool on)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (on) k.SetValue(Name, Command(exe)); else k.DeleteValue(Name, throwOnMissingValue: false);
            Log.Debug($"autostart: {(on ? "on" : "off")}");
        }
        catch (Exception e) { Log.Debug($"autostart: failed {e.GetType().Name}"); }
    }
}

/// The default playback device's name ("扬声器 (Realtek High Definition Audio)") for onboarding.
/// Through Endpoints, never a second [ComImport] MMDeviceEnumerator: the enumerator is one COM object
/// per process, and while an RCW of another class for it lives, `new` of Endpoints' class throws
/// InvalidCastException, so the virtual cable looked uninstalled after onboarding's sound step.
static class AudioDevice
{
    public static string? DefaultName() => Endpoints.Default(Endpoints.Flow.Render)?.Name;
}

/// The meeting apps reading a microphone now (MicUse in Cicada.Core reads the entries): what
/// Windows keeps for Settings › 隐私和安全性 › 麦克风, whose LastUsedTimeStop is 0 while an app has
/// the mic open. Both desktop apps (NonPackaged) and Store apps (the new Teams).
static class MicReaders
{
    const string Root = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";

    public static Dictionary<string, string> Calls()
    {
        var entries = new List<(string, long)>();
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey(Root);
            if (root is null) return [];
            void Read(RegistryKey parent)
            {
                foreach (var name in parent.GetSubKeyNames())
                {
                    if (name == "NonPackaged") continue;
                    using var k = parent.OpenSubKey(name);
                    // An app granted the mic but never used has both times 0: not in a call.
                    if (k?.GetValue("LastUsedTimeStop") is long stop && k.GetValue("LastUsedTimeStart") is long start && start > 0)
                        entries.Add((name, stop));
                }
            }
            Read(root);
            using (var desktop = root.OpenSubKey("NonPackaged")) if (desktop is not null) Read(desktop);
        }
        catch (Exception e) { Log.Debug($"mic users: unreadable ({e.GetType().Name})"); }
        return MicUse.Calls(entries);
    }
}

/// Windows' own proxy settings (Settings › Network & internet › Proxy, which proxy apps switch on as
/// "system proxy"): only read, to word the "can't reach" hint. Cicada never sets or uses one itself.
static class WinProxy
{
    const string Key = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

    /// A manual proxy, or an auto-config (PAC) script, is on.
    public static bool SystemOn()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return k?.GetValue("ProxyEnable") is int on && on == 1 || k?.GetValue("AutoConfigURL") is string { Length: > 0 };
        }
        catch (Exception e) { Log.Debug($"proxy: unreadable ({e.GetType().Name})"); return false; }
    }

    /// The settings that decide where requests go, as one string to compare (WatchProxy).
    public static string Snapshot()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return $"{k?.GetValue("ProxyEnable")}|{k?.GetValue("ProxyServer")}|{k?.GetValue("AutoConfigURL")}|{k?.GetValue("ProxyOverride")}";
        }
        catch { return ""; }
    }
}
