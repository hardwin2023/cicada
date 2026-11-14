import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overlay, language, words, speak, records, ai, diagnostics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overlay: L("显示")
        case .language: L("语言")
        case .words: L("词表")
        case .speak: L("同声传译")
        case .records: L("通用")
        case .ai: L("AI 服务")
        case .diagnostics: L("诊断")
        }
    }
    var icon: String {
        switch self {
        case .overlay: "captions.bubble"
        case .language: "globe"
        case .words: "character.book.closed"
        case .speak: "mic"
        case .records: "gearshape"
        case .ai: "key"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

// MARK: - Building blocks

/// A white card of rows separated by hairlines, like System Settings.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    /// A small state mark before the title, e.g. 共享屏幕时让对方看到's.
    var mark: AnyView? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let mark { mark }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(minHeight: 46)
            if divider { Divider().padding(.leading, 16) }
        }
    }
}

/// A few mutually exclusive choices side by side, the chosen one raised.
struct Segments: View {
    let options: [(id: String, title: String)]
    let value: String
    var fill = false
    /// Darker on a grey card, where `Palette.fill` would vanish.
    var track = Palette.fill
    let onPick: (String) -> Void
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { o in
                let on = o.id == value
                Button { onPick(o.id) } label: {
                    Text(o.title).font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Palette.ink : Palette.secondary).lineLimit(1)
                        .padding(.horizontal, fill ? 6 : 10).frame(maxWidth: fill ? .infinity : nil).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white : .clear)
                            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1.5, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(track))
        .fixedSize(horizontal: !fill, vertical: false)
    }
}

/// 字幕条: shown while someone talks, or always. Settings and the menu bar panel.
@MainActor func overlayAutoSegments(model: AppModel, fill: Bool = false, track: Color = Palette.fill) -> some View {
    Segments(options: [("auto", L("有人说话时")), ("always", L("始终显示"))],
                    value: model.settings.overlayAuto ? "auto" : "always", fill: fill, track: track) { model.setOverlayAuto($0 == "auto") }
}

/// 字幕条: how long it waits after the last words before tucking away.
@MainActor func hideAfterSegments(settings: AppSettings, fill: Bool = false, track: Color = Palette.fill) -> some View {
    Segments(options: [2.0, 4, 8].map { (String(Int($0)), L("\(Int($0)) 秒")) },
             value: String(Int(settings.overlayHideAfter)), fill: fill, track: track) { settings.overlayHideAfter = Double($0) ?? 4 }
}

/// The 字幕 choices.
let subtitleOptions: [(id: String, title: String)] = [("both", L("原文 + 译文")), ("translation", L("只看译文")), ("original", L("只看原文"))]

/// A grey pill that opens a menu: the value and a small chevron.
struct PillMenu: View {
    let value: String
    let options: [(id: String, title: String)]
    let onPick: (String) -> Void
    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in Button(o.title) { onPick(o.id) } }
        } label: {
            HStack(spacing: 6) {
                Text(value).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.ground))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

