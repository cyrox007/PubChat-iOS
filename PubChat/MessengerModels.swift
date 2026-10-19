import Foundation

/// Account-scoped Messenger data. Persona IDs must never replace partner_id.
struct MessengerDialog: Decodable, Identifiable {
    struct Partner: Decodable {
        let username: String?
        let avatar: String?
    }

    let partnerID: String
    let lastMessage: String?
    let lastMessageTime: String?
    let unreadCount: Int
    let partner: Partner

    var id: String { partnerID }
    var title: String { partner.username?.isEmpty == false ? partner.username! : "Участник PubChat" }

    enum CodingKeys: String, CodingKey {
        case partner
        case partnerID = "partner_id"
        case lastMessage = "last_message"
        case lastMessageTime = "last_message_time"
        case unreadCount = "unread_count"
    }
}

struct MessengerDialogsEnvelope: Decodable {
    let status: String
    let dialogs: [MessengerDialog]
}

struct MessengerEncryptionEnvelope: Decodable {
    let status: String
    let encryption: MessengerEncryptionPolicy
}

struct MessengerEncryptionPolicy: Decodable {
    let effectiveMode: String
    let systemPolicy: String

    var allowsPlaintext: Bool { effectiveMode == "plaintext" }

    enum CodingKeys: String, CodingKey {
        case effectiveMode = "effective_mode"
        case systemPolicy = "system_policy"
    }
}

struct MessengerTicket: Decodable {
    let ticket: String
    let websocketPath: String
    let heartbeatSeconds: Int

    enum CodingKeys: String, CodingKey {
        case ticket
        case websocketPath = "websocket_path"
        case heartbeatSeconds = "heartbeat_seconds"
    }
}

/// Only server-confirmed messages belong to the conversation timeline.
/// Ciphertext is not rendered as a plaintext message.
struct MessengerMessage: Decodable, Identifiable {
    let uid: String
    let content: String?
    let contentType: String
    let senderUID: String
    let receiverUID: String
    let isRead: Bool
    let createdAt: String

    var id: String { uid }
    var supportsText: Bool { contentType == "text" }
    var visibleText: String {
        switch contentType {
        case "text": return content ?? ""
        case "e2ee": return "Зашифрованное сообщение — недоступно в этом клиенте"
        case "deleted": return "Сообщение удалено"
        case "image", "video", "audio", "voice", "file":
            return "Вложение — откройте в поддерживаемом клиенте"
        default: return "Неподдерживаемый тип сообщения"
        }
    }

    enum CodingKeys: String, CodingKey {
        case uid, content
        case contentType = "content_type"
        case senderUID = "sender_uid"
        case receiverUID = "receiver_uid"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}
