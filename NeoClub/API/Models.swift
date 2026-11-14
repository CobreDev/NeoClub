import Foundation

// Models verified against live responses (see docs/original-app-analysis.md).
// Decoding is deliberately lenient: every field except `id` is optional.

struct Profile: Decodable, Identifiable, Hashable {
    let viewerID: String
    let nickname: String?
    let username: String?
    let hasPIN: Bool
    let accountOwner: Bool
    let profilePicture: String?
    let avatarPath: String?

    var id: String { viewerID }
    var displayName: String { nickname ?? username ?? "Listener" }
    var pictureURL: URL? { .aio(profilePicture ?? avatarPath) }

    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", nickname, username, hasPIN
        case accountOwner = "account_owner", profilePicture = "profile_picture", avatarPath = "avatar_path"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewerID = try c.decode(String.self, forKey: .viewerID)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        hasPIN = (try? c.decodeIfPresent(Bool.self, forKey: .hasPIN)) ?? false
        accountOwner = (try? c.decodeIfPresent(Bool.self, forKey: .accountOwner)) ?? false
        profilePicture = try? c.decodeIfPresent(String.self, forKey: .profilePicture)
        avatarPath = try? c.decodeIfPresent(String.self, forKey: .avatarPath)
    }
}

struct ProfilesResponse: Decodable {
    let profiles: [Profile]
}

struct ListenProgress: Codable, Hashable {
    var status: String?
    /// Milliseconds into the episode.
    var currentProgress: Int?

    var isComplete: Bool { status == "Complete" }
    var isInProgress: Bool { status == "In Progress" && (currentProgress ?? 0) > 0 }

    /// When this profile last listened (ISO 8601), on list items that include it.
    var activityAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case status, currentProgress = "current_progress", activityAt = "content_activity_time_stamp"
    }

    init(status: String?, currentProgress: Int?) {
        self.status = status
        self.currentProgress = currentProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        currentProgress = c.lenientInt(.currentProgress)
        activityAt = try? c.decodeIfPresent(String.self, forKey: .activityAt)
    }
}

/// An Odyssey character (Whit, Connie, Zoe…), as embedded in episodes and from /character/{id}.
struct CastMember: Decodable, Hashable, Identifiable {
    struct Photo: Decodable, Hashable { let small: String?; let medium: String?; let large: String? }

    let characterID: String?
    let name: String?
    let nickname: String?
    let job: String?
    let thumbnailSmall: String?
    let thumbnailMedium: String?
    let thumbnailLarge: String?
    let voicedBy: String?
    let voicedByID: String?
    let bio: String?
    let photos: [Photo]?
    let featuredIn: [Episode]?

    var id: String { characterID ?? name ?? "character" }
    var avatarURL: URL? { .aio(thumbnailMedium ?? thumbnailSmall ?? thumbnailLarge) }
    var largeURL: URL? { .aio(thumbnailLarge ?? thumbnailMedium ?? thumbnailSmall) }

    enum CodingKeys: String, CodingKey {
        case characterID = "id", name, nickname, job, photos
        case thumbnailSmall = "thumbnail_small", thumbnailMedium = "thumbnail_medium", thumbnailLarge = "thumbnail_large"
        case voicedBy = "voiced_by", voicedByID = "voiced_by_id", bio = "character_bio", featuredIn = "featured_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characterID = c.string(.characterID); name = c.string(.name); nickname = c.string(.nickname); job = c.string(.job)
        thumbnailSmall = c.string(.thumbnailSmall); thumbnailMedium = c.string(.thumbnailMedium); thumbnailLarge = c.string(.thumbnailLarge)
        voicedBy = c.string(.voicedBy); voicedByID = c.string(.voicedByID); bio = c.string(.bio)
        photos = try? c.decodeIfPresent([Photo].self, forKey: .photos)
        featuredIn = try? c.decodeIfPresent([Episode].self, forKey: .featuredIn)
    }

