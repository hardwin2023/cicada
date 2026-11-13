import AppKit
import SwiftUI

enum Palette {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let ground = Color(red: 0.953, green: 0.957, blue: 0.965)
    static let line = Color(red: 0.894, green: 0.902, blue: 0.918)
    static let secondary = Color(red: 0.353, green: 0.373, blue: 0.42)
    static let tertiary = Color(red: 0.42, green: 0.44, blue: 0.50)
    /// Body text in the records window: darker than the greys, lighter than headings.
    static let body = Color(red: 0.239, green: 0.255, blue: 0.29)
    /// Times you can click to jump to the original, and the numbers that order notes: the logo's
    /// orange as ink, so text stays in the brand's family while the bright accent stays "live".
    static let link = Color(red: 0.70, green: 0.23, blue: 0.08)
    /// Highlighter behind numbers and dates in the conclusions.
    static let mark = Color(red: 1.0, green: 0.906, blue: 0.639)
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.17)
    static let accentInk = Color(red: 0.70, green: 0.23, blue: 0.08)
    static let accentPale = Color(red: 0.99, green: 0.93, blue: 0.906)
    /// Controls, chips, search fields.
    static let fill = Color(red: 0.949, green: 0.953, blue: 0.961)
    /// Emphasis blocks (summary, setting cards).
    static let raised = Color(red: 0.961, green: 0.965, blue: 0.973)
    /// Current row while something is live.
    static let accentWash = Color(red: 1.0, green: 0.98, blue: 0.973)
    static let ok = Color(red: 0.122, green: 0.478, blue: 0.271)
    static let okPale = Color(red: 0.906, green: 0.961, blue: 0.925)
    static let error = Color(red: 0.706, green: 0.137, blue: 0.094)
    static let errorPale = Color(red: 0.992, green: 0.925, blue: 0.918)
    /// Headings over placeholder shapes while notes are being written.
    static let placeholder = Color(red: 0.722, green: 0.741, blue: 0.776)
}

/// A service in trouble, said the same way wherever it shows: a dot, what waits for what · what
/// still works, and at most one action. Colour sits in the dot only, so a passing wait doesn't
/// read as a fault: yellow waits and comes back by itself, red needs you, grey is just so you know.
struct StatusLine: View {
    enum Tone { case waiting, needsYou, info }
    let tone: Tone
    let text: String
    var action: (title: String, run: () -> Void)? = nil

    /// #C98A00: the warn ink is too dark to tell from the text at 6 pt.
    static let waitingDot = Color(red: 0.788, green: 0.541, blue: 0.0)

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tone == .waiting ? Self.waitingDot : tone == .needsYou ? Palette.error : Palette.tertiary)
                .frame(width: 6, height: 6)
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action.run) {
                    Text(action.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain).fixedSize()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.fill))
    }
}

struct LogoTile: View {
    var size: CGFloat = 34
    var body: some View { BrandMark(size: size) }
}

typealias ChoiceOption = (id: String, title: String)

/// A gray rounded row that opens a menu, used for the language choices.
struct ChoiceRow: View {
    let label: String
    let value: String
    var badge: String? = nil
    /// 40pt instead of 44, for the menu bar panel where four rows sit one above the other.
    var compact = false
    /// Groups the menu separates; a header is its grey section title.
    let sections: [(header: String?, options: [ChoiceOption])]
    let onPick: (String) -> Void

    init(label: String, value: String, badge: String? = nil, compact: Bool = false,
         sections: [(header: String?, options: [ChoiceOption])], onPick: @escaping (String) -> Void) {
        self.label = label; self.value = value; self.badge = badge; self.compact = compact
        self.sections = sections.filter { !$0.options.isEmpty }
        self.onPick = onPick
    }

    init(label: String, value: String, badge: String? = nil, compact: Bool = false,
         options: [ChoiceOption], onPick: @escaping (String) -> Void) {
        self.init(label: label, value: value, badge: badge, compact: compact, sections: [(nil, options)], onPick: onPick)
    }

    var body: some View {
        Menu {
            // Sections, not Dividers: the menu draws the separators itself, and a Divider next to
            // a headed Section would draw a second one.
            ForEach(sections.indices, id: \.self) { i in
                if let header = sections[i].header {
                    Section(header) { buttons(sections[i].options) }
                } else {
                    Section { buttons(sections[i].options) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(width: uiIsChinese ? 44 : 72, alignment: .leading)
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.accentPale))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: compact ? 40 : 44)
            .background(RoundedRectangle(cornerRadius: 11).fill(Palette.ground))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func buttons(_ options: [ChoiceOption]) -> some View {
        ForEach(options, id: \.id) { o in
            Button(o.title) { onPick(o.id) }
        }
    }
}

// MARK: - Menu bar panel

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    /// Languages without a speech model on this Mac sit in their own group under one line saying
    /// picking one downloads it, rather than a suffix on every row.
    private var sourceSections: [(header: String?, options: [ChoiceOption])] {
        let auto = model.candidates.map(\.name).joined(separator: "、")
        let ready = sourceLanguages.filter { model.installed.isEmpty || model.installed.contains($0.locale) }
        let missing = sourceLanguages.filter { !ready.contains($0) }
        return [
            (nil, [("auto", auto.isEmpty ? L("自动识别") : L("自动识别（\(auto)）"))]),
            (nil, ready.map { ($0.locale, $0.name) }),
            // macOS 14/15 can't download one: the language is added to Dictation in System Settings.
            (Recognition.legacy ? L("要先加进系统的听写语言") : L("选中后自动下载语音模型"), missing.map { ($0.locale, $0.name) }),
        ]
    }

    private var targetOptions: [(id: String, title: String)] {
        [("system", L("跟随系统（\(settings.systemTargetDescription())）"))] + targetLanguages.map { ($0.code, $0.name) }
    }

    private var heardValue: (String, String?) {
        switch settings.sourceMode {
        case .fixed(let l): return (l.name, nil)
        case .auto: return (model.listen.activeLang?.name ?? L("自动"), L("自动识别"))
        }
    }

    /// The panel's natural height, measured; past what the screen can show it scrolls.
    @State private var contentHeight: CGFloat = 0

    /// A popover taller than the screen is cut off at the top (a small screen, the menu bar on it).
    private var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 900) - 24 }

    var body: some View {
        let measured = panel.background(GeometryReader { g in
            Color.clear.preference(key: PanelHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { contentHeight = $0 }
        if contentHeight > maxHeight {
            ScrollView { measured }.frame(width: 320, height: maxHeight).background(Color.white)
        } else {
            measured
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoTile(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(appDisplayName).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
                        if let dev = DevBuild.label {
                            Text("DEV").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Palette.ink))
                                .help(dev)
                        }
                    }
                    if let dev = DevBuild.label {
                        Text(dev).font(.system(size: 10).monospaced()).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(model.running ? Palette.accent : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        // Two lines: "English (detecting…) → 简体中文" doesn't fit one beside the switch.
                        Text(model.running ? model.summary : model.autoEnded ? L("会议已自动结束") : L("已暂停"))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PanelImportLine(importer: model.importer, store: model.store)
                }
                Spacer()
                Toggle("字幕", isOn: Binding(get: { model.running }, set: { model.setRunning($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.ink)
            }

            if let p = model.ending { MeetingEndingStrip(model: model, pending: p, compact: true) }
            // In subtitle-bar mode this is where the bar sends you to pick.
            if model.running { LanguageNotice(model: model) }
            if model.hybridMicDenied { hybridMicStrip }
            if let next = model.roomMicLost { roomMicLostStrip(next) }
            AIServiceStrip(model: model, ling: model.ling)
            // Right under the header: below the settings it was easy to miss.
            UpdateBanner(updates: model.updates, model: model)

            VStack(spacing: 6) {
                ChoiceRow(label: L("听到"), value: heardValue.0, badge: heardValue.1, compact: true, sections: sourceSections) {
                    model.sourceSelection = $0
                }
                ChoiceRow(label: L("翻译成"),
                          value: targetName(model.listen.resolvedTarget),
                          // "Follow system" leaves no room for the language name in the panel.
                          badge: settings.target == "system" ? (uiIsChinese ? L("跟随系统") : L("系统")) : nil,
                          compact: true, options: targetOptions) {
                    model.targetSelection = $0
                }
            }

            micRow

            Divider()

            speakSection
            if let strip = systemMicStrip {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strip.title).font(.system(size: 12)).foregroundStyle(Palette.accentInk)
                        Text(strip.detail).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    SoftButton(strip.button, dark: true, action: strip.action)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.accentPale))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("显示方式").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    HStack(spacing: 5) {
                        KeyCap(settings.toggleKey.display)
                        Text("轮换").foregroundStyle(Palette.tertiary)
                    }
                    .font(.system(size: 11))
                    .help(L("切换显示方式"))
                }
                HStack(spacing: 8) {
                    ForEach(DisplayTile.modes, id: \.self) { mode in
                        DisplayTile(mode: mode, selected: settings.displayMode == mode, caption: tileCaption(mode)) {
                            pickDisplay(mode)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if settings.displayMode != "notes" || !model.ling.hasKey { displayCard }
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.white)
    }

    /// The panel's actions as three equal buttons, so they read as buttons rather than loose
    /// grey words. No version line: an update shows its own strip above, and 设置 › 会议记录 checks.
    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                PanelAction(L("会议记录"), symbol: "doc.text") { model.openMainWindow?() }
                PanelAction(L("导入文件…"), symbol: "square.and.arrow.down") { model.chooseImportFiles() }
                PanelAction(L("退出"), symbol: "power", quiet: true) { NSApp.terminate(nil) }
            }
        }
    }

    /// The picked 实时纪要 tile is also the notes window's open/close switch, so the panel
    /// needs no separate row for it.
    private func pickDisplay(_ mode: String) {
        if mode == "notes", settings.displayMode == "notes" {
            model.notesShown ? model.hideNotesWindow() : model.openNotesWindow()
        } else {
            model.setDisplayMode(mode)
        }
    }

    private func tileCaption(_ mode: String) -> String? {
        guard mode == "notes", settings.displayMode == "notes" else { return nil }
        return model.notesShown ? L("再点收起") : L("再点打开")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension MenuPanelView {
    /// 电脑和会议室 without the microphone: the Mac's side is still recorded.
    var hybridMicStrip: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("听会议室要先允许麦克风").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("电脑声音照常在记").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            SoftButton(L("去设置"), dark: true) { model.openMicrophoneSettings() }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.accentPale))
    }
}

