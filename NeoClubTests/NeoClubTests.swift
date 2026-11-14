import Foundation
import Testing
@testable import NeoClub

/// Builds an Episode the way the API sends one.
private func episode(_ id: String, name: String? = nil, shortName: String? = nil, number: String? = nil,
                     progress: (String, Int)? = nil) -> Episode {
    var json: [String: Any] = ["id": id]
    if let name { json["name"] = name }
    if let shortName { json["short_name"] = shortName }
    if let number { json["episode_number"] = number }
    if let progress { json["progress"] = ["status": progress.0, "current_progress": progress.1] }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(Episode.self, from: data)
}

@Suite struct TitleTests {
    @Test func plainNumberIsStrippedFromTitle() {
        #expect(episode("a", name: "#572: Odyssey Sings!").title == "Odyssey Sings!")
    }

    @Test func bonusNumberStaysInTitle() {
        // Only all-digit prefixes are stripped; "572d" keeps its number.
        #expect(episode("a", name: "#572d: BONUS! Song").title == "#572d: BONUS! Song")
    }

    @Test func numberedTitleKeepsServerName() {
        #expect(episode("a", name: "#572: Odyssey Sings!").numberedTitle == "#572: Odyssey Sings!")
        #expect(episode("a", name: "#572d: BONUS! Song").numberedTitle == "#572d: BONUS! Song")
    }

    @Test func numberedTitleAddsMissingNumber() {
        #expect(episode("a", name: "Whit's Flop", number: "001").numberedTitle == "#001: Whit's Flop")
        #expect(episode("a", name: "Whit's Flop").numberedTitle == "Whit's Flop")
    }
}

@Suite @MainActor struct ResumeTests {
    @Test func noProgressStartsAtBeginning() {
        #expect(AudioPlayer.resumePoint(nil, durationSeconds: 1300) == 0)
    }

    @Test func inProgressResumes() {
        #expect(AudioPlayer.resumePoint(ListenProgress(status: "In Progress", currentProgress: 120_000), durationSeconds: 1300) == 120)
    }

    @Test func nearTheEndStartsOver() {
        #expect(AudioPlayer.resumePoint(ListenProgress(status: "In Progress", currentProgress: 1_290_000), durationSeconds: 1300) == 0)
    }

    @Test func finishedStartsOver() {
        #expect(AudioPlayer.resumePoint(ListenProgress(status: "Complete", currentProgress: 1_300_000), durationSeconds: 1300) == 0)
    }
}

@Suite @MainActor struct NextUpTests {
    @Test func catalogIsNumberedDeduplicatedAndOrdered() {
        let list = [
            episode("c", shortName: "#1041: Later"),
            episode("bonus", shortName: "#572b: BONUS! Song"),
            episode("a", shortName: "#12: Early"),
            episode("b", number: "100"),
            episode("a", shortName: "#12: Early"),
            episode("odd", shortName: "No number"),
        ]
        #expect(NextUpStore.ordered(list).map(\.id) == ["a", "b", "c"])
    }

    @Test func nextAfterFinishedEpisodeSkipsDoneAndStarted() {
        // Finished Babysitting Bassetts → Teambuilding University is next (the user's own example); finished or
        // started episodes in between are skipped.
        let catalog = [
            episode("bassetts", number: "1050"),
            episode("done", number: "1051"),
            episode("started", number: "1052", progress: ("In Progress", 60_000)),
            episode("teambuilding", number: "1053"),
            episode("after", number: "1054"),
        ]
        let next = NextUpStore.nextEpisodes(catalog: catalog, seeds: ["bassetts"], inProgress: []) { $0.id == "done" }
        #expect(next.map(\.id) == ["teambuilding"])
    }

    @Test func continueListeningIsNotRepeated() {
        let catalog = [episode("x", number: "1"), episode("y", number: "2"), episode("z", number: "3")]
        let next = NextUpStore.nextEpisodes(catalog: catalog, seeds: ["x", "y"], inProgress: ["y"]) { _ in false }
        #expect(next.map(\.id) == ["z"])
    }
}

@Suite struct ImageAndStreamTests {
    @Test func decodeSizeBuckets() {
        #expect(ImagePipeline.bucket(forPixels: 100) == 128)
        #expect(ImagePipeline.bucket(forPixels: 450) == 512)
        #expect(ImagePipeline.bucket(forPixels: 5000) == 2048)
    }

    @Test @MainActor func cloudFrontCookiesFromSignedURL() {
        let cookies = AudioPlayer.cloudFrontCookies(
            from: "https://media.example.com/private/audio/AppleHLS1/*?Policy=P&Signature=S&Key-Pair-Id=K")
        let byName = Dictionary(uniqueKeysWithValues: cookies.map { ($0.name, $0.value) })
        #expect(byName == ["CloudFront-Policy": "P", "CloudFront-Signature": "S", "CloudFront-Key-Pair-Id": "K"])
        #expect(cookies.allSatisfy { $0.path == "/private/audio/AppleHLS1" && $0.domain == "media.example.com" })
    }
}

@Suite struct ReleaseDateTests {
    private func released(_ airDate: String) -> Episode {
        try! JSONDecoder().decode(Episode.self, from: Data(#"{"id":"a","air_date":"\#(airDate)"}"#.utf8))
    }

    @Test func midnightCentralShowsTheSameDayInEveryTimeZone() {
        let date = released("2005-10-29T06:00:00.000Z").releaseDate
        #expect(date != nil)
        #expect(Episode.releaseText(date!).contains("29"))
        #expect(Episode.releaseText(date!).contains("2005"))
    }

    @Test func missingOrMalformedDateIsNil() {
        #expect(released("").releaseDate == nil)
        #expect(released("soon").releaseDate == nil)
    }
}

@Suite struct BonusContentTests {
    private func episode(name: String, number: String? = nil) -> Episode {
        let n = number.map { #","episode_number":"\#($0)""# } ?? ""
        return try! JSONDecoder().decode(Episode.self, from: Data(#"{"id":"a","name":"\#(name)"\#(n)}"#.utf8))
    }

    @Test func letteredNumbersAndBonusTitlesAreBonus() {
        #expect(episode(name: "#572d: Odyssey Sings!").isBonus)
        #expect(episode(name: "Odyssey Sings!", number: "572d").isBonus)
        #expect(episode(name: "BONUS! A Message from Whit").isBonus)
    }

    @Test func regularEpisodesAreNot() {
        #expect(!episode(name: "#1041: Whit's Flop").isBonus)
        #expect(!episode(name: "Whit's Flop", number: "1041").isBonus)
    }
}
