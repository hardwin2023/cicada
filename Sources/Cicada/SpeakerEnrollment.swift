import AVFoundation
import Foundation

/// Turns the recorded stretches of one local voice in a meeting into a profile embedding. This is
/// deliberately separate from the live clusterer: it also works after the app restarted, for an old
/// record the user wants to add to the library.
enum SpeakerEnrollmentError: LocalizedError {
    case noAudio
    case notEnoughSpeech
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .noAudio: L("这场会议没有可用的录音，先打开保存会议录音再试")
        case .notEnoughSpeech: L("这个人的发言太少，至少要有 3 句、6 秒左右的声音")
        case .modelUnavailable: L("声纹模型加载失败，稍后再试")
        }
    }
}

struct SpeakerEnrollmentResult {
    var embedding: [Float]
    var clips: Int
    var seconds: Double
}

enum SpeakerEnrollment {
    static let minimumClips = 3
    static let minimumSeconds = 6.0
    private static let maximumClipSeconds = 12.0

    /// `audioURL`: the meeting's system recording, or an imported file's source.
    static func build(session: Session, voice: Int, audioURL: URL,
                      packageURL: URL? = nil) async throws -> SpeakerEnrollmentResult {
        try await Task.detached(priority: .utility) {
            try buildSync(session: session, voice: voice, audioURL: audioURL, packageURL: packageURL)
        }.value
    }

    private static func buildSync(session: Session, voice: Int, audioURL: URL,
                                  packageURL: URL?) throws -> SpeakerEnrollmentResult {
        guard let file = try? AVAudioFile(forReading: audioURL) else { throw SpeakerEnrollmentError.noAudio }
        let candidates = session.lines.enumerated().filter { _, line in
            line.speaker == "them" && line.voice == voice && SpeakerLabels.substantive(line.src)
        }
        guard !candidates.isEmpty else { throw SpeakerEnrollmentError.notEnoughSpeech }

        let model: Voiceprints
        do { model = try Voiceprints.load(packageURL: packageURL) } catch { throw SpeakerEnrollmentError.modelUnavailable }

        var embeddings: [[Float]] = []
        var seconds = 0.0
        for (index, line) in candidates {
            let next = session.lines.indices.contains(index + 1) ? session.lines[index + 1].t : session.duration
            let end = min(next, line.t + maximumClipSeconds)
            guard end - line.t >= 0.5, let samples = read(file, from: line.t, to: end),
                  let embedding = model.embed(samples) else { continue }
            embeddings.append(embedding)
            seconds += Double(samples.count) / 16_000
        }
        guard embeddings.count >= minimumClips, seconds >= minimumSeconds,
              let mean = SpeakerEmbedding.mean(embeddings) else { throw SpeakerEnrollmentError.notEnoughSpeech }
        return SpeakerEnrollmentResult(embedding: mean, clips: embeddings.count, seconds: seconds)
    }

    /// 16 kHz mono floats from `start` to `end` seconds, converting the file's rate and channels.
    /// `ImportVoices.read` is only for files already decoded to 16 kHz; meeting .m4a files are not.
    private static func read(_ file: AVAudioFile, from start: Double, to end: Double) -> [Float]? {
        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition(max(0, start) * rate)
        let last = min(file.length, AVAudioFramePosition(max(0, end) * rate))
        guard last > first, let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                         frameCapacity: AVAudioFrameCount(last - first)) else { return nil }
        file.framePosition = first
        var frames: AVAudioFrameCount = 0
        while file.framePosition < last {
            let want = AVAudioFrameCount(last - file.framePosition)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: want),
                  (try? file.read(into: buf, frameCount: want)) != nil, buf.frameLength > 0 else { break }
            input.frameLength = frames + buf.frameLength
            // AVAudioPCMBuffer has no append API: copy into the backing float channels.
            if let src = buf.floatChannelData, let dst = input.floatChannelData {
                for ch in 0..<Int(file.processingFormat.channelCount) {
                    dst[ch].advanced(by: Int(frames)).update(from: src[ch], count: Int(buf.frameLength))
                }
            } else {
                return nil
            }
            frames += buf.frameLength
        }
        guard frames > 0 else { return nil }
        input.frameLength = frames
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        guard let converted = PCMConverter().convert(input, to: format),
              let data = converted.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
    }
}
