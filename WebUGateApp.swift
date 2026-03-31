import SwiftUI
import UIKit

@main
struct YourAppNameApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var webViewGateService = WebViewGateService()

    @State private var isLaunchComplete = false
    @State private var showWebViewGate = false

    init() {
        // Optional: startup configuration
        // Example:
        // let notificationsEnabled = UserDefaults.standard.bool(
        //     forKey: NotificationManager.notificationsEnabledKey
        // )
        // NotificationManager.shared.syncReminders(isEnabled: notificationsEnabled)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLaunchComplete {
                    MainRootView()
                        .environmentObject(appStore)
                        .preferredColorScheme(.dark)
                } else {
                    launchLoader
                }
            }
            .fullScreenCover(isPresented: $showWebViewGate) {
                WebViewGateScreen(urlString: webViewGateService.targetURL)
            }
            .task {
                async let remoteCheck: Void = webViewGateService.checkRemote()

                // Optional minimum launch delay
                try? await Task.sleep(for: .seconds(2.5))

                await remoteCheck
                isLaunchComplete = true

                if webViewGateService.shouldShowWebView {
                    DispatchQueue.main.async {
                        showWebViewGate = true
                    }
                }
            }
        }
    }

    private var launchLoader: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SwiftUI.ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
        }
        .preferredColorScheme(.dark)
    }
}
