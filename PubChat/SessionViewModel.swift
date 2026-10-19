import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    enum State: Equatable { case restoring, signedOut, signedIn }

    @Published private(set) var state: State = .restoring
    @Published private(set) var identity: IdentityEnvelope?
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var people: [Person] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingDirectory = false
    @Published private(set) var directoryError: String?
    @Published var errorMessage: String?

    private let api = PubChatAPI()

    init() {
        Task { await restore() }
    }

    func signIn(identifier: String, password: String) async {
        await performAuthentication {
            try await self.api.login(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        }
    }

    func signUp(handle: String, displayName: String, email: String, password: String, intent: String) async {
        let payload = RegisterPayload(
            handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
            socialIntent: intent
        )
        await performAuthentication { try await self.api.register(payload) }
    }

    private func performAuthentication(
        _ action: () async throws -> (IdentityEnvelope, String)
    ) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let (identity, cookie) = try await action()
            try completeAuthentication(identity, refreshCookie: cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeAuthentication(_ payload: IdentityEnvelope, refreshCookie: String) throws {
        guard payload.status == "ok",
              payload.account?.uid.isEmpty == false,
              payload.persona != nil,
              let token = payload.accessToken,
              !token.isEmpty,
              refreshCookie.hasPrefix("refresh_token=") else {
            throw APIProblem(status: -1, reason: "Ответ сервера не содержит полноценной сессии.")
        }
        SecureStore.saveSession(accessToken: token, refreshCookie: refreshCookie)
        identity = payload
        state = .signedIn
    }

    func restore() async {
        guard let cookie = SecureStore.refreshCookie else {
            state = .signedOut
            return
        }
        do {
            let (refresh, rotatedCookie) = try await api.refresh(refreshCookie: cookie)
            SecureStore.saveSession(accessToken: refresh.accessToken, refreshCookie: rotatedCookie)
            let profile = try await api.me(accessToken: refresh.accessToken)
            guard profile.account?.uid.isEmpty == false, profile.persona != nil else {
                throw APIProblem(status: -1, reason: "Данные Persona недоступны.")
            }
            identity = profile
            state = .signedIn
        } catch {
            // An unreachable backend is not proof of revocation. Keep Keychain
            // credentials for a later attempt, but do not expose authenticated UI.
            if let problem = error as? APIProblem, problem.status == 401 {
                SecureStore.clearSession()
            }
            state = .signedOut
            errorMessage = "Не удалось восстановить сессию. Повторите вход."
        }
    }

    func reloadDirectory() async {
        guard !isLoadingDirectory, let token = SecureStore.accessToken else { return }
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }
        // Spaces and People are independent destinations. A discovery failure
        // must not make a successfully fetched Spaces catalog look unavailable.
        do {
            spaces = try await api.spaces(accessToken: token)
        } catch {
            directoryError = error.localizedDescription
        }
        // Preserve the legacy People snapshot independently. The People tab
        // performs its own filtered discovery request and error handling.
        do {
            people = try await api.people(accessToken: token)
        } catch {
            // No Spaces error: the People screen has its own load/retry UI.
        }
    }

    // Native clients use the same server-owned social graph as Web.
    // A missing/expired access token never grants local relationship permissions.
    private func socialAccessToken() throws -> String {
        guard state == .signedIn, let token = SecureStore.accessToken, !token.isEmpty else {
            throw APIProblem(status: 401, reason: "Сеанс завершён. Войдите снова.")
        }
        return token
    }

    func discoverPeople(
        query: String, intent: String?, availableNow: Bool, offset: Int = 0
    ) async throws -> DiscoveryPage {
        try await api.discover(
            query: query, intent: intent, availableNow: availableNow,
            offset: offset, accessToken: socialAccessToken()
        )
    }

    func getSocialAvailability() async throws -> SocialAvailability? {
        try await api.socialAvailability(accessToken: socialAccessToken())
    }

    func saveSocialAvailability(intent: String, duration: Int, note: String) async throws -> SocialAvailability? {
        try await api.setSocialAvailability(
            intent: intent, durationMinutes: duration, note: note,
            accessToken: socialAccessToken()
        )
    }

    func endSocialAvailability() async throws {
        try await api.clearSocialAvailability(accessToken: socialAccessToken())
    }

    func relationship(accountUid: String) async throws -> Relationship {
        try await api.relationship(accountUid: accountUid, accessToken: socialAccessToken())
    }

    func toggleFollow(accountUid: String, currentlyFollowing: Bool) async throws -> Relationship {
        try await api.follow(
            accountUid: accountUid, accessToken: socialAccessToken(), isFollowing: currentlyFollowing
        )
    }

    func friendAction(accountUid: String, action: String) async throws -> Relationship {
        try await api.friendAction(
            accountUid: accountUid, action: action, accessToken: socialAccessToken()
        )
    }

    func toggleBlock(accountUid: String, currentlyBlocked: Bool) async throws -> Relationship {
        try await api.block(
            accountUid: accountUid, accessToken: socialAccessToken(), isBlocked: currentlyBlocked
        )
    }

    func listFriendRequests(direction: String, offset: Int = 0) async throws -> FriendRequestsEnvelope {
        try await api.friendRequests(direction: direction, offset: offset, accessToken: socialAccessToken())
    }

    func listFriends(offset: Int = 0) async throws -> FriendshipListEnvelope {
        try await api.friends(offset: offset, accessToken: socialAccessToken())
    }

    func notificationInbox() async throws -> NotificationInboxEnvelope {
        let token = try socialAccessToken()
        try await api.syncNotificationInbox(accessToken: token)
        return try await api.notifications(accessToken: token)
    }

    func markNotificationRead(uid: String) async throws {
        try await api.markNotificationRead(uid: uid, accessToken: socialAccessToken())
    }

    func getBirthdayNotificationPreference() async throws -> Bool {
        try await api.birthdayNotificationPreference(accessToken: socialAccessToken())
    }

    func setBirthdayNotificationPreference(_ enabled: Bool) async throws -> Bool {
        try await api.setBirthdayNotificationPreference(
            enabled, accessToken: socialAccessToken()
        )
    }

    func listPersonas() async throws -> PersonaListEnvelope {
        guard state == .signedIn, let token = SecureStore.accessToken else {
            throw APIProblem(status: 401, reason: "Сеанс завершён.")
        }
        return try await api.personas(accessToken: token)
    }

    func createPersona(handle: String, displayName: String) async throws {
        guard state == .signedIn, let token = SecureStore.accessToken else {
            throw APIProblem(status: 401, reason: "Сеанс завершён.")
        }
        _ = try await api.createPersona(
            handle: handle, displayName: displayName, accessToken: token
        )
    }

    func activatePersona(uid: String) async throws {
        guard state == .signedIn, let token = SecureStore.accessToken else {
            throw APIProblem(status: 401, reason: "Сеанс завершён.")
        }
        let selected = try await api.activatePersona(uid: uid, accessToken: token)
        guard selected.status == "ok", selected.account?.uid == identity?.account?.uid,
              selected.persona?.uid == uid else {
            throw APIProblem(status: -1, reason: "Сервер не подтвердил выбор образа.")
        }
        identity = selected
        // Account-scoped Spaces, DMs and moderation are not separate per Persona.
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        let token = SecureStore.accessToken
        let cookie = SecureStore.refreshCookie
        do {
            try await api.logout(accessToken: token, refreshCookie: cookie)
        } catch {
            // Local credentials are still erased; the remote session may remain
            // active until expiration if the network is unavailable.
        }
        SecureStore.clearSession()
        identity = nil
        spaces = []
        people = []
        errorMessage = nil
        state = .signedOut
        isBusy = false
    }
}
