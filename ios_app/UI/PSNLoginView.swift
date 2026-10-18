import SwiftUI
import WebKit

/// Sony's sign-in page inside the app. The page ends on a redirect URL that carries a `code`; the view cancels
/// that navigation and hands the code over. The session is not kept (non-persistent data store), so nothing
/// of the login stays on the phone.
struct PSNLoginView: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: PSNAccountID.loginURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.absoluteString.hasPrefix(PSNAccountID.redirectURI) {
                decisionHandler(.cancel)
                if let code = PSNAccountID.code(fromRedirectURL: url.absoluteString) { onCode(code) }
                return
            }
            decisionHandler(.allow)
        }
    }
}