extension MenuPanelView {
    /// 外接麦克风断开了: what Cicada did instead. Goes away by itself.
    func roomMicLostStrip(_ next: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("外接麦克风断开了").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(next).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.accentPale))
    }
}

/// Under the panel's status: the file being transcribed in the background, if any.
struct PanelImportLine: View {
    @ObservedObject var importer: FileImporter
    @ObservedObject var store: SessionStore

    var body: some View {
        if let job = importer.current {
            let name = store.session(job.id)?.displayTitle ?? job.url.lastPathComponent
            HStack(spacing: 6) {
                ProgressView(value: importer.progress).progressViewStyle(.circular).controlSize(.mini).tint(Palette.ink)
                    .frame(width: 10, height: 10)
                Text(importer.queue.isEmpty ? L("后台转写 \(name) · \(Int(importer.progress * 100))%")
                     : L("后台转写 \(name) · \(Int(importer.progress * 100))%，还有 \(importer.queue.count) 个"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

extension MenuPanelView {
    /// The settings of the chosen display mode only, so switching modes swaps one card
    /// instead of reshuffling the section.
    @ViewBuilder var displayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch settings.displayMode {
            case "bar":
                cardRow(L("什么时候出现")) {
                    overlayAutoSegments(model: model, fill: uiIsChinese, track: Palette.line).frame(width: uiIsChinese ? segmentWidth : nil)
                }
                if settings.overlayAuto {
                    cardRow(L("安静多久后收起")) {
                        hideAfterSegments(settings: settings, fill: uiIsChinese, track: Palette.line).frame(width: uiIsChinese ? segmentWidth : nil)
                    }
                }
            case "none":
                Text("屏幕上不出字幕，文字记录照常保存")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                // Shown only without a Ling key: the notes window itself opens and closes from the tile.
                Text(Recognition.cloudOnly ? L("填入 Ling key 后才能识别语音、出字幕和纪要") : L("填入 API key 后可生成纪要；文字记录照常保存"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.ground))
    }

    /// Both 字幕条 choices share one width so their right edges line up; English sizes to fit and may stack.
    private var segmentWidth: CGFloat { 160 }

    /// A label and its control on one line, or stacked when the English runs too wide.
    private func cardRow<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
        let label = Text(title).font(.system(size: 12)).foregroundStyle(Palette.ink)
        let c = control()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { label; Spacer(minLength: 8); c }
            VStack(alignment: .leading, spacing: 6) { label; c }
        }
    }

    var systemMicStrip: (title: String, detail: String, button: String, action: () -> Void)? {
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        switch model.systemMicState {
        case .notRestored:
            return (L("系统麦克风还是 \(virtual)"), L("别的软件现在听不到你说话"), L("还原"), model.restoreSystemMic)
        case .moved(let to):
            return (L("系统麦克风被换成了 \(to)"), L("跟随系统的网页听不到译文"), L("换回"), model.switchSystemMic)
        default:
            return nil
        }
    }
}

// MARK: - 麦克风 in the panel

extension MenuPanelView {
    /// 打开麦克风: the people in the room join the meeting the Mac is hearing.
    var micRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("麦克风").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(model.micOn ? L("桌边的人说话也会记下") : L("关着 · 只听电脑声音"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            MicButton(model: model, settings: settings, inHeader: false)
        }
    }
}

/// 打开麦克风 / 关闭麦克风, the same switch in the panel and the notes window. In the panel it is
/// the dark button while off (the thing to do) and a quiet one while on; in the notes window's
/// header it sits beside 结束 like it, tinted while the microphone is on. Its chevron picks the
/// microphone, where the user is when the room sounds wrong rather than in Settings.
struct MicButton: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let inHeader: Bool

    var body: some View {
        let on = model.micOn
        HStack(spacing: 0) {
            Button { model.setMic(!on) } label: {
                HStack(spacing: 5) {
                    Image(systemName: on ? "mic.fill" : "mic")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? Palette.accent : (inHeader ? Palette.ink : Color.white))
                    Text(on ? L("关闭麦克风") : L("打开麦克风")).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink(on))
                        .lineLimit(1).fixedSize()
                }
                .padding(.leading, inHeader ? 10 : 12).padding(.trailing, 7).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? L("关闭麦克风") : L("打开麦克风"))
            Rectangle().fill(divider(on)).frame(width: 1, height: 14)
            chooser(on)
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(background(on)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(border(on), lineWidth: 1))
    }

    /// The room's microphones, with 自动 first naming the one it would take. A chosen one that is
    /// unplugged shows as 自动 until it is back.
    private func chooser(_ on: Bool) -> some View {
        let choices = AudioDevices.roomMicChoices()
        let chosen = choices.contains { $0.device.uid == settings.roomMicUID } ? settings.roomMicUID : ""
        let auto = AudioDevices.roomMic()?.name
        return Menu {
            Picker(L("会议室用哪个麦克风"), selection: Binding(get: { chosen }, set: { model.setRoomMic($0) })) {
                Text(auto.map { L("自动（\($0)）") } ?? L("自动")).tag("")
                ForEach(choices, id: \.device.uid) { c in
                    // A headset hears its wearer, not the table: fine for your own notes, so say it.
                    Text(c.bluetooth ? L("\(c.device.name)（只听得到戴的人）") : c.device.name).tag(c.device.uid)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink(on).opacity(0.75))
                .frame(width: 24, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(L("选择麦克风"))
        .help(L("选择麦克风"))
    }

    private func ink(_ on: Bool) -> Color { !on && !inHeader ? Color.white : Palette.ink }

    private func divider(_ on: Bool) -> Color {
        if inHeader { return on ? Palette.accent.opacity(0.25) : Palette.line }
        return on ? Palette.line : Color.white.opacity(0.25)
    }

    private func background(_ on: Bool) -> Color {
        if inHeader { return on ? Palette.accentPale : .clear }
        return on ? Color.white : Palette.ink
    }

    private func border(_ on: Bool) -> Color {
        if inHeader { return on ? Palette.accentPale : Palette.line }
        return on ? Palette.line : Palette.ink
    }
}

// MARK: - 同声传译 in the panel

extension MenuPanelView {
    private var speakFrom: String { settings.speakFromLang.name }
    private var speakTarget: String { targetName(model.speak.targetCode) }
    private var talkKeyName: String { settings.talkKey.display }

    /// What the switch changes, on hover and in the one-time question.
    private var speakMicLine: String {
        if settings.listensToRoom { return L("译文从扬声器念出来") }
        guard let mic = model.virtualMic?.name else { return L("先装好虚拟麦克风，对方才听得到") }
        return settings.autoSystemMic ? L("系统麦克风换成 \(mic)") : L("译文送进 \(mic)")
    }

    private var speakHelp: String {
        L("打开：\(speakMicLine)，按住 \(talkKeyName) 说话\n关掉：全部还原")
    }

    /// 同声传译: the first time the switch asks in place what it changes; once on, the talk key is
    /// the section, and whatever stops the room hearing you shows on it.
    var speakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同声传译").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    if !settings.speakEnabled && !model.speakAsking {
                        Text("说\(speakFrom) → \(speakTarget)").font(.system(size: 12))
                            .foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if settings.speakEnabled {
                    Button("设置") { model.openSettings(.speak) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                Toggle("同声传译", isOn: Binding(get: { settings.speakEnabled || model.speakAsking }, set: setSpeaking))
                    .toggleStyle(.switch).labelsHidden()
                    .tint(model.speakAsking ? Palette.tertiary : Palette.ink)
                    .help(speakHelp)
            }
            if model.speakAsking {
                speakQuestion
            } else if settings.speakEnabled {
                talkCard
                if model.lastSpeakLatency == nil, model.virtualMic != nil, !settings.listensToRoom, model.speakPhase == .idle {
                    Button("先试一句 →") { model.openSettings(.speak); model.speakTestShown = true }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func setSpeaking(_ on: Bool) {
        if on && !settings.speakConfirmed { model.speakAsking = true; return }
        model.speakAsking = false
        if on != settings.speakEnabled { model.enableSpeaking(on) }
    }

    /// Asked once: switching the system mic is a change people should hear about before it happens.
    private var speakQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("打开后：").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            questionLine(1) { Text(speakMicLine) }
            questionLine(2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { Text("按住"); KeyCap(talkKeyName); Text("说话，松开后播出译文") }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) { Text("按住"); KeyCap(talkKeyName) }
                        Text("说话，松开后播出译文")
                    }
                }
            }
            questionLine(3) { Text("关掉后全部还原") }
            HStack(spacing: 8) {
                Spacer()
                SoftButton(L("取消"), onGrey: true) { model.speakAsking = false }
                SoftButton(L("好，打开"), dark: true) { model.speakAsking = false; model.enableSpeaking(true) }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.ground))
    }

    private func questionLine<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").foregroundStyle(Palette.tertiary).frame(width: 12, alignment: .leading)
            content().foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
    }

    /// The first thing keeping the room from hearing you, with the one action that fixes it.
    private var talkProblem: (text: String, button: String, action: () -> Void)? {
        if model.talkNeedsPermission {
            return (L("按键还需要“输入监控”权限"), L("去允许"), model.allowTalkKey)
        }
        // In 会议室 the translation is read out loud: no virtual mic, no meeting app to set up.
        if settings.listensToRoom { return nil }
        if model.virtualMic == nil {
            return (L("虚拟麦克风还没装好"), L("设置"), { model.openSettings(.speak) })
        }
        if let user = model.micUsers.first(where: { $0.state.isOther }) {
            let text: String
            if case .otherMic(let mic) = user.state, !mic.isEmpty { text = L("\(user.name)还在用 \(mic)") }
            else { text = L("\(user.name)没选虚拟麦克风") }
            return (text, L("怎么改"), { model.showMicGuide(user) })
        }
        return nil
    }

    private var talkCard: some View {
        let phase = model.speakPhase
        let live = phase != .idle
        let problem = live ? nil : talkProblem
        let title: String = switch phase {
        case .idle: L("按住说\(speakFrom)")
        case .listening: L("正在听…")
        case .translating: L("正在翻译…")
        case .speaking: L("正在播出…")
        }
        let hearer = model.micUsers.first { $0.state == .virtualMic }?.name
        let detail = phase == .listening ? L("松开后播出\(speakTarget)")
            : live ? L("说\(speakFrom) → \(speakTarget)")
            : settings.listensToRoom ? L("扬声器念出\(speakTarget)")
            : hearer.map { L("对方听到 \(speakTarget) · \($0)") } ?? L("对方听到 \(speakTarget)")
        return HStack(spacing: 12) {
            TalkKeyCap(text: talkKeyName, pressed: phase == .listening, live: live)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(live ? Palette.accentInk : Palette.ink).lineLimit(1)
                if let problem {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(problem.text).foregroundStyle(Palette.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(problem.button, action: problem.action)
                            .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(Palette.accentInk).fixedSize()
                    }
                    .font(.system(size: 11))
                } else {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if !live {
                Circle().fill(problem == nil ? Palette.ok : Palette.accent).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(live ? Palette.accentWash : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(live ? Palette.accent : Palette.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: live)
    }
}

/// The talk key drawn as a key: raised while it waits, pressed down while you hold it.
struct TalkKeyCap: View {
    let text: String
    let pressed: Bool
    let live: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(live ? Palette.accentInk : Palette.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(live ? Palette.accent : Color(white: 0.82), lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 7).fill(live ? Palette.accent : Color(white: 0.82)).offset(y: pressed ? 0 : 2))
            .offset(y: pressed ? 2 : 0)
            .padding(.bottom, 2)
    }
}

/// One of 实时纪要 / 字幕条 / 不显示 in the menu bar panel: a small picture of what shows on screen.
struct DisplayTile: View {
    static let modes = ["notes", "bar", "none"]
    let mode: String
    let selected: Bool
    /// Under the picked tile's name: what clicking it again does.
    var caption: String? = nil
    let action: () -> Void

    private var title: String {
        switch mode {
        case "bar": return L("字幕条")
        case "none": return L("不显示")
        default: return L("实时纪要")
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                glyph.frame(height: 26).opacity(selected ? 1 : 0.7)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.top, -4)
                }
            }
            .padding(.top, 10).padding(.bottom, 8).padding(.horizontal, 4)
            // The row grows by the caption; every tile takes the row's height.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? Color.white : Palette.ground))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Palette.ink : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private let frameLine = Color(red: 0.79, green: 0.80, blue: 0.83)

    @ViewBuilder private var glyph: some View {
        switch mode {
        case "bar":
            RoundedRectangle(cornerRadius: 4).fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(frameLine, lineWidth: 1))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.ink).frame(width: 26, height: 6).padding(.bottom, 3)
                }
                .frame(width: 38, height: 26)
        case "none":
            RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.tertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 38, height: 26)
        default:
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Palette.ink).frame(width: 18, height: 3)
                Capsule().fill(frameLine).frame(width: 24, height: 3)
                Capsule().fill(frameLine).frame(width: 20, height: 3)
            }
            .padding(5)
            .frame(width: 34, height: 26, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(frameLine, lineWidth: 1))
        }
    }
}

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 0.82), lineWidth: 1))
    }
}

