import AppKit
import SwiftUI

/// 复制纪要 as rich text: one copy puts HTML (document apps: Feishu, DingTalk, Notion, web
/// editors), RTFD (Notes, Pages, Word) and the Markdown as plain text (chats, code editors) on the
/// pasteboard, and each app takes the one it reads. No app's API, no sign-in, no token.
extension TranscriptExport {
    /// A fishbone as a picture: PNG data and the width to show it at (points; the PNG is 2x).
    struct Picture: Equatable {
        var png: Data
        var width: Int
    }

    /// The notes as an HTML fragment (empty when there are none). A fishbone is its picture, when
    /// there is one, followed by the same branches as a list: an app that drops pasted images
    /// still keeps the text.
    static func notesHTML(_ n: MeetingNotes?, picture: (Fishbone) -> Picture? = { _ in nil }) -> String {
        guard let n, !n.isEmpty else { return "" }
        var out = "<h2>\(esc(L("纪要")))</h2>\n<p>\(esc(n.summary))</p>\n"
        for t in n.topics {
            out += "<h3>\(clock(t.start)) \(esc(t.title))</h3>\n"
            if !t.summary.isEmpty { out += "<p>\(esc(t.summary))</p>\n" }
            out += list(t.points.map(esc))
            if let f = t.fishbone {
                out += "<p><b>\(esc(f.question))</b></p>\n"
                if let p = picture(f) {
                    out += "<p><img src=\"data:image/png;base64,\(p.png.base64EncodedString())\" width=\"\(p.width)\" alt=\"\(esc(f.question))\"></p>\n"
                }
                out += list(f.branches.map { "<b>\(esc($0.label))</b>：\(esc($0.detail))" })
            }
        }
        if !n.conclusions.isEmpty { out += "<h3>\(esc(L("结论")))</h3>\n" + list(n.conclusions.map { esc($0.text) }) }
        // A checkbox doesn't survive a paste; the ballot box does.
        if !n.todos.isEmpty { out += "<h3>\(esc(L("待办")))</h3>\n" + list(n.todos.map { "☐ " + esc($0.withOwner) }) }
        if !n.terms.isEmpty { out += "<h3>\(esc(L("人名和术语")))</h3>\n" + list(n.terms.map { "<b>\(esc($0.name))</b> \(esc($0.note))" }) }
        return out
    }

    /// The whole record as HTML, in the order and wording of `markdown(_:)`.
    static func html(_ s: Session, picture: (Fishbone) -> Picture? = { _ in nil }) -> String {
        var out = "<h1>\(esc(s.displayTitle))</h1>\n<p>\(esc(header(s)))</p>\n"
        let notes = notesHTML(s.notes, picture: picture)
        if !notes.isEmpty { out += notes + "<h2>\(esc(L("文字记录")))</h2>\n" }
        let numbers = speakerNumbers(s), names = SpeakerLabels.names(s)
        for l in s.lines {
            let who = saysWho(s, numbers) ? " \(esc(speakerName(l, numbers, names)))" : ""
            var p = "<p><b>[\(clock(l.t))]\(who)</b><br>\(esc(l.shown))"
            if let d = l.dst, d != l.shown { p += "<br><span style=\"color:#5A5F6B\">\(esc(d))</span>" }
            out += p + "</p>\n"
        }
        return out
    }

    /// A fragment as a document a pasting app reads as UTF-8 whatever it assumes.
    static func htmlDocument(_ body: String) -> String {
        "<html><head><meta charset=\"utf-8\"></head><body>\n\(body)</body></html>"
    }

    private static func list(_ items: [String]) -> String {
        items.isEmpty ? "" : "<ul>\n" + items.map { "<li>\($0)</li>\n" }.joined() + "</ul>\n"
    }

    static func esc(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n": out += "<br>"
            default: out.append(c)
            }
        }
        return out
    }
}

@MainActor
enum RichCopy {
    /// Puts `markdown` as plain text and `html` as HTML and RTFD on the general pasteboard.
    static func put(markdown: String, html: String) {
        let doc = TranscriptExport.htmlDocument(html)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
        pb.setString(doc, forType: .html)
        // AppKit's HTML reader loads data: images in place, so the RTFD carries the fishbone too.
        if let data = doc.data(using: .utf8),
           let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil),
           let rtfd = text.rtfd(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) {
            pb.setData(rtfd, forType: .rtfd)
        } else {
            debugLog("rich copy: no RTFD, HTML and text only")
        }
    }

    static func notes(_ n: MeetingNotes?, title: String?) {
        put(markdown: TranscriptExport.notesMarkdown(n), html: TranscriptExport.notesHTML(n) { picture($0, caption: title) })
    }

    static func session(_ s: Session) {
        put(markdown: TranscriptExport.markdown(s), html: TranscriptExport.html(s) { picture($0, caption: s.displayTitle) })
    }

    /// 复制为图片: the PNG alone, so a chat or a slide takes it as a picture.
    static func image(_ f: Fishbone, caption: String?) {
        guard let p = picture(f, caption: caption) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(p.png, forType: .png)
    }

    /// 复制为文字: the question and its branches, as the notes' Markdown has them.
    static func text(_ f: Fishbone) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("**\(f.question)**\n\n" + f.branches.map { "- \($0.label)：\($0.detail)\n" }.joined(), forType: .string)
    }

    static let pictureWidth = 520

    /// The fishbone as it looks in the notes, always light on white (a dark window's picture pasted
    /// into a white document is a black block), without hints that only mean something in the app,
    /// and with the meeting's name under it so a forwarded picture says where it came from.
    static func picture(_ f: Fishbone, caption: String?) -> TranscriptExport.Picture? {
        let view = VStack(alignment: .trailing, spacing: 8) {
            FishboneView(fishbone: f, forPicture: true)
            if let caption, !caption.isEmpty {
                Text("\(caption) · Cicada").font(.system(size: 10)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(16)
        .frame(width: CGFloat(pictureWidth))
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return .init(png: png, width: pictureWidth)
    }
}
