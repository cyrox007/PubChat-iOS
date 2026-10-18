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

    func testServerAccessRestrictionDoesNotBecomeAFalseBadPasswordMessage() {
        let problem = APIProblem(status: 403, reason: "account_access_restricted")
        XCTAssertTrue((problem.errorDescription ?? "").contains("account_access_restricted"))
    }
}
