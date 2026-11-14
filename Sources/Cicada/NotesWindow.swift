import AppKit
import Combine
import SwiftUI

/// The live notes window: floats over the meeting app, can be dragged and resized anywhere,
/// stays out of screen sharing (unless 录屏时可见 is on), and remembers its frame. Three layouts by width: a small card
/// (< 360), a sidebar with 纪要 / 文字记录 tabs, and notes beside the transcript (≥ 760).
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    enum Layout: CaseIterable { case card, sidebar, wide }
    /// Menu commands that change the view's own state.
    enum Command { case catchUp, search, layout(Layout) }

    private var panel: NSPanel?
    private weak var model: AppModel?
    let commands = PassthroughSubject<Command, Never>()

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// Not read back from the panel: its hosting view lowers `minSize` to the content's.
    static let minWidth: CGFloat = 300
    private static let autosave = "LiveSubsNotes"

    var layout: Layout {
        let w = panel?.frame.width ?? 460
        return w < 360 ? .card : w >= 760 ? .wide : .sidebar
    }

    /// "浮在最上层" (`notesOnTop`, on by default).
    var onTop: Bool {
        get { UserDefaults.standard.object(forKey: "notesOnTop") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "notesOnTop")
            panel?.level = newValue ? .floating : .normal
            panel?.isFloatingPanel = newValue
        }
    }

    func send(_ command: Command) {
        if case .search = command { panel?.makeKey() }
        commands.send(command)
    }

    /// `asked`: opened by name, so shown even where it can't keep clear of the onboarding window.
    func show(asked: Bool = false) {
        guard let model else { return }
        if panel == nil {
            let p = NotesPanel(contentRect: defaultFrame(), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.isFloatingPanel = onTop
            p.level = onTop ? .floating : .normal
            p.delegate = self
            p.onMiniaturize = { [weak self] in self?.hide() }
            p.standardWindowButton(.miniaturizeButton)?.isEnabled = true
            // Clicking it leaves the meeting app active and our other windows where they are;
            // it only takes the keyboard for its text fields.
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            p.isReleasedWhenClosed = false
            // Others never see it when you share your screen, unless the user lets recordings in.
            p.sharingType = model.settings.notesCapturable ? .readOnly : .none
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.minSize = NSSize(width: Self.minWidth, height: 180)
            p.backgroundColor = .white
            p.contentView = FirstClickHostingView(rootView: NotesWindowView(
                model: model, engine: model.notes, store: model.store, settings: model.settings,
                commands: commands.eraseToAnyPublisher(),
                setWidth: { [weak self] w, h in self?.resize(width: w, height: h) }))
            p.setFrameAutosaveName(Self.autosave)
            if !p.setFrameUsingName(Self.autosave) { p.setFrame(defaultFrame(), display: false) }
            panel = p
        }
        if !keepClear() && !asked { return }
        waiting = false
        panel?.orderFrontRegardless()
        model.notesVisibilityChanged(true)
    }

    func hide() {
        waiting = false
        panel?.orderOut(nil)
        model?.notesVisibilityChanged(false)
    }

    // MARK: Keeping clear of the onboarding window

    /// The onboarding window while it's open. The panel floats above it and can't be clicked
    /// through, so it must never sit on it: on a 1024×768 screen the sidebar covered 继续.
    private weak var avoiding: NSWindow?
    /// Moved out of the way: the user's own frame, put back when the window closes, and where we put the panel instead.
    private var moved: (own: NSRect, placed: NSRect)?
    /// Asked to show while there was no room beside the window: shown once it closes.
    private var waiting = false

    /// `window`: the onboarding window as it opens; nil as it closes.
    func avoid(_ window: NSWindow?) {
        avoiding = window
        if window != nil {
            if panel?.isVisible == true && !keepClear() {
                panel?.orderOut(nil)
                model?.notesVisibilityChanged(false)
            }
            return
        }
        if let moved, let p = panel {
            // Unless the user has moved it since; either way it's remembered again from here.
            if p.frame == moved.placed { p.setFrame(moved.own, display: true) }
            p.setFrameAutosaveName(Self.autosave)
        }
        moved = nil
        if waiting {
            waiting = false
            show()
        }
    }

    /// Moves the panel beside the window it avoids, or returns false (and waits) when neither side has room.
    private func keepClear() -> Bool {
        guard let p = panel, let w = avoiding, w.isVisible,
              let screen = w.screen ?? NSScreen.main, p.frame.intersects(w.frame) else { return true }
        guard let r = Self.beside(w.frame, in: screen.visibleFrame, width: p.frame.width, minWidth: Self.minWidth) else {
            waiting = true
            debugLog("notes window waits: no room beside onboarding \(w.frame) in \(screen.visibleFrame)")
            return false
        }
        let own = moved?.own ?? p.frame
        // Not remembered: quit during onboarding and the next meeting still opens where the user left it.
        if moved == nil { p.setFrameAutosaveName("") }
        p.setFrame(r, display: true)
        moved = (own, p.frame)
        return true
    }

    /// The panel beside `window` within `visible`: right of it, else left, a gap away and as tall
    /// as the screen allows, no wider than `width`; nil when neither side has `minWidth`.
    nonisolated static func beside(_ window: NSRect, in visible: NSRect, width: CGFloat, minWidth: CGFloat) -> NSRect? {
        let gap: CGFloat = 12
        let right = visible.maxX - window.maxX - 2 * gap, left = window.minX - visible.minX - 2 * gap
        let y = visible.minY + gap, h = visible.height - 2 * gap
        if right >= minWidth {
            let w = min(width, right)
            return NSRect(x: visible.maxX - gap - w, y: y, width: w, height: h)
        }
        if left >= minWidth {
            return NSRect(x: visible.minX + gap, y: y, width: min(width, left), height: h)
        }
        return nil
    }

    /// Closed with its close button (hide() doesn't come here): the meeting goes on in the
    /// records window, so the notes stay one click away.
    func windowWillClose(_ notification: Notification) {
        model?.notesVisibilityChanged(false)
        model?.notesWindowClosed()
    }

    var frame: NSRect? { panel?.frame }

    /// Card ⇄ sidebar ⇄ wide, keeping the window's top-right corner where it is.
    func resize(width: CGFloat, height: CGFloat? = nil) {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        var f = p.frame
        let top = f.maxY, right = f.maxX
        f.size.width = width
        if let height { f.size.height = min(height, screen.visibleFrame.height - 24) }
        f.origin.x = min(max(screen.visibleFrame.minX, right - width), screen.visibleFrame.maxX - width)
        f.origin.y = top - f.size.height
        p.setFrame(f, display: true, animate: true)
    }

    /// After a name is typed: the keyboard goes back to the meeting app, which never stopped being active.
    func returnKeyboard() {
        guard let panel, panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        if !NSApp.isActive { NSWorkspace.shared.frontmostApplication?.activate() }
    }

    func place(_ r: NSRect) { panel?.setFrame(r, display: true) }

    /// Debug control only: what the close button does.
    func performClose() { panel?.performClose(nil) }
    /// Debug control only: what the minimize button does.
    func performMiniaturize() { panel?.performMiniaturize(nil) }

    /// 录屏时可见, and the debug command that flips it for one screenshot without saving it.
    func setCapturable(_ on: Bool) { panel?.sharingType = on ? .readOnly : .none }

    /// The sidebar: docked to the right edge, nearly full height.
    private func defaultFrame() -> NSRect {
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: v.maxX - 460 - 16, y: v.minY + 16, width: 460, height: v.height - 32)
    }
}

