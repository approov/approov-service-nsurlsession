import XCTest
import Foundation
@testable import ApproovNSURLSession
import ApproovNSURLSessionObjC
import Approov
import MiniSDKTestSupport

/// Integration tests for the ApproovService NSURLSession service layer.
///
/// Tests are organized to match the sections defined in TESTING_REQUIREMENTS.md
/// from the core-service-layers-testing repository. Each test includes a comment
/// referencing the requirement(s) it covers.
///
/// - SeeAlso: `TESTING_REQUIREMENTS.md` in core-service-layers-testing
final class ApproovServiceMiniSDKTests: XCTestCase {
    private let validInitialConfig = "#cb-ivol#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo="

    override func setUpWithError() throws {
        try super.setUpWithError()
        MiniSDKAttesterProxyController.reset()
        ApproovService.setLoggingLevel(.off)
        try objcInitializeService(comment: "reinit-nsurlsession-tests")
    }

    override func tearDown() {
        MiniSDKAttesterProxyController.reset()
        super.tearDown()
    }

    // MARK: - §1 Initialization
    // TESTING_REQUIREMENTS.md §1

    /// §1 Same Config Re-initialization
    ///
    /// Re-initializing with the same config string should succeed silently.
    func testInitializeIgnoresSameConfig() throws {
        var error: NSError?
        ApproovService.initialize(validInitialConfig, comment: nil, error: &error)
        XCTAssertNil(error)
        XCTAssertTrue(ApproovService.isInitialized())
        XCTAssertTrue(ApproovService.isApproovEnabled())
    }

    // Note: testInitializeWithEmptyConfigForwardsPlainRequests is not applicable here.
    // The NSURLSession service layer has no resetForTesting() method, so the SDK state
    // cannot be reset between tests. Empty-config re-initialization after a valid
    // config is already initialized has no effect.

    // MARK: - §2 Request Processing & Token Behaviors
    // TESTING_REQUIREMENTS.md §2

    /// §2 Precheck Evaluation
    ///
    /// A call to precheck() should succeed (UNKNOWN_KEY is treated as success).
    func testPrecheckTreatsUnknownKeyAsSuccess() {
        var error: NSError?
        ApproovService.precheck(&error)
        XCTAssertNil(error)
    }

    /// §2 Device ID
    ///
    /// The mini-SDK returns a stable device ID in the test environment.
    func testGetDeviceIDReturnsMiniSDKDeviceID() {
        XCTAssertEqual(ApproovService.getDeviceID(), "daIvmEWBA2gvZny7a/RC/w==")
    }

    /// §2 Protected Request Processing
    ///
    /// A request to a protected domain receives an Approov token and trace ID.
    func testUpdateRequestAddsTokenAndTraceIDToProtectedRequest() throws {
        try reinitializeServiceWithTargetHost()

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply)
        XCTAssertNotNil(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertNotNil(getHeader(from: reply, key: "Approov-TraceID"))
    }

    /// §2 Unprotected Request Processing
    ///
    /// A request to a non-protected domain does not receive an Approov token.
    func testUpdateRequestSkipsUnprotectedDomain() throws {
        try reinitializeServiceWithTargetHost()

        let request = URLRequest(url: try XCTUnwrap(URL(string: unprotectedURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply)
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
        XCTAssertNil(getHeader(from: reply, key: "Approov-TraceID"))
    }

    /// §2 Exclusion URL Matching
    ///
    /// An excluded URL regex should cause the request to be skipped.
    func testUpdateRequestSkipsExcludedURL() throws {
        ApproovService.addExclusionURLRegex("^.*excluded.*$")

        let request = URLRequest(url: try XCTUnwrap(URL(string: "\(targetURLString)/excluded")))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply)
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
    }

    /// §2 NO_APPROOV_SERVICE fallback
    ///
    /// When Approov service is unavailable, the request proceeds without a token.
    func testUpdateRequestProceedsWithoutTokenOnNoApproovService() throws {
        try reinitializeServiceWithTargetHost()
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            """
            {
              "operation": "fetchApproovToken",
              "response": {
                "status": "NO_APPROOV_SERVICE"
              }
            }
            """
        )

        let request = URLRequest(url: try XCTUnwrap(URL(string: targetURLString)))
        let reply = fetchNetworkReply(for: request)

        XCTAssertNotNil(reply)
        XCTAssertNil(getHeader(from: reply, key: "Approov-Token"))
        // Note: Approov-TraceID is still present for protected domains even when NO_APPROOV_SERVICE.
    }

    // MARK: - §6 Secure Strings & Custom JWT
    // TESTING_REQUIREMENTS.md §6

    /// §6 Valid Secure String Key
    func testFetchSecureStringReturnsConfiguredValue() throws {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            """
            {
              "operation": "fetchSecureString",
              "response": {
                "status": "SUCCESS",
                "secureString": "mini-secret"
              }
            }
            """
        )

