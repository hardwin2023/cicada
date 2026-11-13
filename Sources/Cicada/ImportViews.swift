import AVFoundation
import SwiftUI

/// Plays a record's audio, for the player bar and a click on a line's time: an imported record's
/// original file, or a meeting's own system.m4a.
@MainActor
final class RecordingPlayer: ObservableObject {
    @Published private(set) var sessionID: String?
    @Published private(set) var playing = false
    @Published private(set) var time = 0.0
    @Published private(set) var length = 0.0
    /// The file was moved or deleted since it was imported (or since the meeting was recorded).
    @Published private(set) var missing = false
    /// The meeting's own recording rather than an imported file: 找不到录音, not 找不到原文件.
    @Published private(set) var own = false
    @Published private(set) var rate: Float = 1
    /// The transcript keeps the playing line in view. Scrolling it by hand stops that until a line is
    /// picked, the bar is dragged or 回到正在播放 is pressed: following would yank the page away.
    @Published private(set) var following = true
    /// When the transcript last scrolled itself to follow, so that scroll isn't taken for the user's.
    var ownScroll = Date.distantPast
    private var player: AVPlayer?
    private var observer: Any?
    /// The end of the recording: the time observer stops firing there, so it would still say playing.
    private var ended: NSObjectProtocol?

    var ready: Bool { player != nil }

    /// `recording`: the meeting's system.m4a, for a record that has no original file.
    func load(_ s: Session?, recording: URL? = nil) {
        // The same record again only while its recording was still being rewrapped.
        if let s, s.id == sessionID, player != nil || missing { return }
        unload()
        guard let s, let url = s.sourcePath.map({ URL(fileURLWithPath: $0) }) ?? recording else { return }
        sessionID = s.id
        own = s.sourcePath == nil
        length = s.duration
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Right after a meeting only the partial file is there until the rewrap ends: not missing yet.
            missing = !(own && FileManager.default.fileExists(atPath: AudioFileWriter.partial(url).path))
            return
        }
        let p = AVPlayer(url: url)
        player = p
        ended = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: p.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false }
        }
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                self.time = max(0, t.seconds)
                self.playing = p.rate > 0
                if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { self.length = d }
            }
        }
    }

    /// The line the playhead is in, once playing has begun.
    func lineID(in s: Session) -> String? {
        guard s.id == sessionID, ready, playing || time > 0 else { return nil }
        return s.lines.last(where: { $0.t <= time + 0.2 })?.id
    }

    func unload() {
        if let observer { player?.removeTimeObserver(observer) }
        if let ended { NotificationCenter.default.removeObserver(ended) }
        ended = nil
        player?.pause()
        observer = nil
        player = nil
        sessionID = nil
        playing = false
        missing = false
        own = false
        following = true
        time = 0
    }

    /// The transcript was scrolled by hand while it plays.
    func userScrolled() {
        if following, playing { following = false }
    }

    func follow() { following = true }

    func toggle() {
        guard let player else { return }
        if playing { player.pause() } else { player.playImmediately(atRate: rate) }
        playing.toggle()
    }

    func play(from t: Double) {
        guard let player else { return }
        debugLog("play from \(String(format: "%.1f", t))")
        seek(t)
        player.playImmediately(atRate: rate)
        playing = true
    }

    func seek(_ t: Double) {
        time = t
        following = true
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 1× → 1.5× → 2×.
    func nextRate() {
        rate = rate >= 2 ? 1 : rate + 0.5
        if playing { player?.rate = rate }
    }
}

/// Under an imported record's title: how far transcribing got, or that it stopped.
struct ImportStatusStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var importer: FileImporter
    let session: Session

    var body: some View {
        if let status = importer.status(of: session) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(title(status)).font(.system(size: 12)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    switch status {
                    case .running where importer.phase == .transcribing || importer.phase == .translating:
                        Text("\(Int(importer.progress * 100))%").font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                    case .unfinished:
                        if fileExists {
                            SoftButton(L("重新转写"), dark: true) { importer.retry(session.id) }
                        }
                    default:
                        EmptyView()
                    }
                }
                if status == .running {
                    let done = importer.phase == .transcribing || importer.phase == .translating ? importer.progress : 0
                    Capsule().fill(Palette.line).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(Palette.ink).frame(width: g.size.width * done) }
                        }
                        .animation(.easeOut(duration: 0.3), value: done)
                }
                if let helper = helper(status) {
                    Text(helper).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.fill))
        }
    }

    private var fileExists: Bool {
        if let path = session.sourcePath, FileManager.default.fileExists(atPath: path) { return true }
        return [model.store.systemAudioURL(session.id), model.store.micAudioURL(session.id),
                model.store.roomAudioURL(session.id)].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func title(_ status: FileImporter.Status) -> String {
        switch status {
        case .queued(let ahead): return ahead > 0 ? L("排队中，前面还有 \(ahead) 个文件") : L("排队中")
        case .unfinished: return fileExists ? L("没转完") : L("没转完，原文件已不在原来的位置")
        case .running:
            switch importer.phase {
            case .preparing: return L("正在读取文件…")
            case .detecting: return L("正在听是哪种语言…")
            case .downloading(let name): return L("正在下载 \(name) 语音模型…")
            case .transcribing:
                return L("文字记录已转到 \(TranscriptExport.clock(importer.heard)) / \(TranscriptExport.clock(importer.duration))")
            case .translating: return L("还有 \(importer.untranslated) 句在翻译")
            }
        }
    }

    private func helper(_ status: FileImporter.Status) -> String? {
        guard status == .running else { return nil }
        guard model.settings.importNotes, model.ling.hasKey else { return nil }
        return L("纪要等文字记录转完再整理；正在听的会议优先")
    }
}

