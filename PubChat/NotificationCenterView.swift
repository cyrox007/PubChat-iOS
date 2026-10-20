import SwiftUI

/// Server-owned inbox, displayed with native SwiftUI. This is not APNs delivery:
/// no system notification is promised while the app is suspended.
struct NotificationCenterView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var notifications: [NotificationEntry] = []
    @State private var loading = false
    @State private var busyUid: String?
    @State private var birthdayEnabled = false
    @State private var savingPreference = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section("Сообщения вне приложения") {
                Text("Получайте системные уведомления со звуком, когда PubChat свёрнут или закрыт. Личные сообщения и ответы в пространствах звучат по-разному; содержимое переписки не передаётся в Push.")
                    .font(.caption).foregroundStyle(.secondary)
                if session.nativePushEnabled {
                    Button("Отключить Push на этом iPhone") {
                        Task { await session.disableNativePush() }
                    }
                } else {
                    Button("Включить Push для сообщений и ответов") {
                        Task { await session.requestNativePushPermission() }
                    }
                }
                if let status = session.nativePushStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("Требуется разрешение iOS и настроенный сервер APNs. В беззвучном режиме и режиме фокусирования звук определяет iOS.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Напоминания") {
                Toggle("Дни рождения друзей", isOn: Binding(
                    get: { birthdayEnabled },
                    set: { enabled in
                        guard !savingPreference else { return }
                        Task { await changeBirthdayPreference(enabled) }
                    }
                ))
                .disabled(savingPreference)
                Text("Только друзья, разрешившие напоминание; без года рождения. Это внутренние уведомления PubChat, а не фоновый APNs push.")
                    .font(.caption).foregroundStyle(.secondary)
                if savingPreference { ProgressView("Сохраняем…") }
            }
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                    Button("Повторить") { Task { await load() } }
                }
            }
            if loading {
                Section { ProgressView("Синхронизируем уведомления…") }
            } else if notifications.isEmpty && errorText == nil {
                Section {
                    ContentUnavailableView("Новых событий нет", systemImage: "bell.slash")
                }
            }
            ForEach(notifications) { item in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                                .fontWeight(item.isRead ? .regular : .semibold)
                            if !item.isRead {
                                Circle().fill(.blue).frame(width: 7, height: 7)
                            }
                        }
                        Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                        Text(item.createdAt).font(.caption2).foregroundStyle(.tertiary)
                        if !item.isRead {
                            Button("Отметить прочитанным") {
                                Task { await markRead(item.uid) }
                            }.disabled(busyUid != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Уведомления")
        .refreshable { await load() }
        .task {
            await loadPreference()
            await load()
        }
    }

    @MainActor private func loadPreference() async {
        do { birthdayEnabled = try await session.getBirthdayNotificationPreference() }
        catch { errorText = error.localizedDescription }
    }

    @MainActor private func changeBirthdayPreference(_ enabled: Bool) async {
        savingPreference = true
        errorText = nil
        defer { savingPreference = false }
        do {
            birthdayEnabled = try await session.setBirthdayNotificationPreference(enabled)
            await load()
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            notifications = try await session.notificationInbox().notifications
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func markRead(_ uid: String) async {
        guard busyUid == nil else { return }
        busyUid = uid
        defer { busyUid = nil }
        do {
            try await session.markNotificationRead(uid: uid)
            // Never flip the server-owned flag optimistically.
            await load()
        } catch { errorText = error.localizedDescription }
    }
}
