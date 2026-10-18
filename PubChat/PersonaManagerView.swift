import SwiftUI

/// A Persona changes the public-facing self projection of one session.
/// Account credentials, trust, roles, bans, contacts and messages stay shared.
struct PersonaManagerView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var personas: [IdentityEnvelope.Persona] = []
    @State private var activeUID: String?
    @State private var handle = ""
    @State private var displayName = ""
    @State private var loading = true
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                Text("Один Account — несколько образов. Выбор действует только на этом устройстве и в текущем сеансе.")
                    .foregroundStyle(.secondary)
            }

            Section("Мои Persona") {
                if loading {
                    ProgressView("Загружаем образы…")
                }
                ForEach(personas, id: \.uid) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).font(.headline)
                            Text("@\(item.handle)").foregroundStyle(.secondary)
                            Text(item.isPrimary == true ? "Основной" : "Дополнительный — приватный")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.uid == activeUID {
                            Label("Выбран", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                        } else {
                            Button("Выбрать") {
                                Task { await activate(item.uid) }
                            }
                            .disabled(busy)
                        }
                    }
                    .padding(.vertical, 5)
                }
                if personas.isEmpty && !loading {
                    Button("Повторить загрузку") { Task { await reload() } }
                }
            }

            if !loading && personas.count < 3 {
                Section("Создать Persona") {
                    Text("Дополнительный образ скрыт от публичного поиска. Его использование не обходит блокировки и ограничения Account.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Отображаемое имя", text: $displayName)
                    Button("Создать образ") {
                        Task { await create() }
                    }
                    .disabled(busy || handle.trimmingCharacters(in: .whitespaces).count < 3 ||
                        displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Мои образы")
        .task { await reload() }
        .overlay {
            if busy {
                ProgressView("Обновляем…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func reload() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let result = try await session.listPersonas()
            personas = result.personas
            activeUID = result.activePersonaUid
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func create() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await session.createPersona(
                handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            handle = ""
            displayName = ""
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func activate(_ uid: String) async {
        guard !busy else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await session.activatePersona(uid: uid)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
