import AppKit
import SwiftUI

// Notes and transcript views shared by the live notes window and the main window (meeting
// records). The look follows the canvas: white ground, grey blocks for what matters most,
// framed lists with hairlines, orange only for what is happening now.

// MARK: - Notes

struct NotesContentView: View {
    let notes: MeetingNotes
    var fresh: Set<String> = []
    /// The meeting is still going: the last topic is "正在讲".
    var live = false
    /// The main window's page: the summary as a lead paragraph, quiet section labels, rules
    /// between rows instead of cards.
    var document = false
    var updating = false
    var summaryJustChanged = false
    /// The time of the last line the notes cover ("到 03:52").
    var coveredUntil: Double?
    /// Where the last topic ends when the meeting is over (its last line).
    var endedAt: Double?
    /// Lines heard since `coveredUntil` that the notes don't cover yet (shown under the last topic).
    var behind = 0
    var onJump: (Double) -> Void = { _ in }
    /// 改正听错的词's part of 人名和术语 (the words fixed, the ones waiting), from the notes window.
    var fixTerms: AnyView? = nil

    var body: some View {
        if document {
            DocumentNotesView(notes: notes, fresh: fresh, live: live, updating: updating, endedAt: endedAt, onJump: onJump)
        } else {
            cards
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: document ? 32 : 18) {
            if document && !notes.summary.isEmpty {
                Text(notes.summary).font(.system(size: 17)).lineSpacing(7).foregroundStyle(Palette.ink.opacity(0.9))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if !notes.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("总结").font(.system(size: 15, weight: .bold))
                        if summaryJustChanged { Tag(L("刚更新"), live: true) }
                        Spacer()
                        if notes.final { Tag(L("完整版")) } else if live {
                            Tag(coveredUntil.map { L("速记版 · 到 \(NotesEngine.clock($0))") } ?? L("速记版"))
                        }
                    }
                    Text(notes.summary).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
            }

            if !notes.topics.isEmpty {
                VStack(alignment: .leading, spacing: document ? 0 : 14) {
                    title(L("议题"))
                    ForEach(Array(notes.topics.enumerated()), id: \.element.id) { i, topic in
                        if document { Divider() }
                        TopicView(topic: topic,
                                  end: i + 1 < notes.topics.count ? notes.topics[i + 1].start : (live ? nil : endedAt),
                                  current: live && i == notes.topics.count - 1, fresh: fresh, onJump: onJump)
                            .padding(.vertical, document ? 14 : 0)
                            .id(Self.topicID(topic))
                    }
                    if live, behind > 0, let coveredUntil {
                        NotesBehindRow(after: coveredUntil, lines: behind, onJump: onJump)
                    }
                }
            }

            if !notes.conclusions.isEmpty || !notes.todos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    title(notes.todos.isEmpty ? L("结论") : L("结论和待办"))
                    if document {
                        VStack(alignment: .leading, spacing: 0) { items }
                    } else {
                        FramedList { items }
                    }
                }
            }

            if !notes.terms.isEmpty || fixTerms != nil {
                VStack(alignment: .leading, spacing: 10) {
                    title(L("人名和术语"))
                    if let fixTerms { fixTerms }
                    if !notes.terms.isEmpty { TermChips(terms: notes.terms, showHeard: true) }
                }
            }
        }
    }

    /// Scroll target for a topic (the live notes window keeps the current one in view).
    static func topicID(_ topic: NoteTopic) -> String { "topic-\(topic.id)" }

    @ViewBuilder
    private func title(_ text: String) -> some View {
        if document {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.bottom, 2)
        } else {
            SectionTitle(text)
        }
    }

    @ViewBuilder
    private var items: some View {
        let all = notes.conclusions + notes.todos
        ForEach(Array(all.enumerated()), id: \.offset) { i, item in
            let todo = i >= notes.conclusions.count
            if document && i > 0 { Divider() }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if todo {
                    Image(systemName: "circle").font(.system(size: document ? 13 : 11)).foregroundStyle(Palette.tertiary)
                } else if document {
                    Circle().fill(Palette.ink.opacity(0.55)).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        .frame(width: 13)
                }
                Text(item.withOwner)
                    .font(.system(size: 14)).lineSpacing(2)
                    .foregroundStyle(item.support == 0 ? Palette.tertiary : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.support == 0 {
                    Tag(L("依据较少"))
                } else if let t = item.t {
                    TimeLink(text: L("\(NotesEngine.clock(t)) · \(item.support) 句"), t: t, onJump: onJump)
                } else {
                    Tag(L("依据 \(item.support) 句"))
                }
            }
            .padding(.horizontal, document ? 0 : 16).padding(.vertical, 11)
            if !document && i < all.count - 1 { Divider() }
        }
    }
}

/// The main window's page: the conclusions first in one quiet block, the summary, then the topics
/// as numbered rows that open to their points. Less on screen at once than the live window's cards.
private struct DocumentNotesView: View {
    let notes: MeetingNotes
    let fresh: Set<String>
    let live: Bool
    let updating: Bool
    let endedAt: Double?
    let onJump: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            let items = notes.conclusions + notes.todos
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(notes.todos.isEmpty ? L("结论") : L("结论和待办"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                        .padding(.bottom, 2)
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        conclusion(item, index: i + 1, todo: i >= notes.conclusions.count)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.raised))
            }

            if !notes.summary.isEmpty {
                Text(notes.summary).font(.system(size: 15)).lineSpacing(9).foregroundStyle(Palette.body)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }

            if !notes.topics.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("议题").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.tertiary).padding(.bottom, 8)
                    ForEach(Array(notes.topics.enumerated()), id: \.element.id) { i, topic in
                        let current = live && i == notes.topics.count - 1
                        Rectangle().fill(MainWindowView.hairline).frame(height: 1)
                        DocumentTopicRow(index: i, topic: topic, current: current,
                                         updating: updating && current, fresh: fresh,
                                         startOpen: i == 0 || current, onJump: onJump)
                            .id(NotesContentView.topicID(topic))
                    }
                    Rectangle().fill(MainWindowView.hairline).frame(height: 1)
                }
            }

            if !notes.terms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("人名和术语").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.tertiary)
                    TermChips(terms: notes.terms, showHeard: false)
                }
            }
        }
    }

    /// A conclusion reads as a plain sentence, numbered, with its numbers and dates marked; clicking it
    /// jumps to the lines behind it. One with little support stays grey.
    private func conclusion(_ item: NoteItem, index: Int, todo: Bool) -> some View {
        let weak = item.support == 0
        let text = item.withOwner
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if todo { Image(systemName: "circle").font(.system(size: 11)) } else { Text("\(index)").font(.system(size: 12).monospacedDigit()) }
            }
            .fontWeight(.semibold).foregroundStyle(weak ? Palette.secondary : Palette.link).frame(width: 16, alignment: .leading)
            Text(weak ? AttributedString(text) : Highlight.facts(text))
                .font(.system(size: 15)).lineSpacing(5)
                .foregroundStyle(weak ? Palette.secondary : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if weak { Tag(L("依据较少")) }
            if let t = item.t, !weak { TimeLink(text: NotesEngine.clock(t), t: t, onJump: onJump) }
        }
        .padding(.vertical, 3)
    }
}

