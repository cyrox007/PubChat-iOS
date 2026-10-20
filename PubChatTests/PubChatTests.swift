import XCTest
@testable import PubChat

final class PubChatTests: XCTestCase {
    func testAPNsConfigurationAndPreferenceResponseDecodeExactServerContract() throws {
        let config = try JSONDecoder().decode(APNsConfigurationEnvelope.self, from: Data(
            #"{"status":"ok","android":{"provider":"fcm","enabled":true},"ios":{"provider":"apns","enabled":true},"privacy":{"message_content_in_push":false}}"#.utf8
        ))
        XCTAssertEqual(config.ios.provider, "apns")
        XCTAssertTrue(config.ios.enabled)
        let projection = try JSONDecoder().decode(NativePushRegistrationEnvelope.self, from: Data(
            #"{"status":"ok","device":{"installation_uid":"11111111-1111-4111-8111-111111111111","provider":"apns","platform":"ios"}}"#.utf8
        ))
        XCTAssertEqual(projection.device.installationUID, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(projection.device.provider, "apns")
        let preferences = try JSONDecoder().decode(MessagePushPreferencesEnvelope.self, from: Data(
            #"{"status":"ok","preferences":{"native_push_messenger":true,"native_push_space":true}}"#.utf8
        ))
        XCTAssertTrue(preferences.preferences.nativePushMessenger)
        XCTAssertTrue(preferences.preferences.nativePushSpace)
    }

    func testNativePushOptInNeverLeaksBetweenAccounts() throws {
        let a = "11111111-1111-4111-8111-111111111111"
        let b = "22222222-2222-4222-8222-222222222222"
        XCTAssertNotEqual(NativePushPreferences.key(for: a), NativePushPreferences.key(for: b))
        NativePushPreferences.remember(true, accountUID: a)
        NativePushPreferences.remember(false, accountUID: b)
        XCTAssertTrue(NativePushPreferences.optedIn(accountUID: a))
        XCTAssertFalse(NativePushPreferences.optedIn(accountUID: b))
        NativePushPreferences.remember(false, accountUID: a)
    }

    func testSpaceOwnerDetectionUsesAuthenticatedAccountOrOwnerMembership() throws {
        let json = """
        {"uid":"00000000-0000-4000-8000-000000000001","name":"Дизайн",
         "description":null,"category_slugs":["design"],
         "owner_uid":"00000000-0000-4000-8000-000000000099",
         "viewer_membership":{"role":"owner","status":"active"}}
        """
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        XCTAssertTrue(space.owned(by: "00000000-0000-4000-8000-000000000099"))
        XCTAssertTrue(space.owned(by: "different-current-account"))
        XCTAssertFalse(space.owned(by: nil))
    }

    func testSpaceCategoryEditorNeverSendsInvalidSelections() throws {
        XCTAssertTrue(SpaceCategoryValidation.valid([]))
        XCTAssertTrue(SpaceCategoryValidation.valid(["design", "technology", "games"]))
        XCTAssertFalse(SpaceCategoryValidation.valid(["design", "design"]))
        XCTAssertFalse(SpaceCategoryValidation.valid(["design", "technology", "games", "art"]))
        XCTAssertFalse(SpaceCategoryValidation.valid(["../other"]))
        XCTAssertFalse(SpaceCategoryValidation.valid(["bad slug"]))
    }

    func testSpaceCreationAndOwnerPatchPayloadsUseCategorySlugContract() throws {
        let create = try JSONEncoder().encode(
            SpaceCreatePayload(name: "Новый клуб", description: "Описание", categorySlugs: ["design"])
        )
        let createdObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: create) as? [String: Any]
        )
        XCTAssertEqual(createdObject["category_slugs"] as? [String], ["design"])
        XCTAssertNil(createdObject["categorySlugs"])

