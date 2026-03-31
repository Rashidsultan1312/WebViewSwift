import Combine
import Foundation

/// Fetches remote config for the optional launch WebView (same contract as WebViewGodot `webview.gd`).
@MainActor
final class WebViewGateService: ObservableObject {
    private static let productionAPIURL = URL(string: "https://tiny-endpoint.vercel.app/api/webview-target")!
    private static let requestTimeout: TimeInterval = 10

    /// Debug: `http://127.0.0.1:8000/...` (симулятор). На реальному пристрої задайте `WEBVIEW_GATE_API` у схемі Xcode (IP Mac у Wi‑Fi).
    private static func resolvedAPIURL() -> URL {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["WEBVIEW_GATE_API"],
           let url = URL(string: raw),
           !raw.isEmpty {
            return url
        }
        return URL(string: "http://127.0.0.1:8000/api/webview-target")!
        #else
        return productionAPIURL
        #endif
    }

    @Published private(set) var shouldShowWebView = false
    @Published private(set) var targetURL = ""
    @Published private(set) var isLoading = true

    func checkRemote() async {
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: Self.resolvedAPIURL())
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                applyFailure()
                return
            }
            let config = try JSONDecoder().decode(RemoteWebViewConfig.self, from: data)
            let urlString = config.targetURL ?? ""
            let enabled = config.enabled ?? false
            if enabled, !urlString.isEmpty, URL(string: urlString) != nil {
                shouldShowWebView = true
                targetURL = urlString
            } else {
                applyFailure()
            }
        } catch {
            applyFailure()
        }
    }

    private func applyFailure() {
        shouldShowWebView = false
        targetURL = ""
    }
}

private struct RemoteWebViewConfig: Decodable {
    let enabled: Bool?
    let targetURL: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case targetURL = "target_url"
    }
}
