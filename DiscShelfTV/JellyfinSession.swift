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

    var isSignedIn: Bool { accessToken != nil && userID != nil }

    private var baseURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed)
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

        var request = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateByName"))
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
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.server("Login failed. Check the URL, credentials, and server logs.")
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
    }

    func loadMovies() async {
        guard let baseURL, let accessToken, let userID else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userID)/Items"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "Fields", value: "Overview,ProductionYear,RunTimeTicks,MediaSources"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "Limit", value: "500")
        ]
        guard let url = components?.url else {
            errorMessage = "Could not form the library URL."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("MediaBrowser Token=\"\(accessToken)\"", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.server("Could not load movies from Jellyfin.")
            }
            movies = try JSONDecoder().decode(ItemsResponse.self, from: data).Items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func imageURL(for item: MediaItem) -> URL? {
        guard let baseURL, let tag = item.ImageTags?["Primary"] else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.Id)/Images/Primary"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "maxWidth", value: "600")]
        return components?.url
    }

    func playbackURL(for item: MediaItem) -> URL? {
        guard let baseURL, let accessToken else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(item.Id)/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "api_key", value: accessToken)
        ]
        return components?.url
    }
}

enum APIError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}
