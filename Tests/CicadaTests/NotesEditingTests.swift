import Foundation
import Testing
@testable import Cicada

@Suite struct NotesEditingTests {
    private var notes: MeetingNotes {
        var n = MeetingNotes()
        n.summary = "原来的总结"
        n.topics = [NoteTopic(start: 8, title: "发布", summary: "议题", points: ["要点"])]
        n.conclusions = [NoteItem(text: "锁定 3月3日", owner: nil, support: 2, t: 11),
                         NoteItem(text: "第二条", owner: nil, support: 1, t: 20)]
        n.todos = [NoteItem(text: "周五前签署", owner: "说话人2", support: 1, t: 11)]
        n.covered = 4
        n.final = true
        return n
    }

    @Test func replacesASummaryAndKeepsTheRest() {
        let n = notes.editing(.summary, text: "  新总结\n")
        #expect(n.summary == "新总结")
        #expect(n.topics == notes.topics && n.conclusions == notes.conclusions && n.todos == notes.todos)
        #expect(n.covered == 4 && n.final)
    }

    @Test func rowsCountConclusionsThenTodos() {
        let n = notes.editing(.item(1), text: "改过的第二条")
        #expect(n.conclusions[1].text == "改过的第二条")
        #expect(n.conclusions[1].support == 1 && n.conclusions[1].t == 20, "evidence and time stay")
        let m = notes.editing(.item(2), text: "下周一前签署")
        #expect(m.todos[0].text == "下周一前签署")
        #expect(m.todos[0].owner == "说话人2", "an unchanged owner keeps the stored one")
    }

    @Test func ownerChangesOrClears() {
        #expect(notes.editing(.item(2), text: "周五前签署", owner: .some("Emma")).todos[0].owner == "Emma")
        #expect(notes.editing(.item(2), text: "周五前签署", owner: .some(" ")).todos[0].owner == nil)
    }

    @Test func anEmptyRowIsDeleted() {
        let n = notes.editing(.item(0), text: "")
        #expect(n.conclusions.map(\.text) == ["第二条"])
        let m = notes.editing(.item(2), text: "   ")
        #expect(m.todos.isEmpty)
        #expect(notes.editing(.item(9), text: "") == notes, "a row that isn't there changes nothing")
    }
}
