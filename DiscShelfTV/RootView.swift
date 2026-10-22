import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: JellyfinSession

    var body: some View {
        Group {
            if session.isSignedIn {
                LibraryView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: JellyfinSession

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(.white)
            Text("DISC SHELF")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(5)
            Text("Your collection. Original quality first.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                TextField("Jellyfin server URL", text: $session.serverURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                TextField("Username", text: $session.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $session.password)
                    .textContentType(.password)
            }
            .frame(maxWidth: 650)

            if let error = session.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Button {
                Task { await session.signIn() }
            } label: {
                if session.isLoading {
                    ProgressView()
                } else {
                    Text("Connect to Jellyfin").frame(minWidth: 260)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isLoading)

            Text("Use your server's HTTPS address when connecting over an untrusted network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.16), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}

struct LibraryView: View {
    @EnvironmentObject private var session: JellyfinSession
    @State private var selectedMovie: MediaItem?
    @State private var searchText = ""

    private var filteredMovies: [MediaItem] {
        guard !searchText.isEmpty else { return session.movies }
        return session.movies.filter { $0.Name.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 28)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR LIBRARY")
                                .font(.caption.weight(.bold))
                                .tracking(4)
                                .foregroundStyle(.cyan)
                            Text("Movies")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Text("\(session.movies.count) titles")
                            .foregroundStyle(.secondary)
                        Button("Refresh") { Task { await session.loadMovies() } }
                        Button("Sign Out") { session.signOut() }
                    }

                    TextField("Search your collection", text: $searchText)
                        .frame(maxWidth: 500)

                    if let error = session.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }

                    if session.isLoading {
                        ProgressView("Loading your collection…")
                            .frame(maxWidth: .infinity, minHeight: 250)
                    } else if filteredMovies.isEmpty {
                        ContentUnavailableView("No movies found",
                                               systemImage: "film",
                                               description: Text("Check that your Jellyfin user can access a Movies library."))
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(filteredMovies) { movie in
                                Button {
                                    selectedMovie = movie
                                } label: {
                                    MoviePoster(item: movie)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 42)
            }
            .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            .navigationDestination(item: $selectedMovie) { movie in
                MovieDetailView(movie: movie)
            }
        }
    }
}

struct MoviePoster: View {
    @EnvironmentObject private var session: JellyfinSession
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: session.imageURL(for: item)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                    }
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.gray
                }
            }
            .frame(width: 205, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.Name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !item.runtimeText.isEmpty {
                Text([item.ProductionYear.map(String.init), item.runtimeText].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 205, alignment: .leading)
    }
}

struct MovieDetailView: View {
    @EnvironmentObject private var session: JellyfinSession
    let movie: MediaItem
    @State private var showPlayer = false

    var body: some View {
        HStack(spacing: 48) {
            AsyncImage(url: session.imageURL(for: movie)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "film").font(.system(size: 60)))
            }
            .frame(width: 300, height: 450)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 22) {
                Text(movie.displayTitle)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                if !movie.runtimeText.isEmpty {
                    Text(movie.runtimeText).foregroundStyle(.secondary)
                }
                if let overview = movie.Overview, !overview.isEmpty {
                    Text(overview).font(.title3).lineLimit(7)
                }
                Button {
                    showPlayer = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)

                Text("Direct playback is attempted. If this container or stream isn't supported by AVPlayer, this starter does not yet negotiate a Jellyfin transcode fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 650, alignment: .leading)
            }
            Spacer(minLength: 20)
        }
        .padding(60)
        .background(Color.black)
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = session.playbackURL(for: movie) {
                NativePlayerView(url: url)
                    .ignoresSafeArea()
            } else {
                VStack {
                    Text("Could not create playback URL.")
                    Button("Close") { showPlayer = false }
                }
            }
        }
    }
}
