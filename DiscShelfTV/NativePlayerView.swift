import SwiftUI
import AVKit

struct NativePlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> AVPlayerViewController {

        let controller = AVPlayerViewController()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)

        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false

        player.play()

        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        // Do not recreate the player during SwiftUI updates.
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: ()
    ) {
        controller.player?.pause()
        controller.player = nil
    }
}
