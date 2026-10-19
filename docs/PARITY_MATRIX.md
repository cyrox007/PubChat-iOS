# Паритет PubChat — Web / Android / iOS (сверка 19.10.2026)

**Условие 1.0 — одинаковые полезные пользовательские сценарии и правила отказа во всех трёх клиентах**, а не одинаковые макеты. Источник общей очереди и фактических PR: [живой реестр в PubChat](https://github.com/cyrox007/PubChat/blob/main/docs/cross-client-delivery-status.md).

**Важно:** «код» и «CI green» не равны физической проверке или production readiness. Приводим слитые срезы, не откатывая их в «нет».

| Сценарий | Web / Backend | Android | iOS | Что осталось |
| --- | --- | --- | --- | --- |
| Identity v2 / login/refresh/logout | Код | Код | Код | Реальные устройства, revoke и offline |
| **Private Multi-Persona: создать/выбрать** | [PubChat #108](https://github.com/cyrox007/PubChat/pull/108) | [Android #35](https://github.com/cyrox007/PubChat-Android/pull/35) | [iOS #3](https://github.com/cyrox007/PubChat-iOS/pull/3) слит | Публичный Persona UID/address, author attribution, cross-privacy |
| Friends / follows / blocks, friendship hub | Web [#109](https://github.com/cyrox007/PubChat/pull/109) | Android [#36](https://github.com/cyrox007/PubChat-Android/pull/36) | iOS [#4](https://github.com/cyrox007/PubChat-iOS/pull/4) | 401/403/409 + physical device QA |
| People discovery, intent и TTL availability | Код | Код | Код | Устойчивость search/pagination/network и device QA |
| **DM consent** `everyone/shared_spaces/mutual/nobody` | Identity v2 `/privacy` | Слито [#53](https://github.com/cyrox007/PubChat-Android/pull/53), `7160c5d` | Слито [#16](https://github.com/cyrox007/PubChat-iOS/pull/16), `23cce07`; simulator XCTest green | Device QA, блокировка/revocation/new conversation, не позволять обходить сервер |
| Spaces каталог | Код | Код | Код (каталог) | iOS membership и room |
| **Создать Space с параметрами** | `POST /spaces/v1` | Слито [#51](https://github.com/cyrox007/PubChat-Android/pull/51), `05653df` | **Нет native flow** | iOS реализация; Android physical QA |
| Space invitations: inbox, accept/reject/open | Web + API | **Слито [Android #56](https://github.com/cyrox007/PubChat-Android/pull/56), `07cae34`**, обе CI-конфигурации green | Нет native inbox/accept/decline | Android real-device и Web↔Android privacy/expired/revoked QA; iOS реализация |
| Spaces realtime/history/management | Код | Код (не полная Web parity) | **Нет** | iOS полноценное участие |
| Activities/игры/повторы | Код | Частично | Нет | Cross-client recurring/timezone |
| Messenger DM basics | Код | Код (частично) | Начальный Messenger, неполный parity | Медиаполитика, offline/reconnect, consent |
| **E2EE DM** | Web security policy | **Нет полноценного native E2EE** | **Нет** | P0: device crypto, no plaintext fallback, verification |
| Calls WebRTC | Код | Частично | Нет | Физический network/media QA |
| Notifications | Web Push/preferences | FCM foundation | Activity UI, APNs отсутствует | Provider и real-device delivery |
| **Safety Center/appeals** | Web + Trust & Safety | Нет полного flow | Нет полного flow | P0 user safety |
| Device/session management | Web | Нет полного editor | Нет device-revoke UI | Revocation/device tests |
| Real devices | Browser tests | Не подтверждена вся матрица | Simulator CI != физический iPhone | Общий 1.0 release gate |

## Уже выполнено — не начинать заново

Private Multi-Persona selection, friendship hub и TTL availability уже имеют нативные реализации. **Четыре DM consent policy уже доступны в коде обеих мобильных платформ**, однако это не доказывает, что revoke/blocks одинаково работают с реальным Messenger. **Создание Space реализовано в Android**, перенос нужен на iOS, а не повтор на Android.

## Очередь незавершённых сквозных сценариев

1. Android **Space invitation inbox → accept/decline → войти** уже реализован и слит ([#56](https://github.com/cyrox007/PubChat-Android/pull/56)); необходимы Android physical QA и Web↔Android cross-client denial/revocation. **Следующее недостающее приложение — iOS**, где нужно реализовать этот сценарий. Не переписывать Android inbox.
2. **E2EE Messenger** для нативных клиентов: при required E2EE отправка без device keys/verification должна fail-closed; запрещена тихая замена plaintext.
3. **Safety Center**: жалобы, история, ограничения и апелляции с server-only правами и privacy projection.
4. iOS **Spaces participation/realtime и create flow**, затем Activities/notifications/calls.
5. Social Core 0.7: публичные Multi-Persona identities, block/revoke tests и device-to-device parity.

## Как поддерживать правду в репозитории

Перед следующим PR проверить HEAD всех трёх репозиториев, связанные open/merged PR и [PubChat #107](https://github.com/cyrox007/PubChat/issues/107), [#110](https://github.com/cyrox007/PubChat/issues/110), [Android #52](https://github.com/cyrox007/PubChat-Android/issues/52). В PR обновлять **этот файл и центральный реестр**, ссылаться на merge SHA и отдельно фиксировать code/CI/device QA. Не закрывать эпик до прохождения одинаковых success, 401/403/409, блокировки и отзыва разрешения на Web, Android и iOS. Локальный UI не подменяет server permissions.

**Следующий этап не выбирается по старому чекбоксу или по количеству экранов.** Приоритет — законченный безопасный пользовательский сценарий.
