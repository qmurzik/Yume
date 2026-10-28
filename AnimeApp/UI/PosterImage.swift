import NukeUI
import SwiftUI

/// 2:3 poster with a disk-cached image (Nuke) and a placeholder.
struct PosterImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 10

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil || url == nil {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Color(.tertiarySystemBackground)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Landscape thumbnail for episode previews.
struct ThumbnailImage: View {
    let url: URL?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