/// Numbers with their units and day words ("5000 元", "20 岁", "3月3日", "周五晚上") in a conclusion,
/// marked so the facts can be picked out at a glance.
enum Highlight {
    private static let pattern = try! NSRegularExpression(pattern:
        "(\\d+\\s*月\\s*\\d+\\s*[日号])"
        + "|((下|本|这|上)?(周|星期|礼拜)[一二三四五六日天](早上|上午|中午|下午|晚上)?)"
        + "|(\\d[\\d,.]*\\s*(万|千|百|亿)?\\s*(元|块|美元|岁|人|个|次|天|周|个月|月|年|小时|分钟|点|号|%|％|k|K)?)"
        + "|((今天|明天|后天|昨天|月底|月初|年底)(早上|上午|中午|下午|晚上)?)")

    static func facts(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let ns = text as NSString
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            // A lone digit (list numbers, "第1") is noise; keep multi-digit numbers, units and days.
            let hit = ns.substring(with: m.range)
            if hit.count < 2 { continue }
            guard let r = Range(m.range, in: text),
                  let lo = AttributedString.Index(r.lowerBound, within: out),
                  let hi = AttributedString.Index(r.upperBound, within: out) else { continue }
            out[lo..<hi].backgroundColor = Palette.mark
            out[lo..<hi].font = .system(size: 15, weight: .semibold)
        }
        return out
    }
}

private struct DocumentTopicRow: View {
    let index: Int
    let topic: NoteTopic
    let current: Bool
    let updating: Bool
    let fresh: Set<String>
    let onJump: (Double) -> Void
    @State private var open: Bool

    init(index: Int, topic: NoteTopic, current: Bool, updating: Bool, fresh: Set<String>,
         startOpen: Bool, onJump: @escaping (Double) -> Void) {
        self.index = index; self.topic = topic; self.current = current; self.updating = updating
        self.fresh = fresh; self.onJump = onJump
        _open = State(initialValue: startOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.link).frame(width: 28, alignment: .leading)
                        Text(topic.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        if current { Tag(L("正在讲"), live: true) }
                        if fresh.contains(topic.title) && !current { Tag(L("新"), live: true) }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                TimeLink(text: NotesEngine.clock(topic.start), t: topic.start, onJump: onJump)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondary).rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.vertical, 15)

