import Foundation

/// Typed AIO endpoints. Requests mirror the official client's paths, parameters and bodies.
enum AIOService {
    private static var api: APIClient { .shared }

    static func profiles() async throws -> [Profile] {
        try await api.get("/viewer", as: ProfilesResponse.self).profiles
    }

    /// Checks a profile PIN the same way the official app does (headers on GET /viewer/verifyPIN).
    static func verifyPIN(_ pin: String, for viewerID: String) async -> Bool {
        let previous = (api.viewerID, api.viewerPIN)
        api.viewerID = viewerID
        api.viewerPIN = pin
        defer { (api.viewerID, api.viewerPIN) = previous }
        return (try? await api.raw("GET", "/viewer/verifyPIN")) != nil
    }

    static func home() async throws -> HomeResponse {
        try await api.get("/viewer/home", query: [
            "carousel": "true", "where_you_left_off": "true", "playlists": "true",
            "personal_playlists": "true", "odyssey_times": "true", "notifications": "true",
        ])
    }

    /// Full episode detail including signed stream/download URLs.
    static func episode(_ id: String, groupingID: String? = nil) async throws -> Episode {
        try await api.get("/content/\(id)", query: [
            "player": "true", "recommendations": "true", "tag": "false",
            "series": "false", "parent": "false", "content_grouping_id": groupingID,
        ])
    }

    static func grouping(_ id: String) async throws -> Grouping? {
        try await api.get("/contentgrouping/\(id)", as: GroupingsResponse.self).contentGroupings?.first
    }

    struct GroupingSearch: Encodable {
        let type: String
        let pageNumber: Int
        let pageSize: Int
    }

    static func groupings(type: String, page: Int, pageSize: Int = 24) async throws -> GroupingsResponse {
        try await api.post("/contentgrouping/search", body: GroupingSearch(type: type, pageNumber: page, pageSize: pageSize))
    }

    private struct SearchRequest: Encodable {
        struct Object: Encodable {
            let objectName: String
            let fields: [String]
            let pageNumber: Int
            let pageSize: Int
        }
        let searchTerm: String
        let searchObjects: [Object]
    }

    static func search(_ term: String) async throws -> [SearchHit] {
        let request = SearchRequest(searchTerm: term, searchObjects: [
            .init(objectName: "Content__c", fields: ["Name", "Thumbnail_Small__c", "Subtype__c", "Episode_Number__c"], pageNumber: 1, pageSize: 25),
            .init(objectName: "Content_Grouping__c", fields: ["Name", "Image_URL__c", "Type__c"], pageNumber: 1, pageSize: 10),
            .init(objectName: "Character__c", fields: ["Name", "Thumbnail_Small__c"], pageNumber: 1, pageSize: 10),
            .init(objectName: "Author__c", fields: ["Name", "Profile_Image_URL__c"], pageNumber: 1, pageSize: 10),
        ])
        let response: SearchResponse = try await api.post("/search", body: request)
        var hits: [SearchHit] = []
        for object in response.resultObjects ?? [] {
            let isGrouping = object.objectName == "Content_Grouping__c"
            for row in object.results ?? [] {
                if object.objectName == "Character__c" {
                    hits.append(SearchHit(id: row.id, kind: .character, title: row.value("Name") ?? "Character",
                                          detail: "Character", imageURL: .aio(row.value("Thumbnail_Small__c"))))
                } else if object.objectName == "Author__c" {
                    hits.append(SearchHit(id: row.id, kind: .author, title: row.value("Name") ?? "Cast",
                                          detail: "Cast & Crew", imageURL: .aio(row.value("Profile_Image_URL__c"))))
                } else if isGrouping {
                    hits.append(SearchHit(id: row.id, kind: .grouping, title: row.value("Name") ?? "Untitled",
                                          detail: row.value("Type__c") ?? "Collection",
                                          imageURL: .aio(row.value("Image_URL__c"))))
                } else {
                    let number = row.value("Episode_Number__c").map { "#\($0) · " } ?? ""
                    hits.append(SearchHit(id: row.id, kind: .episode, title: row.value("Name") ?? "Episode",
                                          detail: number + (row.value("Subtype__c") ?? "Episode"),
                                          imageURL: .aio(row.value("Thumbnail_Small__c"))))
                }
            }
        }
        return hits
    }

    // MARK: Characters & cast

    static func character(_ id: String) async throws -> CastMember? {
        try await api.get("/character/\(id)", as: CharactersResponse.self).characters?.first
    }

    static func author(_ id: String) async throws -> Author? {
        try await api.get("/author/\(id)", as: AuthorsResponse.self).authors?.first
    }

    // MARK: Bookmarks (like the official app: GET /content/search?is_bookmarked, POST/DELETE /bookmark)

    static func bookmarks(page: Int = 1) async throws -> [Episode] {
        try await api.get("/content/search", query: [
            "community": "Adventures in Odyssey", "is_bookmarked": "true",
            "pagenum": String(page), "pagecount": "50",
        ], as: ContentSearchResponse.self).results ?? []
    }

    private struct BookmarkRequest: Encodable {
        let subject_id: String
        let bookmark_type = "Bookmark"
        let subject_type = "Content__c"
    }

    static func addBookmark(_ contentID: String) async throws {
        _ = try await api.raw("POST", "/bookmark", body: try JSONEncoder().encode(BookmarkRequest(subject_id: contentID)))
    }

    static func removeBookmark(_ contentID: String) async throws {
        _ = try await api.raw("DELETE", "/bookmark", query: [
            "subject_type": "Content__c", "subject_id": contentID, "bookmark_type": "Bookmark",
        ])
    }

    private struct ProgressUpdate: Encodable {
        let content_id: String
        let status: String
        let current_progress: Int
    }

    /// Writes listening progress for the selected profile (PUT /content), like the official app.
    static func saveProgress(episodeID: String, status: String, positionMs: Int) async throws {
        _ = try await api.raw("PUT", "/content",
                              body: try JSONEncoder().encode(ProgressUpdate(content_id: episodeID, status: status, current_progress: positionMs)))
    }
}
