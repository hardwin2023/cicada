import AppKit
import SwiftUI

/// The local voiceprint library. Voiceprints are biometric data: every row can be removed here,
/// and nothing is uploaded.
struct SpeakerLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var editing: UUID?
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    private var profiles: [SpeakerProfile] { model.speakerProfiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("声纹库")).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(L("只保存在这台 Mac；删除后，以前的会议记录不会受影响。"))
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
                                    Button(L("改名")) { editing = p.id; draft = p.name }.buttonStyle(.plain)
                                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                    Button(L("删除")) { delete(p) }.buttonStyle(.plain)
                                        .font(.system(size: 12)).foregroundStyle(Palette.accentInk)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 54)
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
        .frame(width: 520, height: 440)
        .background(Color(red: 0.965, green: 0.969, blue: 0.976))
    }

    private func save(_ p: SpeakerProfile) {
        model.renameSpeakerProfile(id: p.id, to: draft)
        editing = nil
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
