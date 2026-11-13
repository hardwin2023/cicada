import SwiftUI

// The 说话人识别 controls in the notes and records windows; the engine is in SpeakerID.swift.

/// Colours for 说话人 1, 2, 3…, cycling after four: not the accent ("live", and 你) nor link blue
/// (times in the records window), distinct in lightness, all ≥ 4.5:1 on white.
enum SpeakerColor {
    private static let inks: [Color] = [Color(red: 0.059, green: 0.482, blue: 0.424), Color(red: 0.478, green: 0.298, blue: 0.761),
                                        Color(red: 0.690, green: 0.227, blue: 0.478), Color(red: 0.541, green: 0.353, blue: 0)]
    static func ink(_ n: Int) -> Color { inks[(max(1, n) - 1) % inks.count] }
}

/// "说话人 2" above a line.
/// The names given to voices in the meeting on show, by speaker number (set on the transcript's container).
private struct SpeakerNamesKey: EnvironmentKey { static let defaultValue: [Int: String] = [:] }
extension EnvironmentValues {
    var speakerNames: [Int: String] {
        get { self[SpeakerNamesKey.self] }
        set { self[SpeakerNamesKey.self] = newValue }
    }
}

struct SpeakerTag: View {
    let number: Int
    @Environment(\.speakerNames) private var names
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(SpeakerColor.ink(number)).frame(width: 6, height: 6)
            Text(SpeakerLabels.label(number, names)).font(.system(size: 11, weight: .semibold)).foregroundStyle(SpeakerColor.ink(number))
        }
    }
}

/// 现场 / 线上 beside a line in a meeting that heard the room and the Mac together.
struct PlaceTag: View {
    let line: TranscriptLine
    var body: some View {
        Text(RecordList.place(line)).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(line.via == "room" ? Palette.fill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line, lineWidth: line.via == "room" ? 0 : 1))
            .help(line.via == "room" ? L("会议室的麦克风听到的") : L("电脑里放出来的"))
    }
}

/// Your own line: said with the talk key, so what the other side heard was its translation (同传).
struct MeTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("你").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk)
            Text("同传").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accentInk)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.accent.opacity(0.45), lineWidth: 1))
        }
        .help(L("按住说话键说的，对方听到的是译文"))
    }
}

/// A line from the other side whose voice isn't one of the people on show.
struct UnknownSpeakerTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().strokeBorder(Palette.tertiary, lineWidth: 1).frame(width: 6, height: 6)
            Text("未识别").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }
        .help(L("没认出是谁：太短，或和已知的声音都不像"))
    }
}

/// Above the transcript once voices are told apart: who is speaking, and a one-click way out. Each
/// person opens `SpeakerEditor`: a popover in the records window; in the notes window (`editing`
/// set) a card right below the row, since a popover in a panel that never activates the app closes
/// as soon as it opens.
struct SpeakerStrip: View {
    @ObservedObject var model: AppModel
    let session: Session
    /// The notes window's voice being edited: the editor opens inline instead of as a popover.
    var editing: Binding<Int?>? = nil
    @State private var popover: Int?

