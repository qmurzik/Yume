import SwiftUI

struct PlayerScreen: View {
    @StateObject private var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(context: PlayerContext, library: LibraryStore) {
        _model = StateObject(wrappedValue: PlayerViewModel(context: context, library: library))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Color.black
                content
            }
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(.white).controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { model.retry() }
        case .native:
            VideoPlayerView(player: model.player)
                .overlay(alignment: .bottomTrailing) {
                    if model.canSkipOpening {
                        Button {
                            model.skipOpening()
                        } label: {
                            Label("Пропустить опенинг", systemImage: "forward.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.trailing, 16)
                        .padding(.bottom, 72)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: model.canSkipOpening)
        case .embed(let url):
            EmbedPlayerView(url: url)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Закрыть")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.context.anime.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(model.episode.displayTitle) · \(model.episode.voice)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.qualities.count > 1 {
                Menu {
                    Picker("Качество", selection: Binding(get: { model.quality ?? model.qualities[0] }, set: { model.select($0) })) {
                        ForEach(model.qualities) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }
                } label: {
                    Label(model.quality?.label ?? "Качество", systemImage: "gearshape")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                model.playPrevious()
            } label: {
                Label("Предыдущая", systemImage: "backward.end.fill")
            }
            .disabled(!model.hasPrevious)

            Spacer()

            if model.hasNext {
                Button {
                    model.playNext()
                } label: {
                    Label("Следующая серия", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.didFinish || model.isInEnding ? Color.accentColor : Color.gray.opacity(0.6))
            } else if model.didFinish {
                Text("Это последняя серия").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
