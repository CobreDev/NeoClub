import Foundation

/// The version shown in Account: marketing version, build number and the commit the build came from, so a build on
/// a phone can always be traced back to its source (scripts/make-release.sh tags each release `build-<number>`).
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        let commit = info?["NeoClubCommit"] as? String ?? ""
        return commit.isEmpty ? "\(version) (\(build))" : "\(version) (\(build) · \(commit))"
    }
}