struct SoftButton: View {
    let title: String
    var dark = false
    /// White, for a button sitting on a grey card.
    var onGrey = false
    let action: () -> Void
    init(_ title: String, dark: Bool = false, onGrey: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.dark = dark
        self.onGrey = onGrey
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dark ? Color.white : Palette.ink)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(dark ? Palette.ink : onGrey ? Color.white : Color(white: 0.925)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shortcut field

/// Shows a shortcut as key caps; click it, then press the new keys (esc cancels).
/// The talk key also accepts the right ⌥ on its own.
struct ShortcutField: View {
    @ObservedObject var model: AppModel
    let role: AppModel.ShortcutRole
    @State private var recording = false
    @State private var error: String?
    @State private var monitor: Any?
    @State private var rightDown = false

    private var current: Shortcut { role == .talk ? model.settings.talkKey : model.settings.toggleKey }
    private var standard: Shortcut { role == .talk ? .defaultTalk : .defaultToggle }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if current != standard && !recording {
                    Button { error = model.setShortcut(standard, for: role) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("恢复默认（\(standard.display)）")
                }
                Button { recording ? stop() : start() } label: {
                    HStack(spacing: 4) {
                        if recording {
                            Text(role == .talk ? L("按下组合键，或单按右 ⌥") : L("按下新的组合键"))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accentInk)
                        } else {
                            ForEach(Array(current.keys.enumerated()), id: \.offset) { KeyCap($0.element) }
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Palette.accentPale : Palette.ground))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(recording ? Palette.accent : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recording ? L("按 esc 取消") : L("点击更换按键"))
            }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.accentInk)
            }
        }
        .onDisappear { stop() }
        // Another app grabbed the keys (its launcher came up): stop waiting for them.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        error = nil
        recording = true
        rightDown = false
        model.suspendShortcuts(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        model.suspendShortcuts(false)
    }

    private func handle(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch e.type {
        case .keyDown:
            if e.keyCode == UInt16(kVK_Escape) && flags.isEmpty { stop(); return }
            commit(Shortcut(keyCode: e.keyCode, flags: flags))
        case .flagsChanged:
            if role == .talk && e.keyCode == UInt16(kVK_RightOption) {
                // Right ⌥ pressed and released with nothing else: that's the choice.
                if e.modifierFlags.rawValue & 0x40 != 0 { rightDown = true } else if rightDown { commit(.rightOption) }
            } else {
                rightDown = false
            }
        default:
            break
        }
    }

    private func commit(_ s: Shortcut) {
        error = model.setShortcut(s, for: role)
        stop()
    }
}

/// "输入监控" is missing for the right ⌥ key: one line and a button.
struct TalkKeyPermissionRow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        SettingsRow(title: L("还差一步：允许“输入监控”"),
                    detail: L("“按住右 ⌥ 说话”需要此权限。请在系统设置中勾选 \(appDisplayName)，返回此处即可生效")) {
            SoftButton(L("去允许"), dark: true) { model.allowTalkKey() }
        }
    }
}

