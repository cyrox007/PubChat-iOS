# PubChat iOS

Нативный клиент PubChat на **Swift + SwiftUI**. Основной сервер и Web/PWA:
[cyrox007/PubChat](https://github.com/cyrox007/PubChat);
Android-клиент: [cyrox007/PubChat-Android](https://github.com/cyrox007/PubChat-Android).

## Стадия

**Foundation / 0.1 (в разработке)**. Клиент пока не достиг функционального
паритета с Web и Android и не готов к публичному выпуску.

Реализованный начальный срез:
- SwiftUI приложение для iOS 17+ с нативными экранами входа и регистрации;
- Identity v2: login, register, session refresh, me, logout;
- Device UUID и CSRF cookie/header proof для HTTP API;
- Access/refresh session material хранится в iOS Keychain;
- просмотр основных сведений Persona, read-only каталоги Spaces и People;
- CI на GitHub-hosted `macos-26`: XcodeGen, simulator build, XCTest без подписи;
- базовые тесты контракта авторизации и парсинга refresh cookie.

**Пока отсутствуют:** полноценное участие в Spaces/realtime,
Messenger/E2EE, Activities/игры, Reputation/achievements, Safety,
настройки приватности, APNs, WebRTC calls, редактирование Persona,
монетизация и восстановление сессий при сетевых сбоях на уровне production.
Все эти пользовательские сценарии должны получить паритет перед 1.0.

## Разработка без Mac

Исходный код можно редактировать на Windows/Linux. Коммиты/PR автоматически
собираются на macOS раннере в GitHub Actions. Нативную установку на iPhone
позднее обеспечит TestFlight после подключения Apple Developer и CI-подписи.

См. [инструкцию без Mac](docs/NO_MAC_SETUP.md).
Для генерации Xcode-проекта на Mac при необходимости: `brew install xcodegen && xcodegen generate`.

## API

Backend: `https://pubchat.ru/api`. Не храните API credentials или signing
keys в репозитории. Приложение использует серверные контракты, не создаёт
собственные правила модерации, приватности и доверия.

[Матрица паритета](docs/PARITY_MATRIX.md) содержит список всех этапов
трёхклиентной разработки.