            if open {
                VStack(alignment: .leading, spacing: 7) {
                    if !topic.summary.isEmpty {
                        Text(topic.summary).font(.system(size: 14)).lineSpacing(6).foregroundStyle(Palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(topic.points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("·").foregroundStyle(Palette.secondary)
                            Text(p).font(.system(size: 14)).lineSpacing(5).foregroundStyle(Palette.ink).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if fresh.contains(p) { Tag(L("新"), live: true) }
                        }
                        .help(topic.pointTime(i).map { NotesEngine.clock($0) } ?? "")
                        .modifier(FadeIn(active: fresh.contains(p)))
                    }
                    if let fish = topic.fishbone { FishboneView(fishbone: fish, onJump: onJump).padding(.top, 4) }
                    if updating {
                        VStack(alignment: .leading, spacing: 7) {
                            SkeletonBar(fraction: 0.82, height: 10, warm: true)
                            SkeletonBar(fraction: 0.56, height: 10, warm: true)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 36).padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .onChange(of: current) { _, now in if now { open = true } }
    }
}

private struct TopicView: View {
    let topic: NoteTopic
    /// The next topic's start, or the meeting's end; nil while it is still being discussed.
    let end: Double?
    let current: Bool
    let fresh: Set<String>
    let onJump: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(topic.title).font(.system(size: 15, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                if current { Tag(L("正在讲"), live: true) }
                if fresh.contains(topic.title) && !current { Tag(L("新"), live: true) }
                Spacer(minLength: 8)
                Button { onJump(topic.start) } label: {
                    Text(range)
                        .font(.system(size: 12, weight: current ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(current ? Palette.accentInk : Palette.tertiary)
                        .fixedSize()
                }
                .buttonStyle(.plain).help("看原话")
            }
            if !topic.summary.isEmpty {
                Text(topic.summary).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Each point's time and 新 sit on a line above it, so the text keeps the column's whole width.
            ForEach(Array(topic.points.enumerated()), id: \.offset) { i, p in
                VStack(alignment: .leading, spacing: 3) {
                    if topic.pointTime(i) != nil || fresh.contains(p) {
                        HStack(spacing: 6) {
                            if let t = topic.pointTime(i) { TimeLink(text: NotesEngine.clock(t), t: t, onJump: onJump) }
                            if fresh.contains(p) { Tag(L("新"), live: true) }
                        }
                    }
                    Text(p).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(FadeIn(active: fresh.contains(p)))
            }
            if let fish = topic.fishbone { FishboneView(fishbone: fish, onJump: onJump).padding(.top, 4) }
        }
        .padding(.vertical, current ? 12 : 0).padding(.horizontal, current ? 12 : 0)
        .background(RoundedRectangle(cornerRadius: 14).fill(current ? Palette.accentWash : .clear))
    }

    /// "01:04–02:02", or "02:03 起" for the topic being discussed.
    private var range: String {
        let from = NotesEngine.clock(topic.start)
        guard let end, end > topic.start + 1 else { return current ? L("\(from) 起") : from }
        return "\(from)–\(NotesEngine.clock(end))"
    }
}

/// Under the last topic while the notes are behind the meeting: how much isn't in them yet, and a
/// way to read it in the transcript meanwhile.
struct NotesBehindRow: View {
    let after: Double
    let lines: Int
    let onJump: (Double) -> Void

    var body: some View {
        Button { onJump(after) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    LiveDot()
                    Text("\(NotesEngine.clock(after)) 之后的 \(lines) 句还在整理").font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("先看原话 →").font(.system(size: 12))
            }
            .foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small time that jumps to that moment in the transcript.
struct TimeLink: View {
    let text: String
    let t: Double
    let onJump: (Double) -> Void
    @State private var hover = false

    var body: some View {
        Button { onJump(t) } label: {
            Text(text).font(.system(size: 12).monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(Palette.link)
                .underline(hover)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("回到原话")
    }
}

/// A fishbone drawn upright for a narrow window: the question on top, branches alternating on
/// either side of a spine. A branch no transcript line backs is dashed.
struct FishboneView: View {
    let fishbone: Fishbone
    var onJump: (Double) -> Void = { _ in }
    /// Drawn for 复制为图片 or 复制纪要: no hint, no menu.
    var forPicture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(fishbone.question.isEmpty ? L("为什么") : fishbone.question).font(.system(size: 13, weight: .bold))
                Spacer()
                Text("鱼骨图").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: fishbone.branches.count, by: 2)), id: \.self) { i in
                    HStack(alignment: .center, spacing: 0) {
                        branch(fishbone.branches[i])
                        spine
                        if i + 1 < fishbone.branches.count {
                            branch(fishbone.branches[i + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !forPicture {
                Text("点击分支跳回原话").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }

    private var spine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(white: 0.84)).frame(width: 2)
            Circle().fill(Palette.ink).frame(width: 7, height: 7)
            Rectangle().fill(Color(white: 0.84)).frame(width: 2)
        }
        .frame(width: 18)
    }

    private func branch(_ b: FishboneBranch) -> some View {
        let weak = b.support == 0
        return Button { if let t = b.t { onJump(t) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(b.label).font(.system(size: 12, weight: .bold)).foregroundStyle(weak ? Palette.tertiary : Palette.ink)
                if !b.detail.isEmpty {
                    Text(b.detail).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(weak ? Color.clear : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(weak ? Color(white: 0.8) : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(weak ? L("依据较少，仅供参考") : L("看原话"))
    }
}

// MARK: - Transcript

/// When the user last turned a scroll wheel or swiped the trackpad in this app. SwiftUI also moves
/// a scroll view by itself (rows measured late, text rewrapping after a resize), so only a recent
/// real scroll may pause following.
@MainActor
enum UserScroll {
    private static var last = Date.distantPast
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            last = Date()
            return event
        }
    }

    static var recent: Bool { Date().timeIntervalSince(last) < 0.6 }
}

/// The transcript grouped under the notes' topics, oldest first. While live it follows the
/// newest line; scrolling up pauses that and collects new lines into a "↓ N 句新内容" button.
/// A search highlights matches in place instead of hiding the lines around them.
///
/// Every paragraph is its own lazy child, so a long
/// meeting lays out only what is on screen. What is being said right now is `partial`, a view that
/// watches the speech itself: with `.equatable()` a new word redraws that row, not the list.
struct TranscriptListView<Partial: View>: View, Equatable {
    let lines: [TranscriptLine]
    let topics: [NoteTopic]
    /// Spellings to highlight: the query, plus the notes' misrecognised forms of a name.
    var terms: [String] = []
    var currentMatch: String?
    var bilingual = true
    var live = false
    /// `partial` is on show (`TranscriptPartial.shows`).
    var partialShown = false
    var jumpTo: Double?
    /// Line id → speaker number for the other side's lines (SpeakerLabels).
    var speakers: [String: Int] = [:]
    /// When listening began, for the start mark shown before the first line.
    var startedAt: Date?
    /// Speech is coming in but its language isn't known yet: 此刻 says so instead of waiting.
    var identifying = false
    /// Voice → speaker number on show; with `onAssign`, a paragraph's name opens "这段是谁说的".
    var voices: [Int: Int] = [:]
    /// The voice being edited above: its paragraphs are tinted.
    var marked: Int?
    /// 电脑和会议室 heard both: each paragraph says 现场 or 线上 (RecordList.heardBoth).
    var places = false
    /// Lines the meeting record's own recognizer is still settling: their words may change.
    var settling: Set<String> = []
    /// Lines whose voice is still being heard (`AppModel.voicePending`).
    var voicePending: Set<String> = []
    var onAssign: ((Set<String>, Int) -> Void)?
    /// 改回 on a fixed word: the line goes back to what was heard.
    var onRevert: ((String, LineFix) -> Void)?
    /// Debug renders: every fixed paragraph shows its words as if pointed at.
    var revealFixes = false
    @ViewBuilder var partial: Partial

    @State private var assigning: String?
    @State private var hovered: String?

    @State private var following = true
    @State private var seenCount = 0
    @State private var followQueued = false

    static func == (a: Self, b: Self) -> Bool {
        a.lines == b.lines && a.topics == b.topics && a.terms == b.terms && a.currentMatch == b.currentMatch
            && a.bilingual == b.bilingual && a.live == b.live && a.partialShown == b.partialShown
            && a.jumpTo == b.jumpTo && a.speakers == b.speakers && a.startedAt == b.startedAt && a.voices == b.voices && a.marked == b.marked
            && a.identifying == b.identifying && a.places == b.places && a.settling == b.settling
            && a.voicePending == b.voicePending
    }

    private var searching: Bool { !terms.isEmpty }

    private var groups: [(title: String, start: Double, lines: [TranscriptLine])] {
        guard !topics.isEmpty else { return [("", 0, lines)] }
        var out: [(String, Double, [TranscriptLine])] = []
        for (i, t) in topics.enumerated() {
            let end = i + 1 < topics.count ? topics[i + 1].start : .infinity
            let first = i == 0 ? -Double.infinity : t.start
            let ls = lines.filter { $0.t >= first && $0.t < end }
            if !ls.isEmpty { out.append((t.title, t.start, ls)) }
        }
        return out
    }

    /// One lazy child: a topic's title, or a paragraph (one person's lines close together).
    private enum Item: Identifiable {
        case header(title: String, start: Double, gap: Bool)
        case paragraph([TranscriptLine], label: Bool)
        var id: String {
            switch self {
            case .header(_, let start, _): "group-\(start)"
            case .paragraph(let ls, _): ls[0].id
            }
        }
    }

    private var items: [Item] {
        let gs = groups
        let starts = SpeakerLabels.runStarts(lines, speakers)
        var out: [Item] = []
        for (gi, g) in gs.enumerated() {
            if !g.title.isEmpty { out.append(.header(title: g.title, start: g.start, gap: gi > 0)) }
            for (i, p) in TranscriptParagraphs.group(g.lines, speakers, pending: voicePending).enumerated() {
                // With voices told apart, a name only where the speaker changes (and atop each topic).
                // Every paragraph carries its name when voices are on: it is also where it's corrected.
                out.append(.paragraph(p, label: speakers.isEmpty || !voices.isEmpty || i == 0 || starts.contains(p[0].id)))
            }
        }
        return out
    }

    /// The scroll target for a line: the paragraph it is in.
    private func target(_ line: TranscriptLine) -> String {
        for item in items { if case .paragraph(let ls, _) = item, ls.contains(where: { $0.id == line.id }) { return item.id } }
        return line.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            switch item {
                            case .header(let title, let start, let gap):
                                Text("\(NotesEngine.clock(start)) · \(title)")
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.secondary)
                                    .padding(.top, gap ? 16 : 6).padding(.bottom, 10)
                            case .paragraph(let ls, let label):
                                row(ls, label: label).padding(.bottom, 4)
                            }
                        }
                        if partialShown {
                            partial.id("partial")
                        }
                        if lines.isEmpty && !partialShown {
                            if live {
                                TranscriptWaitingView(startedAt: startedAt, identifying: identifying)
                            } else {
                                Text("说话的内容会出现在这里").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                                    .frame(maxWidth: .infinity).padding(.top, 40)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom").bottomMarker()
                    }
                    .padding(.top, 8).padding(.bottom, 12)
                }
                .onLegacyBottomDistance { distance in
                    // macOS 14: only the reader's own scrolling changes following; anything else that
                    // moves the bottom (new lines, translations, resizing) is followed.
                    if UserScroll.recent {
                        if distance < 40 { if !following { following = true } }
                        else if following, distance > 60 { following = false; seenCount = lines.count }
                    } else if following, distance > 1 {
                        follow(proxy)
                    }
                }
                .topFade()
                .onScrollEdgeChange { old, new in
                    if new.height != old.height || new.container != old.container {
                        // Not only new lines move the bottom: a translation arriving under its line,
                        // topic headers from a notes update, rows the lazy stack only now measured,
                        // the window resizing. Following means staying on the newest line through all of them.
                        if new.distance > 1 { follow(proxy) }
                    } else if new.distance < 40 {
                        if !following { following = true }
                    } else if following, new.distance > 60, UserScroll.recent {
                        // The reader scrolled up (content growing or reflowing never pauses following).
                        following = false
                        seenCount = lines.count
                    }
                }
                .onChange(of: lines.count) { _, _ in follow(proxy) }
                .onChange(of: partialShown) { _, _ in follow(proxy) }
                .onChange(of: currentMatch) { _, id in
                    guard let id, let line = lines.first(where: { $0.id == id }) else { return }
                    reveal(line, anchor: .center, proxy)
                }
                .onChange(of: jumpTo) { _, t in
                    guard let t, let target = lines.first(where: { $0.t >= t - 1 }) ?? lines.last else { return }
                    following = false
                    seenCount = lines.count
                    reveal(target, anchor: .top, proxy)
                }
                .onAppear {
                    UserScroll.install()
                    seenCount = lines.count
                    if let t = jumpTo, let target = lines.first(where: { $0.t >= t - 1 }) {
                        following = false
                        reveal(target, anchor: .top, proxy)
                    } else if live {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }

                if live, !following, !searching, lines.count > seenCount {
                    newLinesButton { following = true; proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    /// A row the lazy stack hasn't drawn yet lands where its height was guessed: jump, then settle
    /// once it is measured.
    private func reveal(_ line: TranscriptLine, anchor: UnitPoint, _ proxy: ScrollViewProxy) {
        let id = target(line)
        proxy.scrollTo(id, anchor: anchor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    /// Once per turn of the run loop, after layout: scrolling from inside a layout pass, while rows
    /// are still being measured, could leave the view past the end of what is drawn (a blank window).
    private func follow(_ proxy: ScrollViewProxy) {
        guard live, following, !searching, !followQueued else { return }
        followQueued = true
        DispatchQueue.main.async {
            followQueued = false
            guard following, !searching else { return }
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func newLinesButton(_ action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).frame(height: 40)
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .bold))
                    Text("\(lines.count - seenCount) 句新内容").font(.system(size: 13, weight: .semibold))
                    if let last = lines.last {
                        Text(last.shown).font(.system(size: 13)).foregroundStyle(Color(white: 0.74)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 14).padding(.trailing, 18).frame(height: 40)
                .background(Capsule().fill(Palette.ink).shadow(color: .black.opacity(0.18), radius: 12, y: 6))
                .frame(maxWidth: 380)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .transition(.opacity)
    }

    private func matches(_ l: TranscriptLine) -> Bool {
        terms.contains { l.shown.localizedCaseInsensitiveContains($0) || (l.dst ?? "").localizedCaseInsensitiveContains($0) }
    }

    private func highlighted(_ text: String, current: Bool) -> AttributedString {
        highlighted(AttributedString(text), current: current)
    }

    private func highlighted(_ base: AttributedString, current: Bool) -> AttributedString {
        var a = base
        for term in terms where !term.isEmpty {
            var from = a.startIndex
            while from < a.endIndex, let r = a[from...].range(of: term, options: .caseInsensitive) {
                a[r].backgroundColor = current ? Palette.accent : Palette.accentPale
                a[r].foregroundColor = current ? .white : Palette.accentInk
                from = r.upperBound
            }
        }
        return a
    }

    private func row(_ ls: [TranscriptLine], label: Bool = true) -> some View {
        let l = ls[0]
        let isMatch = ls.contains { $0.id == currentMatch }
        let latest = live && ls.last?.id == lines.last?.id
        let dim = searching && !ls.contains(where: matches)
        let src = TranscriptParagraphs.joinFixed(ls)
        let dst = TranscriptParagraphs.join(ls.compactMap { $0.dst != $0.src && $0.dst != $0.shown ? $0.dst : nil })
        let fixed = ls.flatMap { l in (l.fixes ?? []).filter(\.applied).map { (l.id, $0) } }
        return HStack(alignment: .top, spacing: 12) {
            Text(NotesEngine.clock(l.t)).font(.system(size: 12, weight: isMatch ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(latest || isMatch ? Palette.accentInk : Palette.tertiary)
                .frame(width: l.t >= 3600 ? 56 : 40, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !label {
                    } else if l.speaker == "me" { MeTag() }
                    else if onAssign != nil, !voices.isEmpty {
                        Button { assigning = assigning == l.id ? nil : l.id } label: {
                            HStack(spacing: 4) {
                                if let n = speakers[l.id] { SpeakerTag(number: n) } else { UnknownSpeakerTag() }
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.tertiary)
                            }
                            .padding(.horizontal, assigning == l.id ? 6 : 0).frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 6).fill(assigning == l.id ? Color.white : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(ls.count > 1 ? L("这段是谁说的") : L("这句是谁说的"))
                    }
                    else if let n = speakers[l.id] { SpeakerTag(number: n) }
                    else if !speakers.isEmpty { UnknownSpeakerTag() }
                    if places, label, l.speaker != "me" { PlaceTag(line: l) }
                    if live, ls.contains(where: { settling.contains($0.id) }) {
                        Spacer(minLength: 4)
                        Text("校准中").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                            .help(L("文字稍后会再校准一次，字幕不受影响"))
                    }
                }
                Text(highlighted(src, current: isMatch)).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                if bilingual, !dst.isEmpty {
                    Text(highlighted(dst, current: isMatch)).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        .lineSpacing(2).textSelection(.enabled)
                }
                // 改正听错的词: pointing at the paragraph shows what each fixed word was heard as.
                // The line being said is shown open too: hover in the notes panel, which never takes
                // focus, is not to be counted on.
                if hovered == l.id || revealFixes || latest, !fixed.isEmpty, let onRevert {
                    FixedWords(fixes: fixed, onRevert: onRevert).padding(.top, 2)
                }
                if assigning == l.id, let onAssign {
                    LineSpeakerPicker(voices: voices, current: l.voice.flatMap { voices[$0] != nil ? $0 : nil },
                                      nearby: nearby(ls), several: ls.count > 1) { v in
                        assigning = nil
                        onAssign(Set(ls.map(\.id)), v)
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            assigning == l.id ? Palette.fill
            : latest || isMatch ? Palette.accentWash
            : marked != nil && ls.contains(where: { $0.voice == marked }) ? SpeakerColor.ink(voices[marked!] ?? 1).opacity(0.07)
            : Color.clear))
        .opacity(dim ? 0.5 : 1)
        .onHover { inside in
            if inside { hovered = l.id } else if hovered == l.id { hovered = nil }
        }
    }

}

extension TranscriptListView {
    /// The voices speaking just before and after a paragraph, most likely the right one.
    func nearby(_ ls: [TranscriptLine]) -> [Int] {
        guard let i = lines.firstIndex(where: { $0.id == ls[0].id }) else { return [] }
        let j = i + ls.count
        var out: [Int] = []
        for k in [i - 1, j, i - 2, j + 1] where lines.indices.contains(k) {
            if let v = lines[k].voice, voices[v] != nil, !out.contains(v), !ls.contains(where: { $0.voice == v }) { out.append(v) }
        }
        return out
    }
}

/// The notes window's transcript reads as paragraphs: one person's lines within 30 seconds of the
/// paragraph's first are one block, one time, instead of a row and a rule for every fragment.
/// A fast speaker fills 30 seconds with a wall of text (issue #20): a paragraph that has reached
/// `full` takes no more lines.
enum TranscriptParagraphs {
    static let span: Double = 30
    /// Two or three sentences: Chinese or Japanese characters, or words.
    static let full = (cjk: 80, words: 40)

    static func isFull(_ lines: [TranscriptLine]) -> Bool {
        let text = lines.map(\.src).joined(separator: " ")
        let cjk = text.unicodeScalars.contains { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) }
        return cjk ? text.filter(\.isLetter).count >= full.cjk : text.split(whereSeparator: \.isWhitespace).count >= full.words
    }

    static func group(_ lines: [TranscriptLine], _ speakers: [String: Int], pending: Set<String> = []) -> [[TranscriptLine]] {
        var out: [[TranscriptLine]] = []
        var key: String?
        // Before any number is on show (two voices with five lines each), a question and its answer
        // would read as one block: a known voice that differs from the paragraph's starts a new one.
        // Short lines' voices are left out, as for numbers: they are too often wrong. A line with no
        // voice was like none heard so far (or too short to start one): next to a known voice that is
        // more often someone else ("Great." / "Let's lock that in" after the answer), so it counts as
        // a voice of its own (`noVoice`), which the paragraphs' voices then hold. One still being
        // heard (`pending`) stays put meanwhile rather than jump out and back.
        var voice: Int?
        let noVoice = -1
        for l in lines {
            let k = (l.speaker == "me" ? "me" : speakers[l.id].map { "n\($0)" } ?? "?") + (l.via ?? "")
            let heard = l.voice.map { SpeakerLabels.substantive(l.src) ? $0 : nil } ?? (pending.contains(l.id) ? nil : noVoice)
            let v = speakers.isEmpty && l.speaker == "them" ? heard : nil
            if k == key, let p = out.last, let first = p.first, l.t - first.t <= span, !isFull(p),
               voice == nil || v == nil || v == voice {
                out[out.count - 1].append(l)
                voice = voice ?? v
            } else {
                out.append([l])
                voice = v
            }
            key = k
        }
        return out
    }

    /// The lines as shown, each fixed word with a dotted underline.
    static func joinFixed(_ lines: [TranscriptLine]) -> AttributedString {
        var out = AttributedString()
        var plain = ""
        for l in lines {
            let (text, marks) = Correction.apply(l.fixes ?? [], to: l.src)
            let p = text.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            if let last = plain.unicodeScalars.last, !(last.properties.isIdeographic || "。！？，、；：”）".unicodeScalars.contains(last)) {
                out += AttributedString(" ")
                plain += " "
            }
            var a = AttributedString(text)
            for m in marks {
                guard let lo = AttributedString.Index(m.lowerBound, within: a), let hi = AttributedString.Index(m.upperBound, within: a) else { continue }
                a[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot, color: Palette.tertiary)
            }
            // Words waiting for the user (这样改对吗？) get a pale wash, as heard.
            for f in l.fixes ?? [] where f.ask == true {
                if let r = a.range(of: f.from) { a[r].backgroundColor = Palette.accentPale }
            }
            out += a
            plain += text
        }
        return out
    }

    /// Sentences side by side: a space between words, none after Chinese or Japanese.
    static func join(_ parts: [String]) -> String {
        var out = ""
        for p in parts.map({ $0.trimmingCharacters(in: .whitespaces) }) where !p.isEmpty {
            if let last = out.unicodeScalars.last, !(last.properties.isIdeographic || "。！？，、；：”）".unicodeScalars.contains(last)) {
                out += " "
            }
            out += p
        }
        return out
    }
}

enum TranscriptPartial {
    /// The caption keeps the last sentence after it is finished: only show text not yet a line.
    static func shows(_ partial: String, live: Bool, after last: String?) -> Bool {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        // A lone "." from background noise is not someone speaking.
        guard live, p.rangeOfCharacter(from: .alphanumerics) != nil else { return false }
        guard let last else { return true }
        return !last.contains(p) && !p.contains(last)
    }
}

/// The line being spoken, under the transcript. It watches the app itself so each new word redraws
/// only this row (`TranscriptListView` decides whether it shows).
struct LivePartialRow: View {
    @ObservedObject var model: AppModel
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let time = startedAt.map { max(0, ctx.date.timeIntervalSince($0)) }
            HStack(alignment: .top, spacing: 12) {
                Text(time.map(NotesEngine.clock) ?? "").font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.accentInk)
                    .frame(width: (time ?? 0) >= 3600 ? 56 : 40, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text(model.liveSource).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(2)
                        AnimatedDots().font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    }
                    Text("正在说").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }
}

extension View {
    /// A scroll view's top edge fades to white, so a line scrolled half out of view doesn't look cut off.
    func topFade(_ height: CGFloat = 24) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: height)
                Color.black
            }
        }
    }

}

/// The transcript before anyone has spoken: the start mark, two rows in the bilingual shape
/// lines will take, and 此刻 waiting for the first words.
struct TranscriptWaitingView: View {
    var startedAt: Date?
    var identifying = false

    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let startedAt { Text(Self.time.string(from: startedAt)).monospacedDigit() }
                Rectangle().fill(MainWindowView.hairline).frame(height: 1)
                Text("从这里开始听")
            }
            .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            .padding(.bottom, 14)
            FramedList {
                skeletonRow(0.7, 0.88)
                Divider()
                skeletonRow(0.54, 0.66).opacity(0.55)
            }
            HStack(spacing: 16) {
                legend(Palette.placeholder.opacity(0.6), L("原话"))
                legend(Palette.ink, L("译文"))
            }
            .padding(.top, 10).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("此刻").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accentInk)
                HStack(spacing: 3) {
                    Text(identifying ? L("正在识别语言…") : L("等有人开口")).font(.system(size: 15)).foregroundStyle(Palette.tertiary)
                    BlinkingCaret()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.raised))
            .padding(.top, 28)
        }
        .padding(.top, 8)
    }

    private func skeletonRow(_ a: CGFloat, _ b: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBar(fraction: a, height: 9)
            SkeletonBar(fraction: b, height: 11)
        }
        .padding(14)
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(title)
        }
        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
    }
}

/// A text caret blinking once a second.
struct BlinkingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Rectangle().fill(Palette.accent).frame(width: 2, height: 17)
                .opacity(Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Small parts

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.secondary)
    }
}

struct Tag: View {
    let text: String
    var live = false
    init(_ text: String, live: Bool = false) {
        self.text = text
        self.live = live
    }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(live ? Palette.accentInk : Palette.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(live ? Palette.accentPale : Palette.fill))
            .fixedSize()
    }
}

/// 人名和术语: the corrected spellings first (what the reader can't work out alone), at most
/// `shown` until asked for the rest. All of them still go to the translation glossary.
struct TermChips: View {
    static let shown = 8
    let terms: [NoteTerm]
    var showHeard = true
    @State private var all = false

    var body: some View {
        let list = NoteTerm.ordered(terms)
        let extra = list.count - Self.shown
        FlowLayout(spacing: 6) {
            ForEach(all || extra <= 0 ? list : Array(list.prefix(Self.shown))) { t in
                // What was misheard goes on its own small line, so a long note wraps beside the name.
                VStack(alignment: .leading, spacing: 1) {
                    (Text(t.name).bold() + Text(t.note.isEmpty ? "" : " \(t.note)"))
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    if showHeard, !t.heard.isEmpty {
                        Text("原识别 \(t.heard.prefix(2).joined(separator: "、"))")
                            .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
            }
            if extra > 0 {
                Button(all ? L("收起") : L("展开全部 \(list.count) 个")) { all.toggle() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 5)
            }
        }
    }
}

struct FramedList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }
}

/// Wraps chips onto as many lines as needed. A chip wider than the row is given the row's width,
/// so its text wraps inside it instead of running past the edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func size(_ v: LayoutSubview, _ width: CGFloat) -> CGSize {
        let ideal = v.sizeThatFits(.unspecified)
        return ideal.width <= width ? ideal : v.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = size(v, width)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = size(v, bounds.width)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

// MARK: - Motion (notes in progress)
// One moving thing at a time says the app is working. Driven by TimelineView rather than
// repeatForever animations, which the window's once-a-second redraw would restart.

func phase(_ date: Date, period: Double, delay: Double = 0) -> Double {
    let t = date.timeIntervalSinceReferenceDate - delay
    return (t.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period) / period
}

/// A small orange ring spinner.
struct Spinner: View {
    var size: CGFloat = 16
    var track = Palette.accentPale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            ZStack {
                Circle().stroke(track, lineWidth: 2)
                Circle().trim(from: 0, to: 0.25)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(phase(ctx.date, period: 0.9) * 360))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// "…" whose dots light up one after another.
struct AnimatedDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Text(".").opacity(0.3 + 0.7 * (0.5 - 0.5 * cos(phase(ctx.date, period: 1.2, delay: Double(i) * 0.2) * 2 * .pi)))
                }
            }
        }
    }
}