/// One of the panel's footer buttons: an icon over its name on a grey tile.
struct PanelAction: View {
    let title: String
    let symbol: String
    /// 退出: grey ink, it ends the app rather than opening something.
    var quiet = false
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, symbol: String, quiet: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.quiet = quiet; self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(quiet ? Palette.secondary : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Palette.line : Palette.ground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Main window

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var importer: FileImporter
    @StateObject private var player = RecordingPlayer()
    @State private var dropping = false
    @State private var selection: String?
    @State private var query = ""
    @State private var view = "both"
    @State private var tab = "notes"
    @State private var jumpTo: Double?
    /// A topic's time picked in the notes, for the bilingual column beside them.
    @State private var quoteJump: Double?
    @State private var detailWidth: CGFloat = 0
    /// The title block has scrolled away: a slim bar with the title and tabs stays on top.
    @State private var pinned = false
    @FocusState private var searchFocused: Bool
    /// The bilingual column beside the notes is opt-in: three full columns of text read as crowded.
    @AppStorage("mainShowQuotes") private var showQuotes = false
    @State private var showOlder = false
    /// 分享…: the meeting whose share sheet is open.
    @State private var sharing: Session?
    /// 改这句…: the line being rewritten, and what the editor opens with.
    @State private var editingLine: String?
    @State private var editingStart = ""
    @State private var hoveredLine: String?
    @State private var wordClick = WordClick()

    /// Wide enough for the notes and the bilingual transcript side by side.
    private var sideBySide: Bool { showQuotes && wideEnough }
    private var wideEnough: Bool { detailWidth >= 940 }

    private var filtered: [Session] {
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { s in
            s.displayTitle.localizedCaseInsensitiveContains(query)
                || s.lines.contains { $0.shown.localizedCaseInsensitiveContains(query) || ($0.dst ?? "").localizedCaseInsensitiveContains(query) }
        }
    }

    private var current: Session? { store.session(selection ?? store.sessions.first?.id) }

    /// The shown record's audio: an imported file, or the meeting's own recording once it has ended.
    private func loadPlayer() {
        guard let s = current, s.id != store.liveID else { player.load(nil); return }
        player.load(s, recording: s.hasAudio ? store.systemAudioURL(s.id) : nil)
    }

    var body: some View {
        // One white sheet; the list sits on a faint tint instead of behind a rule. The listening
        // pill lives in the window's toolbar (`MainToolbar`). With no meetings yet, only the
        // welcome shows: an empty list is noise.
        HStack(spacing: 0) {
            if !store.sessions.isEmpty {
                sidebar
                    .frame(width: 232)
                    .background(UnevenRoundedRectangle(topTrailingRadius: 14).fill(Self.listTint).ignoresSafeArea(edges: .bottom))
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
                .overlay(alignment: .bottom) { SpeakerUndoToast(model: model, session: selection) }
        }
        .background(Color.white.ignoresSafeArea())
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0))
        // Recordings and videos dropped anywhere on the window become records.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(FileImporter.importable)
            guard !files.isEmpty else { return false }
            model.importFiles(files)
            return true
        } isTargeted: { dropping = $0 }
        .overlay { if dropping { ImportDropOverlay() } }
        .onChange(of: current?.id, initial: true) { _, _ in loadPlayer() }
        // A meeting that ends while it is shown, and its recording once it is rewrapped into an .m4a.
        .onChange(of: store.liveID) { _, _ in loadPlayer() }
        // Opened afresh: a file opened before the room was mixed in (#19) would play one side only.
        .onChange(of: store.audioFinished) { _, id in if id == current?.id { player.unload(); loadPlayer() } }
        // A click on a line's words: its selectable text takes the mouse before the row's tap.
        .onAppear {
            wordClick.install(line: { hoveredLine.flatMap { id in editingLine == id ? nil : id } }) { id in
                guard let s = current, player.sessionID == s.id, player.ready,
                      let l = s.lines.first(where: { $0.id == id }) else { return }
                player.play(from: l.t)
            }
        }
        .onDisappear { wordClick.remove() }
        .onReceive(NotificationCenter.default.publisher(for: .debugPlay)) { n in
            if let t = n.object as? Double { player.play(from: t) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugShareSheet)) { n in
            sharing = (n.object as? String).flatMap { store.session($0) }
        }
        .onChange(of: model.mainShow) { _, show in
            guard let parts = show?.split(separator: ",").map(String.init), let id = parts.first else { return }
            selection = id
            tab = parts.count > 1 ? parts[1] : "notes"
            if parts.count > 2 { view = parts[2] }
        }
    }

    static let hairline = Color(red: 0.941, green: 0.945, blue: 0.957)
    static let listTint = Color(red: 0.98, green: 0.98, blue: 0.984)

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("搜索", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if query.isEmpty {
                    Text("⌘F").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("清除")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).frame(height: 30)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // The newest day shows; older ones fold under one row until asked for (or searched).
                    let all = RecordList.groups(filtered)
                    let folded = query.isEmpty && !showOlder && all.count > 1
                    ForEach(Array((folded ? Array(all.prefix(1)) : all).enumerated()), id: \.element.title) { i, g in
                        Text(g.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 12).padding(.top, i == 0 ? 0 : 18).padding(.bottom, 6)
                        ForEach(g.sessions) { sessionRow($0) }
                    }
                    if query.isEmpty && all.count > 1 {
                        Button { withAnimation(.easeOut(duration: 0.2)) { showOlder.toggle() } } label: {
                            HStack {
                                Text(showOlder ? L("收起更早的会议") : L("更早的会议"))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                    .rotationEffect(.degrees(showOlder ? -90 : 0))
                            }
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                    if filtered.isEmpty {
                        Text("没有找到“\(query)”").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 10)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 14)
        .onChange(of: selection) { _, id in
            // A meeting picked from elsewhere (search, the notes window) shouldn't hide in a fold.
            if let id, let first = RecordList.groups(filtered).first, !first.sessions.contains(where: { $0.id == id }) { showOlder = true }
        }
    }

    private func sessionRow(_ s: Session) -> some View {
        let selected = s.id == (selection ?? store.sessions.first?.id)
        let live = s.id == store.liveID
        return Button {
            selection = s.id
        } label: {
            // Titles only: the time and length are on the page (and in the tooltip). Unpicked rows
            // stay grey so the one being read stands out.
            HStack(spacing: 8) {
                if live { BreathingDot(size: 6) }
                if s.sourceFile != nil {
                    Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else if s.fromRecording, s.lines.isEmpty {
                    Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .help(L("只有录音"))
                } else if RecordList.heardBoth(s.lines) {
                    HStack(spacing: 2) {
                        Image(systemName: "mic")
                        Image(systemName: "display")
                    }
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .help(L("电脑和会议室"))
                } else if s.room == true {
                    Image(systemName: "mic").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .help(L("会议室"))
                }
                Text(RecordList.untitled(s) ? L("未命名会议") : RecordList.listTitle(s))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected || live ? Palette.ink : Palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let status = importer.status(of: s) { Tag(rowTag(status), live: status == .running) }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white : Color.clear)
                .shadow(color: selected ? Palette.ink.opacity(0.06) : .clear, radius: 1.5, y: 1))
            .contentShape(Rectangle())
        }
        .help(live ? L("正在记录") : [RecordList.when(s), RecordList.length(s)].joined(separator: " · "))
        .buttonStyle(.plain)
        .contextMenu {
            if let path = s.sourcePath, FileManager.default.fileExists(atPath: path) {
                Button("显示原文件") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
            if s.hasAudio, !live, !working(s) {
                Menu("重新转写") {
                    ForEach(sourceLanguages, id: \.locale) { lang in
                        Button(lang.name) { importer.retry(s.id, lang: lang) }
                    }
                }
            }
            if s.renamed ?? !s.title.hasPrefix("会议 "), s.notes?.title != nil {
                Button("恢复自动标题") { store.rename(s.id, to: "") }
            }
            Button("删除", role: .destructive) { model.deleteSession(s.id) }.disabled(live)
        }
    }

    /// Being transcribed or waiting to be.
    private func working(_ s: Session) -> Bool {
        switch importer.status(of: s) {
        case .running, .queued: return true
        default: return false
        }
    }

    /// The list row's word for an imported file still being worked on.
    private func rowTag(_ status: FileImporter.Status) -> String {
        switch status {
        case .queued: return L("排队中")
        case .unfinished: return L("没转完")
        case .running:
            switch importer.phase {
            case .transcribing: return L("转写中 \(Int(importer.progress * 100))%")
            case .translating: return L("翻译中")
            default: return L("准备中")
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let s = current {
            VStack(spacing: 0) {
                if s.lines.isEmpty {
                    ScrollView {
                        header(s).frame(maxWidth: 680).padding(.horizontal, 44).padding(.vertical, 36)
                            .frame(maxWidth: .infinity)
                    }
                        .overlay {
                            Text(s.id == store.liveID ? L("正在听，说话的内容会出现在这里")
                                 : working(s) ? L("转出的文字会陆续出现在这里")
                                 : s.fromRecording ? L("还没有文字记录") : L("这场会议没有记录到内容"))
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                } else if tab == "notes", importer.status(of: s) == nil {
                    HStack(spacing: 0) {
                        SessionNotesView(model: model, engine: model.notes, ling: model.ling, session: s,
                                         header: AnyView(header(s)), bar: { toTop in AnyView(pinnedBar(s, column: 600, inset: 44, toTop: toTop)) }) { t in
                            // Beside the notes, a topic's time scrolls the column; otherwise it opens the transcript.
                            if sideBySide { quoteJump = t } else { jumpTo = t; tab = "transcript" }
                        }
                        if sideBySide {
                            quotes(s).frame(width: 300).padding(.trailing, 24)
                        }
                    }
                } else {
                    transcript(s)
                }
                if s.id == store.liveID { liveNow }
                // Under the page, not in its header: the controls stay while the transcript scrolls.
                if player.sessionID == s.id, s.id != store.liveID, player.ready || player.missing {
                    RecordingPlayerBar(player: player)
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 40).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .overlay(alignment: .top) { Rectangle().fill(Self.hairline).frame(height: 1) }
                }
            }
            .onChange(of: s.id) { _, _ in pinned = false }
            .onChange(of: tab) { _, _ in pinned = false }
        } else {
            welcome
        }
    }

    /// No meetings yet: the logo, one line and the one thing to do.
    private var welcome: some View {
        VStack(spacing: 0) {
            BrandMark(size: 72).shadow(color: Palette.accent.opacity(0.22), radius: 14, y: 8)
            Text("还没有会议").font(.system(size: 26, weight: .bold)).padding(.top, 28)
            Text("打开会议或视频，开始听后，每一场都会存在这里。")
                .font(.system(size: 15)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .padding(.top, 10)
            Button { model.setRunning(true) } label: {
                HStack(spacing: 10) {
                    Circle().fill(Palette.accent).frame(width: 9, height: 9)
                    Text("开始听").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 22).frame(height: 44)
                .background(Capsule().fill(Palette.ink))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).padding(.top, 32)
            Button("先听一段示例") { model.ensureListening(); model.sample.play() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 16)
            Button("或导入录音、视频…") { model.chooseImportFiles() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.ink).padding(.top, 8)
        }
        .frame(maxWidth: 420)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 此刻: the sentence being heard, pinned under the page while the meeting is live.
    @ViewBuilder private var liveNow: some View {
        let src = model.liveSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty || !model.languageAsk.isEmpty || model.modelFetch != nil || model.cloud.listening || model.cloud.back != nil {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 6) {
                    BreathingDot(size: 6)
                    Text("此刻").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accentInk)
                }
                .frame(width: 52, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(src).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        .lineLimit(2).truncationMode(.head)
                    // 听不出 replaces the stuck 正在识别语言…; it says what to do instead.
                    if !model.liveTranslation.isEmpty, model.languageAsk.isEmpty {
                        Text(model.liveTranslation).font(.system(size: 15)).foregroundStyle(Palette.ink)
                            .lineLimit(2).truncationMode(.head)
                    }
                    LanguageNotice(model: model).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentWash)
            .overlay(alignment: .top) { Rectangle().fill(Palette.accentPale).frame(height: 1) }
        }
    }

    /// Text tabs, the transcript's language choice and 导出…, under the title: no toolbar band.
    private func tabsRow(_ s: Session) -> some View {
        HStack(alignment: .center, spacing: 22) {
            tabs(s)
            Spacer()
            tools(s)
        }
    }

    /// Notes wait until an imported file is transcribed to the end.
    private func activeTab(_ s: Session) -> String { importer.status(of: s) != nil ? "transcript" : tab }

    private func tabs(_ s: Session) -> some View {
        let importing = importer.status(of: s) != nil
        let active = activeTab(s)
        return HStack(alignment: .center, spacing: 22) {
            tabButton(L("纪要"), id: "notes", active: active, badge: importing ? L("转完后生成") : nil).disabled(importing)
            tabButton(L("文字记录"), id: "transcript", active: active, count: s.lines.count)
        }
    }

    /// The transcript's language choice (or 原话 beside the notes) and 导出….
    private func tools(_ s: Session) -> some View {
        let active = activeTab(s)
        return HStack(alignment: .center, spacing: 22) {
            if active == "transcript" {
                Segments(options: [("both", L("双语")), ("src", L("原文")), ("dst", L("译文"))], value: view) { view = $0 }
            } else if wideEnough, !s.lines.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.2)) { showQuotes.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sidebar.right").font(.system(size: 12))
                        Text("原话").font(.system(size: 13))
                    }
                    .foregroundStyle(showQuotes ? Palette.ink : Palette.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showQuotes ? L("收起原话") : L("在纪要旁显示原话"))
            }
            // Not while the meeting is still going, nor before an import has its text.
            Button { sharing = s } label: {
                Text("分享…").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .buttonStyle(.plain)
            .disabled((s.lines.isEmpty && (s.notes?.isEmpty ?? true)) || store.liveID == s.id || importer.status(of: s) != nil)
            .sheet(item: $sharing) { shared in ShareSheet(session: shared) { sharing = nil } }
            if s.hasAudio, store.liveID != s.id, importer.status(of: s) == nil {
                Menu {
                    ForEach(sourceLanguages, id: \.locale) { lang in
                        Button(lang.name) { importer.retry(s.id, lang: lang) }
                    }
                } label: {
                    Text("重新转写").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(L("用保存的录音重新识别，替换现在的文字记录和纪要；旧记录会先备份"))
            }
            Menu {
                Button("复制为 Markdown") { model.export(s, kind: "copy") }
                Divider()
                Button("导出 Markdown…") { model.export(s, kind: "md") }
                Button("导出 Word…") { model.export(s, kind: "word") }
                Button("导出字幕 SRT…") { model.export(s, kind: "srt") }
                Divider()
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
            } label: {
                Text("导出…").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(s.lines.isEmpty)
        }
    }

    private func tabButton(_ title: String, id: String, active: String, count: Int? = nil, badge: String? = nil) -> some View {
        let on = active == id
        return Button { tab = id } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Palette.ink : Palette.secondary)
                if let count { Text("\(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary) }
                if let badge { Tag(badge) }
            }
            .fixedSize()
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(on ? Palette.ink : .clear).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Once the title block scrolls away: the title (a click goes back to the top) and the tabs row,
    /// so switching tabs, the transcript's language or exporting never needs a scroll back up.
    private func pinnedBar(_ s: Session, column: CGFloat = 680, inset: CGFloat = 40, toTop: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Button(action: toTop) {
                HStack(spacing: 6) {
                    if s.id == store.liveID { BreathingDot(size: 6) }
                    Text(RecordList.untitled(s) ? L("未命名会议") : RecordList.listTitle(s))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(L("回到顶部"))
            // The title takes what the tabs and tools leave, so the bar keeps to the text column.
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Self.hairline).frame(width: 1, height: 14)
            tabs(s).padding(.top, 6)
            tools(s)
        }
        .frame(maxWidth: column)
        .padding(.horizontal, inset).frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Self.hairline).frame(height: 1) }
        .transition(.opacity)
    }

    /// One grey line of facts, the editable title, then the tabs: the top of the page, scrolling with it.
    private func header(_ s: Session) -> some View {
        let live = s.id == store.liveID
        let notes = live ? model.notes.notes : s.notes
        // When and how long up front; the languages and notes version wait in the tooltip.
        let more = [RecordList.pair(s, short: false),
                    notes.flatMap { $0.isEmpty ? nil : ($0.final ? L("完整版纪要") : L("速记版纪要")) }]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if live { Tag(L("正在记录"), live: true) }
                Text(([dateText(s.startedAt, "MMMdHHmm"), RecordList.length(s)] + (s.sourceFile.map { [$0, L("导入")] } ?? [])
                      + (RecordList.heardBoth(s.lines) ? [L("电脑和会议室")] : s.room == true ? [L("会议室")] : [])).joined(separator: " · "))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary).lineLimit(1)
                    .help(([dateLine(s, live: live)] + more.compactMap { $0 }).joined(separator: " · "))
            }
            RecordTitleField(session: s, store: store).id(s.id).padding(.top, 8)
            if !live { FolderExportLine(exporter: model.folderExport, model: model, session: s).padding(.top, 8) }
            if s.sourcePath != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if s.fromRecording, s.lines.isEmpty || s.importing == true, !working(s) {
                        RecordingLanguageStrip(importer: importer, session: s)
                    } else {
                        ImportStatusStrip(model: model, importer: importer, session: s)
                    }
                }
                .padding(.top, 16)
            } else if live {
                if settings.recordAudio {
                    Text("会议结束后可以回放录音").font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.top, 10)
                }
            } else if !s.hasAudio, !s.lines.isEmpty {
                HStack(spacing: 4) {
                    Text("这场会议没存录音 ·").foregroundStyle(Palette.tertiary)
                    Button(L("保存会议录音")) { model.openSettings(.records) }
                        .buttonStyle(.plain).foregroundStyle(Palette.link)
                }
                .font(.system(size: 12)).padding(.top, 10)
            }
            tabsRow(s).padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bilingual lines beside the notes, so the record's two languages show without switching tabs.
    private func quotes(_ s: Session) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("原话").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(L("全部 \(s.lines.count) 句")) { tab = "transcript" }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    .padding(.bottom, 8)
                    let speakers = settings.speakerVoices ? SpeakerLabels.numbers(s) : [:]
                    let starts = SpeakerLabels.runStarts(s.lines, speakers)
                    ForEach(s.lines) { l in
                        quoteRow(l, speaker: speakers[l.id], picked: quoteJump.map { t in l.id == pickedLine(s, t)?.id } ?? false,
                                 label: settings.speakerEveryLine || starts.contains(l.id), voices: !speakers.isEmpty).id(l.id)
                    }
                }
                .environment(\.speakerNames, SpeakerLabels.names(s))
                .padding(.vertical, 40)
            }
            .scrollIndicators(.never)
            .onChange(of: quoteJump) { _, t in
                guard let t, let l = pickedLine(s, t) else { return }
                withAnimation { proxy.scrollTo(l.id, anchor: .top) }
            }
            .onChange(of: s.lines.count) { _, _ in
                if s.id == store.liveID, quoteJump == nil, let last = s.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: s.id) { _, _ in quoteJump = nil }
        }
    }

    private func pickedLine(_ s: Session, _ t: Double) -> TranscriptLine? {
        s.lines.first(where: { $0.t >= t - 1 }) ?? s.lines.last
    }

    /// Whitespace between lines, no rules; the picked line gets a soft fill.
    private func quoteRow(_ l: TranscriptLine, speaker: Int?, picked: Bool, label: Bool = true, voices: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Only once voices are told apart (or for your own lines): one speaker needs no label;
            // and only where the speaker changes.
            if !label {
            } else if let speaker { SpeakerTag(number: speaker).padding(.bottom, 2) }
            else if voices, l.speaker != "me" { UnknownSpeakerTag().padding(.bottom, 2) }
            else if l.speaker == "me" { MeTag().padding(.bottom, 2) }
            Text(l.shown).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(1)
                .textSelection(.enabled)
            Text(l.dst ?? L("翻译中…")).font(.system(size: 14)).lineSpacing(2)
                .foregroundStyle(l.dst == nil ? Palette.secondary : Palette.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(picked ? Palette.fill : .clear))
        .padding(.horizontal, -8)
        .help(TranscriptExport.clock(l.t))
    }

    private func dateLine(_ s: Session, live: Bool) -> String {
        let start = dateText(s.startedAt, "MMMdEEEHHmm")
        guard !live, let end = s.endedAt else { return live ? L("\(start) 起") : start }
        return "\(start) – \(dateText(end, "HHmm"))"
    }

    private func transcript(_ s: Session) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The header outside the lazy stack, so it is never dropped and always reports where it is.
                VStack(alignment: .leading, spacing: 0) {
                header(s).padding(.bottom, 16)
                    .id(PinnedHeader.top)
                    .pinnedHeader($pinned)
                LazyVStack(alignment: .leading, spacing: 0) {
                    let speakers = settings.speakerVoices ? SpeakerLabels.numbers(s) : [:]
                    if !speakers.isEmpty || (settings.speakerVoices && SpeakerLabels.singleVoice(s.lines) != nil) { SpeakerStrip(model: model, session: s).padding(.bottom, 8) }
                    let both = RecordList.heardBoth(s.lines)
                    // In a meeting that heard the room and the Mac, a change of place starts a new run too.
                    let starts = SpeakerLabels.runStarts(s.lines, speakers).union(both ? RecordList.placeStarts(s.lines) : [])
                    let voices = SpeakerLabels.voiceNumbers(s)
                    let playingLine = player.lineID(in: s)
                    if s.id != store.liveID {
                        FixReviewBanner(fixes: model.fixes, session: s, onShow: { id in withAnimation { proxy.scrollTo(id, anchor: .center) } },
                                        onEdit: { l, suggestion in editingStart = suggestion; editingLine = l.id; proxy.scrollTo(l.id, anchor: .center) })
                            .padding(.bottom, 10)
                    }
                    ForEach(s.lines) { l in
                        lineRow(l, speaker: speakers[l.id], label: speakers.isEmpty || settings.speakerEveryLine || starts.contains(l.id), voices: !speakers.isEmpty, place: both, in: s,
                                current: l.id == playingLine)
                            .contextMenu {
                                Button(L("改这句…")) { editingStart = l.shown; editingLine = l.id }
                                if !speakers.isEmpty, l.speaker == "them" { assignMenu(s, l, voices) }
                            }
                            .id(l.id)
                    }
                }
                }
                .environment(\.speakerNames, SpeakerLabels.names(s))
                .frame(maxWidth: 680)
                .padding(.horizontal, 40).padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: PinnedHeader.space)
            .overlay(alignment: .top) {
                if pinned { pinnedBar(s) { withAnimation { proxy.scrollTo(PinnedHeader.top, anchor: .top) } } }
            }
            .animation(.easeOut(duration: 0.15), value: pinned)
            .onUserScroll(ownSince: { player.ownScroll }) { if player.sessionID == s.id { player.userScrolled() } }
            .overlay(alignment: .bottom) { FixToast(fixes: model.fixes).padding(.bottom, 18) }
            .overlay(alignment: .bottom) {
                // Scrolled away from what is playing: one way back.
                if player.sessionID == s.id, !player.following, let id = player.lineID(in: s),
                   let l = s.lines.first(where: { $0.id == id }) {
                    Button { player.follow() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                            Text(L("回到正在播放") + " · " + TranscriptExport.clock(l.t))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white).padding(.horizontal, 16).frame(height: 34)
                        .background(Capsule().fill(Palette.ink))
                        .shadow(color: Palette.ink.opacity(0.18), radius: 10, y: 4)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).linkPointer()
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: player.following)
            .onChange(of: s.lines.count) { _, _ in
                if s.id == store.liveID, let last = s.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            // The transcript follows the recording while it plays, until scrolled by hand.
            .onChange(of: player.lineID(in: s)) { _, id in
                if player.playing, player.following, let id {
                    player.ownScroll = Date()
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onChange(of: player.following) { _, on in
                if on, let id = player.lineID(in: s) {
                    player.ownScroll = Date()
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onAppear {
                if let t = jumpTo, let l = s.lines.first(where: { $0.t >= t - 1 }) { proxy.scrollTo(l.id, anchor: .top) }
                jumpTo = nil
            }
        }
    }

    private func lineRow(_ l: TranscriptLine, speaker: Int? = nil, label: Bool = true, voices: Bool = false, place: Bool = false, in shownSession: Session? = nil, current: Bool = false) -> some View {
        let me = l.speaker == "me"
        let playable = shownSession.map { player.sessionID == $0.id && player.ready } ?? false
        let hovered = playable && hoveredLine == l.id && editingLine != l.id
        return HStack(alignment: .top, spacing: 16) {
            if playable {
                // The recording plays from this line (so does a click anywhere on it).
                Button { player.play(from: l.t) } label: {
                    HStack(spacing: 3) {
                        if hovered { Image(systemName: "play.fill").font(.system(size: 8)) }
                        Text(TranscriptExport.clock(l.t))
                            .font(.system(size: 12, weight: current || hovered ? .semibold : .regular).monospacedDigit())
                    }
                    .foregroundStyle(current || hovered ? Palette.accent : Palette.link)
                    .frame(width: 52, alignment: .leading).padding(.top, 1).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("从这里播放"))
            } else {
                Text(TranscriptExport.clock(l.t))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                    .frame(width: 52, alignment: .leading).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if !label {
                    } else if voices, !me, let s = shownSession {
                        // A click on whose line it is: say it was someone else's.
                        Menu { assignMenu(s, l, SpeakerLabels.voiceNumbers(s)) } label: {
                            if let speaker { SpeakerTag(number: speaker) } else { UnknownSpeakerTag() }
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                        .help(L("这句是谁说的"))
                    } else if let speaker { SpeakerTag(number: speaker) }
                    else if shownSession?.sourceFile == nil {
                        // An imported file has no "other side": its lines carry no label.
                        if me { MeTag() } else {
                            Text("对方").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                        }
                    }
                    if place, label, !me { PlaceTag(line: l) }
                }
                if editingLine == l.id, let s = shownSession {
                    LineEditor(line: l, session: s.id, fixes: model.fixes, start: editingStart) { editingLine = nil }
                } else if view != "dst" {
                    Text(TranscriptParagraphs.joinFixed([l]))
                        .font(.system(size: view == "src" ? 15 : 13))
                        .foregroundStyle(view == "src" ? Palette.ink : Palette.tertiary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                if view != "src" {
                    Text(l.dst ?? L("翻译中…"))
                        .font(.system(size: 15)).lineSpacing(3)
                        .foregroundStyle(l.dst == nil ? Palette.tertiary : Palette.ink)
                        .textSelection(.enabled)
                }
                // Pointing at a line: what its fixed words were heard as, 改回, and 改这句….
                if hoveredLine == l.id, editingLine != l.id, let s = shownSession {
                    HStack(spacing: 8) {
                        let fixed = (l.fixes ?? []).filter(\.applied).map { (l.id, $0) }
                        if !fixed.isEmpty { FixedWords(fixes: fixed) { id, f in model.fixes.revert(f, lineID: id, in: s.id) } }
                        Button(L("改这句…")) { editingStart = l.shown; editingLine = l.id }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.link)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            PlayingBars(on: current && player.playing).frame(width: 14).padding(.top, 4)
        }
        // The padding is part of the line, so there is no dead strip between two lines.
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { inside in if inside { hoveredLine = l.id } else if hoveredLine == l.id { hoveredLine = nil } }
        // A click anywhere on the line plays from it; a drag selects text instead (a tap ends without moving).
        .onTapGesture { if playable, editingLine != l.id { player.play(from: l.t) } }
        // The line the recording is playing; a lighter fill under the pointer when a click would play it.
        .background(RoundedRectangle(cornerRadius: 10).fill(current ? Palette.accentPale : hovered ? Palette.raised : .clear)
            .padding(.horizontal, -10))
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

extension MainWindowView {
    /// "这句是谁说的": the people on show; the line takes that voice.
    @ViewBuilder
    func assignMenu(_ s: Session, _ l: TranscriptLine, _ voices: [Int: Int]) -> some View {
        let names = SpeakerLabels.names(s)
        Section("这句是谁说的") {
            ForEach(voices.sorted { $0.value < $1.value }, id: \.key) { v, n in
                Button(SpeakerLabels.label(n, names) + (l.voice == v ? " ✓" : "")) {
                    model.assignLines(session: s.id, [l.id], to: v)
                }
            }
        }
    }
}

/// A meeting's notes in the main window: the same notes view as the live window, or a way to
/// make them for a meeting recorded without a key.
struct SessionNotesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: NotesEngine
    @ObservedObject var ling: LingClient
    let session: Session
    /// The page's title block, scrolling with the notes.
    var header: AnyView = AnyView(EmptyView())
    /// The slim bar shown on top once the header scrolls away, given a way back to the top.
    var bar: ((@escaping () -> Void) -> AnyView)? = nil
    let onJump: (Double) -> Void
    @State private var pinned = false

    private var live: Bool { session.id == model.store.liveID }
    private var notes: MeetingNotes? { live ? engine.notes : session.notes }
    private var generating: Bool { engine.generatingID == session.id }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header.id(PinnedHeader.top).pinnedHeader($pinned)
                if let notes, !notes.isEmpty {
                    NotesContentView(notes: SpeakerLabels.named(notes, SpeakerLabels.names(session)), fresh: live ? engine.fresh : [], live: live, document: true,
                                     endedAt: session.lines.last?.t, onJump: onJump)
                } else if generating || (live && ling.hasKey && !session.lines.isEmpty && engine.state == .updating) {
                    NotesGeneratingView(heard: session.lines.count)
                } else if live && ling.hasKey {
                    NotesListeningView(heard: session.lines.count)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(generating ? L("正在整理纪要…") : live ? L("纪要会在会议进行中自动生成") : L("这场会议还没有纪要"))
                            .font(.system(size: 15, weight: .bold))
                        Text(ling.hasKey ? L("用 \(ling.provider.name) 整理出总结、议题、结论和人名，约半分钟。")
                                         : L("前往 设置 › AI 服务 填入 Ling 的 API key 后即可生成。"))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        if !live {
                            HStack(spacing: 8) {
                                if ling.hasKey {
                                    SoftButton(generating ? L("正在生成…") : L("生成纪要"), dark: true) {
                                        engine.generate(for: session.id)
                                    }
                                    .disabled(generating)
                                } else {
                                    SoftButton(L("去填 key"), dark: true) { model.openSettings(.ai) }
                                }
                            }
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
                }
            }
            // A narrow measure and a tall top margin: the page reads as one quiet column.
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 44).padding(.top, 52).padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: PinnedHeader.space)
        .overlay(alignment: .top) {
            if pinned, let bar { bar { withAnimation { proxy.scrollTo(PinnedHeader.top, anchor: .top) } } }
        }
        .animation(.easeOut(duration: 0.15), value: pinned)
        .onChange(of: session.id) { _, _ in pinned = false }
        }
    }
}

/// A page's title block scrolling out of its scroll view, which names its coordinate space `space`.
enum PinnedHeader {
    static let space = "cicada.page"
    static let top = "cicada.page.top"
}

extension View {
    /// Sets `pinned` while this view's bottom is above the scroll view's top edge.
    func pinnedHeader(_ pinned: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { $0.frame(in: .named(PinnedHeader.space)).maxY < 0 } action: { pinned.wrappedValue = $0 }
    }
}

/// Under 此刻 while "auto" can't tell the language yet: the second speech model coming in, or,
/// when nothing more will settle it, 听不出 with the likely languages to pick from.
struct LanguageNotice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let service = model.cloud.back {
            cloudBackCard(service)
        } else if model.cloud.listening, !Recognition.cloudOnly, let service = model.cloud.service {
            cloudCard(service)
        } else if let problem = model.modelProblem, !model.languageAsk.isEmpty || model.modelBlocked {
            problemCard(problem)
        } else if model.languageNotInstalled {
            notInstalledCard
        } else if !model.languageAsk.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("听不出是哪种语言，你来选一下").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(model.languageAsk, id: \.locale) { lang in
                        SoftButton(lang.name) { model.pickLanguage(lang) }
                    }
                    Menu {
                        ForEach(sourceLanguages.filter { !model.languageAsk.contains($0) }, id: \.locale) { lang in
                            Button(lang.name) { model.pickLanguage(lang) }
                        }
                    } label: {
                        Text("更多…").font(.system(size: 12, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(Palette.secondary)
                }
            }
        } else if let fetch = model.modelFetch {
            fetchCard(fetch)
        }
    }

    /// macOS reports a speech model's download only as not started or done, so a bar that fills
    /// would sit at its start: a moving one and the time waited say it is still coming.
    private func fetchCard(_ fetch: ModelFetch) -> some View {
        let offer = model.cloud.offered ? model.cloud.service : nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView().progressViewStyle(.linear).controlSize(.small).tint(Palette.tertiary).frame(width: 64)
                Text(fetch.background ? L("正在补装 \(fetch.name) 语音模型") : L("正在下载 \(fetch.name) 语音模型"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let waited = Self.minutes(context.date.timeIntervalSince(fetch.since))
                Text(offer.map { L("已等 \(waited)，比平常慢。可以先交给 \($0) 听：声音会发给 \($0)，整句出字、慢 2–3 秒") }
                     ?? (fetch.background ? L("约 140 MB · 已等 \(waited) · 装好后自动判断语言") : L("约 140 MB · 已等 \(waited)")))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let offer {
                HStack(spacing: 8) {
                    SoftButton(L("先用 \(offer) 听"), dark: true) { model.startCloud() }
                    SoftButton(L("继续等")) { model.declineCloud() }
                }
            }
        }
    }

    /// The service hears the meeting: lines come whole and a little late, and the audio leaves the Mac.
    private func cloudCard(_ service: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if model.modelFetch != nil {
                    ProgressView().progressViewStyle(.linear).controlSize(.small).tint(Palette.tertiary).frame(width: 64)
                }
                Text("\(service) 先听着").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            Text(model.modelFetch.map { L("整句出字、慢 2–3 秒，\($0.name) 模型装好后自动换回本机") } ?? L("整句出字、慢 2–3 秒，声音会发给 \(service)"))
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            SoftButton(model.modelFetch != nil ? L("换回等待") : L("换回本机")) { model.stopCloud() }
        }
    }

    private func cloudBackCard(_ service: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("语音模型装好了，已换回本机").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            Text("字幕重新边说边出，声音不再发给 \(service)").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// None of the installed models hear their language: the likely ones not installed come first
    /// (picking one downloads it and replays the start), the installed ones in case the check was wrong.
    private var notInstalledCard: some View {
        let installed = model.candidates
        let names = installed.map(\.name)
        let title = names.count == 1 ? L("听着不像 \(names[0])")
            : names.count == 2 ? L("听着不像 \(names[0]) 或 \(names[1])") : L("听着不像已装的语言")
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("选了就下载它的语音模型，开头这段也会补上").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(model.languageAsk, id: \.locale) { lang in
                    SoftButton(lang.name) { model.pickLanguage(lang) }
                }
                Menu {
                    ForEach(sourceLanguages.filter { !model.languageAsk.contains($0) && !installed.contains($0) }, id: \.locale) { lang in
                        Button(lang.name) { model.pickLanguage(lang) }
                    }
                } label: {
                    Text("更多…").font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 10) {
                Text("其实是：").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                ForEach(installed, id: \.locale) { lang in
                    Button(lang.name) { model.pickLanguage(lang) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondary).underline()
                }
            }
        }
    }

    /// The model 听不出 needed couldn't be had: why, the one thing that helps, and the languages
    /// already on the Mac to go on with meanwhile.
    private func problemCard(_ p: ModelProblem) -> some View {
        // Chosen in settings, the language isn't swapped from here.
        let installed = model.settings.sourceMode == .auto ? model.candidates.filter { $0 != p.lang } : []
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("没能下载 \(p.lang.name) 语音模型").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                if let reason = reason(p.cause) {
                    Text(reason).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                switch p.cause {
                case .disk: SoftButton(L("打开存储空间"), dark: true) { model.openStorageSettings() }
                case .dictation: SoftButton(L("打开听写设置"), dark: true) { model.openDictationSettings() }
                case .other, .limit: SoftButton(L("再试一次"), dark: true) { model.retryModel() }
                case .offline: EmptyView()
                }
                // Not offline: the service is out of reach then too.
                if p.cause != .offline, model.running, let service = model.cloud.service {
                    SoftButton(L("先用 \(service) 听")) { model.startCloud() }
                }
            }
            if !installed.isEmpty {
                HStack(spacing: 8) {
                    Text("先用已装的：").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    ForEach(installed, id: \.locale) { lang in
                        SoftButton(lang.name) { model.pickLanguage(lang) }
                    }
                }
            }
        }
    }

    private func reason(_ cause: ModelProblem.Cause) -> String? {
        switch cause {
        case .offline: return L("网络连不上，连上后会自动继续")
        case .disk: return L("这台 Mac 的磁盘空间不够了")
        case .limit: return L("这台 Mac 上的语音模型已满 5 种")
        case .dictation(let message), .other(let message?): return message
        case .other(nil): return nil
        }
    }
}

