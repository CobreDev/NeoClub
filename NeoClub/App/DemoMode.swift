#if SCREENSHOT_DEMO
import Foundation

/// Screenshot demo mode, compiled only with `-DSCREENSHOT_DEMO` (see scripts/screenshots.sh), so no normal build or
/// release contains any of it. Launch with `-demoScreen home|browse|album|episode|nowplaying|upnext|info`.
///
/// What it does, so a signed-in account can be photographed without showing anything personal:
/// - Home is only the newest albums and episodes (`DemoHome`): no promo carousel, Continue Listening, Next Up, bookmarks or
///   recommendations; listening progress is hidden everywhere: no "min left" bars, no played checkmarks (`AudioPlayer.progress(for:)` returns nil), and nothing is ever sent to the account
///   (`ProgressSync.isEnabled` is always false);
/// - the player holds #001 Whit's Flop with the rest of its album queued, paused at 0:42.
enum Demo {
    /// `-demoScreen <name>`, if given.
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    /// #001 Whit's Flop, the only episode the demo plays.
    static let episodeID = "a354W0000046TjUQAU"
}
#endif