/// A check, an exclamation mark, or (speaking off) a grey dash, in a small circle.
struct HealthMark: View {
    let ok: Bool
    let on: Bool
    /// On a tinted problem row the pale circle would vanish.
    var onTint = false
    var body: some View {
        ZStack {
            Circle().fill(onTint ? Color.white : !ok ? Palette.accentPale : on ? Palette.okPale : Palette.fill)
            Image(systemName: !ok ? "exclamationmark" : on ? "checkmark" : "minus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(!ok ? Palette.accent : on ? Palette.ok : Palette.tertiary)
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Virtual microphone checklist

/// The one place the virtual mic is set up: onboarding step 4 and the settings window.
/// Not ready → a three-step checklist with one button that does the next step.
/// Ready → one line with a status dot and the sound test.
struct MicSetupCard: View {
    @ObservedObject var installer: VirtualMicInstaller
    /// Re-read the device list when the app's copy changes.
    var deviceName: String?

    private var onDisk: Bool { installer.isOnDisk || deviceName != nil }
    private var loaded: Bool { deviceName != nil }

    var body: some View {
        if loaded && installer.passed && installer.state != .testing {
            ready
        } else {
            checklist
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(Color(red: 0.12, green: 0.62, blue: 0.33)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("虚拟麦克风已就绪").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("\(deviceName ?? "BlackHole 2ch") · 试音通过，对方听得到").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                SoftButton(L("再试一次")) { installer.runTest() }
            }
            if let t = installer.test { TestResultView(result: t) }
        }
        .padding(16)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("虚拟麦克风").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(statusTag).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(installer.busy ? Palette.accentInk : Palette.tertiary)
            }
            step(1, L("安装"), L("输一次电脑密码"), done: onDisk,
                 active: installer.state == .downloading || installer.state == .installing,
                 activeText: installer.state == .downloading ? L("正在下载…") : L("正在安装…"))
            step(2, L("让系统认出它"), L("声音会短暂中断约 1 秒"), done: loaded,
                 active: installer.state == .reloading, activeText: L("正在让系统认出它…"))
            step(3, L("试音"), L("自动播一句，确认对方听得到"), done: installer.passed,
                 active: installer.state == .testing, activeText: L("正在试音…"))
            if let t = installer.test, !t.heard, installer.state != .testing {
                TestResultView(result: t)
            }
            if case .failed(let msg) = installer.state {
                Text(msg).font(.system(size: 12)).foregroundStyle(Palette.accentInk)
            }
            if !installer.busy {
                SoftButton(buttonTitle, dark: true) { installer.next() }
            }
        }
        .padding(16)
    }

    private var statusTag: String {
        if installer.busy { return L("进行中") }
        if !onDisk { return L("没装") }
        if !loaded { return L("系统还没认出") }
        return installer.test == nil ? L("还没试音") : L("没听到声音")
    }

    private var buttonTitle: String {
        if !onDisk { return L("一键安装") }
        if !loaded { return L("让系统认出它") }
        return installer.test == nil ? L("试音") : L("再试一次")
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, active: Bool, activeText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Palette.ink : active ? Palette.accentPale : Palette.ground)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else if active {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(active ? activeText : title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(done || active ? Palette.ink : Palette.secondary)
                if !done && !active {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
            }
            .padding(.top, 2)
        }
    }
}

struct TestResultView: View {
    let result: VirtualMicInstaller.TestResult
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if result.heard { HStack(alignment: .center, spacing: 2) {
                ForEach(Array(result.levels.enumerated()), id: \.offset) { _, l in
                    Capsule().fill(result.heard ? Palette.accent : Color(white: 0.8))
                        .frame(width: 3, height: max(3, CGFloat(min(1, l * 2.5)) * 24))
                }
            }
            .frame(height: 24) }
            if result.heard {
                (Text("对方会听到：") + Text(result.text.isEmpty ? L("一段声音") : "“\(result.text)”").bold())
                    .font(.system(size: 12)).foregroundStyle(Palette.ink)
            } else {
                Text(result.problem ?? L("虚拟麦克风未收到声音，请再试一次")).font(.system(size: 12)).foregroundStyle(Palette.accentInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(result.heard ? Palette.ground : Palette.accentPale))
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var installer: VirtualMicInstaller

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            ScrollView { page }
        }
        .frame(width: 720, height: 600)
        .background(Color(red: 0.965, green: 0.969, blue: 0.976))
    }

    /// The current section without the scroll view (also drawn by the `settingsRender` debug command).
    var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.settingsSection.title).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
                Spacer()
                if model.settingsSection == .ai { AIServiceMenu(model: model, settings: settings) }
                if model.settingsSection == .speak {
                    Toggle("把我说的翻译给对方", isOn: Binding(get: { settings.speakEnabled }, set: { model.enableSpeaking($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Palette.ink)
                }
            }
            switch model.settingsSection {
            case .speak: speak
            case .overlay: overlay
            case .language: LanguageSettings(model: model, settings: settings)
            case .words: WordListSettings(model: model, settings: settings, vocabulary: model.vocabulary, ling: model.ling)
            case .records: records
            case .ai: AISettingsView(model: model, ling: model.ling, settings: settings)
            case .diagnostics: DiagnosticsView(diagnostics: model.diagnostics, service: settings.aiConfig)
            }
        }
        .padding(.leading, 12).padding(.trailing, 28).padding(.top, 40).padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases.filter { $0 != .diagnostics || settings.diagnostics }) { s in
                let on = s == model.settingsSection
                if s == .diagnostics {
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 6)
                }
                Button { model.settingsSection = s } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).font(.system(size: 13))
                            .foregroundStyle(on ? Palette.accent : Palette.secondary).frame(width: 18)
                        Text(s.title).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(Palette.ink)
                        Spacer()
                        if s == .speak && settings.speakEnabled && model.virtualMic == nil {
                            Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Palette.line : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Diagnostics is for chasing slowness: off it leaves no trace in the sidebar.
            HStack(spacing: 8) {
                Text("诊断").font(.system(size: 12)).foregroundStyle(settings.diagnostics ? Palette.ink : Palette.secondary)
                    .fixedSize()
                Toggle("诊断", isOn: Binding(get: { settings.diagnostics }, set: { model.setDiagnostics($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.mini).tint(Palette.ink)
                Spacer()
                Text(Self.version).font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.tertiary).fixedSize()
            }
            .padding(.horizontal, 10).padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .padding(.horizontal, 10).padding(.top, 44).padding(.bottom, 14)
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    // MARK: Sections

    /// One card says whether the room hears you; it opens into a checklist only when something
    /// is wrong. Below it, plain settings: what you say with, and which microphones.
    private var speak: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.virtualMic == nil {
                SettingsCard { MicSetupCard(installer: installer, deviceName: nil) }
            } else {
                speakHealth
            }
            group(L("说话")) {
                SettingsRow(title: L("按住说话")) { ShortcutField(model: model, role: .talk) }
                // Hands-free runs only while listening, and pauses with the room mic on (`AppModel.handsFreeSetting`).
                SettingsRow(title: L("不用按键"),
                            detail: !settings.speakHandsFree ? L("开口就翻译，停顿 1 秒后说出去")
                                : settings.hearsRoom ? L("打开麦克风时暂停") : model.running ? L("开口就翻译，停顿 1 秒后说出去") : L("开始听会议后生效")) {
                    Toggle("不用按键", isOn: $settings.speakHandsFree)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("说\(settings.speakFromLang.name)，对方听到")) {
                    PillMenu(value: settings.speakTo == "room" ? L("跟随对方（\(targetName(model.speak.targetCode))）") : targetName(settings.speakTo),
                             options: [("room", L("跟随对方"))] + targetLanguages.map { ($0.code, $0.name) }) {
                        settings.speakTo = $0
                        model.objectWillChange.send()
                    }
                }
                VoiceSection(model: model, settings: settings, ling: model.ling)
            }
            if model.virtualMic != nil { micSettings }
        }
        .sheet(isPresented: $model.speakTestShown) {
            SpeakTestView(model: model, tester: model.speakTester) {
                if model.speakTester.busy { model.speakTester.cancel() }
                model.speakTestShown = false
            }
        }
        .sheet(item: $model.micGuide) { user in
            MicGuideView(model: model, bundleID: user.bundleID, name: user.name) { model.micGuide = nil }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary).padding(.horizontal, 4)
            SettingsCard { content() }
        }
        .padding(.top, 4)
    }

    /// Something keeping the room from hearing you, with the one button that fixes it.
    private struct SpeakProblem: Identifiable {
        let id: String
        let text: String
        let button: String
        let action: () -> Void
    }

    private var speakProblems: [SpeakProblem] {
        var out: [SpeakProblem] = []
        if settings.speakEnabled && model.talkNeedsPermission {
            out.append(.init(id: "key", text: L("按键还需要“输入监控”权限"), button: L("去允许"), action: model.allowTalkKey))
        }
        // A switched-away or never-restored system mic matters even with speaking off.
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        switch model.systemMicState {
        case .notRestored:
            out.append(.init(id: "sysmic", text: L("系统麦克风还是 \(virtual)，别的软件听不到你"), button: L("还原"), action: model.restoreSystemMic))
        case .moved(let to):
            out.append(.init(id: "sysmic", text: L("系统麦克风被换成了 \(to)"), button: L("换回"), action: model.switchSystemMic))
        case .off where model.wantsSystemMic:
            out.append(.init(id: "sysmic", text: L("系统麦克风还没换成 \(virtual)"), button: L("切换"), action: model.switchSystemMic))
        default: break
        }
        if settings.speakEnabled {
            for user in model.micUsers where user.state.isOther {
                let text: String
                if case .otherMic(let mic) = user.state, !mic.isEmpty { text = L("\(user.name)还在用 \(mic)") }
                else { text = L("\(user.name)没选虚拟麦克风") }
                out.append(.init(id: user.bundleID, text: text, button: L("怎么改"), action: { model.micGuide = user }))
            }
        }
        return out
    }

    /// What already works, listed above the problems so the broken step reads in context.
    private var speakOK: [String] {
        var out = [L("虚拟麦克风 \(model.virtualMic?.name ?? "BlackHole 2ch")")]
        if case .switched = model.systemMicState { out.append(L("系统麦克风已换好，关掉时换回")) }
        if settings.speakEnabled {
            out += model.micUsers.filter { $0.state == .virtualMic }.map { L("\($0.name)已选虚拟麦克风") }
        }
        return out
    }

    private var speakHealth: some View {
        let problems = speakProblems
        let on = settings.speakEnabled
        let ok = problems.isEmpty
        return SettingsCard {
            HStack(spacing: 12) {
                HealthMark(ok: ok, on: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(!ok ? L("线上的人听不到你") : on ? L("线上的人听得到你") : L("同声传译没打开"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ok ? Palette.ink : Palette.accentInk)
                    Text(latencyLine).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button { model.speakTestShown = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("试一句").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(ok ? Color.white : Palette.ink).padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(ok ? Palette.ink : Palette.fill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("说一句话，听对方听到的声音，看每一步花了多久")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if !ok {
                ForEach(speakOK, id: \.self) { line in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        HealthMark(ok: true, on: true)
                        Text(line).font(.system(size: 13)).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 40)
                }
                ForEach(problems) { p in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        HealthMark(ok: false, on: true, onTint: true)
                        Text(p.text).font(.system(size: 13)).foregroundStyle(Palette.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SoftButton(p.button, dark: true, action: p.action)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 46)
                    .background(Palette.accentPale)
                }
            }
        }
        // The tinted problem rows would otherwise square off the card's corners.
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ok ? Color.clear : Palette.accent.opacity(0.35), lineWidth: 1))
    }

    /// The last measured press, else what to expect.
    private var latencyLine: String {
        guard let v = model.lastSpeakLatency else {
            // Measured with 试一句: Ming's voice ~3 s after release, the Mac's ~1 s.
            let mac = model.voiceID(for: model.speak.targetCode)?.hasPrefix("system:") ?? true
            return mac ? L("按住说话，松开后约 1 秒，对方听到译文") : L("按住说话，松开后约 3 秒，对方听到译文")
        }
        return L("上次发言：松开后 \(String(format: "%.1f", v)) 秒，对方听到译文")
    }

    /// 麦克风: the virtual mic as the system default while speaking, the real mic Cicada records
    /// from, and where the spoken translation goes. Their state shows in the card above.
    private var micSettings: some View {
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        let inputs = model.systemMic.realInputs
        // A chosen mic that's unplugged reads as 自动 until it's back.
        let chosen = inputs.first { $0.uid == settings.speakMic }?.name
        let auto = model.systemMic.recordingDevice?.name
        return group(L("麦克风")) {
            SettingsRow(title: L("打开时把系统麦克风换成 \(virtual)")) {
                Toggle("自动切换系统麦克风", isOn: Binding(get: { settings.autoSystemMic }, set: { model.setAutoSystemMic($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
            }
            SettingsRow(title: L("\(appDisplayName)听你说话用")) {
                PillMenu(value: chosen ?? (auto.map { L("自动（\($0)）") } ?? L("自动")),
                         options: [("", L("自动"))] + inputs.map { ($0.uid, $0.name) }) {
                    settings.speakMic = $0
                }
            }
            // Only virtual mics: the translation is for the people online, never the speakers.
            SettingsRow(title: L("译文送到"), detail: L("只给线上的人听，不从扬声器放"), divider: false) {
                PillMenu(value: outputName,
                         options: [("", L("虚拟麦克风（自动）"))] + model.outputs.filter(\.isVirtualMic).map { ($0.uid, $0.name) }) {
                    settings.speakOutput = $0
                    model.applySystemMic()
                }
            }
        }
    }

    private var outputName: String {
        if settings.speakOutput.isEmpty { return L("虚拟麦克风（自动）") }
        return model.outputs.first { $0.uid == settings.speakOutput && $0.isVirtualMic }?.name ?? L("虚拟麦克风（自动）")
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(title: L("听的时候显示"), detail: L("选择任意模式都会正常保存记录、生成纪要")) {
                    Segments(options: [("notes", L("实时纪要")), ("bar", L("字幕条")), ("none", L("不显示"))],
                             value: settings.displayMode) { model.setDisplayMode($0) }
                }
                SettingsRow(title: L("切换显示方式"), detail: model.toggleKeyTaken ? L("被其他应用占用了，点右边换一个") : L("实时纪要 → 字幕条 → 不显示"), divider: false) {
                    ShortcutField(model: model, role: .toggle)
                }
            }
            Text("实时纪要").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
            SettingsCard {
                SettingsRow(title: L("共享屏幕时让对方看到"), detail: L("录屏也一样；关着时只有你看得到纪要窗口"), divider: false,
                            mark: AnyView(CapturableMark(on: settings.notesCapturable, size: 8).frame(width: 16, height: 16))) {
                    Toggle("共享屏幕时让对方看到", isOn: Binding(get: { settings.notesCapturable }, set: { model.setNotesCapturable($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                }
            }
            Text("字幕条").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
            SettingsCard {
                SettingsRow(title: L("字幕条显示时机")) {
                    overlayAutoSegments(model: model)
                }
                if settings.overlayAuto {
                    SettingsRow(title: L("安静多久后收起")) {
                        hideAfterSegments(settings: settings)
                    }
                }
                SettingsRow(title: L("位置和大小"), detail: L("鼠标悬停可拖动位置，拖拽右下角可缩放大小"), divider: false) {
                    SoftButton(L("恢复默认")) { model.overlay.resetPosition() }
                }
            }
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(title: L("保存会议录音"), detail: L("只存在这台 Mac 上")) {
                    Toggle("保存会议录音", isOn: $settings.recordAudio)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("开始听时打开麦克风"), detail: L("关掉后只听电脑声音；开会时再手动打开")) {
                    Toggle("开始听时打开麦克风", isOn: $settings.autoMicOnStart)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("说话人识别"), detail: L("按声音标出说话人 1、2…，只在这台 Mac 上处理")) {
                    Toggle("说话人识别", isOn: $settings.speakerVoices)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("每句都显示说话人"), detail: L("连续同一个人说话时也重复标出，不再只在换人时标")) {
                    Toggle("每句都显示说话人", isOn: $settings.speakerEveryLine)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                        .disabled(!settings.speakerVoices)
                }
                SettingsRow(title: L("记住说话人"), detail: L("按本机声纹认出以前见过的人；不会上传声音")) {
                    Toggle("记住说话人", isOn: $settings.speakerMemory)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("人员库"), detail: L("\(model.speakerProfiles.count) 个人 · 声纹和备注")) {
                    SoftButton(L("管理")) { model.speakerLibraryShown = true }
                }
                SettingsRow(title: L("记录文件夹"), divider: false) {
                    SoftButton(L("打开")) { NSWorkspace.shared.open(model.store.root) }
                }
            }
            Text("会后存一份").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
            FolderExportSettings(model: model, settings: settings, exporter: model.folderExport)
            Text("导入的文件").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
            SettingsCard {
                SettingsRow(title: L("文件里说的"), detail: L("译成“翻译成”里的语言")) {
                    Picker("文件里说的", selection: $settings.importLanguage) {
                        Text("自动识别").tag("auto")
                        ForEach(sourceLanguages, id: \.locale) { Text($0.name).tag($0.locale) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(title: L("转完后生成纪要"),
                            detail: Recognition.cloudOnly ? L("导入转写和生成纪要都需要 Ling key") : L("需要 Ling key；没有也能转出文字记录"),
                            divider: false) {
                    Toggle("转完后生成纪要", isOn: $settings.importNotes)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
            }
            Text("结束会议").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.top, 4)
            SettingsCard {
                SettingsRow(title: L("会议应用挂断后结束"), detail: L("Zoom、腾讯会议、飞书、Teams 等")) {
                    Toggle("会议应用挂断后结束", isOn: $settings.endWithApp)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("没人说话时"), detail: L("按识别出的话算，背景音乐不算"), divider: settings.silenceEnd != "off") {
                    Segments(options: [("prompt", L("提醒后结束")), ("end", L("直接结束")), ("off", L("一直记录"))],
                             value: settings.silenceEnd) { settings.silenceEnd = $0 }
                }
                if settings.silenceEnd != "off" {
                    SettingsRow(title: L("多久算没人说话"), divider: false) {
                        Segments(options: [5.0, 10, 15, 30].map { (String(Int($0)), L("\(Int($0)) 分钟")) },
                                 value: String(Int(settings.silenceMinutes))) { settings.silenceMinutes = Double($0) ?? 10 }
                    }
                }
            }
            AppRows(updates: model.updates, loginItem: model.loginItem, model: model)
        }
        .sheet(isPresented: $model.speakerLibraryShown) {
            SpeakerLibraryView(model: model)
        }
    }
}