extension Notification.Name {
    /// Debug `play:<seconds>`: the shown record plays from there.
    static let debugPlay = Notification.Name("cicada.debugPlay")
    /// Debug `shareSheet:<id>`: the 分享… sheet opens for that record (no id: it closes).
    static let debugShareSheet = Notification.Name("cicada.debugShareSheet")
}

/// A click on the words of a transcript line plays from it, as a click elsewhere on the line does:
/// selectable text takes the mouse before SwiftUI's tap. A drag (selecting) or a double click
/// (a word) does nothing; the time and 改这句… keep their own buttons.
final class WordClick {
    private var monitor: Any?

    func install(line: @escaping () -> String?, play: @escaping (String) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard e.clickCount == 1, let id = line(), Self.onText(e) else { return e }
            // The text tracks the mouse until it is let go, and its mouse-up never reaches a
            // monitor: look once that tracking is over.
            let start = NSEvent.mouseLocation
            Self.whenReleased(within: 1) {
                let now = NSEvent.mouseLocation
                guard hypot(now.x - start.x, now.y - start.y) < 3, line() == id else { return }
                play(id)
            }
            return e
        }
    }

    /// Once the button is up (a click, not a press held to select): checked every 50 ms.
    private static func whenReleased(within seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if NSEvent.pressedMouseButtons & 1 == 0 { action() } else if seconds > 0.05 { whenReleased(within: seconds - 0.05, action) }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// The mouse went down on selectable text, not on a button or the row's empty space (which
    /// the row's own tap handles).
    private static func onText(_ e: NSEvent) -> Bool {
        guard let content = e.window?.contentView,
              let hit = content.hitTest(content.convert(e.locationInWindow, from: nil)) else { return false }
        return hit is NSText || String(describing: type(of: hit)).contains("TextField")
    }
}
