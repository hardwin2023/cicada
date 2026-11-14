import Foundation
import Testing
@testable import Cicada

@Suite struct ExportTests {
    private func line(_ id: String, _ t: Double, _ speaker: String, _ src: String, _ dst: String?) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: src, dst: dst, srcLang: "en", dstLang: "zh-CN")
    }

    private var session: Session {
        Session(id: "s", title: "Weekly", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 600),
                lines: [line("1", 1.5, "them", "Hello.", "你好。"),
                        line("2", 3.25, "me", "Same", "Same"),
                        line("3", 20, "them", "Bye.", nil)],
                hasAudio: false, notes: nil, renamed: true)
    }

    @Test func clockFormats() {
        #expect(TranscriptExport.clock(0) == "00:00")
        #expect(TranscriptExport.clock(-5) == "00:00")
        #expect(TranscriptExport.clock(125.9) == "02:05")
        #expect(TranscriptExport.clock(3725) == "1:02:05")
    }

    @Test func srtTimesAndTranslations() {
        let srt = TranscriptExport.srt(session)
        let cues = srt.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(cues.count == 3)
        // Ends at the next line, at least 1 s and at most 8 s after it starts.
        #expect(cues[0] == "1\n00:00:01,500 --> 00:00:03,250\nHello.\n你好。")
        // A translation identical to the source isn't repeated; your own line says it was 同传.
        #expect(cues[1] == "2\n00:00:03,250 --> 00:00:11,250\n[同传] Same")
        // The last line gets 4 s.
        #expect(cues[2] == "3\n00:00:20,000 --> 00:00:24,000\nBye.")
    }

    @Test func markdownHasTitleLinesAndQuotes() {
        let md = TranscriptExport.markdown(session)
        #expect(md.hasPrefix("# Weekly\n\n"))
        #expect(md.contains("**[00:01] 对方**  \nHello.\n> 你好。\n"))
        #expect(md.contains("**[00:03] 你 · 同传**  \nSame\n\n"))
        #expect(!md.contains("> Same"))
    }
}

@Suite struct RichCopyTests {
    private var notes: MeetingNotes {
        var n = MeetingNotes()
        n.summary = "A <b> & \"c\""
        n.topics = [NoteTopic(start: 65, title: "Why late", summary: "", points: ["one"],
                              fishbone: Fishbone(question: "Why?", branches: [FishboneBranch(label: "Tests", detail: "not run", t: 70, support: 2)]))]
        n.todos = [NoteItem(text: "Ship", owner: nil, support: 1)]
        return n
    }

    @Test func escapesAndKeepsStructure() {
        let html = TranscriptExport.notesHTML(notes)
        #expect(html.contains("<p>A &lt;b&gt; &amp; &quot;c&quot;</p>"))
        #expect(html.contains("<h3>01:05 Why late</h3>"))
        #expect(html.contains("<li>one</li>"))
        // A to-do keeps a ballot box, as a checkbox doesn't survive a paste.
        #expect(html.contains("<li>☐ Ship</li>"))
        #expect(!html.contains("<img"))
    }

    /// The picture comes first and the same branches follow as text, for an app that drops images.
    @Test func fishboneIsPictureThenList() {
        let html = TranscriptExport.notesHTML(notes) { _ in .init(png: Data([1, 2, 3]), width: 520) }
        let img = html.range(of: "<img src=\"data:image/png;base64,AQID\" width=\"520\" alt=\"Why?\">")
        let list = html.range(of: "<li><b>Tests</b>：not run</li>")
        #expect(img != nil && list != nil)
        if let img, let list { #expect(img.lowerBound < list.lowerBound) }
    }

    @Test func emptyNotesGiveNothing() {
        #expect(TranscriptExport.notesHTML(nil).isEmpty)
        #expect(TranscriptExport.notesHTML(MeetingNotes()).isEmpty)
    }
}
