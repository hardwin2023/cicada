import AVFoundation
import Foundation
import Testing
@testable import Cicada

@Suite struct VoiceReferenceTests {
    /// `seconds` of silence, then `speech` seconds of a 200 Hz tone, then silence.
    private func clip(lead: Double, speech: Double, tail: Double, rate: Double = 16_000) -> [Float] {
        let quiet = { (s: Double) in [Float](repeating: 0.0005, count: Int(s * rate)) }
        let tone = (0..<Int(speech * rate)).map { Float(sin(2 * Double.pi * 200 * Double($0) / rate)) * 0.3 }
        return quiet(lead) + tone + quiet(tail)
    }

    @Test func speechSpanLeavesOutSilenceAtBothEnds() throws {
        let span = try #require(VoiceReference.speechSpan(clip(lead: 1.5, speech: 6, tail: 2), sampleRate: 16_000))
        #expect(abs(span - 6) < 0.05)
    }

    @Test func silenceHasNoSpanOrPace() {
        let quiet = [Float](repeating: 0.0005, count: 16_000 * 3)
        #expect(VoiceReference.speechSpan(quiet, sampleRate: 16_000) == nil)
        #expect(VoiceReference.pace(text: "大家好", samples: quiet, sampleRate: 16_000) == nil)
    }

    @Test func paceCountsChineseCharactersPerSecondOfSpeech() throws {
        // 19 characters over 10 s of speech: the recital that made the clone 4× slow.
        let text = "贤文慧汝尊尊集运增广多见多闻观今一见古。"
        let pace = try #require(VoiceReference.pace(text: text, samples: clip(lead: 0.5, speech: 10, tail: 0.5), sampleRate: 16_000))
        #expect(abs(pace - 1.9) < 0.05)
        #expect(VoiceReference.isSlow(text: text, pace: pace))
    }

    @Test func theChinesePassageAtAnOrdinaryPaceIsNotSlow() {
        let text = VoiceReference.passage(for: "zh-CN")
        let units = Double(SpeakScore.tokens(text).count)
        #expect(!VoiceReference.isSlow(text: text, pace: units / 15))
        #expect(VoiceReference.isSlow(text: text, pace: units / 30))
    }

    @Test func englishIsMeasuredInWords() {
        let text = VoiceReference.passage(for: "en-US")
        let words = Double(SpeakScore.tokens(text).count)
        #expect(!VoiceReference.isSlow(text: text, pace: words / 16))
        #expect(VoiceReference.isSlow(text: text, pace: words / 30))
    }

    /// The pause before 读完了 made Ming's clone come back silent: it goes, 0.2 s kept each side.
    @Test func trimsTheQuietAroundTheReading() {
        let kept = VoiceReference.trimmed(clip(lead: 1, speech: 6, tail: 2), sampleRate: 16_000)
        #expect(abs(Double(kept.count) / 16_000 - 6.4) < 0.05)
        let quiet = [Float](repeating: 0.0005, count: 16_000)
        #expect(VoiceReference.trimmed(quiet, sampleRate: 16_000).count == quiet.count)
    }

    @Test func trimsASavedWAVInPlace() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trim-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let samples = clip(lead: 0.5, speech: 5, tail: 1.5)
        do {
            let f = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
            samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            buf.frameLength = AVAudioFrameCount(samples.count)
            try f.write(from: buf)
        }
        #expect(VoiceReference.trim(url))
        let f = try AVAudioFile(forReading: url)
        #expect(abs(Double(f.length) / 16_000 - 5.4) < 0.05)
        #expect(f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(!VoiceReference.trim(url))
    }
}