    static func == (a: CastMember, b: CastMember) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A real person in the cast & crew (actor, writer, director), from episodes and /author/{id}.
struct Author: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let role: String?
    let bio: String?
    let profileImageUrl: String?
    var imageURL: URL? { .aio(profileImageUrl) }

    enum CodingKeys: String, CodingKey { case id, name, role, bio, profileImageUrl }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.string(.name); role = c.string(.role); bio = c.string(.bio); profileImageUrl = c.string(.profileImageUrl)
    }
}

/// An episode, podcast or video. The same shape appears in lists and in full detail;
/// detail-only fields (stream URLs, cast, album list) are nil in lists.
struct Episode: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let shortName: String?
    let type: String?
    let subtype: String?
    let episodeNumber: String?
    var albumName: String?
    /// The album's grouping ID, found from the library when the episode is fetched (not part of the response).
    var albumID: String?
    let description: String?
    let airDate: String?
    /// Milliseconds.
    let mediaLength: Int?
    let thumbnailSmall: String?
    let thumbnailMedium: String?
    let thumbnailLarge: String?
    var progress: ListenProgress?

    // Detail-only
    let streamURL: String?
    let signedCookie: String?
    let downloadURL: String?
    let characters: [CastMember]?
    let authors: [Author]?
    let inAlbum: [Episode]?
    let isBookmarked: Bool?

    /// Display title without a leading "#1035: " (the number is shown separately).
    var title: String {
        let raw = name ?? shortName ?? "Episode"
        guard raw.hasPrefix("#"), let colon = raw.firstIndex(of: ":"),
              raw[raw.index(after: raw.startIndex)..<colon].allSatisfy(\.isNumber) else { return raw }
        return raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    /// Title with its episode number in front ("#572: Odyssey Sings!", "#572d: BONUS! …"), as the server sends it;
    /// shown in Now Playing, where the number isn't shown anywhere else.
    var numberedTitle: String {
        let raw = name ?? shortName ?? "Episode"
        if raw.hasPrefix("#") { return raw }
        if let n = episodeNumber, !n.isEmpty { return "#\(n): \(raw)" }
        return raw
    }
    /// Album name, ignoring the server quirk where it repeats the type (e.g. "Episode").
    var albumTitle: String? {
        guard let a = albumName, !a.isEmpty, a != subtype, a != type else { return nil }
        return a
    }
    /// Only audio and video have playable media; articles and others don't.
    var isPlayable: Bool { type == nil || type == "Audio" || type == "Video" }
    var isAudio: Bool { type == "Audio" }
    var artworkURL: URL? { .aio(thumbnailLarge ?? thumbnailMedium ?? thumbnailSmall) }
    var smallArtworkURL: URL? { .aio(thumbnailMedium ?? thumbnailSmall ?? thumbnailLarge) }

    var subtitle: String {
        var parts: [String] = []
        if let n = episodeNumber, !n.isEmpty { parts.append("#\(n)") }
        if let ms = mediaLength, ms > 0 { parts.append(ms.msDurationText) }
        return parts.joined(separator: " · ")
    }

    /// The air date ("2005-10-29T06:00:00.000Z", midnight in Central time), read as UTC so every time zone shows the same day.
    var releaseDate: Date? {
        guard let airDate, airDate.count >= 10 else { return nil }
        return Self.dayParser.date(from: String(airDate.prefix(10)))
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "November 5, 2005", in the device's language and region.
    static func releaseText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: .autoupdatingCurrent, timeZone: TimeZone(identifier: "UTC")!))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, subtype, description, progress, characters
        case shortName = "short_name", episodeNumber = "episode_number", albumName = "album_name"
        case airDate = "air_date", mediaLength = "media_length"
        case thumbnailSmall = "thumbnail_small", thumbnailMedium = "thumbnail_medium", thumbnailLarge = "thumbnail_large"
        case streamURL = "stream_url", signedCookie = "signed_cookie", downloadURL = "download_url", inAlbum = "in_album"
        case authors, isBookmarked = "is_bookmarked"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.string(.name); shortName = c.string(.shortName)
        type = c.string(.type); subtype = c.string(.subtype)
        episodeNumber = c.string(.episodeNumber); albumName = c.string(.albumName)
        description = c.string(.description); airDate = c.string(.airDate)
        mediaLength = c.lenientInt(.mediaLength)
        thumbnailSmall = c.string(.thumbnailSmall); thumbnailMedium = c.string(.thumbnailMedium)
        thumbnailLarge = c.string(.thumbnailLarge)
        progress = try? c.decodeIfPresent(ListenProgress.self, forKey: .progress)
        streamURL = c.string(.streamURL); signedCookie = c.string(.signedCookie); downloadURL = c.string(.downloadURL)
        characters = try? c.decodeIfPresent([CastMember].self, forKey: .characters)
        authors = try? c.decodeIfPresent([Author].self, forKey: .authors)
        isBookmarked = try? c.decodeIfPresent(Bool.self, forKey: .isBookmarked)
        inAlbum = try? c.decodeIfPresent([Episode].self, forKey: .inAlbum)
    }

    static func == (a: Episode, b: Episode) -> Bool { a.id == b.id && a.progress == b.progress }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Album, series, collection, podcast year, or an autogenerated home shelf.
