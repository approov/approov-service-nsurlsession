// Copyright (c) 2026 Approov Ltd.
//
// Proves that secure-string substitution decisions reach the installed service mutator.
//
// Until this branch, handleInterceptorHeaderSubstitutionResult and
// handleInterceptorQueryParamSubstitutionResult were declared on ApproovServiceMutator with default
// implementations and had ZERO call sites: the Objective-C interceptor decided substitution with
// hardcoded status logic, so a customer mutator could not influence it. These tests drive the real
// entry point, updateRequestWithApproov, with a recording mutator installed, so they fail if the hooks
// are ever unwired again - which a test of the mutator in isolation could not detect.

import XCTest
import Approov
import MiniSDKTestSupport
@testable import ApproovNSURLSession
import ApproovNSURLSessionObjC

final class ApproovSubstitutionMutatorTests: XCTestCase {

    private struct RecordingMutator: ApproovServiceMutator {
        enum Behaviour { case substitute, skip, abort }
        let behaviour: Behaviour
        let record: (String) -> Void

        func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                      header: String) throws -> Bool {
            record("header:" + header + ":" + Approov.string(from: approovResults.status))
            return try decide(subject: header)
        }

        func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult,
                                                          queryKey: String) throws -> Bool {
            record("query:" + queryKey + ":" + Approov.string(from: approovResults.status))
            return try decide(subject: queryKey)
        }

        private func decide(subject: String) throws -> Bool {
            switch behaviour {
            case .substitute: return true
            case .skip: return false
            case .abort: throw ApproovServiceError.permanentError(message: "mutator refused " + subject)
            }
        }
    }

    // Must match the ObjC suite: the platform SDK refuses a second initialization with a different
    // configuration, so a private config here passes alone and fails in a full run.
    private let sharedTestConfig = "#cb-ivol#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo="
    private let placeholder = "test-secure-string-key"
    private var calls: [String] = []

    override func setUp() {
        super.setUp()
        calls = []
        // Mirrors reinitializeServiceWithTargetHostAndScenarioBody in the ObjC suite: the scenario has
        // to declare the target host as a protected domain, or the fetch returns UNPROTECTED_URL and no
        // substitution is attempted at all.
        MiniSDKAttesterProxyController.reset()
        let host = URL(string: targetURLString())?.host ?? ""
        XCTAssertFalse(host.isEmpty, "TESTING_REPLY_URL must carry a host")
        let caseName = "swift-mutator-" + UUID().uuidString.lowercased()
        let scenario = "{\"activeCase\":\"" + caseName + "\",\"cases\":{\"" + caseName
            + "\":{\"protectedDomains\":[\"" + host + "\"]}}}"
        MiniSDKAttesterProxyController.loadScenarioJSON(scenario)
        ApproovService.setLoggingLevel(.off)

        var initError: NSError?
        ApproovService.initialize(sharedTestConfig, comment: "reinit-swift-mutator", error: &initError)
        XCTAssertNil(initError, "unexpected initialization error")
        ApproovService.addSubstitutionHeader("Api-Key", requiredPrefix: "")
        ApproovService.addSubstitutionQueryParam("api-key")
    }

    override func tearDown() {
        ApproovServiceMutatorBridge.shared.resetServiceMutator()
        ApproovService.removeSubstitutionHeader("Api-Key")
        ApproovService.removeSubstitutionQueryParam("api-key")
        MiniSDKAttesterProxyController.reset()
        super.tearDown()
    }

    func testHeaderSubstitutionConsultsTheInstalledMutator() throws {
        install(.skip)
        let updated = try updateRequest(headerValue: placeholder)

        XCTAssertTrue(calls.contains { $0.hasPrefix("header:Api-Key:") },
                      "the interceptor must consult the mutator for header substitution; calls=\(calls)")
        XCTAssertEqual(updated?.value(forHTTPHeaderField: "Api-Key"), placeholder,
                       "a mutator returning false must leave the placeholder in place")
    }

    func testQueryParamSubstitutionConsultsTheInstalledMutator() throws {
        install(.skip)
        let updated = try updateRequest(query: "api-key=" + placeholder)

        XCTAssertTrue(calls.contains { $0.hasPrefix("query:api-key:") },
                      "the interceptor must consult the mutator for query substitution; calls=\(calls)")
        XCTAssertEqual(updated?.url?.query, "api-key=" + placeholder,
                       "a mutator returning false must leave the query placeholder in place")
    }

    func testAMutatorThatRefusesLeavesTheRequestUnprocessed() {
        install(.abort)
        var thrown: Error?
        var returned: URLRequest?
        do {
            returned = try ApproovService.updateRequest(withApproov: request(headerValue: placeholder),
                                                        sessionConfig: .ephemeral)
        } catch {
            thrown = error
        }

        XCTAssertTrue(calls.contains { $0.hasPrefix("header:Api-Key:") },
                      "the mutator must be consulted before it can refuse; calls=\(calls)")
        // Documents a bridging limitation rather than asserting what one might expect: Swift surfaces a
        // trailing NSError** as a throw ONLY when the method returns nil. This entry point returns the
        // caller's original request on failure while writing *error, so an ObjC caller sees the error
        // and a Swift caller sees neither a throw nor any other signal.
        XCTAssertNil(thrown, "no throw reaches Swift because a non-nil request is returned")
        XCTAssertEqual(returned?.value(forHTTPHeaderField: "Api-Key"), placeholder,
                       "the refused request must come back with its placeholder untouched")
    }

    private func install(_ behaviour: RecordingMutator.Behaviour) {
        ApproovServiceMutatorBridge.shared.serviceMutator =
            RecordingMutator(behaviour: behaviour) { [self] line in calls.append(line) }
    }

    private func updateRequest(headerValue: String? = nil, query: String? = nil) throws -> URLRequest? {
        return try ApproovService.updateRequest(withApproov: request(headerValue: headerValue, query: query),
                                                sessionConfig: .ephemeral)
    }

    private func request(headerValue: String? = nil, query: String? = nil) -> URLRequest {
        var components = URLComponents(string: targetURLString())!
        if let query { components.query = query }
        var request = URLRequest(url: components.url!)
        if let headerValue { request.setValue(headerValue, forHTTPHeaderField: "Api-Key") }
        return request
    }

    private func targetURLString() -> String {
        let value = ProcessInfo.processInfo.environment["TESTING_REPLY_URL"]
        XCTAssertNotNil(value, "TESTING_REPLY_URL must be set, as CI sets it")
        return value ?? ""
    }
}
