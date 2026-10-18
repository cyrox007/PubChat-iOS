import Foundation

struct IdentityEnvelope: Decodable {
    let status: String
    let accessToken: String?
    let account: Account?
    let persona: Persona?
    let user: LegacyUser?

    enum CodingKeys: String, CodingKey {
        case status, account, persona, user
        case accessToken = "access_token"
    }

    struct Account: Decodable {
        let uid: String
    }

    struct LegacyUser: Decodable {
        let displayName: String?
        let username: String?
        enum CodingKeys: String, CodingKey {
            case username
            case displayName = "display_name"
        }
    }

    struct Persona: Decodable {
        let uid: String
        let handle: String
        let displayName: String
        let bio: String?
        let socialIntent: String?
        let isPrimary: Bool?

        enum CodingKeys: String, CodingKey {
            case uid, handle, bio
            case displayName = "display_name"
            case socialIntent = "social_intent"
            case isPrimary = "is_primary"
        }
    }
}

struct PersonaListEnvelope: Decodable {
    let personas: [IdentityEnvelope.Persona]
    let activePersonaUid: String?
    enum CodingKeys: String, CodingKey {
        case personas
        case activePersonaUid = "active_persona_uid"
    }
}

struct PersonaCreatePayload: Encodable {
    let handle: String
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
    }
}

struct RefreshEnvelope: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

struct Space: Decodable, Identifiable {
    let uid: String
    let name: String
    let description: String?
    var id: String { uid }
}

struct SpaceListEnvelope: Decodable {
    let spaces: [Space]
}

struct Person: Decodable, Identifiable {
    let accountUid: String
    let displayName: String
    let handle: String?
    let bio: String?
    let socialIntent: String?
    var id: String { accountUid }

    enum CodingKeys: String, CodingKey {
        case handle, bio
        case accountUid = "account_uid"
        case displayName = "display_name"
        case socialIntent = "social_intent"
    }
}

struct PeopleEnvelope: Decodable {
    let people: [Person]
}

struct Relationship: Decodable, Equatable {
    let accountUid: String
    let following: Bool
    let followedBy: Bool
    let friends: Bool
    let friendRequest: String?
    let blockedByMe: Bool
    let blockedMe: Bool

    enum CodingKeys: String, CodingKey {
        case following, friends
        case accountUid = "account_uid"
        case followedBy = "followed_by"
        case friendRequest = "friend_request"
        case blockedByMe = "blocked_by_me"
        case blockedMe = "blocked_me"
    }

    var canInteract: Bool { !blockedByMe && !blockedMe }
    var friendAction: String {
        if friends || friendRequest == "outgoing" { return "remove" }
        if friendRequest == "incoming" { return "accept" }
        return "request"
    }
    var friendActionTitle: String {
        if friends { return "Удалить из друзей" }
        if friendRequest == "incoming" { return "Принять запрос" }
        if friendRequest == "outgoing" { return "Отменить запрос" }
        return "Предложить дружбу"
    }
}

struct RelationshipEnvelope: Decodable {
    let status: String
    let relationship: Relationship
}

struct FriendActionPayload: Encodable {
    let action: String
}

struct RegisterPayload: Encodable {
    let handle: String
    let displayName: String
    let password: String
    let email: String?
    let socialIntent: String

    enum CodingKeys: String, CodingKey {
        case handle, password, email
        case displayName = "display_name"
        case socialIntent = "social_intent"
    }
}

struct LoginPayload: Encodable {
    let identifier: String
    let password: String
}

struct APIProblem: Error, LocalizedError {
    let status: Int
    let reason: String
    var errorDescription: String? {
        switch status {
        case 401: return "Неверные учётные данные или истекла сессия."
        case 403: return "Доступ ограничен сервером: \(reason)"
        case 409: return "Конфликт данных: \(reason)"
        case -1: return reason
        default: return "Ошибка сервера (\(status)): \(reason)"
        }
    }
}

enum APIErrorDecoder {
    static func reason(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Повторите попытку позже."
        }
        if let detail = json["detail"] as? String { return detail }
        if let detail = json["detail"] as? [String: Any],
           let code = detail["error_type"] as? String {
            return code
        }
        return "Повторите попытку позже."
    }
}
