import SwiftUI

/// Edit the notes by hand. Names and terms are what speech recognition gets wrong most, so they
/// are fields of their own; the AI's text stays a draft until the user saves it.
struct NotesEditorView: View {
    @ObservedObject var model: AppModel
    let sessionID: String
    @State private var draft: MeetingNotes
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, sessionID: String) {
        self.model = model
        self.sessionID = sessionID
        _draft = State(initialValue: model.store.session(sessionID)?.notes ?? MeetingNotes())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑纪要").font(.system(size: 18, weight: .bold))
                    Text("改完保存在这场会议里；人名和术语也会用于以后整理。")
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                SoftButton("保存", dark: true) { save() }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("纪要标题") {
                        TextField("例如：招商局软件工厂沟通", text: optional(\.title))
                            .textFieldStyle(.roundedBorder)
                    }

                    field("总结") {
                        editor($draft.summary, height: 110)
                    }

                    if !draft.topics.isEmpty {
                        section("议题")
                        ForEach(draft.topics.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("议题标题", text: $draft.topics[i].title)
                                    .textFieldStyle(.roundedBorder)
                                editor($draft.topics[i].summary, height: 64)
                                ForEach(draft.topics[i].points.indices, id: \.self) { j in
                                    HStack(spacing: 6) {
                                        Text("·").foregroundStyle(Palette.tertiary)
                                        TextField("要点", text: $draft.topics[i].points[j])
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
                        }
                    }

                    if !draft.conclusions.isEmpty {
                        section("结论")
                        ForEach(draft.conclusions.indices, id: \.self) { i in
                            item($draft.conclusions[i], prefix: "结论")
                        }
                    }
                    if !draft.todos.isEmpty {
                        section("待办")
                        ForEach(draft.todos.indices, id: \.self) { i in
                            item($draft.todos[i], prefix: "待办")
                        }
                    }

                    if !draft.terms.isEmpty {
                        section("人名和术语")
                        Text("名字写对后，纪要里所有人名会按这里显示；识别错的写法放在“听成”里。")
                            .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                        ForEach(draft.terms.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    TextField("正确名字/术语", text: $draft.terms[i].name)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("说明（公司、职位…）", text: $draft.terms[i].note)
                                        .textFieldStyle(.roundedBorder)
                                }
                                TextField("听成（逗号分隔）", text: Binding(
                                    get: { draft.terms[i].heard.joined(separator: "，") },
                                    set: { draft.terms[i].heard = $0.split(whereSeparator: { $0 == "," || $0 == "，" })
                                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 680)
        .background(Color.white)
    }

    private func save() {
        draft.updatedAt = Date()
        model.saveEditedNotes(draft, session: sessionID)
        dismiss()
    }

    private func optional(_ key: WritableKeyPath<MeetingNotes, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: key] ?? "" },
                set: { draft[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
            content()
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
            .padding(.top, 4)
    }

    private func editor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(7)
            .frame(minHeight: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
    }

    private func item(_ item: Binding<NoteItem>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("\(prefix)内容", text: item.text).textFieldStyle(.roundedBorder)
            TextField("负责人（可空）", text: Binding(
                get: { item.wrappedValue.owner ?? "" },
                set: { item.wrappedValue.owner = $0.isEmpty ? nil : $0 }
            )).textFieldStyle(.roundedBorder).font(.system(size: 11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
    }
}

/// The small 编辑 control that opens `NotesEditorView`; no state outside the button.
struct NotesEditButton: View {
    @ObservedObject var model: AppModel
    let session: Session
    @State private var shown = false

    var body: some View {
        Button("编辑") { shown = true }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Palette.secondary)
            .help("手动改纪要、人名和术语")
            .sheet(isPresented: $shown) { NotesEditorView(model: model, sessionID: session.id) }
    }
}
