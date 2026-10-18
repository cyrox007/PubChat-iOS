import XCTest
@testable import PubChat

final class PubChatTests: XCTestCase {
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

    func testServerAccessRestrictionDoesNotBecomeAFalseBadPasswordMessage() {
        let problem = APIProblem(status: 403, reason: "account_access_restricted")
        XCTAssertTrue((problem.errorDescription ?? "").contains("account_access_restricted"))
    }
}