/// The live dot beside "正在记录", breathing slowly.
/// 共享屏幕时让对方看到 as a lamp. On: an orange dot whose halo breathes outward, the first
/// breath a wider ring so turning it on is seen without any words (words would show in the
/// shared screen). Off: a small hollow grey ring, quiet. Reduce Motion holds the halo still.
struct CapturableMark: View {
    let on: Bool
    /// The dot's diameter; the halo spills past it, so leave room around the mark.
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var since = Date()

    private static let off = Color(red: 0.663, green: 0.682, blue: 0.722) // #A9AEB8

    var body: some View {
        Group {
            if !on {
                Circle().strokeBorder(Self.off, lineWidth: 1.5)
            } else if reduceMotion {
                Circle().fill(Palette.accent).background(Circle().fill(Palette.accent).opacity(0.25).scaleEffect(1.6))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let age = ctx.date.timeIntervalSince(since)
                    // Starts expanding the moment it turns on: 0 → 1 → 0 over 2.4 s.
                    let t = 0.5 - 0.5 * cos(phase(ctx.date, period: 2.4, delay: since.timeIntervalSinceReferenceDate) * 2 * .pi)
                    let first = min(1, age / 0.7)
                    ZStack {
                        Circle().fill(Palette.accent).scaleEffect(1 + 0.9 * t).opacity(0.5 * (1 - t))
                        if first < 1 {
                            Circle().stroke(Palette.accent, lineWidth: 1.5).scaleEffect(1 + 1.6 * first).opacity(0.7 * (1 - first))
                        }
                        Circle().fill(Palette.accent)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: on) { _, now in if now { since = Date() } }
    }
}

struct LiveDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            Circle().fill(Palette.accent).frame(width: 7, height: 7)
                .opacity(0.35 + 0.65 * (0.5 + 0.5 * cos(phase(ctx.date, period: 1.4) * 2 * .pi)))
        }
    }
}

