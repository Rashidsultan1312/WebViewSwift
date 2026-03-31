import Foundation
import Combine

@MainActor
final class WebUGateService: ObservableObject {
    @Published private(set) var shouldShowWebView = false
    @Published private(set) var targetURL = ""
    @Published private(set) var isLoading = false

    private static let apiURL = URL(string: "https://tiny-endpoint.vercel.app/api/webview-target")!

    private struct ResponseDTO: Decodable {
        let enabled: Bool
        let targetURL: String?

        enum CodingKeys: String, CodingKey {
            case enabled
            case targetURL = "target_url"
        }
    }

    func checkRemote() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: Self.apiURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                applyFailure()
                return
            }

            let decoded = try JSONDecoder().decode(ResponseDTO.self, from: data)

            guard decoded.enabled,
                  let raw = decoded.targetURL,
                  !raw.isEmpty,
                  URL(string: raw) != nil
            else {
                applyFailure()
                return
            }

            shouldShowWebView = true
            targetURL = raw

        } catch {
            applyFailure()
        }
    }

    private func applyFailure() {
        shouldShowWebView = false
        targetURL = ""
    }
}
