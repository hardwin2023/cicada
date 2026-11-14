import AppKit
import SwiftUI

/// The local people library: voices remembered by voiceprint, plus what the user knows about the
/// person and a note on how they tend to talk. Voiceprints are biometric data: every row can be
/// removed here, and nothing is uploaded.
struct SpeakerLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var editing: UUID?
    @State private var draft = ""
    @State private var detail: SpeakerProfile?
    @Environment(\.dismiss) private var dismiss

    private var profiles: [SpeakerProfile] { model.speakerProfiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("人员库")).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(L("声纹只保存在这台 Mac；可以写备注、看说话风格，也可以删除。"))
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Button(L("完成")) { dismiss() }.buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accentInk)
            }

            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.badge.key").font(.system(size: 26)).foregroundStyle(Palette.tertiary)
                    Text(L("还没有记住的人")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(L("在会议里点一个说话人，选“记住这个声音”，下次就会自动认出。"))
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(profiles) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    Circle().fill(Palette.accentPale).frame(width: 28, height: 28)
                                        .overlay(Text(String(p.name.prefix(1))).font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Palette.accentInk))
                                    VStack(alignment: .leading, spacing: 2) {
                                        if editing == p.id {
                                            TextField(L("名字"), text: $draft)
                                                .textFieldStyle(.roundedBorder)
                                                .onSubmit { save(p) }
                                        } else {
                                            Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                                        }
                                        Text(L("\(p.sampleCount) 段样本 · 最近 \(seen(p.lastSeenAt))"))
                                            .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                    }
                                    Spacer()
                                    if editing == p.id {
                                        SoftButton(L("保存"), dark: true) { save(p) }
                                        Button(L("取消")) { editing = nil }.buttonStyle(.plain)
                                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                    } else {
                                        Button(L("资料")) { detail = p }.buttonStyle(.plain)
                                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                        Button(L("分析")) { analyze(p) }.buttonStyle(.plain)
                                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                        Button(L("改名")) { editing = p.id; draft = p.name }.buttonStyle(.plain)
                                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                        Button(L("删除")) { delete(p) }.buttonStyle(.plain)
                                            .font(.system(size: 12)).foregroundStyle(Palette.accentInk)
                                    }
                                }
                                if let style = p.style, !style.isEmpty {
                                    Text(style).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 40)
                                }
                                if let notes = p.notes, !notes.isEmpty {
                                    Text(notes).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 40)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 54)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
                }
                HStack {
                    Text(L("共 \(profiles.count) 个人")).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    Spacer()
                    Button(L("全部删除")) { deleteAll() }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accentInk)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
        .background(Color(red: 0.965, green: 0.969, blue: 0.976))
        .sheet(item: $detail) { p in SpeakerProfileEditor(model: model, profile: p) }
    }

    private func save(_ p: SpeakerProfile) {
        model.renameSpeakerProfile(id: p.id, to: draft)
        editing = nil
    }

    private func analyze(_ p: SpeakerProfile) {
        guard model.analyzeSpeakerStyle(id: p.id) != nil else {
            let a = NSAlert()
            a.messageText = L("还没有这个人的发言")
            a.informativeText = L("先在会议里给这个声音命名并记住，分析会从已绑定到这个声纹的发言里归纳。")
            a.addButton(withTitle: L("知道了"))
            a.runModal()
            return
        }
    }

    private func delete(_ p: SpeakerProfile) {
        let a = NSAlert()
        a.messageText = L("删除“\(p.name)”的声纹？")
        a.informativeText = L("之后的会议不会再自动认出这个人；已经生成的记录保持原样。")
        a.addButton(withTitle: L("删除"))
        a.addButton(withTitle: L("取消"))
        if a.runModal() == .alertFirstButtonReturn { model.deleteSpeakerProfile(id: p.id) }
    }

    private func deleteAll() {
        let a = NSAlert()
        a.messageText = L("删除全部声纹？")
        a.informativeText = L("之后所有会议都不会再自动认出人；已有记录保持原样。")
        a.addButton(withTitle: L("全部删除"))
        a.addButton(withTitle: L("取消"))
        if a.runModal() == .alertFirstButtonReturn { model.deleteAllSpeakerProfiles() }
    }

    private func seen(_ date: Date?) -> String {
        guard let date else { return L("还没在新会议里出现") }
        let f = RelativeDateTimeFormatter()
        f.locale = uiLocale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Edit the human part of a person's profile; the voiceprint itself stays untouched.
struct SpeakerProfileEditor: View {
    @ObservedObject var model: AppModel
    let profile: SpeakerProfile
    @State private var name: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, profile: SpeakerProfile) {
        self.model = model
        self.profile = profile
        _name = State(initialValue: profile.name)
        _notes = State(initialValue: profile.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("人员资料")).font(.system(size: 18, weight: .bold))
            TextField(L("名字"), text: $name).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("备注（公司、职位、下次要记住的事）"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                TextEditor(text: $notes)
                    .font(.system(size: 13))
                    .padding(7)
                    .frame(minHeight: 140)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.raised))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
            }
            if let style = profile.style, !style.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("说话风格")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                    Text(style).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("这是从发言内容做的表达方式归纳，不是心理测评。"))
                        .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }.buttonStyle(.plain)
                SoftButton(L("保存"), dark: true) {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { model.renameSpeakerProfile(id: profile.id, to: clean) }
                    model.saveSpeakerProfileNotes(id: profile.id, notes: notes)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 430)
        .background(Color.white)
    }
}