/// A placeholder line with a light sweeping across it. `warm` is the pale orange used inside
/// the topic being updated.
struct SkeletonBar: View {
    var fraction: CGFloat = 1
    var height: CGFloat = 12
    var warm = false

    var body: some View {
        let base = warm ? Color(red: 0.965, green: 0.89, blue: 0.86) : Color(red: 0.933, green: 0.941, blue: 0.953)
        let light = warm ? Color(red: 0.992, green: 0.953, blue: 0.933) : Color(red: 0.969, green: 0.973, blue: 0.98)
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let x = phase(ctx.date, period: 1.4) * 2 - 0.5
                RoundedRectangle(cornerRadius: min(6, height / 2))
                    .fill(LinearGradient(stops: [.init(color: base, location: 0), .init(color: light, location: 0.5),
                                                 .init(color: base, location: 1)],
                                         startPoint: UnitPoint(x: x - 0.6, y: 0.5), endPoint: UnitPoint(x: x + 0.6, y: 0.5)))
                    .frame(width: g.size.width * fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Listening, no notes asked for yet: one quiet status row, then the notes' own shape waiting to be
/// filled, so the first version lands where the reader is already looking.
struct NotesListeningView: View {
    /// Lines heard so far; the first notes request waits for a few of them.
    var heard = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                SoundBars()
                Text("有人开口后，约半分钟出第一版").font(.system(size: 13)).foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if heard > 0 {
                    Text("已听到 \(heard) 句").font(.system(size: 12)).foregroundStyle(Palette.tertiary).fixedSize()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale.opacity(0.7)))
            VStack(alignment: .leading, spacing: 10) {
                Text("总结").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                SkeletonBar(fraction: 0.94, height: 10)
                SkeletonBar(fraction: 0.8, height: 10)
                SkeletonBar(fraction: 0.56, height: 10)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("议题").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                topicSlot(time: "00:00", lines: [0.52, 0.88, 0.7])
                topicSlot(time: "--:--", lines: [0.4, 0.76]).opacity(0.6)
            }
            // Wraps: the English chips don't fit one line in a narrow window.
            FlowLayout(spacing: 6) {
                Text("会整理出").font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.vertical, 4)
                ForEach([L("结论"), L("待办"), L("人名和术语"), L("鱼骨图")], id: \.self) { t in
                    Text(t).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.fill))
                }
            }
            .padding(.top, 4)
        }
    }

    private func topicSlot(time: String, lines: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.placeholder)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, f in
                    SkeletonBar(fraction: f, height: i == 0 ? 11 : 8)
                }
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

