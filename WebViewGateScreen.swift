import SwiftUI
import UIKit
import WebKit

/// Full-screen WebView shown after launch when remote config enables it.
struct WebViewGateScreen: View {
    let urlString: String

    @State private var isPageLoading = true

    private static let closeButtonFadeDelay: TimeInterval = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            FullScreenWebViewRepresentable(
                urlString: urlString,
                isLoading: $isPageLoading
            )
            .ignoresSafeArea()

            if isPageLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - Close button

private struct CloseGateButton: View {
    let delay: TimeInterval
    let action: () -> Void

    @State private var visible = false

    var body: some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.55))
                .clipShape(Circle())
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: visible)
        .onAppear {
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    visible = true
                }
            } else {
                visible = true
            }
        }
    }
}

// MARK: - WKWebView

struct FullScreenWebViewRepresentable: UIViewRepresentable {
    let urlString: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all

        let leakAvoider = LeakAvoider(delegate: context.coordinator)
        config.userContentController.add(leakAvoider, name: "godot")

        let noZoomScript = WKUserScript(
            source: """
            var meta=document.createElement('meta');
            meta.name='viewport';
            meta.content='width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no';
            document.head.appendChild(meta);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(noZoomScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        context.coordinator.webView = webView

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }
}

// MARK: - Coordinator

extension FullScreenWebViewRepresentable {
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: FullScreenWebViewRepresentable
        weak var webView: WKWebView?

        init(_ parent: FullScreenWebViewRepresentable) {
            self.parent = parent
        }

        // MARK: WKScriptMessageHandler (JS bridge)

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Optional: forward to analytics / deep links later
            _ = message.body
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = false
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme != "http", scheme != "https", scheme != "about", scheme != "blob" {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleLoadError(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func handleLoadError(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return
            }
            Task { @MainActor in
                parent.isLoading = false
            }
        }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentAlert(title: nil, message: message, confirm: completionHandler)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let presenter = topViewController(from: webView) else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "alert.ok"), style: .default) { _ in completionHandler(true) })
            alert.addAction(UIAlertAction(title: String(localized: "alert.cancel"), style: .cancel) { _ in completionHandler(false) })
            presenter.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil || !(navigationAction.targetFrame?.isMainFrame ?? false) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func presentAlert(title: String?, message: String, confirm: @escaping () -> Void) {
            guard let presenter = topViewController(from: webView) else {
                confirm()
                return
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "alert.ok"), style: .default) { _ in confirm() })
            presenter.present(alert, animated: true)
        }

        private func topViewController(from webView: WKWebView?) -> UIViewController? {
            if let window = webView?.window, let root = window.rootViewController {
                return root.topMost
            }
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                let window = windowScene.windows.first { $0.isKeyWindow } ?? windowScene.windows.first
                if let root = window?.rootViewController {
                    return root.topMost
                }
            }
            return nil
        }
    }
}

// MARK: - Leak avoider for WKScriptMessageHandler

private final class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

// MARK: - UIViewController helper

private extension UIViewController {
    var topMost: UIViewController {
        if let presented = presentedViewController {
            return presented.topMost
        }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.topMost
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topMost
        }
        return self
    }
}

#if DEBUG
#Preview {
    WebViewGateScreen(urlString: "https://www.apple.com")
}
#endif