        let secureString = try ApproovService.fetchSecureString("api-key", newDef: nil)
        XCTAssertEqual(secureString, "mini-secret")
    }

    /// §6 Non-existent Secure String Key
    ///
    /// UNKNOWN_KEY returns nil secureString with no Approov error.
    /// NOTE: Swift's ObjC error bridging throws a nilError when an ObjC method returns nil
    /// with no NSError set. This is a bridging artefact, not an Approov error.
    func testFetchSecureStringReturnsNilForUnknownKey() {
        MiniSDKAttesterProxyController.setNextAttestationDirectiveJSON(
            """
            {
              "operation": "fetchSecureString",
              "response": {
                "status": "UNKNOWN_KEY"
              }
            }
            """
        )

        do {
            let value = try ApproovService.fetchSecureString("missing-key", newDef: nil)
            // If we get here with a value, that is unexpected
            XCTAssertNil(value, "Expected nil secureString for UNKNOWN_KEY")
        } catch let error as NSError {
            // Swift ObjC bridge throws a _GenericObjCError (error 0) when the method returns nil
            // with no NSError set. This is a Swift bridging artefact for UNKNOWN_KEY, not an
            // Approov error. Any other domain indicates a real failure.
            let isNilBridgingError = error.domain.contains("GenericObjCError")
                || error.domain.contains("NilError")
                || (error.domain == "NSCocoaErrorDomain" && error.code == 4865)
            XCTAssertTrue(isNilBridgingError,
                "Unexpected Approov error for UNKNOWN_KEY: [\(error.domain)] \(error.localizedDescription)")
        }
    }

    /// §6 Custom JWT Fetch
    func testFetchCustomJWTReturnsSignedJWT() throws {
        let jwtStr = try XCTUnwrap(try ApproovService.fetchCustomJWT("{\"role\":\"tester\"}"))
        let payload = try XCTUnwrap(decodeJWTBody(jwtStr))
        XCTAssertEqual(payload["role"] as? String, "tester")
    }

    // MARK: - Helpers

    private var targetURLString: String {
        guard let url = ProcessInfo.processInfo.environment["TESTING_REPLY_URL"] else {
            fatalError("TESTING_REPLY_URL environment variable is not set")
        }
        return url
    }

    private var unprotectedURLString: String {
        guard let url = ProcessInfo.processInfo.environment["TESTING_REPLY_URL_UNPROTECTED"] else {
            fatalError("TESTING_REPLY_URL_UNPROTECTED environment variable is not set")
        }
        return url
    }

    private func fetchNetworkReply(for request: URLRequest) -> [String: Any]? {
        let expectation = self.expectation(description: "network request")
        var receivedData: Data?

        let configuration = URLSessionConfiguration.ephemeral
        guard let session = ApproovNSURLSession(configuration: configuration) else {
            XCTFail("Failed to create ApproovNSURLSession")
            return nil
        }
        let task = session.dataTask(with: request) { data, _, _ in
            receivedData = data
            expectation.fulfill()
        }
        task?.resume()

        waitForExpectations(timeout: 5.0)

        guard let data = receivedData,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func getHeader(from reply: [String: Any]?, key: String) -> String? {
        guard let headers = reply?["headers"] as? [String: Any] else { return nil }
        let lowerKey = key.lowercased()
        let val = headers[lowerKey] ?? headers[key]
        if let str = val as? String { return str }
        if let arr = val as? [String], let first = arr.first { return first }
        return nil
    }

    private func reinitializeServiceWithTargetHost(scenarioBody: String = "") throws {
        let targetHost = try XCTUnwrap(URL(string: targetURLString)?.host)
        let domainsJSON = "\"protectedDomains\": [\"\(targetHost)\"]"
        let fullBody = scenarioBody.isEmpty ? domainsJSON : "\(domainsJSON), \(scenarioBody)"
        try reinitializeService(
            scenarioJSON: scenarioJSON(caseName: uniqueCaseName(prefix: "target-host"), body: fullBody),
            comment: "reinit-target-host"
        )
    }

    private func objcInitializeService(comment: String?) throws {
        var error: NSError?
        ApproovService.initialize(validInitialConfig, comment: comment, error: &error)
        if let error { throw error }
    }

    private func reinitializeService(scenarioJSON: String? = nil, comment: String) throws {
        MiniSDKAttesterProxyController.reset()
        if let scenarioJSON {
            MiniSDKAttesterProxyController.loadScenarioJSON(scenarioJSON)
        }
        ApproovService.setLoggingLevel(.off)
        try objcInitializeService(comment: comment)
    }

    private func uniqueCaseName(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private func scenarioJSON(caseName: String, body: String) -> String {
        """
        {
          "activeCase": "\(caseName)",
          "cases": {
            "\(caseName)": {
              \(body)
            }
          }
        }
        """
    }

    private func decodeJWTBody(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded.append(String(repeating: "=", count: (4 - padded.count % 4) % 4))
        return Data(base64Encoded: padded)
    }
}
