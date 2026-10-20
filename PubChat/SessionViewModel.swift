import Foundation
import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class SessionViewModel: ObservableObject {
    enum State: Equatable { case restoring, signedOut, signedIn }

    @Published private(set) var state: State = .restoring
    @Published private(set) var identity: IdentityEnvelope?
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var spaceCategories: [SpaceCategory] = []
    @Published private(set) var selectedSpaceCategory: String?
    @Published private(set) var spaceCategoryError: String?
    @Published private(set) var people: [Person] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingDirectory = false
    @Published private(set) var directoryError: String?
    @Published var errorMessage: String?
    @Published private(set) var nativePushStatus: String?
    @Published private(set) var nativePushEnabled = false

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
        nativePushEnabled = false // A stored opt-in is not a verified current APNs registration.
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
            nativePushEnabled = false // Re-register and await a fresh server acknowledgement.
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

    func loadSpaceCategories() async {
        guard let token = SecureStore.accessToken else { return }
        spaceCategoryError = nil
        do { spaceCategories = try await api.spaceCategories(accessToken: token) }
        catch { spaceCategoryError = "Не удалось получить категории. Попробуйте снова." }
    }

    func selectSpaceCategory(_ slug: String?) async {
        guard !isLoadingDirectory else { return }
        if let slug, !spaceCategories.contains(where: { $0.slug == slug }) { return }
        selectedSpaceCategory = slug
        // Explicit filter changes must not display unrelated stale Space cards.
        spaces = []
        await reloadDirectory()
    }

    func spaceCategoryName(_ slug: String) -> String {
        spaceCategories.first(where: { $0.slug == slug })?.name ?? slug
    }

    func reloadDirectory() async {
        guard !isLoadingDirectory, let token = SecureStore.accessToken else { return }
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }
        // Spaces and People are independent destinations. A discovery failure
        // must not make a successfully fetched Spaces catalog look unavailable.
        do {
            spaces = try await api.spaces(accessToken: token, category: selectedSpaceCategory)
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

    /// Always refresh from the server; a cached identity is not an authority
    /// for current DM privacy. The secondary Persona cannot change this policy.
    func fetchDMPrivacy() async throws -> IdentityPrivacy {
        let token = try socialAccessToken()
        guard let accountUID = identity?.account?.uid,
              let personaUID = identity?.persona?.uid else {
            throw APIProblem(status: 401, reason: "Не найдена текущая Persona.")
        }
        let fresh = try await api.me(accessToken: token)
        guard fresh.status == "ok", fresh.account?.uid == accountUID,
              fresh.persona?.uid == personaUID, let privacy = fresh.privacy else {
            throw APIProblem(status: -1, reason: "Сервер не подтвердил настройки приватности.")
        }
        identity = fresh
        return privacy
    }

    func saveDMPrivacy(_ policy: DMConsentPolicy) async throws -> IdentityPrivacy {
        let token = try socialAccessToken()
        guard let accountUID = identity?.account?.uid,
              let personaUID = identity?.persona?.uid else {
            throw APIProblem(status: 401, reason: "Не найдена текущая Persona.")
        }
        let updated = try await api.updateDMPolicy(policy, accessToken: token)
        guard updated.status == "ok", updated.account?.uid == accountUID,
              updated.persona?.uid == personaUID, let privacy = updated.privacy,
              privacy.dmPolicy == policy else {
            throw APIProblem(status: -1, reason: "Сервер не подтвердил изменение приватности.")
        }
        identity = updated
        return privacy
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

    func requestNativePushPermission() async {
        guard state == .signedIn, let account = identity?.account?.uid,
              let access = SecureStore.accessToken else {
            nativePushStatus = "Сначала войдите в аккаунт."
            return
        }
        do {
            let config = try await api.apnsConfiguration(accessToken: access)
            guard config.status == "ok", config.ios.enabled else {
                nativePushStatus = "APNs на сервере ещё не настроен. Проверьте APNS_* в backend."
                return
            }
            let authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            guard authorized else {
                nativePushStatus = "Системные уведомления запрещены. Разрешите их в настройках iPhone."
                return
            }
            NativePushPreferences.remember(true, accountUID: account)
            nativePushEnabled = false
            nativePushStatus = "Получаем токен Apple и подключаем уведомления…"
            UIApplication.shared.registerForRemoteNotifications()
            if let token = PubChatAppDelegate.latestAPNsToken {
                await registerNativePushToken(token)
            }
        } catch {
            nativePushStatus = "Не удалось подключить Push: \(error.localizedDescription)"
        }
    }

    func restoreNativePushIfOptedIn() {
        guard state == .signedIn, let account = identity?.account?.uid,
              NativePushPreferences.optedIn(accountUID: account) else { return }
        nativePushStatus = "Проверяем регистрацию уведомлений…"
        UIApplication.shared.registerForRemoteNotifications()
        if let token = PubChatAppDelegate.latestAPNsToken {
            Task { await registerNativePushToken(token) }
        }
    }

    func registerNativePushToken(_ token: String) async {
        guard state == .signedIn, let account = identity?.account?.uid,
              NativePushPreferences.optedIn(accountUID: account),
              let access = SecureStore.accessToken else { return }
        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                nativePushStatus = "Разрешение на уведомления отключено в iOS."
                return
            }
            let config = try await api.apnsConfiguration(accessToken: access)
            guard config.ios.enabled else {
                nativePushEnabled = false
                nativePushStatus = "Сервер APNs отключён. Свяжитесь с администратором."
                return
            }
            try await api.registerAPNsDevice(token: token, accessToken: access)
            try await api.setAPNsMessagePreferences(true, accessToken: access)
            nativePushEnabled = true
            nativePushStatus = "Push для личных сообщений и ответов в Space включён."
        } catch {
            nativePushEnabled = false
            nativePushStatus = "Сервер не подтвердил Push: \(error.localizedDescription)"
        }
    }

    func disableNativePush() async {
        guard state == .signedIn, let account = identity?.account?.uid,
              let access = SecureStore.accessToken else { return }
        do {
            try await api.removeAPNsDevice(accessToken: access)
            // Preferences are Account-wide and may be needed by another Android device.
            // Only the local iOS installation is revoked.
            NativePushPreferences.remember(false, accountUID: account)
            nativePushEnabled = false
            nativePushStatus = "Это устройство больше не зарегистрировано для Push."
        } catch {
            nativePushStatus = "Не удалось отозвать устройство. Повторите при доступной сети."
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        let token = SecureStore.accessToken
        let cookie = SecureStore.refreshCookie
        do {
            if let token {
                // Revoke *before* clearing Keychain: otherwise former Account can
                // continue receiving generic pushes until the installation rebinds.
                try? await api.removeAPNsDevice(accessToken: token)
            }
            try await api.logout(accessToken: token, refreshCookie: cookie)
        } catch {
            // Local credentials are still erased; the remote session may remain
            // active until expiration if the network is unavailable.
        }
        SecureStore.clearSession()
        identity = nil
        nativePushEnabled = false
        nativePushStatus = nil
        spaces = []
        people = []
        errorMessage = nil
        state = .signedOut
        isBusy = false
    }
}
