import Foundation
import XCTest

@testable import ApproovNSURLSession

final class ApproovDefaultMessageSigningTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(nil)
        ApproovDefaultMessageSigning.setAccountMessageSignatureOverrideForTesting(nil)
    }

    override func tearDown() {
        ApproovDefaultMessageSigning.clearMessageSignatureOverridesForTesting()
        super.tearDown()
    }

    func testInstallSignatureRetrievalFailureFailsOpenUnsigned() throws {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testAccountSignatureRetrievalFailureFailsOpenUnsigned() throws {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseAccountMessageSigning()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testSignatureBaseBuildFailureFailsOpenUnsigned() throws {
        let baseParameters = SignatureParameters()
            .addComponentIdentifier(ApproovURLSessionComponentProvider.DC_METHOD)
            .addComponentIdentifier("X-Required-Missing")
        let factory = SignatureParametersFactory()
            .setBaseParameters(baseParameters)
            .setUseInstallMessageSigning()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testUnsupportedSigningAlgorithmFailsClosed() {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setAlgOverrideForTesting("unsupported-alg")
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)

        XCTAssertThrowsError(try signer.processedRequest(staleSignedRequest(), changes: tokenChanges())) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsupported algorithm identifier"))
        }
    }

    private func assertMessageSigningFailsOpenUnsigned(factory: SignatureParametersFactory,
                                                       file: StaticString = #filePath,
                                                       line: UInt = #line) throws {
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        let updatedRequest = try signer.processedRequest(staleSignedRequest(), changes: tokenChanges())

        XCTAssertEqual(updatedRequest.value(forHTTPHeaderField: "Approov-Token"), "test-token", file: file, line: line)
        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Signature"), file: file, line: line)
        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Signature-Input"), file: file, line: line)
        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Signature-Base-Digest"), file: file, line: line)
    }

    private func tokenChanges() -> ApproovRequestMutations {
        let changes = ApproovRequestMutations()
        changes.setTokenHeaderKey("Approov-Token")
        return changes
    }

    private func staleSignedRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://example.com/protected?query=value")!)
        request.httpMethod = "POST"
        request.setValue("test-token", forHTTPHeaderField: "Approov-Token")
        request.setValue("stale-signature", forHTTPHeaderField: "Signature")
        request.setValue("stale-input", forHTTPHeaderField: "Signature-Input")
        request.setValue("stale-digest", forHTTPHeaderField: "Signature-Base-Digest")
        return request
    }
}
