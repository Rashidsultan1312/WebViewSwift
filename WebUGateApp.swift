import SwiftUI

@main
struct WebUGateApp: App {
    @StateObject private var gateService = WebUGateService()
    @State private var isLaunchComplete = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLaunchComplete {
                    if gateService.shouldShowWebView {
                        WebUGateScreen(urlString: gateService.targetURL)
                    } else {
                        Text("MAIN APP (fallback)")
                            .font(.title)
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                async let remoteCheck: Void = gateService.checkRemote()
                try? await Task.sleep(for: .seconds(2.0))
                await remoteCheck
                isLaunchComplete = true
            }
        }
    }
}
