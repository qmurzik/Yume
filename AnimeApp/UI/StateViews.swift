import SwiftUI

struct LoadingStateView: View {
    var text = "Загрузка…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
    }
}

struct ErrorStateView: View {
    let error: Error
    var compact = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(compact ? .title3 : .largeTitle)
                .foregroundStyle(.orange)
            if !compact {
                Text("Что-то пошло не так").font(.headline)
            }
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            Button(action: retry) {
                Label("Повторить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .small : .regular)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 120 : 220)
        .padding()
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

/// Renders loading, error (with retry), empty and loaded states of one request.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var emptyTitle = "Здесь пока пусто"
    var emptyMessage: String?
    var isEmpty: (Value) -> Bool = { _ in false }
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let value):
            if isEmpty(value) {
                EmptyStateView(title: emptyTitle, message: emptyMessage)
            } else {
                content(value)
            }
        }
    }
}
