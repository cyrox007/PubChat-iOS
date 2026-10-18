import Foundation

/// REST adapter for the same Identity v2 API used by the web and Android apps.
/// Unsafe methods require both the signed CSRF cookie and its header proof.
final class PubChatAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = nil, session: URLSession? = nil) {
        let configured = Bundle.main.object(forInfoDictionaryKey: "PubChatAPIBaseURL") as? String
        self.baseURL = baseURL
            ?? URL(string: configured ?? "https://pubchat.ru/api")!
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func login(identifier: String, password: String) async throws -> (IdentityEnvelope, String) {
        let body = try JSONEncoder().encode(LoginPayload(identifier: identifier, password: password))
        let (result, cookie): (IdentityEnvelope, String?) =
            try await request("POST", "/identity/v2/login", body: body)
        guard let cookie else { throw APIProblem(status: -1, reason: "Сервер не выдал refresh-cookie.") }
        return (result, cookie)
    }

    func register(_ payload: RegisterPayload) async throws -> (IdentityEnvelope, String) {
        let body = try JSONEncoder().encode(payload)
        let (result, cookie): (IdentityEnvelope, String?) =
            try await request("POST", "/identity/v2/register", body: body)
        guard let cookie else { throw APIProblem(status: -1, reason: "Сервер не выдал refresh-cookie.") }
        return (result, cookie)
    }

    func refresh(refreshCookie: String) async throws -> (RefreshEnvelope, String) {
        let (result, cookie): (RefreshEnvelope, String?) =
            try await request("POST", "/identity/v2/refresh", refreshCookie: refreshCookie)
        // A missing rotated cookie is a failure: reusing an old refresh token is unsafe.
        guard let cookie else { throw APIProblem(status: -1, reason: "Сервер не обновил refresh-cookie.") }
        return (result, cookie)
    }

    func me(accessToken: String) async throws -> IdentityEnvelope {
        let (result, _): (IdentityEnvelope, String?) =
            try await request("GET", "/identity/v2/me", accessToken: accessToken)
        return result
    }

    func spaces(accessToken: String) async throws -> [Space] {
        let (result, _): (SpaceListEnvelope, String?) =
            try await request("GET", "/spaces/v1?limit=50", accessToken: accessToken)
        return result.spaces
    }

    func people(accessToken: String) async throws -> [Person] {
        let (result, _): (PeopleEnvelope, String?) =
            try await request("GET", "/social/v1/discover?limit=50", accessToken: accessToken)
        return result.people
    }

    func relationship(accountUid: String, accessToken: String) async throws -> Relationship {
        let (result, _): (RelationshipEnvelope, String?) =
            try await request("GET", "/social/v1/relationships/\(accountUid)", accessToken: accessToken)
        return result.relationship
    }

    func follow(accountUid: String, accessToken: String, isFollowing: Bool) async throws -> Relationship {
        let (result, _): (RelationshipEnvelope, String?) = try await request(
            isFollowing ? "DELETE" : "POST",
            "/social/v1/follows/\(accountUid)",
            accessToken: accessToken
        )
        return result.relationship
    }

    func friendAction(accountUid: String, action: String, accessToken: String) async throws -> Relationship {
        let payload = try JSONEncoder().encode(FriendActionPayload(action: action))
        let (result, _): (RelationshipEnvelope, String?) = try await request(
            "PATCH", "/social/v1/friends/\(accountUid)", body: payload, accessToken: accessToken
        )
        return result.relationship
    }

    func block(accountUid: String, accessToken: String, isBlocked: Bool) async throws -> Relationship {
        let (result, _): (RelationshipEnvelope, String?) = try await request(
            isBlocked ? "DELETE" : "POST",
            "/social/v1/blocks/\(accountUid)", accessToken: accessToken
        )
        return result.relationship
    }

    func friendRequests(direction: String, offset: Int = 0, accessToken: String) async throws -> FriendRequestsEnvelope {
        guard direction == "incoming" || direction == "outgoing" else {
            throw APIProblem(status: -1, reason: "Некорректное направление запросов.")
        }
        let (result, _): (FriendRequestsEnvelope, String?) = try await request(
            "GET", "/social/v1/friend-requests?direction=\(direction)&limit=50&offset=\(offset)",
            accessToken: accessToken
        )
        return result
    }

