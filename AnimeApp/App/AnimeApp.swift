import AVFoundation
import SwiftUI

@main
struct AnimeAppMain: App {
    @StateObject private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Playback category keeps audio going in the background and enables Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { library.saveNow() }
        }
    }
}
