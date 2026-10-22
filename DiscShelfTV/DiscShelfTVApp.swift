import SwiftUI

@main
struct DiscShelfTVApp: App {
    @StateObject private var session = JellyfinSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