    var body: some View {
        let numbers = SpeakerLabels.voiceNumbers(session)
        let names = SpeakerLabels.names(session)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(numbers.sorted { $0.value < $1.value }, id: \.key) { voice, n in
                        let on = (editing?.wrappedValue ?? popover) == voice
                        Button {
                            if let editing { editing.wrappedValue = on ? nil : voice } else { popover = voice }
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(on ? Color.white : SpeakerColor.ink(n)).frame(width: 6, height: 6)
                                Text(SpeakerLabels.label(n, names)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(on ? Color.white : SpeakerColor.ink(n))
                            }
                            .fixedSize()
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(on ? SpeakerColor.ink(n) : SpeakerColor.ink(n).opacity(0.08)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(SpeakerLabels.guessed(session)[n].map { _ in L("Ling 从对话里认出，点一下可以改") } ?? L("改名字，或和别人合并"))
                        .popover(isPresented: Binding(get: { editing == nil && popover == voice }, set: { if !$0 { popover = nil } }), arrowEdge: .bottom) {
                            SpeakerEditor(model: model, namer: model.speakerNamer, sessionID: session.id, voice: voice) { popover = nil }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { model.settings.speakerVoices = false } label: {
                    Text("不准？关掉").font(.system(size: 11)).foregroundStyle(Palette.secondary).underline().fixedSize()
                }
                .buttonStyle(.plain)
                .frame(height: 22)
                .help(L("关掉说话人识别，记录里的名字一起收起"))
            }
            if let editing, let voice = editing.wrappedValue, numbers[voice] != nil {
                SpeakerEditor(model: model, namer: model.speakerNamer, sessionID: session.id, voice: voice, inline: true) {
                    editing.wrappedValue = nil
                    model.notesWindow.returnKeyboard()
                }
                .id(voice)
            }
        }
        .onAppear { model.speakerNamer.guess(session.id) }
    }
}

/// Correct one voice: its name (Ling's guess and people from 人名和术语 are a click away), or merge it
/// into another voice. `inline` (the notes window): a click on a name or a merge applies at once.
struct SpeakerEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var namer: SpeakerNamer
    let sessionID: String
    let voice: Int
    var inline = false
    let close: () -> Void
    @State private var draft = ""
    @State private var allMerges = false
    @FocusState private var typing: Bool

    private var session: Session? { model.store.session(sessionID) }

    var body: some View {
        // Gone once merged into someone else: the editor closes on the next turn.
        if let s = session, let n = SpeakerLabels.voiceNumbers(s)[voice] {
            let numbers = SpeakerLabels.voiceNumbers(s)
            let names = SpeakerLabels.names(s)
            let guess = SpeakerLabels.guessed(s)[n]
            let suggestion = model.speakerSuggestion(session: s.id, voice: voice)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(SpeakerColor.ink(n)).frame(width: 8, height: 8)
                    Text(SpeakerLabels.label(n, names)).font(.system(size: 14, weight: .bold))
                    Text("说了 \(s.lines.filter { $0.voice == voice }.count) 句").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    Spacer()
                    if inline {
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                                .frame(width: 24, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("收起").accessibilityLabel(L("收起"))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("是谁").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                    let picks = suggestions(s, names: names, number: n, guess: guess)
                    if !picks.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(picks, id: \.self) { name in
                                choice(name, dark: name == names[n]) {
                                    if inline { apply(s, guess, name) } else { draft = name }
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField(L("输入名字"), text: $draft).textFieldStyle(.roundedBorder)
                            .focused($typing)
                            .onSubmit { apply(s, guess, draft) }
                            .onExitCommand { close() }
                        if inline, typing || draft != (names[n] ?? "") {
                            SoftButton(L("保存"), dark: true) { apply(s, guess, draft) }
                        }
                    }
                    if inline && typing {
                        // The panel holds the keyboard only while a name is typed; Return or Esc gives it back.
                        Text("键盘暂时在这里，会议软件收不到 · 回车保存 · Esc 交还")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let guess {
                        HStack(alignment: .top, spacing: 8) {
                            Text(guess.evidence.isEmpty ? L("Ling 从对话里认出") : L("Ling 从对话里认出：\(guess.evidence)"))
                                .font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(2)
                            Spacer(minLength: 6)
                            Button(L("不是 TA")) {
                                model.renameSpeaker(session: s.id, voice: voice, "")
                                close()
                            }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    } else if namer.busy.contains(s.id) {
                        Text("Ling 正在从对话里找名字…").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    }
                }
                if let suggestion {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 13)).foregroundStyle(Palette.accentInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("声纹库：可能是 \(suggestion.name)（\(Int((suggestion.similarity * 100).rounded()))%）"))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(L("声音像，但还不够确定。确认后，下次会议会直接认出。"))
                                .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                        }
                        Spacer(minLength: 6)
                        Button(L("是 TA")) {
                            model.acceptSpeakerSuggestion(session: s.id, voice: voice)
                            close()
                        }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk)
                        Button(L("不是")) {
                            model.dismissSpeakerSuggestion(session: s.id, voice: voice)
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.accentPale.opacity(0.55)))
                } else if let known = s.voiceProfiles?[String(voice)] {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 13)).foregroundStyle(Palette.accentInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("声纹库：\(known.name)"))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(L("这次会议按这个声纹标的。认错了可以只断开本次，不会删掉声纹。"))
                                .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                        }
                        Spacer(minLength: 6)
                        Button(L("更新声纹")) {
                            model.rememberSpeaker(session: s.id, voice: voice, name: known.name)
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        Button(L("不是 TA")) {
                            model.forgetSpeaker(session: s.id, voice: voice)
                        }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            model.rememberSpeaker(session: s.id, voice: voice, name: draft.isEmpty ? nil : draft)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "person.badge.plus").font(.system(size: 10))
                                Text(model.speakerMemoryBusy ? L("正在记住…") : L("记住这个声音"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Palette.accentInk).padding(.horizontal, 9).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.accentPale))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.speakerMemoryBusy)
                        .help(L("需要 3 句以上发言；声纹只保存在这台 Mac"))
                        Text(L("下次会议自动认出")).font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                    }
                }
                let others = numbers.filter { $0.key != voice }.sorted { $0.value < $1.value }
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("其实是同一个人").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(allMerges ? others : Array(others.prefix(3)), id: \.key) { other, on in
                                choice(L("并入 \(SpeakerLabels.label(on, names))")) {
                                    model.mergeSpeaker(session: s.id, voice, into: other)
                                    close()
                                }
                            }
                            if others.count > 3 && !allMerges {
                                choice(L("更多")) { allMerges = true }
                            }
                        }
                    }
                }
                if !inline {
                    HStack(spacing: 8) {
                        Spacer()
                        SoftButton(L("取消")) { close() }
                        SoftButton(L("完成"), dark: true) { apply(s, guess, draft) }
                    }
                }
            }
            .padding(inline ? 14 : 16)
            .frame(width: inline ? nil : 320)
            .frame(maxWidth: inline ? .infinity : nil, alignment: .leading)
            .background {
                if inline {
                    RoundedRectangle(cornerRadius: 14).fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                }
            }
            .onAppear { draft = names[n] ?? "" }
        }
    }

    private func choice(_ title: String, dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dark ? Color.white : Palette.ink)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Palette.ink : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(dark ? Palette.ink : Palette.line, lineWidth: 1))
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ling's guess first, then people the notes mention, without names other voices already have.
    private func suggestions(_ s: Session, names: [Int: String], number: Int, guess: VoiceGuess?) -> [String] {
        let taken = Set(names.filter { $0.key != number }.values)
        var out: [String] = []
        if let g = s.voiceGuesses?[String(voice)]?.name ?? guess?.name { out.append(g) }
        for t in NoteTerm.people(s.notes?.terms ?? []) where !out.contains(t) && !taken.contains(t) { out.append(t) }
        if let mine = names[number], !out.contains(mine) { out.insert(mine, at: 0) }
        return Array(out.prefix(4))
    }

    /// Keeping Ling's name stores nothing, so a later, better guess can still replace it.
    private func apply(_ s: Session, _ guess: VoiceGuess?, _ typed: String) {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if let guess, name == guess.name { model.renameSpeaker(session: s.id, voice: voice, nil) }
        else if s.voiceNames?[String(voice)] != nil || !name.isEmpty { model.renameSpeaker(session: s.id, voice: voice, name) }
        close()
    }
}

