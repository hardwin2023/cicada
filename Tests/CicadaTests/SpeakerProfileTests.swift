import Foundation
import Testing
@testable import Cicada

@Suite struct SpeakerProfileTests {
    private func unit(_ index: Int, noise: Float = 0) -> [Float] {
        var v = [Float](repeating: noise, count: SpeakerEmbedding.dimensions)
        v[index] = 1
        return v
    }

    private func store() throws -> (SpeakerProfileStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SpeakerProfileStore(url: root.appendingPathComponent("profiles.json")), root)
    }

    @Test func rememberMatchAndDelete() throws {
        let (s, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let p = try #require(s.remember(name: "张总", embedding: unit(0)))
        #expect(s.all().count == 1)
        #expect(s.match(unit(0, noise: 0.01))?.kind == .auto)
        #expect(s.match(unit(1)) == nil)
        let attrs = try FileManager.default.attributesOfItem(atPath: s.url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        // A fresh process reads the profile back, dates included.
        #expect(SpeakerProfileStore(url: s.url).all().map(\.name) == ["张总"])
        s.delete(id: p.id)
        #expect(s.all().isEmpty)
    }

    @Test func aCloseMatchIsOnlySuggested() throws {
        let (s, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = s.remember(name: "A", embedding: unit(0))
        _ = s.remember(name: "B", embedding: unit(1))
        // 0.62 toward A, 0.60 toward B: above suggested, below auto, and not a clear winner.
        let mixed = (0..<SpeakerEmbedding.dimensions).map { i in
            i == 0 ? Float(0.62) : (i == 1 ? Float(0.60) : 0)
        }
        let m = try #require(s.match(mixed))
        #expect(m.kind == .suggested)
    }

    @Test func blendedProfileMovesGradually() throws {
        let (s, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let p = try #require(s.remember(name: "A", embedding: unit(0)))
        #expect(s.updateEmbedding(id: p.id, embedding: unit(0, noise: 0.02)))
        let after = try #require(s.snapshot().first)
        #expect(after.sampleCount == 2)
        #expect(after.embedding[0] > 0.9)
    }

    @Test func corruptLibraryIsEmptyNotFatal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not json".utf8).write(to: root.appendingPathComponent("profiles.json"))
        #expect(SpeakerProfileStore(url: root.appendingPathComponent("profiles.json")).all().isEmpty)
    }

    @Test func aKnownVoiceShowsBeforeFiveLines() {
        let line = TranscriptLine(id: "l0", t: 1, speaker: "them", src: "我们周四上线",
                                  dst: nil, srcLang: "zh-CN", dstLang: "en", voice: 2)
        let s = Session(id: "s", title: "t", startedAt: Date(), endedAt: nil, lines: [line], hasAudio: false,
                        notes: nil, voiceProfiles: ["2": VoiceProfileRef(id: UUID(), name: "张总", similarity: 0.8)])
        #expect(SpeakerLabels.numbers(s) == ["l0": 1])
        #expect(SpeakerLabels.names(s) == [1: "张总"])
    }

    @Test func oldSessionJSONStillDecodes() throws {
        let json = """
        {"id":"old","title":"会议","startedAt":"2026-01-01T00:00:00Z","lines":[],"hasAudio":false}
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let s = try d.decode(Session.self, from: Data(json.utf8))
        #expect(s.id == "old")
        #expect(s.voiceProfiles == nil)
    }

    @Test func pooledSampleVoicesMatchThemselvesAndNotEachOther() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let audio = repo.appendingPathComponent("Resources/sample/sample.m4a")
        let modelURL = repo.appendingPathComponent("Resources/models/SpeakerEmbedding.mlpackage")
        let all = try #require(Voiceprints.samples(of: audio))
        let rate = 16_000.0
        func clip(_ start: Double, _ end: Double) -> [Float] {
            Array(all[Int(start * rate)..<min(all.count, Int(end * rate))])
        }
        let model = try Voiceprints.load(packageURL: modelURL)
        let emma1 = try #require(model.embed(clip(0.25, 1.30)))
        let emma2 = try #require(model.embed(clip(7.17, 8.40)))
        let george = try #require(model.embed(clip(2.56, 4.70)))
        let same = try #require(SpeakerEmbedding.cosine(emma1, emma2))
        let other = try #require(SpeakerEmbedding.cosine(emma1, george))
        #expect(same > other)
    }

    /// A real model + real audio path, using two macOS system voices: the same voice should
    /// enrol and match across two recordings, a different voice should stay anonymous.
    @Test func enrollmentAndCrossMeetingMatchWithRealAudio() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-tts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func say(_ file: String, _ voice: String, _ text: String) throws -> URL {
            let url = dir.appendingPathComponent(file)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-v", voice, "-o", url.path, text]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return url
        }
        let long = "Today we are reviewing the project schedule, the budget, and the next steps. "
            + "Please write down the decisions and the owners, and send the notes to the team tomorrow morning."
        let first = try say("first.aiff", "Samantha", long)
        let second = try say("second.aiff", "Samantha", long + " We will meet again on Friday.")
        let other = try say("other.aiff", "Fred", long)
        let modelURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/models/SpeakerEmbedding.mlpackage")
        let started = Date()
        func session(_ voice: Int) -> Session {
            let texts = ["We should review the project schedule and the budget today.",
                         "Please write down the decisions and the owners in the notes.",
                         "Send the notes to the team tomorrow morning, before the next meeting."]
            let times = [0.2, 3.8, 7.4]
            let lines = zip(times, texts).enumerated().map { i, pair in
                TranscriptLine(id: "l\(i)", t: pair.0, speaker: "them", src: pair.1, dst: nil,
                               srcLang: "en", dstLang: "zh-CN", voice: voice)
            }
            return Session(id: "s\(voice)", title: "t", startedAt: started,
                           endedAt: started.addingTimeInterval(11.5), lines: lines, hasAudio: true)
        }
        let a = try await SpeakerEnrollment.build(session: session(0), voice: 0, audioURL: first, packageURL: modelURL)
        let b = try await SpeakerEnrollment.build(session: session(0), voice: 0, audioURL: second, packageURL: modelURL)
        let c = try await SpeakerEnrollment.build(session: session(0), voice: 0, audioURL: other, packageURL: modelURL)
        let same = try #require(SpeakerEmbedding.cosine(a.embedding, b.embedding))
        let different = try #require(SpeakerEmbedding.cosine(a.embedding, c.embedding))
        #expect(a.clips >= 3)
        #expect(same > 0.70)
        #expect(different < 0.55)
        let store = SpeakerProfileStore(url: dir.appendingPathComponent("profiles.json"))
        let profile = try #require(store.remember(name: "Samantha", embedding: a.embedding))
        #expect(store.match(b.embedding)?.profile.id == profile.id)
        #expect(store.match(c.embedding) == nil)
    }
}
