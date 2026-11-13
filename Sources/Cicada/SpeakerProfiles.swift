import Foundation

/// A known voice: the name the user gave it and the voiceprint it is recognised by.
/// Kept only on this Mac, in Application Support (never in a meeting record).
struct SpeakerProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// 256-d, L2-normalised WeSpeaker embedding (`Voiceprints.embed`).
    var embedding: [Float]
    var sampleCount: Int
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date?
    /// When the user agreed to keep this voice. Absent for a profile made before this field existed.
    var consentAt: Date?
}

/// What a meeting remembers about a local voice id: enough to show the name even if the global
/// profile is later renamed or deleted.
struct VoiceProfileRef: Codable, Equatable {
    var id: UUID
    var name: String
    /// The similarity that first matched it (0…1).
    var similarity: Float
}

enum SpeakerMatchKind: Equatable {
    /// Similar enough to name without asking.
    case auto
    /// Shown as a suggestion; the user decides.
    case suggested
}

struct SpeakerProfileMatch: Equatable {
    let profile: SpeakerProfile
    let similarity: Float
    let kind: SpeakerMatchKind

    var ref: VoiceProfileRef {
        VoiceProfileRef(id: profile.id, name: profile.name, similarity: similarity)
    }
}

/// Starting thresholds for the 256-d WeSpeaker model. `VoiceClusterer`'s 0.5 is a within-meeting
/// threshold and must not be reused for identity: a wrong name in a customer's minutes is worse
/// than "未识别". These are deliberately conservative and are covered by tests with the bundled
/// sample; tune on real meetings before lowering them.
struct SpeakerMatchPolicy: Equatable {
    var auto: Float = 0.70
    var suggested: Float = 0.55
    /// The best profile must be this much ahead of the second one before it may be named silently.
    var margin: Float = 0.08
}

/// Vector helpers shared by the clusterer, the profile store and tests.
enum SpeakerEmbedding {
    static let dimensions = 256

    static func normalized(_ v: [Float]) -> [Float]? {
        guard v.count == dimensions else { return nil }
        var sum: Float = 0
        for x in v { sum += x * x }
        guard sum.isFinite, sum > 0 else { return nil }
        let scale = sum.squareRoot()
        let out = v.map { $0 / scale }
        return out.allSatisfy(\.isFinite) ? out : nil
    }

    /// Dot product; both vectors are unit length, so this is their cosine similarity.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == dimensions, b.count == dimensions else { return nil }
        var dot: Float = 0
        for i in 0..<dimensions { dot += a[i] * b[i] }
        return dot.isFinite ? dot : nil
    }

    /// Unit-length mean of unit vectors, without letting a short noisy clip dominate.
    static func mean(_ vectors: [[Float]]) -> [Float]? {
        guard !vectors.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: dimensions)
        for v in vectors {
            guard v.count == dimensions else { continue }
            for i in 0..<dimensions { sum[i] += v[i] }
        }
        return normalized(sum)
    }

    /// A new sample joins an existing profile gradually: `normalize(old * weight + fresh)`.
    /// The weight is capped so a profile cannot become impossible to correct after years of use.
    static func blended(old: [Float], fresh: [Float], sampleCount: Int) -> [Float]? {
        guard old.count == dimensions, fresh.count == dimensions else { return nil }
        let weight = Float(min(max(1, sampleCount), 20))
        var sum = [Float](repeating: 0, count: dimensions)
        for i in 0..<dimensions { sum[i] = old[i] * weight + fresh[i] }
        return normalized(sum)
    }
}