/// A meeting kept for its recording alone (the language was never settled while it ran): the
/// user says which language was spoken, and it is transcribed like an imported file.
struct RecordingLanguageStrip: View {
    @ObservedObject var importer: FileImporter
    let session: Session
    @State private var picked: Lang?

    /// The Mac's languages first, as chips; the rest under 其他语言.
    private var likely: [Lang] {
        var out = likelySourceLanguages(last: nil, systemLanguages: Locale.preferredLanguages)
        for l in sourceLanguages where !out.contains(l) { out.append(l) }
        return out
    }

    var body: some View {
        let langs = likely
        let chips = Array(langs.prefix(4))
        let rest = Array(langs.dropFirst(4))
        let lang = picked ?? langs[0]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("这场会议只留下了录音").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("当时没听出是哪种语言。选一下，就按它转成文字")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                SoftButton(L("重新转写"), dark: true) { importer.retry(session.id, lang: lang) }
            }
            HStack(spacing: 6) {
                ForEach(chips, id: \.locale) { l in chip(l.name, on: l == lang) { picked = l } }
                if !rest.isEmpty {
                    let other = rest.contains(lang)
                    Menu {
                        ForEach(rest, id: \.locale) { l in Button(l.name) { picked = l } }
                    } label: {
                        Text(other ? lang.name : L("其他语言…"))
                            .font(.system(size: 12, weight: other ? .semibold : .regular))
                            .foregroundStyle(other ? Palette.ink : Palette.secondary)
                            .padding(.horizontal, 12).frame(height: 26)
                            .background(Capsule().fill(Color.white))
                            .overlay(Capsule().strokeBorder(other ? Palette.ink : Palette.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.fill))
    }

    private func chip(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name).font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.ink : Palette.secondary)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Play / pause, where in the file, and the speed, for an imported record.
struct RecordingPlayerBar: View {
    @ObservedObject var player: RecordingPlayer

    var body: some View {
        if player.missing {
            Text(player.own ? L("找不到录音，没法播放") : L("找不到原文件，没法播放")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        } else if player.ready {
            HStack(spacing: 12) {
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Circle().fill(Palette.ink))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(player.playing ? L("暂停") : L("播放"))
                .accessibilityLabel(player.playing ? L("暂停") : L("播放"))
                Text(TranscriptExport.clock(player.time)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary)
                Slider(value: Binding(get: { min(player.time, max(player.length, 1)) }, set: { player.seek($0) }),
                       in: 0...max(player.length, 1))
                    .controlSize(.small).tint(Palette.accent)
                Text(TranscriptExport.clock(player.length)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary)
                Button { player.nextRate() } label: {
                    Text(player.rate == 1 ? "1×" : player.rate == 1.5 ? "1.5×" : "2×")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
                }
                .buttonStyle(.plain).help(L("播放速度"))
            }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))
        }
    }
}

/// Over the whole main window while files are dragged onto it.
struct ImportDropOverlay: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line").font(.system(size: 26, weight: .medium)).foregroundStyle(Palette.ink)
            Text("松开，开始转写").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Text("录音或视频，一次可放多个").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(12))
        .allowsHitTesting(false)
    }
}

/// Three bars that bounce beside the line the recording is playing; nothing while paused.
struct PlayingBars: View {
    var on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if on {
            TimelineView(.animation(paused: reduceMotion)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        let h = reduceMotion ? 0.7 : 0.35 + 0.65 * abs(sin(t * 3.5 + Double(i) * 0.9))
                        Capsule().fill(Palette.accent).frame(width: 3, height: 12 * h)
                    }
                }
                .frame(height: 12, alignment: .bottom)
            }
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 12)
        }
    }
}
