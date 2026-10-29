import SafariServices
import SwiftUI
import WebKit

/// The source's official embeddable player (YummyAnime voice-overs).
///
/// Third-party players often refuse to play outside the sites they're licensed for: an HTTP error,
/// an error page ("страницы не существует", "недоступен в вашем регионе") or a redirect to a
/// YouTube placeholder. Those are reported through `onFailure` so the player can try another copy.
struct EmbedPlayerView: UIViewRepresentable {
    let url: URL
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        context.coordinator.start(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFailure = onFailure
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.start(url, in: webView)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var onFailure: (String) -> Void
        private(set) var loadedURL: URL?
        private var reported = false

        /// Texts the common players show instead of the video.
        static let errorPhrases = [
            "страницы не существует", "страница не найдена", "недоступен в вашем регионе",
            "недоступно в вашем регионе", "видео удалено", "видео не найдено", "заблокирован",
            "bad gateway", "not found", "access denied", "forbidden",
        ]
        static let placeholderHosts = ["youtube.com", "youtu.be"]

        init(onFailure: @escaping (String) -> Void) {
            self.onFailure = onFailure
        }

        func start(_ url: URL, in webView: WKWebView) {
            loadedURL = url
            reported = false
            webView.load(URLRequest(url: url))
        }

        private func fail(_ reason: String) {
            guard !reported else { return }
            reported = true
            DispatchQueue.main.async { self.onFailure(reason) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let host = navigationAction.request.url?.host?.lowercased() ?? ""
            if Self.placeholderHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                // The player swapped itself for a placeholder clip instead of the episode.
                decisionHandler(.cancel)
                fail("плеер показал заглушку вместо серии")
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
                fail("ошибка \(http.statusCode)")
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Give the page a moment to render its message, then read the visible text.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
                webView?.evaluateJavaScript("document.body ? document.body.innerText.slice(0, 600) : ''") { result, _ in
                    guard let text = (result as? String)?.lowercased(), !text.isEmpty else { return }
                    if Self.errorPhrases.contains(where: { text.contains($0) }) {
                        self?.fail(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { fail(error.localizedDescription) }
        }

        /// Pop-up windows (usually ads) are not opened.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}

/// The source's website inside the app, as the last resort when no embed plays.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.accent)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A web page to present in `SafariView` with `.sheet(item:)`.
struct SiteLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
