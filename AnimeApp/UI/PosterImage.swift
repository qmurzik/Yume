import NukeUI
import SwiftUI

/// 2:3 poster with a disk-cached image (Nuke) and a placeholder.
struct PosterImage: View {
    let url: URL?
    var cornerRadius: CGFloat = Theme.posterRadius

    var body: some View {
        Rectangle()
            .fill(Theme.surfaceStrong)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                RemoteImage(url: url, placeholderIcon: "photo")
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Landscape thumbnail for episode previews.
struct ThumbnailImage: View {
    let url: URL?

    var body: some View {
        Rectangle()
            .fill(Theme.surfaceStrong)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { RemoteImage(url: url, placeholderIcon: "play.rectangle") }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Fills its frame with the image, fading it in once loaded.
struct RemoteImage: View {
    let url: URL?
    var placeholderIcon = "photo"

    var body: some View {
        LazyImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else if state.error != nil || url == nil {
                Image(systemName: placeholderIcon)
                    .font(.title2)
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                Theme.surfaceStrong.shimmering()
            }
        }
    }
}

/// Full-bleed blurred backdrop built from a poster.
struct BackdropImage: View {
    let url: URL?
    var blur: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay { RemoteImage(url: url) }
            .blur(radius: blur)
            .clipped()
    }
}