        let patch = try JSONEncoder().encode(
            SpaceCategoryUpdatePayload(categorySlugs: [])
        )
        let patchObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: patch) as? [String: Any]
        )
        XCTAssertEqual(patchObject["category_slugs"] as? [String], [])
    }

    func testNativeSpacesDecodeServerManagedCategoriesWithoutRequiringOldDataMigration() throws {
        let json = """
        {"spaces":[
          {"uid":"one","name":"Дизайн","description":"UX","category_slugs":["design","technology"]},
          {"uid":"two","name":"Без категории","description":null}
        ]}
        """
        let envelope = try JSONDecoder().decode(SpaceListEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.spaces[0].categorySlugs, ["design", "technology"])
        XCTAssertNil(envelope.spaces[1].categorySlugs)
    }

    func testSpaceCategoriesAreServerOwnedAndDecodedBySlug() throws {
        let json = """
        {"categories":[{"slug":"design","name":"Дизайн","icon":"palette",
          "description":null,"locale":"ru","position":10,"is_active":true}]}
        """
        let catalog = try JSONDecoder().decode(SpaceCategoryEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.categories.first?.slug, "design")
        XCTAssertEqual(catalog.categories.first?.name, "Дизайн")
    }

    func testMessengerDialogIsAccountScopedAndDoesNotInterpretCiphertextPreview() throws {
        let json = """
        {"status":"ok","dialogs":[{"partner_id":"8d56084c-5cb8-4756-861a-3254873e0e07",
          "last_message":"encrypted-opaque-string","last_message_time":"2026-10-19T07:00:00",
          "unread_count":2,"partner":{"username":"friend","avatar":null}}]}
        """
        let result = try JSONDecoder().decode(MessengerDialogsEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(result.dialogs.first?.partnerID, "8d56084c-5cb8-4756-861a-3254873e0e07")
        XCTAssertEqual(result.dialogs.first?.title, "friend")
        XCTAssertEqual(result.dialogs.first?.unreadCount, 2)
    }

    func testMessengerEncryptionPolicyFailsClosedForE2EE() throws {
        let json = """
        {"status":"ok","encryption":{"effective_mode":"e2ee","system_policy":"required"}}
        """
        let policy = try JSONDecoder().decode(MessengerEncryptionEnvelope.self, from: Data(json.utf8))
        XCTAssertFalse(policy.encryption.allowsPlaintext)
        XCTAssertEqual(policy.encryption.systemPolicy, "required")
    }

    func testMessengerServerConfirmedMessagesHaveSafeTypeProjection() throws {
        let encrypted = """
        {"uid":"m1","content":"ciphertext-not-to-be-shown","content_type":"e2ee",
        "sender_uid":"account-a","receiver_uid":"account-b","is_read":false,
        "created_at":"2026-10-19T07:00:00"}
        """
        let message = try JSONDecoder().decode(MessengerMessage.self, from: Data(encrypted.utf8))
        XCTAssertFalse(message.supportsText)
        XCTAssertFalse(message.visibleText.contains("ciphertext-not-to-be-shown"))

        let plain = """
        {"uid":"m2","content":"Привет!","content_type":"text",
        "sender_uid":"account-b","receiver_uid":"account-a","is_read":true,
        "created_at":"2026-10-19T07:01:00"}
        """
        let decoded = try JSONDecoder().decode(MessengerMessage.self, from: Data(plain.utf8))
        XCTAssertTrue(decoded.supportsText)
        XCTAssertEqual(decoded.visibleText, "Привет!")
        XCTAssertTrue(decoded.isRead)
    }

    func testPrivacyMinimalBirthdayInboxDecodesNativeClient() throws {
        let json = """
        {"status":"ok","notifications":[{"uid":"abbbaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "kind":"friend_birthday","title":"Сегодня день рождения у друга",
          "body":"Можете поздравить друга в PubChat.","is_read":false,
          "created_at":"2026-10-18T09:00:00"}],"pagination":{"total":1},"unread":1}
        """
        let inbox = try JSONDecoder().decode(NotificationInboxEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(inbox.notifications.count, 1)
        XCTAssertEqual(inbox.unread, 1)
        XCTAssertEqual(inbox.notifications[0].kind, "friend_birthday")
        XCTAssertFalse(inbox.notifications[0].isRead)
    }

    func testBirthdayConsentPayloadIsExplicitBoolean() throws {
        let data = try JSONEncoder().encode(BirthdayNotificationPreferencePayload(friendBirthdayReminders: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["friend_birthday_reminders"] as? Bool, true)
    }

    func testLiveAvailabilityAndDiscoveryPrivacyProjection() throws {
        let json = """
        {"people":[{"account_uid":"visible-a","display_name":"Знакомый",
        "handle":"friend","bio":null,"social_intent":"meet",
        "availability":{"intent":"meet","note":"Ищу компанию","expires_at":"2026-10-18T20:00:00"}}],
        "pagination":{"limit":30,"offset":0,"count":1,"total":1}}
        """
        let result = try JSONDecoder().decode(DiscoveryPage.self, from: Data(json.utf8))
        XCTAssertEqual(result.people.count, 1)
        XCTAssertEqual(result.people[0].availability?.intent, "meet")
        XCTAssertEqual(result.people[0].availability?.note, "Ищу компанию")
    }

    func testExpiredAvailabilityCanBeAbsentWithoutBreakingPerson() throws {
        let json = """
        {"account_uid":"visible-b","display_name":"Друг","handle":"fox",
        "social_intent":"friends","availability":null}
        """
        let person = try JSONDecoder().decode(Person.self, from: Data(json.utf8))
        XCTAssertNil(person.availability)
        XCTAssertEqual(person.socialIntent, "friends")
    }

    func testSocialAvailabilityUpdateContract() throws {
        let payload = SocialAvailabilityPayload(intent: "open", durationMinutes: 120, note: "Привет!")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["intent"] as? String, "open")
        XCTAssertEqual(object["duration_minutes"] as? Int, 120)
        XCTAssertEqual(object["note"] as? String, "Привет!")
    }

    func testIncomingFriendRequestsDecodeNestedPersonaAndMissingPersona() throws {
        let json = """
        {"status":"ok","direction":"incoming","requests":[
          {"account_uid":"account-a","persona":{"uid":"account-a","persona_uid":"persona-a","handle":"f1","display_name":"Друг","avatar":null}},
          {"account_uid":"account-b","persona":null}
        ],"pagination":{"limit":50,"offset":0,"count":2,"total":2}}
        """
        let result = try JSONDecoder().decode(FriendRequestsEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(result.direction, "incoming")
        XCTAssertEqual(result.requests.count, 2)
        XCTAssertEqual(result.requests[0].id, "account-a")
        XCTAssertEqual(result.requests[0].displayName, "Друг")
        XCTAssertEqual(result.requests[1].displayName, "Участник PubChat")
        XCTAssertEqual(result.pagination.total, 2)
    }

    func testFriendListDistinguishesAccountUidFromPersonaUid() throws {
        let json = """
        {"status":"ok","friends":[
          {"account_uid":"account-id","persona":{"uid":"account-id","persona_uid":"public-persona-id","handle":"friendly","display_name":"Друг"}}
        ],"pagination":{"limit":50,"offset":0,"count":1,"total":1}}
        """
        let result = try JSONDecoder().decode(FriendshipListEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(result.friends.first?.accountUid, "account-id")
        XCTAssertEqual(result.friends.first?.persona?.handle, "friendly")
        XCTAssertEqual(result.pagination.total, 1)
    }

    func testIdentityV2ProjectionDecodesWithoutLeakingHiddenAccountFields() throws {
        let json = """
        {
          "status":"ok",
          "access_token":"dummy-access",
          "account":{"uid":"account-id"},
          "persona":{"uid":"persona-id","handle":"space_fox","display_name":"Space Fox","social_intent":"friends"},
          "user":{"username":"space_fox"}
        }
        """
        let identity = try JSONDecoder().decode(IdentityEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(identity.account?.uid, "account-id")
        XCTAssertEqual(identity.persona?.handle, "space_fox")
        XCTAssertEqual(identity.persona?.displayName, "Space Fox")
        XCTAssertEqual(identity.persona?.socialIntent, "friends")
    }

    func testRefreshCookieIsExtractedWithoutAttributes() throws {
        let url = try XCTUnwrap(URL(string: "https://pubchat.ru/api/identity/v2/login"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "refresh_token=dummy.jwt.value; HttpOnly; Secure; Path=/; SameSite=Lax"]
        ))
        XCTAssertEqual(PubChatAPI.refreshCookie(from: response), "refresh_token=dummy.jwt.value")
    }

    func testRefreshCookieMustBePresent() throws {
        let url = try XCTUnwrap(URL(string: "https://pubchat.ru/api/identity/v2/login"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:]))
        XCTAssertNil(PubChatAPI.refreshCookie(from: response))
    }

    func testRegistrationPayloadUsesServerContract() throws {
        let payload = RegisterPayload(
            handle: "space_fox",
            displayName: "Space Fox",
            password: "safePassword2026",
            email: nil,
            socialIntent: "friends"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["handle"] as? String, "space_fox")
        XCTAssertEqual(object["display_name"] as? String, "Space Fox")
        XCTAssertEqual(object["social_intent"] as? String, "friends")
        XCTAssertNil(object["email"])
    }

    func testRelationshipProjectsAccountPrivacyAndFriendRequest() throws {
        let json = """
        {"status":"ok","relationship":{"account_uid":"f6aabbcf-18ab-48ce-aa10-e21745df04a1",
          "following":false,"followed_by":true,"friends":false,"friend_request":"incoming",
          "blocked_by_me":false,"blocked_me":false}}
        """
        let decoded = try JSONDecoder().decode(RelationshipEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.relationship.friendRequest, "incoming")
        XCTAssertEqual(decoded.relationship.friendAction, "accept")
        XCTAssertEqual(decoded.relationship.friendActionTitle, "Принять запрос")
        XCTAssertTrue(decoded.relationship.followedBy)
        XCTAssertTrue(decoded.relationship.canInteract)
    }

    func testPendingAndConfirmedFriendshipActions() throws {
        let source = """
        {"account_uid":"some-other-account","following":true,"followed_by":false,
         "friends":true,"friend_request":null,"blocked_by_me":false,"blocked_me":false}
        """
        let friends = try JSONDecoder().decode(Relationship.self, from: Data(source.utf8))
        XCTAssertEqual(friends.friendAction, "remove")
        let outgoing = try JSONDecoder().decode(
            Relationship.self,
            from: Data(source.replacingOccurrences(of: "\"friends\":true", with: "\"friends\":false")
                .replacingOccurrences(of: "\"friend_request\":null", with: "\"friend_request\":\"outgoing\"").utf8)
        )
        XCTAssertEqual(outgoing.friendAction, "remove")
        XCTAssertEqual(outgoing.friendActionTitle, "Отменить запрос")
    }

    func testBlockStateDoesNotOfferLocalPermission() throws {
        let source = """
        {"account_uid":"other","following":false,"followed_by":false,
         "friends":false,"friend_request":null,"blocked_by_me":false,"blocked_me":true}
        """
        let relation = try JSONDecoder().decode(Relationship.self, from: Data(source.utf8))
        XCTAssertFalse(relation.canInteract)
        XCTAssertEqual(relation.friendAction, "request")
        // UI must suppress actions when canInteract is false.
    }

    func testFriendPayloadUsesExistingBackendActionContract() throws {
        let encoded = try JSONEncoder().encode(FriendActionPayload(action: "accept"))
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
        XCTAssertEqual(dictionary, ["action": "accept"])
    }

    func testSessionScopedPersonaListDecodes() throws {
        let source = """
        {"status":"ok","active_persona_uid":"persona-b","personas":[
          {"uid":"persona-a","handle":"original","display_name":"Primary","is_primary":true},
          {"uid":"persona-b","handle":"alt","display_name":"Secondary","is_primary":false}]}
        """
        let parsed = try JSONDecoder().decode(PersonaListEnvelope.self, from: Data(source.utf8))
        XCTAssertEqual(parsed.personas.count, 2)
        XCTAssertEqual(parsed.activePersonaUid, "persona-b")
        XCTAssertEqual(parsed.personas[0].isPrimary, true)
        XCTAssertEqual(parsed.personas[1].isPrimary, false)
    }

    func testPersonaCreationDoesNotSupplyAccountPrivilegeFields() throws {
        let data = try JSONEncoder().encode(PersonaCreatePayload(
            handle: "alt", displayName: "Another"
        ))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["handle"], "alt")
        XCTAssertEqual(json["display_name"], "Another")
        XCTAssertNil(json["account_uid"])
        XCTAssertNil(json["is_primary"])
    }

    func testDMConsentProjectionUsesServerOwnedPrimaryPersonaPolicy() throws {
        let json = """
        {"status":"ok","account":{"uid":"account-a"},
         "persona":{"uid":"persona-a","handle":"main","display_name":"Main","is_primary":true},
         "privacy":{"profile_visibility":"public","dm_policy":"shared_spaces"}}
        """
        let decoded = try JSONDecoder().decode(IdentityEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.privacy?.dmPolicy, .sharedSpaces)
        XCTAssertEqual(decoded.persona?.isPrimary, true)
    }

    func testDMConsentPatchSendsOnlyRequestedField() throws {
        for policy in DMConsentPolicy.allCases {
            let encoded = try JSONEncoder().encode(DMPrivacyUpdatePayload(dmPolicy: policy))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            XCTAssertEqual(payload.count, 1)
            XCTAssertEqual(payload["dm_policy"] as? String, policy.rawValue)
            XCTAssertNil(payload["profile_visibility"])
            XCTAssertNil(payload["account_uid"])
            XCTAssertNil(payload["persona_uid"])
        }
    }

    func testUnrecognizedDMConsentNeverFallsBackToEveryone() throws {
        let json = """
        {"status":"ok","account":{"uid":"account-a"},
         "persona":{"uid":"persona-a","handle":"main","display_name":"Main","is_primary":true},
         "privacy":{"dm_policy":"unknown_or_broken"}}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(IdentityEnvelope.self, from: Data(json.utf8))
        )
    }

    func testSecondaryPersonaPolicyRemainsDistinctFromAccountPolicy() throws {
        let json = """
        {"status":"ok","account":{"uid":"account-a"},
         "persona":{"uid":"persona-b","handle":"secondary","display_name":"Secondary","is_primary":false},
         "privacy":{"dm_policy":"nobody"}}
        """
        let identity = try JSONDecoder().decode(IdentityEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(identity.persona?.isPrimary, false)
        XCTAssertEqual(identity.privacy?.dmPolicy, .nobody)
        let forbidden = APIProblem(status: 409, reason: "secondary_privacy_not_supported")
        XCTAssertTrue((forbidden.errorDescription ?? "").contains("secondary_privacy_not_supported"))
    }

    func testServerAccessRestrictionDoesNotBecomeAFalseBadPasswordMessage() {
        let problem = APIProblem(status: 403, reason: "account_access_restricted")
        XCTAssertTrue((problem.errorDescription ?? "").contains("account_access_restricted"))
    }
}
