import Foundation

/// The share document (v1): what goes to the share page, made from a meeting record. Only these
/// fields leave the Mac: never the record's file paths (`sourcePath` has the user's name in it),
/// Ling's guesses at names with the lines they came from, or the record's own bookkeeping. Speakers
/// are 说话人 N unless the user chose to show names. The ports produce the same bytes
/// (Tests/fixtures/share), and server/src/doc.js reads exactly these fields.
struct ShareDoc: Codable, Equatable {
    struct Line: Codable, Equatable {
        var t: Double
        var who: String
        var src: String
        var dst: String?
    }
    struct Topic: Codable, Equatable {
        var start: Double
        var title: String
        var summary: String
        var points: [String]
    }
    struct Item: Codable, Equatable {
        var text: String
        var owner: String?
        var t: Double?
    }
    struct Term: Codable, Equatable {
        var name: String
        var note: String
    }
    struct Notes: Codable, Equatable {
        var summary: String
        var topics: [Topic]
        var conclusions: [Item]
        var todos: [Item]
        var terms: [Term]
    }

    var v = 1
    var title: String
    var startedAt: String
    var duration: Int
    var langs: [String]
    var notes: Notes?
    var lines: [Line]
    /// How many parts the user left out (the review flagged them): the page says so.
    var hidden: Int
}

enum ShareScope: String, CaseIterable {
    case notes, full
}

enum ShareProjection {
    /// `removed`: indices into the record's lines the user took out; `dropNotes` leaves the notes out.
    static func doc(_ s: Session, scope: ShareScope, names: Bool, removed: Set<Int> = [], dropNotes: Bool = false) -> ShareDoc {
        let numbers = SpeakerLabels.numbers(s)
        let nameMap = names ? SpeakerLabels.names(s) : [:]
        func who(_ l: TranscriptLine) -> String {
            if l.speaker == "me" { return L("分享者") }
            guard let n = numbers[l.id] else { return L("对方") }
            return names ? SpeakerLabels.label(n, nameMap) : L("说话人 \(n)")
        }
        var lines: [ShareDoc.Line] = []
        if scope == .full {
            for (i, l) in s.lines.enumerated() where !removed.contains(i) && !l.src.isEmpty {
                let dst = l.dst.flatMap { $0.isEmpty || $0 == l.src ? nil : $0 }
                lines.append(.init(t: round(l.t), who: who(l), src: l.src, dst: dst))
            }
        }
        var notes: ShareDoc.Notes?
        if !dropNotes, let raw = s.notes, !raw.isEmpty {
            let n = names ? SpeakerLabels.named(raw, nameMap) : raw
            notes = .init(
                summary: n.summary,
                topics: n.topics.map { .init(start: round($0.start), title: $0.title, summary: $0.summary, points: $0.points) },
                conclusions: n.conclusions.map { .init(text: $0.text, owner: nil, t: $0.t.map(round)) },
                todos: n.todos.map { .init(text: $0.text, owner: names ? $0.owner : nil, t: $0.t.map(round)) },
                terms: names ? n.terms.map { .init(name: $0.name, note: $0.note) } : [])
        }
        let hidden = (scope == .full ? removed.count : 0) + (dropNotes && !(s.notes?.isEmpty ?? true) ? 1 : 0)
        return ShareDoc(title: s.displayTitle, startedAt: iso.string(from: s.startedAt),
                        duration: Int(s.duration.rounded()), langs: languages(s.lines),
                        notes: notes, lines: lines, hidden: hidden)
    }

    /// The meeting's usual direction ("en" → "zh"), by the most lines.
    static func languages(_ lines: [TranscriptLine]) -> [String] {
        var count: [String: Int] = [:], first: [String: Int] = [:]
        for (i, l) in lines.enumerated() where l.dst != nil {
            let key = base(l.srcLang) + ">" + base(l.dstLang)
            count[key, default: 0] += 1
            if first[key] == nil { first[key] = i }
        }
        guard let top = count.keys.max(by: { (count[$0]!, -first[$0]!) < (count[$1]!, -first[$1]!) }) else { return [] }
        return top.split(separator: ">").map(String.init)
    }

    private static func base(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    /// One decimal: the page shows seconds, and short numbers keep the bytes the same on every platform.
    private static func round(_ t: Double) -> Double { (t * 10).rounded() / 10 }

    private static let iso = ISO8601DateFormatter()

    static func encode(_ d: ShareDoc) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(d)) ?? Data()
    }
}
