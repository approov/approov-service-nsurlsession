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

    // MARK: - Minimum regression matrix (§5.12)

    func testInstallSigningSucceedsWithValidDERSignature() throws {
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(validInstallDERBase64())
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)

        let updatedRequest = try signer.processedRequest(staleSignedRequest(), changes: tokenChanges())

        XCTAssertNotNil(updatedRequest.value(forHTTPHeaderField: "Signature"))
        XCTAssertNotNil(updatedRequest.value(forHTTPHeaderField: "Signature-Input"))
        XCTAssertEqual(updatedRequest.value(forHTTPHeaderField: "Approov-Token"), "test-token")
    }

    func testAccountSigningSucceedsWithValidBase64Signature() throws {
        ApproovDefaultMessageSigning.setAccountMessageSignatureOverrideForTesting(
            Data(repeating: 0x42, count: 32).base64EncodedString()
        )
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
            .setUseAccountMessageSigning()
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)

        let updatedRequest = try signer.processedRequest(staleSignedRequest(), changes: tokenChanges())

        XCTAssertNotNil(updatedRequest.value(forHTTPHeaderField: "Signature"))
        XCTAssertNotNil(updatedRequest.value(forHTTPHeaderField: "Signature-Input"))
        XCTAssertEqual(updatedRequest.value(forHTTPHeaderField: "Approov-Token"), "test-token")
    }

    func testInvalidBase64SigningResultFailsOpenUnsigned() throws {
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting("!!!not-valid-base64!!!")
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testMalformedES256DERSignatureFailsOpenUnsigned() throws {
        // 0xFF is not a SEQUENCE tag — decodeASN_1_DER_ES256_Signature throws immediately
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(
            Data([0xFF, 0x00]).base64EncodedString()
        )
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testTruncatedES256DERSignatureFailsOpenUnsigned() throws {
        // Valid SEQUENCE header (length 4) with a 2-byte r INTEGER but no s INTEGER — readByte() hits
        // end of data when trying to read the s tag, throwing "Truncated ASN.1 DER signature".
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(
            Data([0x30, 0x04, 0x02, 0x02, 0x00, 0x00]).base64EncodedString()
        )
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()

        try assertMessageSigningFailsOpenUnsigned(factory: factory)
    }

    func testInstallSignatureFailureLeavesNoContentDigest() throws {
        // Regression: the fail-open return used to hand back the provider's request, which carries the
        // Content-Digest that generateBodyDigest added before signing was attempted.
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(nil)
        defer { ApproovDefaultMessageSigning.clearMessageSignatureOverridesForTesting() }

        let factory = try SignatureParametersFactory()
            .setBaseParameters(SignatureParameters().addComponentIdentifier("@method"))
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: false)
        try assertBodyDigestNotLeftUncovered(factory: factory)
    }

    func testNonRequiredBodyDigestDoesNotAbortTheRequest() throws {
        // A non-required body digest must fail open (TESTING_REQUIREMENTS section 5). Signing itself
        // succeeds here, so the request must come back signed regardless of the digest outcome.
        ApproovDefaultMessageSigning.setInstallMessageSignatureOverrideForTesting(validInstallDERBase64())
        defer { ApproovDefaultMessageSigning.clearMessageSignatureOverridesForTesting() }

        let factory = try SignatureParametersFactory()
            .setBaseParameters(SignatureParameters().addComponentIdentifier("@method"))
            .setBodyDigestConfig(ApproovDefaultMessageSigning.DIGEST_SHA256, required: false)
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)

        let updatedRequest = try signer.processedRequest(staleSignedRequestWithBody(), changes: tokenChanges())

        let signature = updatedRequest.value(forHTTPHeaderField: "Signature")
        XCTAssertNotNil(signature)
        // Byte-sequence encoding per RFC 8941, which nothing else in this suite asserts.
        XCTAssertTrue(signature?.hasPrefix("install=:") == true, "expected a byte sequence, got \(signature ?? "nil")")
        XCTAssertTrue(signature?.hasSuffix(":") == true)
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

    /// Same contract as above but starting from a request WITH a replayable body, so the body-digest
    /// path actually runs and adds `Content-Digest` before signing fails. Without a body,
    /// `generateBodyDigest` returns early and the header is never created, which is why the
    /// body-less fixture cannot catch an orphaned digest.
    private func assertBodyDigestNotLeftUncovered(factory: SignatureParametersFactory,
                                                  file: StaticString = #filePath,
                                                  line: UInt = #line) throws {
        let signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        let updatedRequest = try signer.processedRequest(staleSignedRequestWithBody(), changes: tokenChanges())

        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Signature"), file: file, line: line)
        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Signature-Input"), file: file, line: line)
        // A body digest with no signature covering it is not "proceeds unsigned": the request must
        // carry no signing artifacts at all (TESTING_REQUIREMENTS section 5).
        XCTAssertNil(updatedRequest.value(forHTTPHeaderField: "Content-Digest"), file: file, line: line)
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

    private func staleSignedRequestWithBody() -> URLRequest {
        var request = staleSignedRequest()
        request.httpBody = Data("field=value".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    // Minimal valid ES256 DER: SEQUENCE { INTEGER r(32 bytes), INTEGER s(32 bytes) }
    // r = 0x01 * 32, s = 0x02 * 32 — no high bit set, no zero-padding needed.
    private func validInstallDERBase64() -> String {
        var der = Data([0x30, 0x44, 0x02, 0x20])
        der.append(contentsOf: repeatElement(UInt8(0x01), count: 32))
        der.append(contentsOf: [0x02, 0x20])
        der.append(contentsOf: repeatElement(UInt8(0x02), count: 32))
        return der.base64EncodedString()
    }
}