/// "这句是谁说的": the people on show, the ones speaking just before and after first. Picked → done.
struct LineSpeakerPicker: View {
    /// Voice → speaker number, for the voices on show.
    let voices: [Int: Int]
    let current: Int?
    let nearby: [Int]
    let several: Bool
    let pick: (Int) -> Void
    @Environment(\.speakerNames) private var names

    var body: some View {
        let order = voices.keys.sorted { a, b in
            let ia = nearby.firstIndex(of: a) ?? Int.max, ib = nearby.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : voices[a]! < voices[b]!
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(several ? "这段是谁说的" : "这句是谁说的").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
            FlowLayout(spacing: 6) {
                ForEach(order, id: \.self) { v in
                    let n = voices[v]!
                    Button { pick(v) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(SpeakerColor.ink(n)).frame(width: 6, height: 6)
                            Text(SpeakerLabels.label(n, names)).font(.system(size: 12, weight: .semibold)).foregroundStyle(SpeakerColor.ink(n))
                        }
                        .padding(.horizontal, 9).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(v == current ? SpeakerColor.ink(n) : Palette.line, lineWidth: 1))
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// "说话人 6 已改成 David · 撤销", for a few seconds after a speaker edit.
struct SpeakerUndoToast: View {
    @ObservedObject var model: AppModel
    let session: String?

    var body: some View {
        if let u = model.speakerUndo, u.session == session, !u.text.isEmpty {
            HStack(spacing: 14) {
                Text(u.text).font(.system(size: 13)).foregroundStyle(.white).lineLimit(2)
                Button("撤销") { model.undoSpeakerEdit() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accentPale)
            }
            .padding(.horizontal, 14).frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.ink).shadow(color: .black.opacity(0.2), radius: 12, y: 6))
            .padding(.bottom, 18)
            .transition(.opacity)
        }
    }
}

/// Debug render (`speakersRender`): the people row and the first lines, labelled as the transcript
/// labels them (a name only where the speaker changes).
struct SpeakerPreview: View {
    @ObservedObject var model: AppModel
    let session: Session
    var body: some View {
        let numbers = SpeakerLabels.numbers(session)
        let starts = SpeakerLabels.runStarts(session.lines, numbers)
        VStack(alignment: .leading, spacing: 10) {
            if !numbers.isEmpty { SpeakerStrip(model: model, session: session) }
            ForEach(session.lines.prefix(12)) { l in
                VStack(alignment: .leading, spacing: 3) {
                    if !starts.contains(l.id) {
                    } else if l.speaker == "me" { MeTag() }
                    else if let n = numbers[l.id] { SpeakerTag(number: n) }
                    else if !numbers.isEmpty { UnknownSpeakerTag() }
                    Text(l.shown).font(.system(size: 13)).foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(16)
    }
}
