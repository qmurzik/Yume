import SwiftUI

struct LoadingStateView: View {
    var text = "Загрузка…"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.pink).controlSize(.large)
            Text(text).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding()
    }
}

struct ErrorStateView: View {
    let error: Error
    var compact = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.14)).frame(width: compact ? 44 : 72, height: compact ? 44 : 72)
                Image(systemName: "wifi.exclamationmark")
                    .font(compact ? .title3.weight(.semibold) : .title.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if !compact {
                Text("Не получилось загрузить").font(.headline).foregroundStyle(.white)
            }
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            Button {
                Haptics.tap()
                retry()
            } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : 240)
        .padding()
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage = "tray"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentGradient).opacity(0.18).frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accentGradient)
            }
            Text(title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
    }
}