/// Four small orange bars rising and falling: "listening", at the size of a line of text.
struct SoundBars: View {
    var height: CGFloat = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let p = phase(ctx.date, period: 1.1, delay: Double(i) * 0.15)
                    Capsule().fill(Palette.accent).frame(width: 3, height: height)
                        .scaleEffect(x: 1, y: 0.3 + 0.7 * (0.5 - 0.5 * cos(p * 2 * .pi)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The first version of the notes is being written: a spinner, how much has been heard, and
/// the shape of the notes shimmering where they will appear.
struct NotesGeneratingView: View {
    var heard: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Spinner()
                HStack(spacing: 0) {
                    Text("正在生成纪要")
                    AnimatedDots()
                }
                .font(.system(size: 15, weight: .bold))
                Spacer()
                if let heard, heard > 0 {
                    Text("已听到 \(heard) 句").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("总结").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                SkeletonBar()
                SkeletonBar(fraction: 0.92)
                SkeletonBar(fraction: 0.64)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
            VStack(alignment: .leading, spacing: 14) {
                Text("议题").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                topicRow(lines: [0.55, 0.88, 0.72])
                topicRow(lines: [0.42, 0.8]).opacity(0.6)
            }
        }
    }

    private func topicRow(lines: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBar(height: 12).frame(width: 36)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, f in
                    SkeletonBar(fraction: f, height: i == 0 ? 14 : 10)
                }
            }
        }
    }
}

