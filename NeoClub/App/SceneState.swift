import Foundation

/// A navigation destination reduced to what's needed to rebuild it, so the app's place (tab, pages, Now Playing)
/// survives the window being recreated, e.g. when the iPhone Duo is unfolded and the app moves to the inner screen.
struct StoredRoute: Codable {
    enum Kind: String, Codable { case episode, grouping, groupingList, character, author, bookmarks, downloads }
    var kind: Kind
    var id: String?
    var title: String?
    var artwork: String?
    var groupingID: String?
    var type: String?
    var filter: GroupingFilter?

    init?(_ route: Route) {
        switch route {
        case .episode(let e, let gid):
            self.init(kind: .episode, id: e.id, title: e.name ?? e.shortName,
                      artwork: e.thumbnailMedium ?? e.thumbnailSmall, groupingID: gid)
        case .grouping(let id, let preview):
            self.init(kind: .grouping, id: id, title: preview?.name)
        case .groupingList(let type, let title, let filter):
            self.init(kind: .groupingList, title: title, type: type, filter: filter)
        case .character(let id, _): self.init(kind: .character, id: id)
        case .author(let id, _): self.init(kind: .author, id: id)
        case .bookmarks: self.init(kind: .bookmarks)
        case .downloads: self.init(kind: .downloads)
        }
    }

    private init(kind: Kind, id: String? = nil, title: String? = nil, artwork: String? = nil, groupingID: String? = nil,
                 type: String? = nil, filter: GroupingFilter? = nil) {
        self.kind = kind; self.id = id; self.title = title; self.artwork = artwork
        self.groupingID = groupingID; self.type = type; self.filter = filter
    }

    /// The route again. Pages load their full details themselves, so a stand-in with the ID and title is enough.
    var route: Route? {
        switch kind {
        case .episode:
            guard let id else { return nil }
            var json: [String: Any] = ["id": id]
            if let title { json["name"] = title }
            if let artwork { json["thumbnail_medium"] = artwork; json["thumbnail_small"] = artwork }
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let stub = try? JSONDecoder().decode(Episode.self, from: data) else { return nil }
            return .episode(stub, groupingID: groupingID)
        case .grouping: return id.map { .grouping(id: $0, preview: nil) }
        case .groupingList: return type.map { .groupingList(type: $0, title: title ?? "", filter: filter ?? .all) }
        case .character: return id.map { .character(id: $0, preview: nil) }
        case .author: return id.map { .author(id: $0, preview: nil) }
        case .bookmarks: return .bookmarks
        case .downloads: return .downloads
        }
    }
}

/// Everything restored with the window: the selected tab, each tab's pages, and whether Now Playing is open.
struct SceneState: Codable {
    var tab: String
    var paths: [String: [StoredRoute]]
    var nowPlayingOpen: Bool
}