/// The yellow button tucks the window away to the menu bar, like 收起: with only the menu bar
/// item there is no Dock to minimize into, and the panel's 打开 brings it back either way.
private final class NotesPanel: NSPanel {
    var onMiniaturize: (() -> Void)?
    // AppKit greys the button out for a floating, all-Spaces panel, and re-greys it on every
    // titlebar update; it hides instead of minimizing, so keep it lit.
    override func update() {
        super.update()
        if let b = standardWindowButton(.miniaturizeButton), !b.isEnabled { b.isEnabled = true }
    }
    override func performMiniaturize(_ sender: Any?) { onMiniaturize?() }
    override func miniaturize(_ sender: Any?) { onMiniaturize?() }
}

// MARK: - Views

struct NotesWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: NotesEngine
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    let commands: AnyPublisher<NotesWindowController.Command, Never>
    let setWidth: (CGFloat, CGFloat?) -> Void

    @State private var tab = "notes"
    @State private var query = ""
    @State private var jumpTo: Double?
    @State private var keyDraft = ""
    /// Session time when the window was collapsed to the card, and the topics and points the
    /// notes had then: the card offers what was added since.
    @State private var collapsedAt: Double = 0
    @State private var seenItems: Set<String> = []
    @State private var catchUp = false
    @State private var matchIndex = 0
    @State private var now = Date()
    @State private var badgeHover = false
    @State private var badgeHint = false
    @State private var width: CGFloat = 460
    /// "结束" was clicked during a meeting with lines: the confirmation strip is showing.
    @State private var confirmEnd = false
    @State private var languageOpen = false
    /// The voice whose editor is open under the people row.
    @State private var editingVoice: Int?
    /// When the reader last scrolled the notes: a live update only brings the current topic into
    /// view when they haven't just been reading something else.
    @State private var notesScrolledAt = Date.distantPast
    @FocusState private var searchFocused: Bool

    private var session: Session? { store.session(store.liveID ?? engine.shownID) }
    private var live: Bool { store.liveID != nil }
    private var heard: Int { session?.lines.count ?? 0 }
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width < 360 {
                    card
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        header(wide: geo.size.width >= 760)
                        meetingBar.padding(.horizontal, 24).padding(.bottom, 4)
                        banner.padding(.horizontal, 24).padding(.bottom, 4)
                        if live { liveAsks.padding(.horizontal, 24).padding(.bottom, 4) }
                        // 这样改对吗？ above both tabs: the window opens on 纪要, where a card in the
                        // transcript would never be seen.
                        fixAsk.padding(.horizontal, 24).padding(.bottom, 4)
                        if live { LanguageNotice(model: model).padding(.horizontal, 24).padding(.bottom, 8) }
                        // Where the scrolling starts: a hairline, and each column fades in under it (`topFade`).
                        Rectangle().fill(MainWindowView.hairline).frame(height: 1)
                        if geo.size.width >= 760 {
                            HStack(alignment: .top, spacing: 0) {
                                notesPane.frame(maxWidth: .infinity)
                                Divider()
                                transcript.padding(.horizontal, 20).padding(.top, 12).frame(maxWidth: .infinity)
                            }
                        } else if tab == "notes" {
                            notesPane
                        } else {
                            transcript.padding(.horizontal, 24).padding(.top, 12)
                        }
                        // The transcript shows what is being said in place; the caption is for the notes tab.
                        if geo.size.width < 760 && tab == "notes" { caption }
                    }
                    // The title bar is transparent: start the header beside its buttons, not below a blank band.
                    .ignoresSafeArea(.container, edges: .top)
                    .overlay(alignment: .bottom) { SpeakerUndoToast(model: model, session: session?.id) }
                    .overlay(alignment: .bottom) { FixToast(fixes: model.fixes).padding(.bottom, 14) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { width = geo.size.width }
            .onChange(of: geo.size.width) { _, w in width = w }
        }
        .background(Color.white)
        .foregroundStyle(Palette.ink)
        .onReceive(tick) { now = $0 }
        .onReceive(commands) { run($0) }
    }

    /// Commands from the app menu (纪要 / 显示 / 编辑).
    private func run(_ command: NotesWindowController.Command) {
        let card = width < 360
        switch command {
        case .catchUp:
            // From the full window: what was added in the last three minutes.
            if !card {
                collapsedAt = max(0, elapsed - 180)
                seenItems = items(before: collapsedAt)
            }
            catchUp = true
            setWidth(320, 420)
        case .search:
            if card { setWidth(460, 760) }
            tab = "transcript"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true }
        case .layout(.card):
            guard !card else { return }
            collapse()
        case .layout(.sidebar):
            setWidth(460, card ? 760 : nil)
        case .layout(.wide):
            setWidth(820, card ? 760 : nil)
        }
    }

    private func collapse() {
        collapsedAt = elapsed
        seenItems = items(before: .infinity)
        catchUp = false
        setWidth(320, 230)
    }

    /// Topic titles and points of the current notes said before a time (all of them for `.infinity`).
    private func items(before t: Double) -> Set<String> {
        var out: Set<String> = []
        for topic in engine.notes.topics {
            if topic.start < t { out.insert(topic.title) }
            for (i, p) in topic.points.enumerated() where (topic.pointTime(i) ?? topic.start) < t { out.insert(p) }
        }
        return out
    }

    // MARK: Header

    private func header(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // The status line gets its own full-width row: beside the buttons it had a third of a
            // narrow window, and "Listening · 00:09" or "Live notes" broke onto two lines in English.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    Text(live || session == nil ? L("实时纪要") : L("会议纪要")).font(.system(size: 24, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    if live {
                        MicButton(model: model, settings: settings, inHeader: true).padding(.trailing, 2)
                        Button(action: askToEnd) {
                            Text("结束").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 12).frame(height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("结束这场会议").padding(.trailing, 4)
                    }
                    iconButton(wide ? "rectangle.split.2x1.fill" : "rectangle.split.2x1", help: wide ? L("收窄") : L("纪要和原话并排")) {
                        setWidth(wide ? 460 : 820, nil)
                    }
                    iconButton("minus", help: L("收成小卡")) { collapse() }
                }
                // State lives here, not in buttons beside 结束: the meeting's languages as a text link
                // and a small spinner while the notes are being written. The sharing mark sits apart on
                // the right, so turning it on or off doesn't move the text.
                HStack(alignment: .top, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        if live { LiveDot().frame(height: 22) }
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(Palette.tertiary).frame(height: 22)
                        if live {
                            dotSeparator
                            languageLink
                        }
                        if live, engine.state == .updating, !engine.notes.isEmpty {
                            dotSeparator
                            HStack(spacing: 5) {
                                Spinner(size: 10)
                                Text("整理中").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                            }
                            .frame(height: 22)
                        }
                    }
                    Spacer(minLength: 0)
                    capturableBadge
                }
            }
            if !wide {
                HStack(spacing: 0) {
                    segment(L("纪要"), "notes")
                    segment(engine.notes.isEmpty && heard > 0 ? L("文字记录 · \(heard)") : L("文字记录"), "transcript")
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
            }
            if wide || tab == "transcript" {
                searchField
            }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 12)
    }

    /// 共享屏幕时让对方看到, always here so it can be turned back on: an orange lamp while shared
    /// screens and recordings see the window, a hollow grey one while only you do (the window
    /// isn't captured then, so nobody else sees it). No words beside it except a hint while the
    /// pointer rests on it: once on, words would show in the shared screen; the lamp's first wide
    /// breath confirms the click instead.
    private var capturableBadge: some View {
        let on = settings.notesCapturable
        return Button { model.setNotesCapturable(!on) } label: {
            CapturableMark(on: on)
                .frame(width: 22, height: 22)
                .background(Circle().fill(badgeHover ? Palette.fill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Drawn here rather than .help: the window never activates the app, and macOS doesn't
        // show tooltips for an app in the background.
        .onHover { inside in
            badgeHover = inside
            if !inside { badgeHint = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if badgeHover { badgeHint = true } }
        }
        .overlay(alignment: .trailing) {
            if badgeHint {
                Text(on ? L("对方可见 · 点击关闭") : L("仅自己可见 · 点击共享"))
                    .font(.system(size: 11)).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Palette.ink.opacity(0.88)))
                    .offset(x: -28).allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: badgeHint)
        .accessibilityLabel(Text("共享屏幕时让对方看到"))
        .accessibilityValue(on ? Text("对方可见") : Text("仅自己可见"))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
            TextField("在文字记录中搜索  ⌘F", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { step(1) }
                .onChange(of: query) { _, _ in matchIndex = 0 }
            if !query.isEmpty {
                Text(matches.isEmpty ? L("无结果") : "\(currentIndex + 1) / \(matches.count)")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                iconButton("chevron.up", help: L("上一个")) { step(-1) }.disabled(matches.isEmpty)
                iconButton("chevron.down", help: L("下一个")) { step(1) }.disabled(matches.isEmpty)
                iconButton("xmark", help: L("清除")) { query = "" }
            }
        }
        .padding(.leading, 12).padding(.trailing, 2).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(searchFocused ? Color.white : Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Palette.accent : .clear, lineWidth: 1.5))
    }

    /// The query, plus every way the notes say that name was heard (江充 also finds 江松).
    private var searchTerms: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out = [q]
        for t in engine.notes.terms {
            let forms = [t.name] + t.heard
            if forms.contains(where: { $0.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains($0) }) {
                out += forms.filter { !out.contains($0) }
            }
        }
        return out
    }

    private var matches: [String] {
        let terms = searchTerms
        guard !terms.isEmpty else { return [] }
        return (session?.lines ?? []).filter { l in
            terms.contains { l.shown.localizedCaseInsensitiveContains($0) || (l.dst ?? "").localizedCaseInsensitiveContains($0) }
        }.map(\.id)
    }

    private var currentIndex: Int { matches.isEmpty ? 0 : min(matchIndex, matches.count - 1) }

    private func step(_ d: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (currentIndex + d + matches.count) % matches.count
    }

    private func segment(_ title: String, _ id: String) -> some View {
        Button { tab = id } label: {
            Text(title).font(.system(size: 13, weight: tab == id ? .semibold : .regular))
                .foregroundStyle(tab == id ? Palette.ink : Palette.secondary)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(tab == id ? Color.white : .clear)
                    .shadow(color: .black.opacity(tab == id ? 0.08 : 0), radius: 1.5, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var elapsed: Double { store.liveStart.map { now.timeIntervalSince($0) } ?? 0 }

    private var statusLine: String {
        if live {
            var parts = [(heard == 0 ? L("正在听 · ") : L("正在记录 · ")) + NotesEngine.clock(elapsed)]
            if heard > 0 { parts.append(L("\(heard) 句")) }
            return parts.joined(separator: " · ")
        }
        let clock = session.map { L("已结束 · ") + TranscriptExport.header($0) } ?? L("没有在记录")
        guard let at = engine.notes.updatedAt, engine.state != .updating else { return clock }
        let ago = Int(now.timeIntervalSince(at))
        return clock + " · " + (ago < 10 ? L("刚刚更新") : ago < 60 ? L("\(ago) 秒前更新") : L("\(ago / 60) 分钟前更新"))
    }

    // MARK: This meeting's languages

    /// "EN → 中": what the meeting speaks → what the notes are written in. Opens this meeting's
    /// choices below the header (not a popover: the panel never activates the app, and a popover in
    /// an inactive app closes as soon as it opens); the defaults live in 设置 › 语言.
    private var languageLink: some View {
        let id = session?.id ?? ""
        let from = model.meetingLanguage(store.liveID).map(targetName) ?? L("自动")
        return Button { languageOpen.toggle() } label: {
            Text("\(from) → \(targetName(model.notesLanguageCode(id)))")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .underline(color: Palette.line)
                .frame(height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("这场会议的语言").accessibilityLabel(L("这场会议的语言"))
    }

    private var dotSeparator: some View {
        Text("·").font(.system(size: 12)).foregroundStyle(Palette.tertiary).frame(height: 22)
    }

    private func languageCard(_ id: String) -> some View {
        let source = model.meetingLanguage(store.liveID)
        let mine = settings.myLanguage
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("这场会议").font(.system(size: 14, weight: .bold))
                    Text("只改这一场，默认值在 设置 › 语言").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                iconButton("xmark", help: L("收起")) { languageOpen = false }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("对方说").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Text(source.map(targetName) ?? L("还没听出来")).font(.system(size: 13))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("字幕").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Segments(options: [("both", L("双语")), ("translation", L("只看译文")), ("original", L("只看原文"))],
                         value: model.subtitles, fill: true) { model.setSubtitles($0, meetingOnly: true) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("纪要").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Segments(options: [("mine", targetName(mine)), ("source", source.map { L("\(targetName($0))（原文）") } ?? L("会议原文"))],
                         value: model.notesChoice(id), fill: true) { model.setNotesLanguage($0, meetingOnly: true) }
                Text("换了以后会马上用新语言重写纪要").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            Button("打开语言设置") {
                languageOpen = false
                model.openSettings(.language)
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accentInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
        .foregroundStyle(Palette.ink)
    }

    // MARK: Ending a meeting

    /// Nothing heard yet: there is nothing to lose, stop at once. Otherwise ask first, below the
    /// header (away from the button, so a double click can't confirm it).
    private func askToEnd() {
        if heard == 0 { model.stop() } else { confirmEnd = true }
    }

    /// While live: the confirmation, when asked. After the meeting: what happens to it and what next.
    @ViewBuilder
    private var meetingBar: some View {
        if live {
            if let p = model.ending { MeetingEndingStrip(model: model, pending: p).padding(.bottom, confirmEnd ? 8 : 0) }
            if languageOpen && !confirmEnd { languageCard(session?.id ?? "") }
            if confirmEnd {
                VStack(alignment: .leading, spacing: 10) {
                    Text("结束这场会议？").font(.system(size: 14, weight: .bold))
                    Text("已记录 \(NotesEngine.clock(elapsed)) · \(heard) 句。结束后停止收听，并整理一份完整版纪要。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SoftButton(L("继续记录")) { confirmEnd = false }
                        SoftButton(L("结束会议"), dark: true) {
                            confirmEnd = false
                            model.stop()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
                // No timeout: a strip that vanished under the pointer would let the click land on the notes.
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if session != nil && engine.state == .updating {
                        ProgressView().controlSize(.small)
                    } else if session != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                    }
                    Text(endedText).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let id = session?.id, let other = otherNotesLanguage(id) {
                        // A Latin name gets spaces in Chinese ("改用 English 重新整理"), a Chinese one
                        // doesn't ("改用简体中文重新整理"). Both keys translate alike.
                        let name = targetName(other.code)
                        SoftButton(name.first?.isASCII == true ? L("改用 \(name) 重新整理") : L("改用\(name)重新整理")) {
                            model.regenerateNotes(id, choice: other.choice)
                        }
                            .disabled(engine.state == .updating)
                    }
                    if let id = session?.id {
                        SoftButton(L("在会议记录中查看")) {
                            model.mainShow = nil
                            model.mainShow = "\(id),notes"
                            model.openMainWindow?()
                        }
                    }
                    SoftButton(session == nil ? L("开始记录") : L("开始新会议"), dark: true) { model.start(byUser: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
        }
    }

    /// The notes language this meeting's notes are not in, when the meeting's language differs from mine.
    private func otherNotesLanguage(_ id: String) -> (choice: String, code: String)? {
        guard let source = model.meetingLanguage(id), source != settings.myLanguage else { return nil }
        return model.notesChoice(id) == "source" ? ("mine", settings.myLanguage) : ("source", source)
    }

    private var endedText: String {
        guard session != nil else { return L("现在没有在记录") }
        if engine.state == .updating { return L("会议已结束，正在整理完整版纪要…") }
        if engine.state == .noKey || engine.notes.isEmpty { return L("会议已结束，文字记录已保存") }
        return L("会议已结束，完整版纪要已整理好 · ") + targetName(model.notesLanguageCode(session?.id ?? ""))
    }

    // MARK: Banners (key and service states)

    @ViewBuilder
    private var banner: some View {
        // 语音和文字只发给你的服务, and nothing translates finished sentences: it picks up by itself, and
        // no 改用 Ling, which would send the meeting elsewhere. A dead key or a missing local network
        // permission is the user's to fix: those lines come first.
        if live, model.translationHealth.googleOff, model.translationHealth.sentencesUntranslated,
           engine.state != .invalidKey, !model.ling.aiCheck.localNetworkDenied {
            let notesWait = [.unreachable, .updating].contains(engine.state) && model.ling.aiCheck.failure?.reason == .unreachable
            StatusLine(tone: .waiting, text: notesWait ? L("译文和纪要等 \(serviceLabel) 恢复 · 字幕先显示原文")
                                                       : L("译文等 \(serviceLabel) 恢复 · 字幕先显示原文"))
        } else {
            serviceBanner
        }
    }

    @ViewBuilder
    private var serviceBanner: some View {
        switch engine.state {
        case .noKey where session?.lines.isEmpty == false || live:
            keyEntry
        case .invalidKey:
            StatusLine(tone: .needsYou, text: lastCovered > 0 ? L("key 失效了 · 纪要停在 \(NotesEngine.clock(lastCovered))")
                                                              : L("key 失效了 · 纪要等新的 key"),
                       action: (L("换 key"), { model.openSettings(.ai) }))
        // The rest is about a round of the meeting going on now: a record opened later has none.
        case .rateLimited where live:
            StatusLine(tone: .waiting, text: L("\(serviceLabel) 很忙 · 纪要稍后补上，字幕照常"))
        // Both: the notes' own request failed, and the service doesn't answer anything. Notes that
        // only timed out while translations still came back aren't "can't reach"; the next round retries.
        // The retry that follows (`updating`) hangs as long as a timeout: the line stays meanwhile.
        case .unreachable where live && model.ling.aiCheck.failure?.reason == .unreachable,
             .updating where live && model.ling.aiCheck.failure?.reason == .unreachable:
            if model.ling.aiCheck.localNetworkDenied {
                StatusLine(tone: .needsYou, text: L("连不上 \(serviceLabel) · 缺本地网络权限"),
                           action: (L("去开启"), { model.openLocalNetworkSettings() }))
            } else {
                // The network or the proxy, not the notes: it picks up by itself. Where the service
                // also hears the meeting (Intel) the subtitles wait too.
                StatusLine(tone: .waiting, text: Recognition.cloudOnly
                           ? L("字幕和纪要等 \(serviceLabel) 恢复 · 连上后自动继续")
                           : lastCovered > 0 ? L("纪要等 \(serviceLabel) 恢复 · 停在 \(NotesEngine.clock(lastCovered))，字幕照常")
                                             : L("纪要等 \(serviceLabel) 恢复 · 字幕照常"),
                           action: model.canSwitchToLing ? (L("改用 Ling"), { model.switchToLing() }) : nil)
            }
        case .failed where live:
            StatusLine(tone: .info, text: L("这轮纪要没写好 · 下轮自动补上"))
        default:
            EmptyView()
        }
    }

    /// What the menu bar panel asks while you meet, here too: the panel is shut during a meeting,
    /// this window is what you look at.
    @ViewBuilder
    private var liveAsks: some View {
        if model.hybridMicDenied {
            ask(L("听会议室要先允许麦克风"), L("电脑声音照常在记")) {
                SoftButton(L("去设置"), dark: true) { model.openMicrophoneSettings() }
            }
        }
        if model.roomMicSilent {
            ask(L("麦克风没声音"), L("重开了一次也没好")) {
                SoftButton(L("换麦克风"), dark: true) { model.openSoundInputSettings() }
            }
        }
    }

    private func ask<Buttons: View>(_ title: String, _ detail: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
    }

    private var serviceLabel: String { model.ling.serviceLabel }

    /// Lines the notes don't cover yet, once they are two minutes behind the meeting (between
    /// ordinary 45 s updates there is always a little that isn't in yet).
    private var behind: Int {
        guard live, let s = session, lastCovered > 0, elapsed - lastCovered >= 120 else { return 0 }
        return max(0, s.lines.count - engine.notes.covered)
    }

    private var lastCovered: Double {
        guard let s = session, engine.notes.covered > 0, engine.notes.covered <= s.lines.count else { return 0 }
        return s.lines[engine.notes.covered - 1].t
    }


    /// Without a key, finished sentences rely on Google too: when it can't be reached and nothing
    /// stands in, the key panel says so, since a key is the fix (Ling needs no proxy in China).
    private var untranslated: Bool {
        live && model.translationHealth.googleDown && model.translationHealth.sentencesUntranslated
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            let p = model.ling.provider
            if untranslated {
                Text("连不上翻译，新字幕暂时只有原文").font(.system(size: 15, weight: .bold))
                Text(p.id == .ling ? L("填 Ling key 后不用代理也能翻译，还会整理出纪要。")
                                   : L("填好 \(p.name) 的 key 后用它翻译，还会整理出纪要。"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(2)
            } else {
                Text(Recognition.cloudOnly ? L("识别语音和生成纪要需要 Ling key") : L("生成纪要需要 API key")).font(.system(size: 15, weight: .bold))
                Text(Recognition.cloudOnly
                     ? L("填好 \(p.name) 的 key 后，立即开始识别语音、出双语字幕和实时纪要。")
                     : L("文字记录仍在保存。填好 \(p.name) 的 key 后，会从头整理出整场纪要。"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(2)
            }
            HStack(spacing: 8) {
                SecureField("sk-…", text: $keyDraft)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
                    .onSubmit(saveKey)
                SoftButton(L("保存并开始"), dark: true, action: saveKey)
            }
            HStack(spacing: 16) {
                if let site = model.ling.provider.site {
                    Button(L("获取 \(model.ling.provider.name) key ↗")) { NSWorkspace.shared.open(site) }
                }
                if untranslated {
                    Button(L("怎么设置代理 ↗")) { NSWorkspace.shared.open(ProxyProbe.helpURL) }
                }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.raised))
    }

    private func saveKey() {
        let k = keyDraft
        keyDraft = ""
        Task {
            await model.ling.setKey(k)
            if model.ling.usable { model.notes.updateNow() }
        }
    }

    // MARK: Content

    /// Notes, or what is happening before there are any: listening, writing the first version.
    @ViewBuilder
    private var notesPane: some View {
        if !engine.notes.isEmpty {
            notesScroll
        } else if engine.state == .noKey || engine.state == .invalidKey {
            Spacer()
        } else if (live && heard > 0 && engine.state == .updating)
                    || (session != nil && engine.generatingID == session?.id) {  // nil == nil is not "generating"
            ScrollView {
                NotesGeneratingView(heard: heard).padding(.horizontal, 24).padding(.vertical, 12)
            }
        } else if live {
            // Until a request is actually out: the first one waits for a few lines or 20 s, and
            // audio already playing at the start brings a line within seconds.
            ScrollView {
                NotesListeningView(heard: heard).padding(.horizontal, 24).padding(.vertical, 12)
            }
        } else {
            VStack {
                Spacer()
                Text(session == nil ? L("没有进行中的会议") : L("这场会议还没有纪要"))
                    .font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var notesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                NotesContentView(notes: session.map { SpeakerLabels.named(engine.notes, SpeakerLabels.names($0)) } ?? engine.notes,
                                 fresh: engine.fresh, live: live,
                                 updating: engine.state == .updating,
                                 summaryJustChanged: engine.summaryChangedAt.map { now.timeIntervalSince($0) < 20 } ?? false,
                                 coveredUntil: lastCovered > 0 ? lastCovered : nil,
                                 endedAt: session?.lines.last?.t,
                                 behind: behind,
                                 onJump: { t in jumpTo = t; tab = "transcript" },
                                 fixTerms: fixTermsView)
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
            }
            .topFade()
            .onScrolled {
                if UserScroll.recent { notesScrolledAt = Date() }
            }
            // Each live update lands on the topic being discussed now, which is the last one and
            // soon below the fold; 20 s after the reader's own scroll, follow it again.
            .onChange(of: engine.notes.updatedAt) { _, _ in
                guard live, Date().timeIntervalSince(notesScrolledAt) > 20 else { return }
                showCurrentTopic(proxy, animated: true)
            }
            .onAppear {
                UserScroll.install()
                if live { showCurrentTopic(proxy, animated: false) }
            }
        }
    }

    private func showCurrentTopic(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current = engine.notes.topics.last, engine.notes.topics.count > 1 else { return }
        let id = NotesContentView.topicID(current)
        if animated { withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(id, anchor: .top) } } else { proxy.scrollTo(id, anchor: .top) }
    }

    /// Not while the window is shown to the other side: names wait in 人名和术语 then.
    @ViewBuilder private var fixAsk: some View {
        if let s = session, !model.settings.notesCapturable, let a = model.fixes.asking(in: s.id) {
            FixConfirmCard(line: a.line, fix: a.fix, count: a.of, onAnswer: { yes in
                model.fixes.answer(a.fix, yes: yes, in: s.id)
            }, onLater: { model.fixes.later(a.fix, in: s.id) })
        }
    }

    private var fixTermsView: AnyView? {
        guard let s = session, !FixTermsView.fixedWords(s).isEmpty || !model.fixes.pending(in: s.id).isEmpty else { return nil }
        return AnyView(FixTermsView(fixes: model.fixes, session: s) { word in query = word; tab = "transcript" })
    }

    private var transcript: some View {
        let ms = matches
        let lines = session?.lines ?? []
        let speakers = model.settings.speakerVoices ? session.map(SpeakerLabels.numbers) ?? [:] : [:]
        return VStack(alignment: .leading, spacing: 10) {
            if !speakers.isEmpty || (model.settings.speakerVoices && session.map { SpeakerLabels.singleVoice($0.lines) != nil } == true), let s = session {
                SpeakerStrip(model: model, session: s, editing: $editingVoice)
            }
            TranscriptListView(lines: lines, topics: engine.notes.topics, terms: searchTerms,
                               currentMatch: ms.isEmpty ? nil : ms[currentIndex], live: live,
                               partialShown: TranscriptPartial.shows(model.liveSource, live: live, after: lines.last?.src),
                               jumpTo: jumpTo, speakers: speakers, startedAt: store.liveStart,
                               identifying: model.identifyingLanguage,
                               voices: speakers.isEmpty ? [:] : session.map(SpeakerLabels.voiceNumbers) ?? [:], marked: editingVoice,
                               places: RecordList.heardBoth(lines), settling: model.settling, voicePending: model.voicePending,
                               onAssign: { ids, voice in if let s = session { model.assignLines(session: s.id, ids, to: voice) } },
                               onRevert: { lineID, fix in if let s = session { model.fixes.revert(fix, lineID: lineID, in: s.id) } }) {
                LivePartialRow(model: model, startedAt: store.liveStart)
            }
            .equatable()
        }
        .environment(\.speakerNames, session.map(SpeakerLabels.names) ?? [:])
    }

    @ViewBuilder
    private var caption: some View {
        let shown = model.displayed(model.liveSource, model.liveTranslation)
        if live, !shown.source.isEmpty || !shown.translation.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !shown.source.isEmpty {
                    Text(shown.source).font(.system(size: 12)).foregroundStyle(Color(white: 0.74)).lineLimit(2)
                }
                if !shown.translation.isEmpty {
                    Text(shown.translation).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink))
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if catchUp {
                    Text("收起之后 · \(NotesEngine.clock(collapsedAt)) – \(NotesEngine.clock(elapsed))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                } else {
                    if live { LiveDot() }
                    Text(currentTopic.map { (live ? L("正在讲 · ") : L("最后一个议题 · ")) + L("\(NotesEngine.clock($0.start)) 起") } ?? (live ? L("正在记录") : L("实时纪要")))
                        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                capturableBadge
                iconButton("arrow.up.left.and.arrow.down.right", help: L("展开纪要")) { setWidth(460, 760) }
            }
            if live, let p = model.ending {
                MeetingEndingStrip(model: model, pending: p, compact: true)
                Spacer(minLength: 0)
            } else if catchUp {
                Text("这 \(span) 讲了").font(.system(size: 17, weight: .bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(added, id: \.topic.id) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(NotesEngine.clock(item.topic.start)).font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Palette.tertiary).frame(width: 38, alignment: .leading)
                                    Text(item.topic.title).font(.system(size: 14, weight: .bold))
                                }
                                if !item.points.isEmpty {
                                    Text(item.points.joined(separator: "；")).font(.system(size: 13))
                                        .foregroundStyle(Palette.secondary).lineSpacing(2).padding(.leading, 46)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if added.isEmpty {
                            Text("纪要里还没有新内容").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    SoftButton(L("展开纪要"), dark: true) { setWidth(460, 760) }
                    SoftButton(L("看过了")) {
                        catchUp = false
                        collapsedAt = elapsed
                        seenItems = items(before: .infinity)
                        setWidth(320, 230)
                    }
                }
            } else {
                Text(currentTopic?.title ?? (!live ? L("还没有纪要") : heard == 0 ? L("正在听") : L("正在生成纪要…")))
                    .font(.system(size: 17, weight: .bold)).lineLimit(2)
                if addedCount.points == 0 && addedCount.topics == 0, let last = currentTopic?.points.last {
                    Text(last).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if addedCount.topics + addedCount.points > 0 {
                    // Only says something when there is something new.
                    Button { catchUp = true; setWidth(320, 420) } label: {
                        HStack {
                            Text(addedLabel).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if collapsedAt > 0 || live {
                    Text(L("收起 \(span) · ") + (live ? L("还在讲这个") : L("没有新内容")))
                        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 16)
    }

    private var currentTopic: NoteTopic? { engine.notes.topics.last }

    /// Topics with what was added to them since the card was collapsed.
    private var added: [(topic: NoteTopic, points: [String])] {
        engine.notes.topics.compactMap { t in
            let points = t.points.filter { !seenItems.contains($0) }
            return seenItems.contains(t.title) && points.isEmpty ? nil : (t, points)
        }
    }

    private var addedCount: (topics: Int, points: Int) {
        let a = added
        return (a.filter { !seenItems.contains($0.topic.title) }.count, a.reduce(0) { $0 + $1.points.count })
    }

    private var addedLabel: String {
        let c = addedCount
        var parts: [String] = []
        if c.topics > 0 { parts.append(L("\(c.topics) 个议题")) }
        if c.points > 0 { parts.append(L("\(c.points) 条要点")) }
        return L("收起后新增 ") + parts.joined(separator: uiIsChinese ? "、" : ", ")
    }

    private var span: String {
        let s = max(0, Int(elapsed - collapsedAt))
        return s < 60 ? L("\(s) 秒") : L("\(s / 60) 分钟")
    }
}

/// The panel never activates the app, so it is almost never the key window when clicked; a plain
/// hosting view would spend that click on focus and every button would need two.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
