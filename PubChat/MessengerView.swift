import SwiftUI

/// Real account-scoped Messenger inbox, not a mock destination.
struct MessengerHubView: View {
    @EnvironmentObject private var session: SessionViewModel
    @StateObject private var messenger = MessengerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if messenger.loadingDialogs && messenger.dialogs.isEmpty {
                    VStack(spacing: 16) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 14) {
                                Circle().fill(PubChatDesign.primary.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 10) {
                                    Capsule().fill(PubChatDesign.primary.opacity(0.12))
                                        .frame(width: 140, height: 14)
                                    Capsule().fill(PubChatDesign.primary.opacity(0.07))
                                        .frame(width: 210, height: 10)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(PubChatDesign.surface, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityLabel("Загрузка диалогов")
                        }
                    }
                    .padding(16)
                    Spacer()
                } else if messenger.dialogs.isEmpty {
                    PubChatStateCard(
                        symbol: messenger.errorText == nil ? "bubble.left.and.bubble.right" : "wifi.exclamationmark",
                        title: messenger.errorText == nil ? "Переписок пока нет" : "Не удалось загрузить чаты",
                        message: messenger.errorText ?? "В разделе «Люди» можно найти собеседника.",
                        actionTitle: "Повторить",
                        action: { Task { await messenger.refreshDialogs() } }
                    )
                    .padding(16)
                } else {
                    List {
                        if let errorText = messenger.errorText {
                            Section {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Не удалось обновить чаты", systemImage: "wifi.exclamationmark")
                                        .foregroundStyle(PubChatDesign.danger)
                                    Text(errorText).font(.footnote)
                                    Text("Показан ранее загруженный список.")
                                        .font(.caption)
                                    Button("Повторить") {
                                        Task { await messenger.refreshDialogs() }
                                    }
                                }
                            }
                        }
                        if messenger.connection != "connected" {
                            Section {
                                Label(messenger.connection == "restricted"
                                      ? "Доступ к Messenger ограничен"
                                      : "Подключаем Messenger…",
                                      systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote)
                                    .foregroundStyle(PubChatDesign.secondaryInk)
                            }
                        }
                        ForEach(messenger.dialogs) { dialog in
                            NavigationLink {
                                MessengerConversationView(messenger: messenger, dialog: dialog)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(dialog.title.prefix(1)).uppercased())
                                        .font(.headline.bold())
                                        .foregroundStyle(PubChatDesign.primary)
                                        .frame(width: 48, height: 48)
                                        .background(PubChatDesign.primary.opacity(0.1), in: Circle())
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(dialog.title).font(.headline)
                                            .foregroundStyle(PubChatDesign.ink)
                                        // Legacy /dialogs omits content_type: never expose unknown
                                        // ciphertext as a seemingly plaintext message preview.
                                        Text("Открыть переписку")
                                            .font(.subheadline)
                                            .foregroundStyle(PubChatDesign.secondaryInk)
                                    }
                                    Spacer()
                                    if dialog.unreadCount > 0 {
                                        Text("\(min(99, dialog.unreadCount))")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(8)
                                            .background(PubChatDesign.primary, in: Circle())
                                            .accessibilityLabel("Непрочитанных: \(dialog.unreadCount)")
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(PubChatDesign.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable { await messenger.refreshDialogs() }
                }
            }
            .background(PubChatDesign.background)
            .navigationTitle("Чаты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await messenger.refreshDialogs() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Обновить чаты")
                    .disabled(messenger.loadingDialogs)
                }
            }
        }
        .task { await messenger.start(accountUID: session.identity?.account?.uid) }
        .onDisappear { messenger.stop() }
    }
}

private struct MessengerConversationView: View {
    @ObservedObject var messenger: MessengerViewModel
    let dialog: MessengerDialog

    var body: some View {
        VStack(spacing: 0) {
            if messenger.connection != "connected" {
                Label(connectionLabel, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(PubChatDesign.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(PubChatDesign.primary.opacity(0.07))
            }
            if let error = messenger.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(PubChatDesign.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            if messenger.loadingConversation && messenger.messages.isEmpty {
                Spacer()
                ProgressView("Загружаем историю переписки…")
                Spacer()
            } else if messenger.messages.isEmpty {
                Spacer()
                PubChatStateCard(
                    symbol: "bubble.left",
                    title: "Здесь пока тихо",
                    message: messenger.connection == "connected"
                        ? "Начните общение, если собеседник принимает сообщения."
                        : "Сообщения появятся после восстановления соединения."
                )
                .padding(16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messenger.messages) { message in
                            HStack {
                                if messenger.isMine(message) { Spacer(minLength: 28) }
                                VStack(alignment: messenger.isMine(message) ? .trailing : .leading,
                                       spacing: 6) {
                                    Text(message.visibleText)
                                        .font(.body)
                                        .foregroundStyle(PubChatDesign.ink)
                                        .textSelection(.enabled)
                                    if messenger.isMine(message) {
                                        Text(message.isRead ? "Прочитано" : "Отправлено")
                                            .font(.caption2)
                                            .foregroundStyle(PubChatDesign.secondaryInk)
                                    }
                                }
                                .padding(12)
                                .background(messenger.isMine(message)
                                            ? PubChatDesign.primary.opacity(0.13)
                                            : PubChatDesign.surface,
                                            in: RoundedRectangle(cornerRadius: 18))
                                if !messenger.isMine(message) { Spacer(minLength: 28) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            if messenger.encryption?.effectiveMode == "e2ee" {
                Label("Для E2EE-переписки используйте клиент с поддержкой шифрования.",
                      systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(PubChatDesign.secondaryInk)
                    .padding(12)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Сообщение", text: $messenger.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Текст сообщения")
                        .disabled(messenger.connection != "connected")
                    Button {
                        Task { await messenger.sendText() }
                    } label: {
                        if messenger.sending { ProgressView() }
                        else { Image(systemName: "arrow.up").font(.headline.bold()) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PubChatDesign.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(messenger.sending ? "Ожидаем подтверждения" : "Отправить сообщение")
                    .disabled(!messenger.canSend)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                if messenger.sending {
                    Text("Ожидаем подтверждения сервера. Повторная отправка заблокирована.")
                        .font(.caption2)
                        .foregroundStyle(PubChatDesign.secondaryInk)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(PubChatDesign.background)
        .navigationTitle(dialog.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await messenger.open(dialog) }
        .onDisappear { Task { await messenger.closeConversation() } }
    }

    private var connectionLabel: String {
        switch messenger.connection {
        case "restricted": return "Доступ к Messenger ограничен"
        case "reconnecting": return "Переподключаем Messenger…"
        case "connecting": return "Подключаем Messenger…"
        default: return "Нет соединения с Messenger"
        }
    }
}
