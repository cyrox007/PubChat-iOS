# Разработка PubChat-iOS без Mac

## Цель

Нативный **SwiftUI** клиент использует единые backend/API и business rules из
[PubChat](https://github.com/cyrox007/PubChat). Код редактируется на Windows или
Linux, а Xcode-проект генерируется и компилируется в GitHub Actions на `macos-26`.
Разработчику не требуется локальный Mac для CI-компиляции.

## Автоматическая сборка

1. Создайте ветку и pull request в `cyrox007/PubChat-iOS`.
2. Workflow `.github/workflows/ios-ci.yml` запускает XcodeGen, `xcodebuild build`
   и тесты на доступном iPhone Simulator.
3. `CODE_SIGNING_ALLOWED=NO` используется **только** в simulator CI и не создаёт
   подписанный `.ipa` для установки на физический iPhone.
4. После зелёного CI изменённый код можно объединить с `main`.

Для локальной сборки на Mac (необязательно):
```sh
brew install xcodegen
xcodegen generate
xcodebuild -project PubChat.xcodeproj -scheme PubChat \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Установка на iPhone и выпуск

Для TestFlight/App Store отдельно понадобятся участие в **Apple Developer Program**,
настроенные App Store Connect и Apple signing credentials. Секреты подписания
разрешается хранить только в GitHub Secrets/Environments, не в репозитории,
публичных CI-логах или документации.

TestFlight workflow **ещё не подключён**. Его добавляют после настройки
Apple Developer, подписания и App Store Connect API key. CI compile без подписи
не означает готовности к TestFlight и не заменяет тестирование на настоящем iPhone.

## Безопасность сеансов

- Base URL по умолчанию: `https://pubchat.ru/api`.
- `POST /identity/v2/login|register|refresh|logout`, `GET /identity/v2/me`.
- Нативный device UUID передаётся в `X-PubChat-Device-ID`.
- Сервер требует `X-CSRF-Token` и совпадающий `XSRF-TOKEN` cookie для изменяющих запросов.
- Access token и refresh cookie хранятся в iOS Keychain, а не в UserDefaults.
- Отозванная сессия должна завершиться на сервере; не обходите 401/403.
- Push через APNs и звонки, DM E2EE, настройки приватности и Web parity требуют
  отдельных реализации и испытаний.

## Паритет Web / Android / iOS

Признак завершённости функции: API contract + одинаковый пользовательский сценарий
на Web, Android и iOS + автоматические и реальные device tests, где применимо.
Текущий iOS bootstrap реализует регистрацию/вход, восстановление/выход, профиль
и базовый **read-only** каталог Spaces и People. В нём **нет** полноценных
чатов, звонков, APNs, E2EE, модерации и управления Spaces; их наличие в Web
не означает автоматического наличия на iOS.
