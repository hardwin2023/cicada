import Foundation

/// A finished meeting's notes changed in place on the main window's page: the summary, or one
/// conclusion or to-do. Only what people take away is editable here; the title has its own field,
/// names and terms go through 改这句… and 词表, and topics are the AI's to rewrite (重新整理).
struct NoteEdit: Equatable {
    enum Target: Equatable {
        case summary
        /// A row as the page lists them: conclusions first, then to-dos.
        case item(Int)
    }
    let session: String
    let target: Target
}

/// What the page needs to edit in place: which piece is open, and how to open, save or close one.
struct NotesEditHooks {
    let current: NoteEdit.Target?
    let open: (NoteEdit.Target?) -> Void
    /// `owner`: nil keeps the stored owner; .some("") clears it.
    let save: (NoteEdit.Target, String, String??) -> Void
}

extension MeetingNotes {
    /// The notes with one piece replaced. An empty conclusion or to-do is deleted; an empty summary
    /// stays empty. Everything else (topics, terms, coverage, evidence counts) is kept as it was.
    func editing(_ target: NoteEdit.Target, text: String, owner: String?? = nil) -> MeetingNotes {
        var n = self
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func apply(_ item: inout NoteItem) {
            item.text = text
            if let owner { item.owner = owner.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        }
        switch target {
        case .summary:
            n.summary = text
        case .item(let i):
            let c = n.conclusions.count
            if i >= 0, i < c {
                if text.isEmpty { n.conclusions.remove(at: i) } else { apply(&n.conclusions[i]) }
            } else if i >= c, i - c < n.todos.count {
                if text.isEmpty { n.todos.remove(at: i - c) } else { apply(&n.todos[i - c]) }
            }
        }
        return n
    }
}

extension AppModel {
    /// Not while the meeting is being written (the next pass would redo the notes), nor while an
    /// import is still transcribing.
    func canEditNotes(_ s: Session) -> Bool {
        s.id != store.liveID && importer.status(of: s) == nil && !(s.notes?.isEmpty ?? true)
    }

    func editHooks(_ s: Session) -> NotesEditHooks? {
        guard canEditNotes(s) else { return nil }
        return NotesEditHooks(
            current: noteEdit?.session == s.id ? noteEdit?.target : nil,
            open: { [weak self] t in self?.noteEdit = t.map { NoteEdit(session: s.id, target: $0) } },
            save: { [weak self] t, text, owner in self?.saveNote(s.id, t, text: text, owner: owner) })
    }

    func saveNote(_ id: String, _ target: NoteEdit.Target, text: String, owner: String?? = nil) {
        guard let notes = store.session(id)?.notes else { return }
        saveEditedNotes(notes.editing(target, text: text, owner: owner), session: id)
        noteEdit = nil
        debugLog("notes edit: saved \(target) in \(id)")
    }
}