struct FadeIn: ViewModifier {
    let active: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!active || shown ? 1 : 0)
            .offset(y: !active || shown ? 0 : 4)
            .onAppear { if active { withAnimation(.easeOut(duration: 0.6)) { shown = true } } }
    }
}

/// "已经 10 分钟没人说话 · 60 秒后结束": the meeting is about to end by itself. In the notes window
/// and the menu panel; neither takes focus, so a click lands on the buttons at once.
struct MeetingEndingStrip: View {
    @ObservedObject var model: AppModel
    let pending: MeetingEndWatch.Pending
    var compact = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.endingTitle(pending)).font(.system(size: compact ? 13 : 14, weight: .bold)).lineLimit(2)
                Text(model.endingDetail(pending, now: now)).font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                SoftButton(L("继续记录"), dark: true) { model.keepRecording() }
                SoftButton(L("现在结束")) { model.stop() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
        .onReceive(tick) { now = $0 }
    }
}


/// Under a paragraph being pointed at: each fixed word, what it was heard as, and 改回.
struct FixedWords: View {
    let fixes: [(line: String, fix: LineFix)]
    let onRevert: (String, LineFix) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(fixes.enumerated()), id: \.offset) { _, item in
                let c = Correction.label(item.fix)
                HStack(spacing: 6) {
                    (Text("听成").foregroundStyle(Palette.tertiary) + Text(" " + c.from) + Text(" → ").foregroundStyle(Palette.tertiary) + Text(c.to))
                        .font(.system(size: 11))
                    Button(L("改回")) { onRevert(item.line, item.fix) }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.link)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
            }
        }
    }
}

