
import Foundation
import SwiftUI

@MainActor
final class JellyfinSession: ObservableObject {
    @Published var serverURL = "http://192.168.1.20:8096"
    @Published var username = ""
    @Published var password = ""
    @Published var accessToken: String?
    @Published var userID: String?
    @Published var movies: [MediaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let deviceID = "DiscShelfTV-" + UUID().uuidString
    private let appName = "DiscShelf TV"
    private let appVersion = "0.1.0"

    var isSignedIn: Bool {
        accessToken != nil && userID != nil
    }

    private var baseURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        return URL(string: normalized)
    }

    private var authorizationHeader: String? {
        guard let accessToken else { return nil }
        return "MediaBrowser Token=\"\(accessToken)\""
    }

    func signIn() async {
        errorMessage = nil

        guard let baseURL else {
            errorMessage = "Enter a valid Jellyfin server URL."
            return
        }

        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your Jellyfin username and password."
            return
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("Users/AuthenticateByName")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "MediaBrowser Client=\"\(appName)\", Device=\"Apple TV\", DeviceId=\"\(deviceID)\", Version=\"\(appVersion)\"",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw APIError.server(
                    "Login failed. Check the URL, credentials, and server logs."
                )
            }

            let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
            accessToken = auth.AccessToken
            userID = auth.User.Id
            password = ""

            await loadMovies()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        accessToken = nil
        userID = nil
        movies = []
        errorMessage = nil
    }

    func loadMovies() async {
        guard let baseURL, let accessToken, let userID else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        var components = URLComponents(
            url: baseURL.appendingPathComponent("Users/\(userID)/Items"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(
                name: "Fields",
                value: "Overview,ProductionYear,RunTimeTicks,MediaSources"
            ),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "Limit", value: "500")
        ]

        guard let url = components?.url else {
            errorMessage = "Could not form the library URL."
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "MediaBrowser Token=\"\(accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw APIError.server("Could not load movies from Jellyfin.")
            }

            movies = try JSONDecoder().decode(ItemsResponse.self, from: data).Items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func imageURL(for item: MediaItem) -> URL? {
        guard let baseURL, let tag = item.ImageTags?["Primary"] else {
            return nil
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "Items/\(item.Id)/Images/Primary"
            ),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "maxWidth", value: "600")
        ]

        return components?.url
    }

    /// Requests Jellyfin's playback options instead of forcing a static stream.
    func playbackInfo(for item: MediaItem) async throws -> PlaybackInfoResponse {
        guard let baseURL, let accessToken else {
            throw APIError.server("Connect to Jellyfin before playing a movie.")
        }

        let url = baseURL.appendingPathComponent("Items/\(item.Id)/PlaybackInfo")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "MediaBrowser Token=\"\(accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let profile: [String: Any] = [
            "Name": "DiscShelf TV",
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 120_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3,mp3,alac"
                ],
                [
                    "Container": "ts,m2ts",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3,mp3"
                ]
            ],
            "TranscodingProfiles": [
                [
                    "Container": "ts",
                    "Type": "Video",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac,ac3",
                    "Protocol": "hls",
                    "Context": "Streaming",
                    "MaxAudioChannels": "6",
                    "MinSegments": 1,
                    "BreakOnNonKeyFrames": true,
                    "EnableMpegtsM2TsMode": false
                ]
            ],
            "CodecProfiles": [],
            "ResponseProfiles": [],
            "ContainerProfiles": [],
            "SubtitleProfiles": [
                ["Format": "vtt", "Method": "External"],
                ["Format": "srt", "Method": "External"]
            ]
        ]

        let body: [String: Any] = [
            "DeviceProfile": profile,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.server(
                "Jellyfin playback negotiation failed (HTTP \(status))."
            )
        }

        return try JSONDecoder().decode(PlaybackInfoResponse.self, from: data)
    }

    /// Builds a stream URL for a selected source.
    /// A transcoding URL returned by Jellyfin takes precedence when present.
    func playbackURL(
        for item: MediaItem,
        source: PlaybackMediaSource? = nil
    ) async throws -> URL {
        guard let baseURL, let accessToken else {
            throw APIError.server("Connect to Jellyfin before playing a movie.")
        }

        let info = try await playbackInfo(for: item)

        if let transcodingPath = source?.TranscodingUrl,
           let transcodingURL = URL(
                string: transcodingPath,
                relativeTo: baseURL
           ) {
            return transcodingURL
        }

        if let selectedSource = source,
           selectedSource.SupportsDirectPlay != true,
           selectedSource.SupportsDirectStream != true {
            throw APIError.server(
                "Jellyfin did not provide a usable direct stream or transcoding URL for this source."
            )
        }

        if let sourcePath = info.MediaSources?.first?.TranscodingUrl,
           let transcodingURL = URL(string: sourcePath, relativeTo: baseURL) {
            return transcodingURL
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(item.Id)/stream"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "api_key", value: accessToken)
        ]

        guard let streamURL = components?.url else {
            throw APIError.server("Could not create a playback URL.")
        }

        return streamURL
    }
}

enum APIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}
