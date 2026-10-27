import Foundation
import SwiftUI

/// Native Messenger controller. Only the server can confirm message delivery.
/// Never automatically re-send an unacknowledged frame after a reconnect.
@MainActor
final class MessengerViewModel: ObservableObject {
    @Published private(set) var dialogs: [MessengerDialog] = []
    @Published private(set) var messages: [MessengerMessage] = []
    @Published private(set) var selectedDialog: MessengerDialog?
    @Published private(set) var encryption: MessengerEncryptionPolicy?
    @Published private(set) var connection = "idle"
    @Published private(set) var loadingDialogs = false
    @Published private(set) var loadingConversation = false
    @Published private(set) var errorText: String?
    @Published private(set) var sending = false
    @Published var draft = ""

    private let api = PubChatAPI()
    private var accountUID: String?
    private var isRunning = false
    private var generation = 0
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pendingFrontID: String?
    private var pendingText: String?
    private var pendingPeerUID: String?

    func isMine(_ message: MessengerMessage) -> Bool { message.senderUID == accountUID }

    var canSend: Bool {
        connection == "connected" && encryption?.allowsPlaintext == true
            && selectedDialog != nil && !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(accountUID: String?) async {
        guard let accountUID, UUID(uuidString: accountUID) != nil,
              SecureStore.accessToken != nil else {
            errorText = "Сеанс недоступен. Войдите снова."
            connection = "restricted"
            return
        }
        self.accountUID = accountUID
        if !isRunning {
            isRunning = true
            generation += 1
            connectionTask = Task { await connectionLoop(epoch: generation) }
        }
        await refreshDialogs()
    }

    func stop() {
        isRunning = false
        generation += 1
        connectionTask?.cancel()
        connectionTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        selectedDialog = nil
        messages = []
        encryption = nil
        pendingFrontID = nil
        pendingText = nil
        pendingPeerUID = nil
        sending = false
        draft = ""
        connection = "idle"
        accountUID = nil
    }

    func refreshDialogs() async {
        guard !loadingDialogs, let token = SecureStore.accessToken else { return }
        loadingDialogs = true
        errorText = nil
        defer { loadingDialogs = false }
        do {
            dialogs = try await api.messengerDialogs(accessToken: token)
        } catch {
            errorText = error.localizedDescription
            // Keep previously loaded items; never claim an empty inbox on a failed load.
        }
    }

    func open(_ dialog: MessengerDialog) async {
        guard UUID(uuidString: dialog.partnerID) != nil,
              let token = SecureStore.accessToken else { return }
        selectedDialog = dialog
        messages = []
        encryption = nil  // Fail closed until the server confirms conversation mode.
        loadingConversation = true
        errorText = nil
        do {
            let policy = try await api.messengerEncryption(peerUID: dialog.partnerID, accessToken: token)
            guard selectedDialog?.id == dialog.id else { return }
            encryption = policy
        } catch {
            guard selectedDialog?.id == dialog.id else { return }
            errorText = "Не удалось проверить настройки шифрования. Отправка недоступна. \(error.localizedDescription)"
        }
        if connection == "connected" {
            do { try await requestConversation(dialog.partnerID) }
            catch { errorText = error.localizedDescription }
        }
    }

    func closeConversation() async {
        selectedDialog = nil
        messages = []
        encryption = nil
        loadingConversation = false
        if connection == "connected" {
            try? await sendFrame(["action": "clear_active_dialog"])
        }
    }

    func sendText() async {
        guard canSend, let peerUID = selectedDialog?.partnerID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 1000 else {
            errorText = "Сообщение не должно превышать 1000 символов."
            return
        }
        if let pendingText, let pendingPeerUID,
           (pendingText != text || pendingPeerUID != peerUID) {
            errorText = "Есть неподтверждённая отправка. Повторите тот же текст в том же диалоге."
            return
        }
        let frontID = pendingFrontID ?? UUID().uuidString.lowercased()
        pendingFrontID = frontID
        pendingText = text
        pendingPeerUID = peerUID
        sending = true
        errorText = nil
        // The optimistic row must have the same stable identity when the
        // backend echoes its persisted canonical UID after a reconnect.
        if let accountUID, !messages.contains(where: { $0.frontId == frontID }) {
            messages.append(MessengerMessage(
                uid: "local:\(frontID)", frontId: frontID, content: text, contentType: "text",
                senderUID: accountUID, receiverUID: peerUID, isRead: false,
                createdAt: ISO8601DateFormatter().string(from: Date())
            ))
        }
        do {
            try await sendFrame([
                "action": "send_message", "frontId": frontID,
                "receiver_uid": peerUID, "content": text,
                "content_type": "text", "media_metadata": [:]
            ])
            // A socket write is NOT an acknowledgement: do not clear the draft.
        } catch {
            sending = false
            errorText = "Нет подтверждения отправки. Повторите тот же текст с прежним ID после восстановления связи. \(error.localizedDescription)"
        }
    }

    private func failPending(_ message: String) {
        pendingFrontID = nil
        pendingText = nil
        pendingPeerUID = nil
        sending = false
        errorText = message
    }

    private func connectionLoop(epoch: Int) async {
        var failures = 0
        while isRunning && generation == epoch && !Task.isCancelled {
            var currentSocket: URLSessionWebSocketTask?
            do {
                guard let token = SecureStore.accessToken else {
                    connection = "restricted"
                    return
                }
                connection = failures == 0 ? "connecting" : "reconnecting"
                let ticket = try await api.messengerTicket(accessToken: token)
                guard isRunning, generation == epoch, !Task.isCancelled else { break }
                let url = try api.messengerSocketURL(for: ticket)
                let task = URLSession.shared.webSocketTask(with: url)
                socket = task
                currentSocket = task
                task.resume()
                try await task.send(.string(try jsonString([
                    "type": "auth", "ticket": ticket.ticket
                ])))
                while isRunning && generation == epoch && !Task.isCancelled {
                    let incoming = try await task.receive()
                    guard isRunning, generation == epoch else { break }
                    let text: String
                    switch incoming {
                    case .string(let value): text = value
                    case .data(let data): text = String(decoding: data, as: UTF8.self)
                    @unknown default: continue
                    }
                    guard let data = text.data(using: .utf8),
                          let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    await handle(frame, ticket: ticket, on: task, epoch: epoch)
                    if frame["type"] as? String == "realtime_ready" { failures = 0 }
                }
            } catch {
                guard isRunning, generation == epoch, !Task.isCancelled else { break }
                let code = currentSocket?.closeCode.rawValue
                if code == 4003 || code == 4401 || (error as? APIProblem)?.status == 401 ||
                    (error as? APIProblem)?.status == 403 {
                    connection = "restricted"
                    errorText = "Доступ к переписке ограничен. Проверьте состояние аккаунта."
                    break
                }
                errorText = "Соединение потеряно. Переподключаемся…"
            }
            heartbeatTask?.cancel()
            heartbeatTask = nil
            currentSocket?.cancel(with: .normalClosure, reason: nil)
            if socket === currentSocket { socket = nil }
            if pendingFrontID != nil {
                sending = false
                errorText = "Нет подтверждения отправки. История будет сверена после подключения; повтор сохраняет тот же ID."
            }
            guard isRunning, generation == epoch, !Task.isCancelled, connection != "restricted" else { break }
            failures += 1
            connection = "reconnecting"
            let delay = min(20, 1 << min(failures, 4))
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func handle(_ frame: [String: Any], ticket: MessengerTicket,
                        on task: URLSessionWebSocketTask, epoch: Int) async {
        guard generation == epoch else { return }
        switch frame["type"] as? String {
        case "realtime_ready":
            connection = "connected"
            errorText = nil
            let seconds = max(10, frame["heartbeat_seconds"] as? Int ?? ticket.heartbeatSeconds)
            heartbeatTask?.cancel()
            heartbeatTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                        try Task.checkCancellation()
                        try await task.send(.string(try jsonString([
                            "type": "heartbeat", "action": "heartbeat"
                        ])))
                    } catch { return }
                }
            }
            if let peerUID = selectedDialog?.partnerID {
                do { try await requestConversation(peerUID) }
                catch { errorText = error.localizedDescription }
            }
        case "ping":
            try? await task.send(.string(#"{"type":"pong"}"#))
        case "conversation":
            guard let peerUID = frame["other_user_uid"] as? String,
                  selectedDialog?.partnerID == peerUID,
                  let payload = frame["messages"] as? [[String: Any]] else { return }
            let decoded = payload.compactMap(Self.message)
            // Reconcile by canonical uid OR stable client frontId. Preserve
            // an unresolved optimistic row outside the limited history window.
            let pendingRows = messages.filter(\.isOptimistic)
            messages = decoded.sorted { $0.createdAt < $1.createdAt }
            for local in pendingRows where !messages.contains(where: {
                $0.uid == local.uid ||
                ($0.frontId != nil && $0.frontId == local.frontId && $0.senderUID == local.senderUID)
            }) {
                messages.append(local)
            }
            for message in decoded { confirmPendingIfSaved(message) }
            messages.sort { $0.createdAt < $1.createdAt }
            loadingConversation = false
        case "private_message":
            guard let message = Self.message(frame) else { return }
            if let accountUID, let peerUID = selectedDialog?.partnerID,
               (message.senderUID == accountUID && message.receiverUID == peerUID ||
                message.senderUID == peerUID && message.receiverUID == accountUID) {
                if let i = messages.firstIndex(where: { old in
                    old.uid == message.uid || (old.frontId != nil &&
                    old.frontId == message.frontId && old.senderUID == message.senderUID)
                }) {
                    messages[i] = message
                } else {
                    messages.append(message)
                }
                messages.sort { $0.createdAt < $1.createdAt }
                if message.senderUID != accountUID {
                    try? await sendFrame(["action": "mark_message_as_read", "message_uid": message.uid])
                }
            }
            confirmPendingIfSaved(message)
        case "duplicate_pending", "duplicate_ignored":
            // A Redis claim is not a durable ACK. Keep the same pending ID;
            // history reconciliation may still discover an already saved row.
            if (frame["frontId"] as? String) == pendingFrontID {
                sending = false
                errorText = "Результат отправки пока неизвестен. Сверьте историю и повторите тот же текст."
            }
        case "error", "rate_limited":
            let id = frame["frontId"] as? String
            let kind = frame["error_type"] as? String ?? "message_send_failed"
            let message: String
            switch kind {
            case "conversation_requires_e2ee": message = "Диалог требует E2EE. Откройте его в клиенте с поддержкой шифрования."
            case "dm_not_allowed": message = "Отправка этому собеседнику недоступна."
            case "rate_limited": message = "Слишком много сообщений. Попробуйте позже."
            default: message = "Сервер отклонил действие: \(kind)."
            }
            if id != nil && id == pendingFrontID {
                messages.removeAll { $0.frontId == id && $0.isOptimistic }
                failPending(message)
            }
            else { errorText = message; if kind == "conversation_failed" { loadingConversation = false } }
        default: break
        }
    }

    private func confirmPendingIfSaved(_ message: MessengerMessage) {
        guard !message.isOptimistic, message.senderUID == accountUID,
              message.frontId != nil, message.frontId == pendingFrontID,
              message.receiverUID == pendingPeerUID else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == pendingText { draft = "" }
        pendingFrontID = nil
        pendingText = nil
        pendingPeerUID = nil
        sending = false
        errorText = nil
        Task { await refreshDialogs() }
    }

    private func requestConversation(_ peerUID: String) async throws {
        try await sendFrame([
            "action": "get_conversation", "other_user_uid": peerUID,
            "request_id": UUID().uuidString.lowercased()
        ])
    }

    private func sendFrame(_ value: [String: Any]) async throws {
        guard connection == "connected", let socket else {
            throw APIProblem(status: -1, reason: "Нет соединения с Messenger.")
        }
        try await socket.send(.string(try jsonString(value)))
    }

    private func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func message(_ value: [String: Any]) -> MessengerMessage? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(MessengerMessage.self, from: data)
    }
}
