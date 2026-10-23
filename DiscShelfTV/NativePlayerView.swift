import SwiftUI
import AVKit

struct NativePlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()

        print("DiscShelfTV PLAYBACK URL:")
        print(url.absoluteString)

        let playerItem = AVPlayerItem(url: url)

        context.coordinator.observe(playerItem)

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
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        coordinator.stopObserving()

        controller.player?.pause()
        controller.player = nil
    }

    final class Coordinator {
        private var statusObservation: NSKeyValueObservation?
        private var loadedTimeRangesObservation: NSKeyValueObservation?

        func observe(_ item: AVPlayerItem) {
            statusObservation = item.observe(
                \.status,
                options: [.initial, .new]
            ) { item, _ in

                DispatchQueue.main.async {
                    switch item.status {

                    case .unknown:
                        print("DiscShelfTV AVPlayer status: UNKNOWN")

                    case .readyToPlay:
                        print("DiscShelfTV AVPlayer status: READY TO PLAY")

                    case .failed:
                        print("DiscShelfTV AVPlayer status: FAILED")

                        if let error = item.error {
                            print("DiscShelfTV AVPlayer error:")
                            print(error)

                            let nsError = error as NSError

                            print("Domain: \(nsError.domain)")
                            print("Code: \(nsError.code)")
                            print("Description: \(nsError.localizedDescription)")
                            print("UserInfo: \(nsError.userInfo)")

                            if let underlying = nsError.userInfo[
                                NSUnderlyingErrorKey
                            ] as? NSError {
                                print("Underlying error:")
                                print(underlying)
                                print("Underlying domain: \(underlying.domain)")
                                print("Underlying code: \(underlying.code)")
                                print(
                                    "Underlying description: " +
                                    "\(underlying.localizedDescription)"
                                )
                            }
                        }

                    @unknown default:
                        print("DiscShelfTV AVPlayer status: UNKNOWN FUTURE VALUE")
                    }
                }
            }

            loadedTimeRangesObservation = item.observe(
                \.loadedTimeRanges,
                options: [.new]
            ) { item, _ in
                if !item.loadedTimeRanges.isEmpty {
                    print(
                        "DiscShelfTV loaded time ranges: " +
                        "\(item.loadedTimeRanges)"
                    )
                }
            }
        }

        func stopObserving() {
            statusObservation = nil
            loadedTimeRangesObservation = nil
        }
    }
}
