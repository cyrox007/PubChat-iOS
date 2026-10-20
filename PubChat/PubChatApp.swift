import SwiftUI

@main
struct PubChatApp: App {
    @UIApplicationDelegateAdaptor(PubChatAppDelegate.self) private var appDelegate
    @StateObject private var session = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onReceive(NotificationCenter.default.publisher(for: .pubChatPushToken)) { signal in
                    if let token = signal.object as? String {
                        Task { await session.registerNativePushToken(token) }
                    }
                }
                .onChange(of: session.state) { _, state in
                    if state == .signedIn { session.restoreNativePushIfOptedIn() }
                }
        }
    }
}