/// 这样改对吗？: a name the Mac couldn't check by sound, asked about once. Clicks only: the notes
/// window never takes focus. 对 fixes every line waiting on it and adds it to the word list.
struct FixConfirmCard: View {
    let line: TranscriptLine
    let fix: LineFix
    let count: Int
    let onAnswer: (Bool) -> Void
    /// ×: 稍后再看, asked again after the meeting.
    var onLater: (() -> Void)? = nil

    var body: some View {
        let c = Correction.label(fix)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("这样改对吗？").font(.system(size: 13, weight: .semibold))
                Text("确认后整场一起改，以后也这样改").font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(1)
                Spacer(minLength: 4)
                if count > 1 { Text("1 / \(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary) }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(c.from) + Text(" → ").foregroundStyle(Palette.tertiary) + Text(c.to).bold()).font(.system(size: 14))
                    Text("\(NotesEngine.clock(line.t)) · \(line.src)").font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { onAnswer(true) } label: {
                    Text("对").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Palette.ink))
                }.buttonStyle(.plain)
                Button { onAnswer(false) } label: {
                    Text("不对").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 14).frame(height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
                }.buttonStyle(.plain)
                if let onLater {
                    Button(action: onLater) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
                            .frame(width: 26, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(L("稍后再看")).accessibilityLabel(L("稍后再看"))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// 人名和术语, the fixing part: each word fixed in this meeting with what it was heard as and how
/// often (a click shows those lines), and the names still waiting, with ✓ and ×.
struct FixTermsView: View {
    @ObservedObject var fixes: LiveFixes
    let session: Session
    let onShow: (String) -> Void

    var body: some View {
        let words = Self.fixedWords(session)
        let waiting = fixes.pending(in: session.id)
        VStack(alignment: .leading, spacing: 8) {
            if !words.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.word) { w in
                        Button { onShow(w.word) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.word).font(.system(size: 12)).bold().foregroundStyle(Palette.ink)
                                Text("听成 \(w.heard.prefix(2).joined(separator: "、")) · 改了 \(w.count) 处")
                                    .font(.system(size: 11)).foregroundStyle(Palette.link)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !waiting.isEmpty {
                Text("等你确认，还没改").font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.top, 2)
                ForEach(Array(waiting.enumerated()), id: \.offset) { _, w in
                    let c = Correction.label(w.fix)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.to).font(.system(size: 13)).bold()
                            Text("听成 \(c.from)").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                        }
                        Spacer(minLength: 4)
                        Button { fixes.answer(w.fix, yes: true, in: session.id) } label: {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Palette.ink))
                        }
                        .buttonStyle(.plain).accessibilityLabel(L("对"))
                        Button { fixes.answer(w.fix, yes: false, in: session.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
                        }
                        .buttonStyle(.plain).accessibilityLabel(L("不对"))
                    }
                    .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color(white: 0.8)))
                }
            }
        }
    }

    /// The words fixed in a meeting, most fixed first: what each was heard as, and how often.
    static func fixedWords(_ s: Session) -> [(word: String, heard: [String], count: Int)] {
        var out: [String: (heard: [String], count: Int)] = [:]
        for l in s.lines {
            for f in l.fixes ?? [] where f.applied {
                let c = Correction.label(f)
                let word = c.to.trimmingCharacters(in: .whitespaces)
                var e = out[word] ?? ([], 0)
                if !e.heard.contains(c.from) { e.heard.append(c.from) }
                e.count += 1
                out[word] = e
            }
        }
        // Ties by word: a Dictionary's order differs with each instance, and this runs on every
        // redraw (the window ticks each second), so the chips would swap places.
        return out.map { ($0.key, $0.value.heard, $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word < $1.word }
    }
}
