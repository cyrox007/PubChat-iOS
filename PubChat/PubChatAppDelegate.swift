import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let pubChatPushToken = Notification.Name("ru.pubchat.app.pushToken")
    static let pubChatPushOpened = Notification.Name("ru.pubchat.app.pushOpened")
}

/// Handles token callbacks even when the SwiftUI notifications screen is closed.
final class PubChatAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static private(set) var latestAPNsToken: String?
    private static var pendingPushType: String?

    static func consumePushDestination() -> String? {
        let target = pendingPushType
        pendingPushType = nil
        return target
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let encoded = token.map { String(format: "%02x", $0) }.joined()
        guard !encoded.isEmpty else { return }
        Self.latestAPNsToken = encoded
        NotificationCenter.default.post(name: .pubChatPushToken, object: encoded)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .pubChatPushToken, object: nil,
                                        userInfo: ["error": "iPhone не зарегистрировался в APNs. Проверьте подпись и Push Notifications."])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // When PubChat is visible, respect system alert/sound/Focus controls.
        completion([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        let payload = response.notification.request.content.userInfo
        let type = payload["type"] as? String ?? ""
        if type == "messenger" || type == "space_reply" {
            Self.pendingPushType = type
            let room = payload["room_uid"] as? String
            let safeRoom = room.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
            NotificationCenter.default.post(name: .pubChatPushOpened, object: nil,
                userInfo: ["type": type, "room_uid": safeRoom ?? ""])
        }
        completion()
    }
}
