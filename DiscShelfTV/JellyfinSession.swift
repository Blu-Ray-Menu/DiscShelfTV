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
        let trimmed = serverURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let normalized = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed

        return URL(string: normalized)
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
            url: baseURL.appendingPathComponent(
                "Users/AuthenticateByName"
            )
        )

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "MediaBrowser Client=\"\(appName)\", Device=\"Apple TV\", DeviceId=\"\(deviceID)\", Version=\"\(appVersion)\"",
            forHTTPHeaderField: "Authorization"
        )

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "Username": username,
                "Pw": password
            ]
        )

        do {
            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw APIError.server(
                    "Login failed. Check the URL, credentials, and server logs."
                )
            }

            let auth = try JSONDecoder().decode(
                AuthResponse.self,
                from: data
            )

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
        guard let baseURL,
              let accessToken,
              let userID else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        errorMessage = nil

        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "Users/\(userID)/Items"
            ),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(
                name: "IncludeItemTypes",
                value: "Movie"
            ),
            URLQueryItem(
                name: "Recursive",
                value: "true"
            ),
            URLQueryItem(
                name: "SortBy",
                value: "SortName"
            ),
            URLQueryItem(
                name: "SortOrder",
                value: "Ascending"
            ),
            URLQueryItem(
                name: "Fields",
                value: "Overview,ProductionYear,RunTimeTicks,MediaSources"
            ),
            URLQueryItem(
                name: "ImageTypeLimit",
                value: "1"
            ),
            URLQueryItem(
                name: "Limit",
                value: "500"
            )
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
            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw APIError.server(
                    "Could not load movies from Jellyfin."
                )
            }

            movies = try JSONDecoder().decode(
                ItemsResponse.self,
                from: data
            ).Items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func imageURL(for item: MediaItem) -> URL? {
        guard let baseURL,
              let tag = item.ImageTags?["Primary"] else {
            return nil
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent(
                "Items/\(item.Id)/Images/Primary"
            ),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(
                name: "tag",
                value: tag
            ),
            URLQueryItem(
                name: "maxWidth",
                value: "600"
            )
        ]

        return components?.url
    }

    // MARK: - Playback

    /// Creates the device profile describing what AVPlayer can consume.
    ///
    /// We deliberately advertise HLS/TS output as our fallback.
    /// This lets Jellyfin remux/transcode formats such as MKV rather
    /// than sending the original MKV directly to AVPlayer.
    private var deviceProfile: [String: Any] {
        [
            "Name": "DiscShelf TV",
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 120_000_000,

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
                    "AudioCodec": "aac,ac3,eac3",
                    "Protocol": "http",
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
                [
                    "Format": "vtt",
                    "Method": "External"
                ],
                [
                    "Format": "srt",
                    "Method": "External"
                ]
            ]
        ]
    }

    /// Asks Jellyfin how this particular movie should be played.
    ///
    /// If mediaSourceId is supplied, Jellyfin evaluates that exact
    /// source rather than choosing from all available sources.
    func playbackInfo(
        for item: MediaItem,
        mediaSourceId: String? = nil
    ) async throws -> PlaybackInfoResponse {

        guard let baseURL,
              let accessToken else {
            throw APIError.server(
                "Connect to Jellyfin before playing a movie."
            )
        }

        let url = baseURL.appendingPathComponent(
            "Items/\(item.Id)/PlaybackInfo"
        )

        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(
                name: "UserId",
                value: userID
            ),
            URLQueryItem(
                name: "MaxStreamingBitrate",
                value: "120000000"
            ),
            URLQueryItem(
                name: "MaxStaticBitrate",
                value: "120000000"
            ),
            URLQueryItem(
                name: "EnableDirectPlay",
                value: "true"
            ),
            URLQueryItem(
                name: "EnableDirectStream",
                value: "true"
            ),
            URLQueryItem(
                name: "EnableTranscoding",
                value: "true"
            )
        ]

        if let mediaSourceId {
            queryItems.append(
                URLQueryItem(
                    name: "MediaSourceId",
                    value: mediaSourceId
                )
            )
        }

        components?.queryItems = queryItems

        guard let finalURL = components?.url else {
            throw APIError.server(
                "Could not create the Jellyfin playback URL."
            )
        }

        var request = URLRequest(url: finalURL)

        request.httpMethod = "POST"

        request.setValue(
            "MediaBrowser Token=\"\(accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let body: [String: Any] = [
            "DeviceProfile": deviceProfile,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 120_000_000
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        let (data, response) =
            try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {

            let status =
                (response as? HTTPURLResponse)?.statusCode ?? -1

            throw APIError.server(
                "Jellyfin playback negotiation failed (HTTP \(status))."
            )
        }

        let info = try JSONDecoder().decode(
            PlaybackInfoResponse.self,
            from: data
        )

        if let errorCode = info.ErrorCode,
           !errorCode.isEmpty {
            throw APIError.server(
                "Jellyfin playback error: \(errorCode)"
            )
        }

        guard let sources = info.MediaSources,
              !sources.isEmpty else {
            throw APIError.server(
                "Jellyfin returned no playable media sources."
            )
        }

        return info
    }

    /// Negotiates playback and returns the URL that AVPlayer should open.
    ///
    /// The important distinction here is:
    ///
    /// 1. Get the available source.
    /// 2. Ask Jellyfin to evaluate that exact source.
    /// 3. Use Jellyfin's TranscodingUrl if it requires conversion.
    /// 4. Otherwise use the direct stream URL.
    func playbackURL(for item: MediaItem) async throws -> URL {
        guard let baseURL,
              let accessToken else {
            throw APIError.server(
                "Connect to Jellyfin before playing a movie."
            )
        }

        // First request lets Jellyfin tell us which media source exists.
        let initialInfo = try await playbackInfo(for: item)

        guard let source = initialInfo.MediaSources?.first else {
            throw APIError.server(
                "Jellyfin returned no media source for this movie."
            )
        }

        // If Jellyfin has supplied a transcoding URL, use it.
        //
        // This is the path we expect for MKV and other content
        // AVPlayer cannot natively consume.
        if let transcodingPath = source.TranscodingUrl,
           !transcodingPath.isEmpty {

            guard let url = URL(
                string: transcodingPath,
                relativeTo: baseURL
            ) else {
                throw APIError.server(
                    "Jellyfin returned an invalid transcoding URL."
                )
            }

            return url
        }

        // Jellyfin considers the source directly playable.
        if source.SupportsDirectPlay == true ||
           source.SupportsDirectStream == true {

            var components = URLComponents(
                url: baseURL.appendingPathComponent(
                    "Videos/\(item.Id)/stream"
                ),
                resolvingAgainstBaseURL: false
            )

            components?.queryItems = [
                URLQueryItem(
                    name: "Static",
                    value: "true"
                ),
                URLQueryItem(
                    name: "MediaSourceId",
                    value: source.Id
                ),
                URLQueryItem(
                    name: "api_key",
                    value: accessToken
                )
            ]

            guard let url = components?.url else {
                throw APIError.server(
                    "Could not create the direct playback URL."
                )
            }

            return url
        }

        // Jellyfin did not give us a usable direct or transcoded URL.
        throw APIError.server(
            """
            Jellyfin could not find a playback method for this movie.

            Container: \(source.Container ?? "unknown")
            Direct Play: \(source.SupportsDirectPlay == true)
            Direct Stream: \(source.SupportsDirectStream == true)
            Transcoding: \(source.SupportsTranscoding == true)
            """
        )
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
