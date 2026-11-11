import AVFoundation
import MediaPlayer
import SwiftUI

/// App-wide audio engine: streaming/offline playback, lock-screen controls, queue, and progress sync.
@MainActor
@Observable
final class AudioPlayer {
    static let shared = AudioPlayer()

    private(set) var episode: Episode?
    private(set) var queue: [Episode] = []
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    var rate: Float = 1.0 { didSet { if isPlaying { player.rate = rate } } }
    var showNowPlaying = false

    /// Latest known progress per episode, so lists update immediately while listening.
    private(set) var progressOverrides: [String: ListenProgress] = [:]

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var artwork: MPMediaItemArtwork?
    private let sync = ProgressSync()

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        configureRemoteCommands()
    }

    // MARK: Public API

    var hasItem: Bool { episode != nil }
    var progressFraction: Double { duration > 0 ? position / duration : 0 }

    func progress(for item: Episode) -> ListenProgress? {
        progressOverrides[item.id] ?? item.progress
    }

    /// Plays an episode, resuming from the profile's saved position. `queue` is the rest of its album/list.
    func play(_ item: Episode, queue: [Episode] = [], groupingID: String? = nil) {
        Task { await load(item, queue: queue, groupingID: groupingID) }
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func resume() {
        guard episode != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: rate)
        isPlaying = true
        sync.didResume()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        reportProgress()
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration > 0 ? duration - 1 : seconds))
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNowPlaying() }
        }
    }

    func skip(by seconds: Double) { seek(to: position + seconds) }

    func playNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        play(next, queue: queue)
    }

    func stop() {
        if episode != nil { reportProgress() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        episode = nil
        queue = []
        isPlaying = false
        position = 0
        duration = 0
        showNowPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Loading

    private func load(_ item: Episode, queue: [Episode], groupingID: String?) async {
        if let current = episode, current.id != item.id { reportProgress() }
        isLoading = true
        errorMessage = nil
        episode = item
        self.queue = queue
        defer { isLoading = false }

        do {
            let local = DownloadStore.shared.localFile(for: item.id)
            // Detail gives signed stream URLs and the authoritative saved position for this profile.
            let detail: Episode
            if let fetched = try? await AIOService.episode(item.id, groupingID: groupingID) {
                detail = fetched
            } else if local != nil, let cached = DownloadStore.shared.episode(for: item.id) {
                detail = cached
            } else {
                throw APIError.decoding("Couldn't load this episode.")
            }
            guard episode?.id == item.id else { return }
            episode = detail

            let asset: AVURLAsset
            if let local {
                asset = AVURLAsset(url: local)
            } else if let stream = URL.aio(detail.streamURL) {
                asset = AVURLAsset(url: stream, options: [AVURLAssetHTTPCookiesKey: Self.cloudFrontCookies(from: detail.signedCookie)])
            } else {
                throw APIError.decoding("This episode isn't available to stream.")
            }

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let playerItem = AVPlayerItem(asset: asset)
            playerItem.audioTimePitchAlgorithm = .timeDomain
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didFinish() }
            }
            player.replaceCurrentItem(with: playerItem)

            duration = Double(detail.mediaLength ?? 0) / 1000
            let saved = progress(for: detail)
            sync.begin(episodeID: detail.id, serverProgress: saved, durationMs: detail.mediaLength ?? 0)
            let start = Self.resumePoint(saved, durationSeconds: duration)
            position = start
            if start > 0 { await player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }

            loadArtwork(detail.artworkURL)
            resume()
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    /// Resume where the profile left off; finished (or nearly finished) episodes start over.
    static func resumePoint(_ progress: ListenProgress?, durationSeconds: Double) -> Double {
        guard let progress, progress.isInProgress, let ms = progress.currentProgress else { return 0 }
        let seconds = Double(ms) / 1000
        if durationSeconds > 0 && seconds > durationSeconds - 15 { return 0 }
        return seconds
    }

    /// The API returns `…/AppleHLS1/*?Policy=…&Signature=…&Key-Pair-Id=…`; HLS segments need these as CloudFront cookies.
    static func cloudFrontCookies(from signed: String?) -> [HTTPCookie] {
        guard let signed, let comps = URLComponents(string: signed), let host = comps.host else { return [] }
        let path = comps.path.replacingOccurrences(of: "/*", with: "")
        let names = ["Policy": "CloudFront-Policy", "Signature": "CloudFront-Signature", "Key-Pair-Id": "CloudFront-Key-Pair-Id"]
        return (comps.queryItems ?? []).compactMap { item in
            guard let name = names[item.name], let value = item.value else { return nil }
            return HTTPCookie(properties: [.domain: host, .path: path.isEmpty ? "/" : path,
                                           .name: name, .value: value, .secure: "TRUE"])
        }
    }

    // MARK: Ticks, end, progress

    private func tick(_ time: CMTime) {
        guard episode != nil else { return }
        if time.isNumeric { position = time.seconds }
        if let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0 { duration = d.seconds }
        isPlaying = player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if isPlaying, sync.shouldReportPeriodically() { reportProgress() }
    }

    private func didFinish() {
        guard let episode else { return }
        position = duration
        sync.report(positionMs: Int(duration * 1000), finished: true) { [weak self] p in self?.progressOverrides[episode.id] = p }
        isPlaying = false
        if !queue.isEmpty { playNext() } else { updateNowPlaying() }
    }

    private func reportProgress() {
        guard let episode else { return }
        let ms = Int(position * 1000)
        sync.report(positionMs: ms, finished: false) { [weak self] p in self?.progressOverrides[episode.id] = p }
    }

    // MARK: Lock screen / Control Center

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.togglePlayPause() }; return .success }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.skip(by: -15) }; return .success }
        c.skipForwardCommand.preferredIntervals = [30]
        c.skipForwardCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.skip(by: 30) }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.playNext() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let episode else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyAlbumTitle: episode.albumName ?? "Adventures in Odyssey",
            MPMediaItemPropertyArtist: "Adventures in Odyssey",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = !queue.isEmpty
    }

    private func loadArtwork(_ url: URL?) {
        artwork = nil
        guard let url else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            updateNowPlaying()
        }
    }
}