struct Grouping: Decodable, Identifiable, Hashable {
    let groupingID: String?
    let name: String?
    let type: String?
    let albumNumber: String?
    let imageURL: String?
    let description: String?
    let fullDescription: String?
    let copyrightYear: String?
    let contentList: [Episode]

    var id: String { groupingID ?? "\(type ?? "")-\(name ?? "")" }
    var title: String { name ?? "Untitled" }
    var artworkURL: URL? { .aio(imageURL) }

    enum CodingKeys: String, CodingKey {
        case groupingID = "id", name, type, description, contentList, imageURL
        case albumNumber = "album_number", fullDescription = "full_description", copyrightYear = "album_copyright_year"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupingID = c.string(.groupingID)
        name = c.string(.name); type = c.string(.type)
        albumNumber = c.string(.albumNumber) ?? c.lenientInt(.albumNumber).map(String.init)
        imageURL = c.string(.imageURL)
        description = c.string(.description); fullDescription = c.string(.fullDescription)
        copyrightYear = c.string(.copyrightYear) ?? c.lenientInt(.copyrightYear).map(String.init)
        contentList = (try? c.decodeIfPresent([Episode].self, forKey: .contentList)) ?? []
    }
}

struct PageMetadata: Decodable {
    let totalRecordCount: Int?
    let totalPageCount: Int?
    let pageNumber: Int?
}

struct GroupingsResponse: Decodable {
    let contentGroupings: [Grouping]?
    let metadata: PageMetadata?
}

struct CarouselItem: Decodable, Identifiable, Hashable {
    let id: String
    let imageUrl: String?
    let hyperlink: String?
}

struct HomeResponse: Decodable {
    let carousel: [CarouselItem]?
    let playlists: [Grouping]?
}

struct SearchResponse: Decodable {
    struct Column: Decodable { let value: String?; let name: String? }
    struct Row: Decodable, Identifiable {
        let id: String
        let column1: Column?, column2: Column?, column3: Column?, column4: Column?
        var columns: [Column] { [column1, column2, column3, column4].compactMap { $0 } }
        func value(_ field: String) -> String? { columns.first { $0.name == field }?.value }
    }
    struct ResultObject: Decodable { let objectName: String?; let results: [Row]? }
    let resultObjects: [ResultObject]?
}

struct SearchHit: Identifiable, Hashable {
    enum Kind { case episode, grouping, character, author }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let imageURL: URL?
}

// MARK: - Lenient decoding helpers

extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
}

struct CharactersResponse: Decodable { let characters: [CastMember]? }
struct AuthorsResponse: Decodable { let authors: [Author]? }
struct ContentSearchResponse: Decodable {
    let results: [Episode]?
    let totalCount: Int?
    enum CodingKeys: String, CodingKey { case results, totalCount = "total_count" }
}