/// The persistent voiceprint library. Reads may happen on the voiceprint queue; changes happen on
/// the main actor. A lock keeps a snapshot safe while a profile is being written.
final class SpeakerProfileStore: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var cached: [SpeakerProfile] = []

    /// Called after a change, with a snapshot; AppModel refreshes its `@Published` copy here.
    var onChange: (([SpeakerProfile]) -> Void)?

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder)
            .appendingPathComponent("VoiceProfiles", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    init(url: URL = SpeakerProfileStore.defaultURL) {
        self.url = url
        cached = Self.load(from: url)
        try? Self.protectDirectory(url.deletingLastPathComponent())
        try? Self.protectFile(url)
        for p in cached where p.consentAt == nil { try? markConsent(p.id, at: p.createdAt) }
    }

    func all() -> [SpeakerProfile] {
        lock.lock()
        defer { lock.unlock() }
        return cached.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A sorted snapshot for matching; does not expose the live array.
    func snapshot() -> [SpeakerProfile] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Best profile above `suggested`, with high-confidence hits distinguished from suggestions.
    func match(_ embedding: [Float], policy: SpeakerMatchPolicy = SpeakerMatchPolicy()) -> SpeakerProfileMatch? {
        guard let probe = SpeakerEmbedding.normalized(embedding) else { return nil }
        let profiles = snapshot()
            .filter { $0.embedding.count == SpeakerEmbedding.dimensions && !$0.name.isEmpty }
            .compactMap { p -> (SpeakerProfile, Float)? in
                guard let v = SpeakerEmbedding.normalized(p.embedding),
                      let score = SpeakerEmbedding.cosine(probe, v) else { return nil }
                return (p, score)
            }
            .sorted { $0.1 > $1.1 }
        guard let best = profiles.first, best.1 >= policy.suggested else { return nil }
        let second = profiles.dropFirst().first?.1
        let clear = second == nil || (best.1 - second!) >= policy.margin
        return SpeakerProfileMatch(profile: best.0, similarity: best.1,
                                   kind: best.1 >= policy.auto && clear ? .auto : .suggested)
    }

    /// Add a profile from an explicit user action. Returns nil when the embedding is unusable or
    /// the name is empty; the caller must not silently fall back to a profile with no name.
    @discardableResult
    func remember(name: String, embedding: [Float], at date: Date = Date()) -> SpeakerProfile? {
        let clean = Self.cleanName(name)
        guard !clean.isEmpty, let v = SpeakerEmbedding.normalized(embedding) else { return nil }
        let p = SpeakerProfile(id: UUID(), name: clean, embedding: v, sampleCount: 1,
                               createdAt: date, updatedAt: date, lastSeenAt: nil, consentAt: date)
        mutate { $0.append(p) }
        return p
    }

    @discardableResult
    func updateEmbedding(id: UUID, embedding: [Float], at date: Date = Date()) -> Bool {
        guard let v = SpeakerEmbedding.normalized(embedding) else { return false }
        var updated = false
        mutate { profiles in
            guard let i = profiles.firstIndex(where: { $0.id == id }),
                  let blended = SpeakerEmbedding.blended(old: profiles[i].embedding, fresh: v,
                                                         sampleCount: profiles[i].sampleCount) else { return }
            profiles[i].embedding = blended
            profiles[i].sampleCount += 1
            profiles[i].updatedAt = date
            updated = true
        }
        return updated
    }

    @discardableResult
    func rename(id: UUID, to name: String, at date: Date = Date()) -> Bool {
        let clean = Self.cleanName(name)
        guard !clean.isEmpty else { return false }
        var updated = false
        mutate { profiles in
            guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[i].name = clean
            profiles[i].updatedAt = date
            updated = true
        }
        return updated
    }

    func delete(id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    func deleteAll() {
        mutate { $0.removeAll() }
    }

    /// Make a matched profile's last-seen time current. Writes at most once a minute per profile,
    /// so matching a line every few seconds does not hammer the disk.
    func markSeen(id: UUID, at date: Date = Date()) {
        let old = snapshot().first { $0.id == id }?.lastSeenAt
        guard old == nil || date.timeIntervalSince(old!) > 60 else { return }
        mutate { profiles in
            guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[i].lastSeenAt = date
        }
    }

    private func markConsent(_ id: UUID, at date: Date) throws {
        mutate { profiles in
            guard let i = profiles.firstIndex(where: { $0.id == id }), profiles[i].consentAt == nil else { return }
            profiles[i].consentAt = date
        }
    }

    private func mutate(_ change: (inout [SpeakerProfile]) -> Void) {
        lock.lock()
        change(&cached)
        let snapshot = cached
        lock.unlock()
        save(snapshot)
        onChange?(snapshot)
    }

    private func save(_ profiles: [SpeakerProfile]) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Self.protectDirectory(dir)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: url, options: .atomic)
            try Self.protectFile(url)
        } catch {
            debugLog("voice profiles: save failed \(error)")
        }
    }

    private static func load(from url: URL) -> [SpeakerProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([SpeakerProfile].self, from: data) else { return [] }
        // A damaged entry must not take the whole library, or the app, down with it.
        return decoded.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.embedding.count == SpeakerEmbedding.dimensions
        }
    }

    private static func cleanName(_ name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(40))
    }

    private static func protectDirectory(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func protectFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
