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
    /// How many episodes at the front of `queue` were added with Play Next / Play Last (Apple Music's "Playing
    /// Next"); the rest is the album or list the current episode was started from.
    private(set) var addedCount = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    var rate: Float = 1.0 { didSet { if isPlaying { player.rate = rate } } }
    var showNowPlaying = false { didSet { if showNowPlaying { startPendingRestore() } } }
    /// Album/collection the current episode was started from (for "Go to Album").
    private(set) var groupingID: String?
    /// Recently played episodes, newest first, persisted across launches.
    private(set) var history: [HistoryEntry] = HistoryEntry.load()
    /// Set to ask the tab shell to dismiss Now Playing and navigate somewhere.
    var navigationRequest: Route?

    // MARK: Sleep timer (like Apple Podcasts)
    enum SleepTimer: Hashable { case off, minutes(Int), seconds(Int), endOfEpisode }
    private(set) var sleepTimer: SleepTimer = .off
    private(set) var sleepEndsAt: Date?
    private var sleepTask: Task<Void, Never>?

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTimer = timer
        sleepEndsAt = nil
        var seconds = 0
        if case .minutes(let m) = timer { seconds = m * 60 }
        if case .seconds(let s) = timer { seconds = s }
        if seconds > 0 {
            let end = Date().addingTimeInterval(TimeInterval(seconds))
            sleepEndsAt = end
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(seconds)))
                guard !Task.isCancelled, let self else { return }
                self.pause()
                self.sleepTimer = .off
                self.sleepEndsAt = nil
            }
        }
    }

    struct HistoryEntry: Codable, Identifiable, Hashable {
        let id: String
        let title: String
        let album: String?
        let artwork: String?
        var playedAt: Date

        static let key = "playHistory"

        /// A stand-in episode (pages and playback load the full details).
        var episodeStub: Episode? {
            var json: [String: Any] = ["id": id, "name": title]
            if let album { json["album_name"] = album }
            if let artwork { json["thumbnail_medium"] = artwork; json["thumbnail_small"] = artwork }
            guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
            return try? JSONDecoder().decode(Episode.self, from: data)
        }
        static func load() -> [HistoryEntry] {
            guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([HistoryEntry].self, from: d)) ?? []
        }
    }

    /// Latest known progress per episode, so lists update immediately while listening.
    private(set) var progressOverrides: [String: ListenProgress] = [:]

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var artwork: MPMediaItemArtwork?
    /// The current episode's artwork, loaded once and shared by the lock screen and Now Playing (so the artwork
    /// never reloads while it moves between the player and Up Next).
    private(set) var artworkImage: UIImage?
    private let sync = ProgressSync()

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        configureRemoteCommands()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistSession() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.route = AudioRoute.current }
        }
    }

    /// Where audio is going right now (kept current as headphones, cars and AirPlay come and go).
    private(set) var route = AudioRoute.current

    // MARK: Last session (the mini player is always there, showing what was playing last)

    private struct Session: Codable {
        let id: String, title: String, album: String?, artwork: String?, groupingID: String?
        let positionMs: Int, durationMs: Int
        static let key = "lastSession"
    }
    private var lastPersist = Date.distantPast

    /// Saves what's loaded and where, so the next launch can show it in the mini player.
    private func persistSession() {
        guard let e = episode else { return }
        lastPersist = Date()
        // The full name (with its "#572: " number) so the restored Now Playing title matches.
        let s = Session(id: e.id, title: e.name ?? e.title, album: e.albumTitle, artwork: e.thumbnailMedium ?? e.thumbnailSmall,
                        groupingID: groupingID, positionMs: Int(position * 1000),
                        durationMs: e.mediaLength ?? Int(duration * 1000))
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: Session.key)
    }

    /// At launch: show the last episode in the mini player right away, then load it paused where it left off.
    /// Nothing plays and nothing is synced until Play.
    func restoreLastSession() {
        guard episode == nil, let data = UserDefaults.standard.data(forKey: Session.key),
              let s = try? JSONDecoder().decode(Session.self, from: data) else { return }
        var json: [String: Any] = ["id": s.id, "name": s.title, "media_length": s.durationMs]
        if let album = s.album { json["album_name"] = album }
        if let art = s.artwork { json["thumbnail_medium"] = art; json["thumbnail_small"] = art }
        guard let raw = try? JSONSerialization.data(withJSONObject: json),
              let stub = try? JSONDecoder().decode(Episode.self, from: raw) else { return }
        episode = stub
        duration = Double(s.durationMs) / 1000
        position = Double(s.positionMs) / 1000
        // Where this device left off, unless the account has newer progress (the detail fetch decides).
        if s.positionMs > 0 { localResume[s.id] = s.positionMs }
        // The mini player is filled in now (artwork from the image cache); loading the episode itself (an API
        // request and the audio) waits until after launch, or until it's needed (Play, or opening Now Playing).
        loadArtwork(stub.artworkURL)
        pendingRestore = (stub, s.groupingID)
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.startPendingRestore()
        }
    }

    private var pendingRestore: (episode: Episode, groupingID: String?)?
    private var restoreTask: Task<Void, Never>?

    /// Loads the restored episode now, paused (or playing, for Play), if it hasn't been yet.
    private func startPendingRestore(autoplay: Bool = false) {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        restoreTask?.cancel()
        Task { await load(pending.episode, queue: [], groupingID: pending.groupingID, autoplay: autoplay) }
    }
    /// Positions saved on this device, used when the account has no in-progress position for the episode.
    private var localResume: [String: Int] = [:]

    // MARK: Public API

    var hasItem: Bool { episode != nil }
    var progressFraction: Double { duration > 0 ? position / duration : 0 }

    func progress(for item: Episode) -> ListenProgress? {
        if let override = progressOverrides[item.id] { return override }
        if finishedHere.contains(item.id), !(item.progress?.isComplete ?? false) {
            return ListenProgress(status: "Complete", currentProgress: item.mediaLength)
        }
        return item.progress
    }

    /// Clears an episode's progress so it reads as new again (status "New" at 0). Only syncs when progress sync is on.
    func markUnplayed(_ item: Episode) {
        progressOverrides[item.id] = ListenProgress(status: "New", currentProgress: 0)
        if finishedHere.remove(item.id) != nil {
            UserDefaults.standard.set(Array(finishedHere), forKey: "finishedHere")
        }
        guard ProgressSync.isEnabled else { return }
        Task {
            try? await AIOService.saveProgress(episodeID: item.id, status: "New", positionMs: 0)
        }
    }

    /// Episodes finished in this app on this device, remembered across launches. They count as played everywhere
    /// in the app even when progress sync is off, so the account never has to hear about them.
    private(set) var finishedHere: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "finishedHere") ?? [])

    private func rememberFinished(_ id: String) {
        guard !finishedHere.contains(id) else { return }
        finishedHere.insert(id)
        UserDefaults.standard.set(Array(finishedHere), forKey: "finishedHere")
    }

    /// Marks an episode finished, like the official app's "Mark as Complete": the same progress update playback
    /// sends at the end (status Complete at the full length). Only syncs when progress sync is on.
    /// Marks every episode of an album played or unplayed (Mark Album as Played/Unplayed). The app updates at once;
    /// the account gets the same per-episode updates as Mark as Played/Unplayed, sent one at a time with a short
    /// pause between them. Only syncs when progress sync is on.
    func markAll(_ items: [Episode], played: Bool) {
        let items = items.filter { (progress(for: $0)?.isComplete ?? false) != played }
        guard !items.isEmpty else { return }
        for item in items {
            if played {
                progressOverrides[item.id] = ListenProgress(status: "Complete", currentProgress: item.mediaLength ?? 0)
                finishedHere.insert(item.id)
            } else {
                progressOverrides[item.id] = ListenProgress(status: "New", currentProgress: 0)
                finishedHere.remove(item.id)
            }
        }
        UserDefaults.standard.set(Array(finishedHere), forKey: "finishedHere")
        guard ProgressSync.isEnabled else { return }
        Task {
            for item in items {
                do {
                    var length = item.mediaLength ?? 0
                    if played && length == 0 { length = (try? await AIOService.episode(item.id))?.mediaLength ?? 0 }
                    try await AIOService.saveProgress(episodeID: item.id, status: played ? "Complete" : "New",
                                                      positionMs: played ? length : 0)
                } catch {}
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func markPlayed(_ item: Episode) {
        let length = item.mediaLength ?? 0
        rememberFinished(item.id)
        progressOverrides[item.id] = ListenProgress(status: "Complete", currentProgress: length)
        guard ProgressSync.isEnabled else { return }
        Task {
            do {
                // Lists like search results don't carry the length; the details do.
                var length = length
                if length == 0 { length = (try? await AIOService.episode(item.id))?.mediaLength ?? 0 }
                try await AIOService.saveProgress(episodeID: item.id, status: "Complete", positionMs: length)
            } catch {}
        }
    }

    /// Plays an episode, resuming from the profile's saved position. `queue` is the rest of its album/list.
    func play(_ item: Episode, queue: [Episode] = [], groupingID: String? = nil) {
        addedCount = 0
        start(item, queue: queue, groupingID: groupingID)
    }

    private func start(_ item: Episode, queue: [Episode], groupingID: String?) {
        Task { await load(item, queue: queue, groupingID: groupingID) }
    }

    /// Apple Music's Play Next: plays right after the current episode, ahead of anything queued before.
    /// With nothing loaded, it just plays.
    func queueNext(_ item: Episode) {
        guard episode != nil else { play(item); return }
        removeFromQueue(item)
        queue.insert(item, at: 0)
        addedCount += 1
        updateNowPlaying()
    }

    /// Apple Music's Play Last: after the other episodes you've added, before the rest of the album.
    func queueLast(_ item: Episode) {
        guard episode != nil else { play(item); return }
        removeFromQueue(item)
        queue.insert(item, at: addedCount)
        addedCount += 1
        updateNowPlaying()
    }

    private func removeFromQueue(_ item: Episode) {
        guard let i = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue.remove(at: i)
        if i < addedCount { addedCount -= 1 }
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func resume() {
        guard episode != nil else { return }
        // Play pressed on the restored mini player before its episode finished loading: load it and play.
        if pendingRestore != nil { startPendingRestore(autoplay: true); return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: rate)
        isPlaying = true
        sync.didResume()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        persistSession()
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
        addedCount = max(0, addedCount - 1)
        start(next, queue: queue, groupingID: groupingID)
    }

    /// Jumps to an episode in Up Next, keeping the episodes after it queued.
    func playQueued(_ item: Episode) {
        guard let i = queue.firstIndex(where: { $0.id == item.id }) else { return }
        addedCount = max(0, addedCount - (i + 1))
        start(item, queue: Array(queue.dropFirst(i + 1)), groupingID: groupingID)
    }

    /// Replays something from History (its album context isn't kept, so nothing is queued after it).
    func playFromHistory(_ entry: HistoryEntry) {
        guard let stub = entry.episodeStub else { return }
        play(stub)
    }

    /// Name of the current audio output, e.g. "Cooper's AirPods Pro" or "iPhone".
    var outputName: String { route.name }

    private func recordHistory(_ e: Episode) {
        history.removeAll { $0.id == e.id }
        history.insert(HistoryEntry(id: e.id, title: e.title, album: e.albumTitle,
                                    artwork: e.thumbnailMedium ?? e.thumbnailSmall, playedAt: Date()), at: 0)
        history = Array(history.prefix(50))
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: HistoryEntry.key)
    }

    func stop() {
        pendingRestore = nil
        restoreTask?.cancel()
        prefetched = nil
        if episode != nil { reportProgress() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        episode = nil
        queue = []
        addedCount = 0
        isPlaying = false
        position = 0
        duration = 0
        showNowPlaying = false
        UserDefaults.standard.removeObject(forKey: Session.key)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Loading

    private func load(_ item: Episode, queue: [Episode], groupingID: String?, autoplay: Bool = true) async {
        if let current = episode, current.id != item.id { reportProgress() }
        isLoading = true
        errorMessage = nil
        episode = item
        self.queue = queue
        self.groupingID = groupingID
        defer { isLoading = false }

        do {
            let local = DownloadStore.shared.localFile(for: item.id)
            // Detail gives signed stream URLs and the authoritative saved position for this profile.
            let detail: Episode
            let ready = prefetched?.id == item.id ? prefetched : nil
            prefetched = nil
            if let ready {
                detail = ready.detail
            } else if let fetched = try? await AIOService.episode(item.id, groupingID: groupingID) {
                detail = fetched
            } else if local != nil, let cached = DownloadStore.shared.episode(for: item.id) {
                detail = cached
            } else {
                throw APIError.decoding("Couldn't load this episode.")
            }
            guard episode?.id == item.id else { return }
            episode = detail
            recordHistory(detail)

            guard let asset = ready?.asset ?? Self.makeAsset(detail, local: local) else {
                throw APIError.decoding("This episode isn't available to stream.")
            }

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            // Restoring at launch stays silent: don't take the audio session from other apps until Play.
            if autoplay { try AVAudioSession.sharedInstance().setActive(true) }

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
            var start = Self.resumePoint(saved, durationSeconds: duration)
            if let local = localResume.removeValue(forKey: detail.id), !(saved?.isComplete ?? false) {
                // Restored session: keep this device's place if it's further along than the account's.
                start = max(start, Self.resumePoint(ListenProgress(status: "In Progress", currentProgress: local),
                                                    durationSeconds: duration))
            }
            position = start
            if start > 0 { await player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }

            loadArtwork(detail.artworkURL)
            persistSession()
            if autoplay { resume() }
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    private static func makeAsset(_ detail: Episode, local: URL?) -> AVURLAsset? {
        if let local { return AVURLAsset(url: local) }
        guard let stream = URL.aio(detail.streamURL) else { return nil }
        return AVURLAsset(url: stream, options: [AVURLAssetHTTPCookiesKey: cloudFrontCookies(from: detail.signedCookie)])
    }

    // MARK: Preloading the next episode

    /// The next queued episode's details and audio, fetched shortly before the current one ends so it starts
    /// without a gap.
    private var prefetched: (id: String, detail: Episode, asset: AVURLAsset)?
    private var prefetchTask: Task<Void, Never>?

    private func prefetchNextIfNeeded() {
        guard isPlaying, duration > 0, duration - position < 45, let next = queue.first,
              prefetched?.id != next.id, prefetchTask == nil else { return }
        let grouping = groupingID
        prefetchTask = Task { [weak self] in
            defer { self?.prefetchTask = nil }
            let local = DownloadStore.shared.localFile(for: next.id)
            let detail: Episode? = if let fetched = try? await AIOService.episode(next.id, groupingID: grouping) {
                fetched
            } else if local != nil {
                DownloadStore.shared.episode(for: next.id)
            } else {
                nil
            }
            guard let detail, let asset = Self.makeAsset(detail, local: local) else { return }
            _ = try? await asset.load(.isPlayable)
            self?.prefetched = (next.id, detail, asset)
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
        // Only set what changed: every set of an observed property redraws everything that reads it.
        if time.isNumeric, time.seconds != position { position = time.seconds }
        if let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0, d.seconds != duration { duration = d.seconds }
        let playing = player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if playing != isPlaying { isPlaying = playing }
        if isPlaying, sync.shouldReportPeriodically() { reportProgress() }
        if isPlaying, Date().timeIntervalSince(lastPersist) > 10 { persistSession() }
        prefetchNextIfNeeded()
    }

    private func didFinish() {
        guard let episode else { return }
        position = duration
        rememberFinished(episode.id)
        sync.report(positionMs: Int(duration * 1000), finished: true) { [weak self] p in self?.progressOverrides[episode.id] = p }
        isPlaying = false
        if sleepTimer == .endOfEpisode {
            sleepTimer = .off
            updateNowPlaying()
        } else if !queue.isEmpty { playNext() } else { updateNowPlaying() }
    }

    private func reportProgress() {
        guard let episode else { return }
        let ms = Int(position * 1000)
        // Within the last 30 seconds counts as finished (the same rule progress sync uses).
        if duration > 60, position >= duration - 30 { rememberFinished(episode.id) }
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
            MPMediaItemPropertyAlbumTitle: episode.albumTitle ?? "Adventures in Odyssey",
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
        artworkImage = nil
        guard let url else { return }
        // Make Now Playing's blurred backdrop now, so it's there the moment the card opens (made on open, the card
        // showed its plain fill and then faded the art in: a flash).
        Task { _ = await ImagePipeline.shared.blurred(url, radius: NowPlayingBackdrop.blurRadius, saturation: NowPlayingBackdrop.saturation) }
        Task {
            guard let image = await ImagePipeline.shared.image(url, pixels: 1024) else { return }
            artworkImage = image
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            updateNowPlaying()
        }
    }
}
