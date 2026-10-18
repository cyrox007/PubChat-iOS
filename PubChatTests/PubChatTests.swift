import XCTest
@testable import PubChat

final class PubChatTests: XCTestCase {
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

    func testServerAccessRestrictionDoesNotBecomeAFalseBadPasswordMessage() {
        let problem = APIProblem(status: 403, reason: "account_access_restricted")
        XCTAssertTrue((problem.errorDescription ?? "").contains("account_access_restricted"))
    }
}
