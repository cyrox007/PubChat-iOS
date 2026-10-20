import Foundation
import UserNotifications
import UIKit

/// Account-scoped opt-in. APNs token is a delivery credential, not a crypto identity.
enum NativePushPreferences {
    static func key(for accountUID: String) -> String {
        "pubchat.native_push.optin." + (UUID(uuidString: accountUID)?.uuidString.lowercased() ?? "invalid")
    }

    static func optedIn(accountUID: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: accountUID))
    }

    static func remember(_ enabled: Bool, accountUID: String) {
        UserDefaults.standard.set(enabled, forKey: key(for: accountUID))
    }
}

struct APNsConfigurationEnvelope: Decodable {
    let status: String
    let ios: APNsCapability

    struct APNsCapability: Decodable {
        let provider: String
        let enabled: Bool
    }
}

/// A server acknowledgement is required before the UI calls the channel enabled.
struct NativePushRegistrationEnvelope: Decodable {
    let status: String
    let device: NativePushDeviceProjection

    struct NativePushDeviceProjection: Decodable {
        let installationUID: String
        let platform: String
        let provider: String

        enum CodingKeys: String, CodingKey {
            case installationUID = "installation_uid", platform, provider
        }
    }
}

struct MessagePushPreferencesEnvelope: Decodable {
    let status: String
    let preferences: MessagePushPreferences

    struct MessagePushPreferences: Decodable {
        let nativePushMessenger: Bool
        let nativePushSpace: Bool

        enum CodingKeys: String, CodingKey {
            case nativePushMessenger = "native_push_messenger", nativePushSpace = "native_push_space"
        }
    }
}