    func friends(offset: Int = 0, accessToken: String) async throws -> FriendshipListEnvelope {
        let (result, _): (FriendshipListEnvelope, String?) = try await request(
            "GET", "/social/v1/friends?limit=50&offset=\(offset)", accessToken: accessToken
        )
        return result
    }

    func personas(accessToken: String) async throws -> PersonaListEnvelope {
        let (result, _): (PersonaListEnvelope, String?) =
            try await request("GET", "/identity/v2/personas", accessToken: accessToken)
        return result
    }

    func createPersona(
        handle: String, displayName: String, accessToken: String
    ) async throws -> IdentityEnvelope.Persona {
        let body = try JSONEncoder().encode(PersonaCreatePayload(handle: handle, displayName: displayName))
        let (result, _): (CreatePersonaEnvelope, String?) =
            try await request("POST", "/identity/v2/personas", body: body, accessToken: accessToken)
        return result.persona
    }

    func activatePersona(uid: String, accessToken: String) async throws -> IdentityEnvelope {
        let (result, _): (IdentityEnvelope, String?) = try await request(
            "POST", "/identity/v2/personas/\(uid)/activate", accessToken: accessToken
        )
        return result
    }

    private struct CreatePersonaEnvelope: Decodable {
        let persona: IdentityEnvelope.Persona
    }

    func logout(accessToken: String?, refreshCookie: String?) async throws {
        let _: (StatusEnvelope, String?) = try await request(
            "POST",
            "/identity/v2/logout",
            accessToken: accessToken,
            refreshCookie: refreshCookie
        )
    }

    private struct StatusEnvelope: Decodable { let status: String }
    private struct CSRFEnvelope: Decodable {
        let csrfToken: String
        enum CodingKeys: String, CodingKey { case csrfToken = "csrf_token" }
    }

    private func url(_ path: String) -> URL {
        let origin = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: origin + path)!
    }

    private func csrfToken() async throws -> String {
        var request = URLRequest(url: url("/csrf/get"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(SecureStore.deviceID, forHTTPHeaderField: "X-PubChat-Device-ID")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIProblem(status: -1, reason: "Нет HTTP-ответа.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIProblem(status: http.statusCode, reason: APIErrorDecoder.reason(from: data))
        }
        let proof = try JSONDecoder().decode(CSRFEnvelope.self, from: data).csrfToken
        // The server sets the same signed token as a cookie and returns its proof in JSON.
        guard http.value(forHTTPHeaderField: "Set-Cookie")?.contains("XSRF-TOKEN=\(proof)") == true else {
            throw APIProblem(status: -1, reason: "Не удалось проверить CSRF-cookie сервера.")
        }
        return proof
    }

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        accessToken: String? = nil,
        refreshCookie: String? = nil
    ) async throws -> (T, String?) {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SecureStore.deviceID, forHTTPHeaderField: "X-PubChat-Device-ID")
        request.setValue("PubChat-iOS/0.1", forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        var cookies: [String] = []
        if let refreshCookie { cookies.append(refreshCookie) }
        if !["GET", "HEAD", "OPTIONS"].contains(method) {
            let proof = try await csrfToken()
            request.setValue(proof, forHTTPHeaderField: "X-CSRF-Token")
            cookies.append("XSRF-TOKEN=\(proof)")
        }
        if !cookies.isEmpty {
            request.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIProblem(status: -1, reason: "Нет HTTP-ответа.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIProblem(status: http.statusCode, reason: APIErrorDecoder.reason(from: data))
        }
        let result = try JSONDecoder().decode(T.self, from: data)
        return (result, Self.refreshCookie(from: http))
    }

    /// Keep only the cookie pair; its remaining attributes belong to the HTTP response.
    static func refreshCookie(from response: HTTPURLResponse) -> String? {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie"),
              let range = header.range(of: "refresh_token=") else { return nil }
        let pair = header[range.lowerBound...].split(separator: ";", maxSplits: 1).first.map(String.init)
        guard let pair, pair.count > "refresh_token=".count else { return nil }
        return pair
    }
}
