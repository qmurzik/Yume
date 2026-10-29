import SwiftUI
import WebKit

/// Anime365's own sign-in page inside the app. Once the site reports a signed-in user, its
/// session cookies are handed to the app's networking and the sheet closes.
struct Anime365LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Войдите в свой аккаунт Anime365"

    var body: some View {
        NavigationStack {
            LoginWebView(url: AppConfig.anime365BaseURL.appendingPathComponent("users/login")) { message, done in
                status = message
                if done { dismiss() }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Theme.elevated)
            }
            .navigationTitle("Anime365")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LoginWebView: UIViewRepresentable {
    let url: URL
    let onStatus: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onStatus: (String, Bool) -> Void
        private var finished = false

        init(onStatus: @escaping (String, Bool) -> Void) {
            self.onStatus = onStatus
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where Anime365Account.isAnime365(domain: cookie.domain) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                Task { await self.check() }
            }
        }

        @MainActor
        private func check() async {
            guard !finished, let me = try? await Anime365Source(signedIn: { true }).me(), me.isLogined == true else { return }
            finished = true
            let premium = me.isPremium == true ? me.premiumUntil : nil
            Anime365Account.shared.save(name: me.name ?? "Аккаунт", premiumUntil: premium)
            Haptics.success()
            onStatus(premium == nil ? "Вход выполнен, но подписки нет — видео не откроется" : "Вход выполнен", true)
        }
    }
}
