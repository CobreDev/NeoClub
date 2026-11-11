import Foundation

/// Sends listening progress to the AIO account (PUT /content), like the official app.
///
/// Rules:
/// - Nothing is written for an episode that was only opened: real playback must happen first.
/// - Progress is reported every 30 s while playing, on pause/switch, and on finish.
/// - Debug builds default to NOT syncing, so testing never touches real listening history.
@MainActor
final class ProgressSync {
    static let enabledKey = "syncProgress"

    /// Release builds sync by default; debug builds must opt in (Library → Developer).
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                #if DEBUG
                return false
                #else
                return true
                #endif
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private var episodeID: String?
    private var durationMs = 0
    private var serverWasComplete = false
    private var hasPlayed = false
    private var lastSentMs: Int?
    private var lastReport = Date.distantPast

    func begin(episodeID: String, serverProgress: ListenProgress?, durationMs: Int) {
        self.episodeID = episodeID
        self.durationMs = durationMs
        serverWasComplete = serverProgress?.isComplete ?? false
        hasPlayed = false
        lastSentMs = serverProgress?.currentProgress
        lastReport = Date()
    }

    func didResume() { hasPlayed = true }

    func shouldReportPeriodically() -> Bool {
        hasPlayed && Date().timeIntervalSince(lastReport) >= 30
    }

    /// `onLocalUpdate` always runs so the UI reflects progress, even when syncing is off.
    func report(positionMs: Int, finished: Bool, onLocalUpdate: @escaping (ListenProgress) -> Void) {
        guard let episodeID, hasPlayed else { return }
        lastReport = Date()
        let nearEnd = durationMs > 0 && positionMs >= durationMs - 30_000
        let complete = finished || nearEnd
        // Replaying a finished episode keeps it marked finished.
        let status = (complete || serverWasComplete) ? "Complete" : "In Progress"
        let progress = ListenProgress(status: status, currentProgress: positionMs)
        onLocalUpdate(progress)

        guard Self.isEnabled, positionMs != lastSentMs else { return }
        lastSentMs = positionMs
        if complete { serverWasComplete = true }
        Task {
            do {
                try await AIOService.saveProgress(episodeID: episodeID, status: status, positionMs: positionMs)
            } catch {
                SignInLog.write("progress sync failed: \(error.localizedDescription)")
            }
        }
    }
}
