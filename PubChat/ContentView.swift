import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView("Восстанавливаем сеанс…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                AuthenticationView()
            case .signedIn:
                MainTabsView()
            }
        }
        .tint(Color(red: 0.58, green: 0.30, blue: 0.75))
    }
}

private struct AuthenticationView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var registering = false
    @State private var identifier = ""
    @State private var handle = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var intent = "open"

    private let intents = [
        ("open", "Открыт к общению"),
        ("meet", "Знакомства"),
        ("friends", "Друзья"),
        ("games", "Игры"),
        ("quiet", "Спокойное общение")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("PubChat", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.largeTitle.bold())
                        Text("Общение начинается с твоей Persona.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Picker("Действие", selection: $registering) {
                        Text("Вход").tag(false)
                        Text("Регистрация").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section(registering ? "Создать Persona" : "Войти в PubChat") {
                    if registering {
                        TextField("Handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Отображаемое имя", text: $displayName)
                        TextField("Email (необязательно)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Picker("Цель общения", selection: $intent) {
                            ForEach(intents.indices, id: \.self) { index in
                                Text(intents[index].1).tag(intents[index].0)
                            }
                        }
                    } else {
                        TextField("Handle или email", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField("Пароль", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                }

                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task {
                            if registering {
                                await session.signUp(
                                    handle: handle,
                                    displayName: displayName.isEmpty ? handle : displayName,
                                    email: email,
                                    password: password,
                                    intent: intent
                                )
                            } else {
                                await session.signIn(identifier: identifier, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text(registering ? "Создать аккаунт" : "Войти").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        session.isBusy ||
                        password.isEmpty ||
                        (registering ? handle.trimmingCharacters(in: .whitespaces).count < 3 : identifier.isEmpty)
                    )
                }
            }
            .navigationTitle("Добро пожаловать")
        }
    }
}

private struct MainTabsView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        TabView {
            NavigationStack {
                List(session.spaces) { space in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(space.name).font(.headline)
                        if let description = space.description, !description.isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .overlay {
                    if session.spaces.isEmpty && !session.isLoadingDirectory {
                        ContentUnavailableView("Пока нет пространств", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .refreshable { await session.reloadDirectory() }
                .navigationTitle("Пространства")
            }
            .tabItem { Label("Spaces", systemImage: "square.grid.2x2.fill") }

            NavigationStack {
                SocialDiscoveryView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                FriendshipHubView()
                            } label: {
                                Label("Друзья и заявки", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
            }
            .tabItem { Label("Люди", systemImage: "person.2.fill") }

            NavigationStack {
                NotificationCenterView()
            }
            .tabItem { Label("Уведомления", systemImage: "bell.fill") }

            NavigationStack {
                Form {
                    if let persona = session.identity?.persona {
                        Section("Моя Persona") {
                            LabeledContent("Имя", value: persona.displayName)
                            LabeledContent("Handle", value: "@\(persona.handle)")
                            if let bio = persona.bio, !bio.isEmpty {
                                Text(bio)
                            }
                        }
                    }
                    Section {
                        Text("Это базовый iOS-клиент. Переписки, игры, управление Spaces и настройки приватности будут добавляться по общей матрице Web / Android / iOS.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Persona") {
                        NavigationLink("Мои образы") { PersonaManagerView() }
                    }
                    Section {
                        Button("Выйти из аккаунта", role: .destructive) {
                            Task { await session.signOut() }
                        }
                        .disabled(session.isBusy)
                    }
                }
                .navigationTitle("Профиль")
            }
            .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
        }
        .task { await session.reloadDirectory() }
        .overlay(alignment: .top) {
            if session.isLoadingDirectory {
                ProgressView().padding(8)
            }
        }
    }
}
