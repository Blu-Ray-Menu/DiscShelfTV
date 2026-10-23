
import Foundation

struct JellyfinUser: Decodable {
    let Id: String
    let Name: String
}

struct AuthResponse: Decodable {
    let User: JellyfinUser
    let AccessToken: String
    let ServerId: String?
}

struct ItemsResponse: Decodable {
    let Items: [MediaItem]
    let TotalRecordCount: Int?
}

struct MediaItem: Decodable, Identifiable, Hashable {
    let Id: String
    let Name: String
    let ProductionYear: Int?
    let Overview: String?
    let RunTimeTicks: Int64?
    let `Type`: String?
    let ImageTags: [String: String]?

    var id: String { Id }

    var displayTitle: String {
        if let year = ProductionYear {
            return "\(Name) (\(year))"
        }
        return Name
    }

    var runtimeText: String {
        guard let ticks = RunTimeTicks else { return "" }
        let seconds = Double(ticks) / 10_000_000
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct PlaybackInfoResponse: Decodable {
    let MediaSources: [PlaybackMediaSource]?
    let PlaySessionId: String?
    let ErrorCode: String?
}

struct PlaybackMediaSource: Decodable {
    let Id: String?
    let Container: String?
    let SupportsDirectPlay: Bool?
    let SupportsDirectStream: Bool?
    let SupportsTranscoding: Bool?
    let TranscodingUrl: String?
}
