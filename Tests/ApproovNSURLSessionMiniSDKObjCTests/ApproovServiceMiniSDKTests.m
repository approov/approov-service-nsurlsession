#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@import ApproovNSURLSessionObjC;
@import MiniSDKTestSupport;

@interface ApproovTestChallengeSender : NSObject <NSURLAuthenticationChallengeSender>
@end

@implementation ApproovTestChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
}

@end

@interface ApproovServiceMiniSDKTests : XCTestCase
@end

@implementation ApproovServiceMiniSDKTests

- (NSString *)validInitialConfig {
    return @"#cb-ivol#mAxOF0ekJUOC36J5XWmVmVipOcUoEdMjhPSp2FVtyTo=";
}

- (void)setUp {
    [super setUp];
    [MiniSDKAttesterProxyController reset];
    [ApproovService clearMutatorBridgeOverrideForTesting];
    [ApproovService resetForTesting];
    [ApproovService setLoggingLevel:ApproovLogLevelOff];
}

- (void)tearDown {
    [ApproovService clearMutatorBridgeOverrideForTesting];
    [ApproovService resetForTesting];
    [MiniSDKAttesterProxyController reset];
    [super tearDown];
}

#pragma mark - Initialization

- (void)testInitializeIgnoresSameConfig {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-nsurlsession-tests"]);

    NSError *error = nil;
    [ApproovService initialize:[self validInitialConfig] comment:@"reinit-same-config" error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([ApproovService isInitialized]);
    XCTAssertTrue([ApproovService isApproovEnabled]);
}

- (void)testEmptyConfigBypassForwardsPlainRequests {
    NSError *error = nil;
    [ApproovService initialize:@"" comment:@"empty-config-bypass" error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([ApproovService isInitialized]);
    XCTAssertFalse([ApproovService isApproovEnabled]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testEmptyConfigThenValidConfigEnablesProtection {
    NSError *error = nil;
    [ApproovService initialize:@"" comment:@"empty-config-bypass" error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([ApproovService isInitialized]);
    XCTAssertFalse([ApproovService isApproovEnabled]);

    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNotNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNotNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testValidConfigThenEmptyConfigKeepsProtectionEnabled {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);

    NSError *error = nil;
    [ApproovService initialize:@"" comment:@"empty-config-after-valid" error:&error];

    XCTAssertNil(error);
    XCTAssertTrue([ApproovService isInitialized]);
    XCTAssertTrue([ApproovService isApproovEnabled]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNotNil([self headerFromReply:reply key:@"Approov-Token"]);
}

- (void)testBridgeClassIsVisibleForSwiftObjCLinkage {
    XCTAssertNotNil(NSClassFromString(@"ApproovServiceMutatorBridge"));
    XCTAssertNotNil([ApproovService mutatorBridge]);
}

- (void)testMissingBridgeFailsGracefullyAndForwardsUnprotected {
    [ApproovService setMutatorBridgeOverrideForTesting:nil];

    NSError *error = nil;
    [ApproovService initialize:[self validInitialConfig] comment:@"missing-bridge" error:&error];

    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"approov");
    XCTAssertEqualObjects(error.userInfo[@"type"], @"general");
    XCTAssertFalse([ApproovService isInitialized]);
    XCTAssertFalse([ApproovService isApproovEnabled]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testResumeSwizzleIsInstalledAndIdempotent {
    NSUInteger swizzleCountBefore = [ApproovService sessionTaskSwizzleCountForTesting];

    XCTAssertTrue([self initializeServiceWithComment:@"reinit-swizzle"]);

    NSUInteger swizzleCountAfterFirstInit = [ApproovService sessionTaskSwizzleCountForTesting];
    XCTAssertTrue([ApproovService isSessionTaskSwizzledForTesting]);
    XCTAssertTrue((swizzleCountAfterFirstInit == swizzleCountBefore) ||
                  (swizzleCountAfterFirstInit == swizzleCountBefore + 1));

    NSError *error = nil;
    [ApproovService initialize:[self validInitialConfig] comment:@"reinit-swizzle-again" error:&error];

    XCTAssertNil(error);
    XCTAssertEqual(swizzleCountAfterFirstInit, [ApproovService sessionTaskSwizzleCountForTesting]);
}

#pragma mark - Request Processing and Token Behaviors

- (void)testUninitializedServiceForwardsPlainRequests {
    XCTAssertFalse([ApproovService isInitialized]);
    XCTAssertFalse([ApproovService isApproovEnabled]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testPrecheckTreatsUnknownKeyAsSuccess {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-precheck"]);

    NSError *error = nil;
    [ApproovService precheck:&error];

    XCTAssertNil(error);
}

- (void)testGetDeviceIDReturnsMiniSDKDeviceID {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-device-id"]);

    XCTAssertEqualObjects([ApproovService getDeviceID], @"daIvmEWBA2gvZny7a/RC/w==");
}

- (void)testUpdateRequestAddsTokenAndTraceIDToProtectedRequest {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNotNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNotNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testUpdateRequestSkipsUnprotectedDomain {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self unprotectedURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-TraceID"]);
}

- (void)testUpdateRequestSkipsExcludedURL {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService addExclusionURLRegex:@"^.*excluded.*$"];

    NSString *urlString = [[self targetURLString] stringByAppendingString:@"/excluded"];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
}

- (void)testUpdateRequestProceedsWithoutTokenOnNoApproovService {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchApproovToken\","
          @"\"response\":{"
            @"\"status\":\"NO_APPROOV_SERVICE\""
          @"}"
        @"}"];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSDictionary *reply = [self fetchNetworkReplyForRequest:request];

    XCTAssertNotNil(reply);
    XCTAssertNil([self headerFromReply:reply key:@"Approov-Token"]);
}

- (void)testNilTokenPrefixIsNormalizedToEmptyString {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService setApproovTokenPrefix:nil];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];
    NSString *tokenHeader = [updatedRequest valueForHTTPHeaderField:@"Approov-Token"];

    XCTAssertNil(error);
    XCTAssertEqualObjects([ApproovService getApproovTokenPrefix], @"");
    XCTAssertNotNil(tokenHeader);
    XCTAssertFalse([tokenHeader hasPrefix:@"(null)"]);
}

- (void)testUserPropertyReportsLayerAndVersionInTheToken {
    // Restores the coverage dropped in c5f1d60. No mini-SDK accessor is needed: the fixture already
    // records the user property set at initialization and emits it as the `user_property` token claim,
    // so this asserts what actually reaches an attestation rather than what the source contains.
    // The version segment is deliberately not hardcoded - CI stamps the "dev" placeholder at release,
    // so the assertion is on the prefix plus a non-empty version.
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];
    XCTAssertNil(error);

    NSString *token = [updatedRequest valueForHTTPHeaderField:@"Approov-Token"];
    XCTAssertNotNil(token);
    NSDictionary *claims = [self decodeJWTBody:token];
    XCTAssertNotNil(claims);

    NSString *userProperty = claims[@"user_property"];
    XCTAssertNotNil(userProperty, @"the layer must report itself through setUserProperty at initialization");
    XCTAssertTrue([userProperty hasPrefix:@"approov-service-nsurlsession/"],
                  @"expected a versioned layer identifier, got %@", userProperty);
    XCTAssertTrue(userProperty.length > [@"approov-service-nsurlsession/" length],
                  @"the version segment must not be empty: %@", userProperty);
}

- (void)testSuccessWithEmptyTokenOmitsTheTokenHeader {
    // TESTING_REQUIREMENTS section 2 "Missing Artifacts Fallback": with no token available and the
    // status fallback disabled, the header must be OMITTED - not sent empty, and not sent as the prefix
    // alone. A domain registered for secure-string substitution or pinning only reaches exactly this
    // shape: the fetch succeeds but no token is minted for it.
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService setApproovTokenPrefix:@"Bearer "];
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchApproovToken\","
          @"\"response\":{"
            @"\"status\":\"SUCCESS\","
            @"\"emptyToken\":true"
          @"}"
        @"}"];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];

    XCTAssertNil(error);
    NSString *tokenHeader = [updatedRequest valueForHTTPHeaderField:@"Approov-Token"];
    XCTAssertNil(tokenHeader,
                 @"expected the token header to be omitted, got %@", tokenHeader ? [NSString stringWithFormat:@"\"%@\"", tokenHeader] : @"nil");
}

- (void)testEmptyTokenWithStatusFallbackEnabledSendsTheStatus {
    // The counterpart: setUseApproovStatusIfNoToken is the supported way to give the backend evidence
    // that Approov ran, so with it enabled the header carries the status rather than being omitted.
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService setUseApproovStatusIfNoToken:YES];
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchApproovToken\","
          @"\"response\":{"
            @"\"status\":\"SUCCESS\","
            @"\"emptyToken\":true"
          @"}"
        @"}"];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects([updatedRequest valueForHTTPHeaderField:@"Approov-Token"], @"SUCCESS");
}

- (void)testEmptyTraceIDDoesNotProduceAnEmptyHeader {
    // TESTING_REQUIREMENTS section 2 "Missing Artifacts Fallback": an empty artifact must be omitted,
    // never sent as an empty-valued header. The SDK returns an empty string when no trace ID is
    // available, so a nil check alone is not sufficient.
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService setApproovTraceIDHeader:@"Approov-TraceID"];
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchApproovToken\","
          @"\"response\":{"
            @"\"status\":\"SUCCESS\","
            @"\"traceID\":\"\""
          @"}"
        @"}"];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];

    XCTAssertNil(error);
    XCTAssertNil([updatedRequest valueForHTTPHeaderField:@"Approov-TraceID"],
                 @"an empty trace ID must not be sent as an empty-valued header");
}

#pragma mark - Secure Strings and Custom JWT

- (void)testFetchSecureStringReturnsConfiguredValue {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-secure-string"]);
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchSecureString\","
          @"\"response\":{"
            @"\"status\":\"SUCCESS\","
            @"\"secureString\":\"mini-secret\""
          @"}"
        @"}"];

    NSError *error = nil;
    NSString *secureString = [ApproovService fetchSecureString:@"api-key" newDef:nil error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(secureString, @"mini-secret");
}

- (void)testFetchSecureStringReturnsNilForUnknownKey {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-secure-string-unknown"]);
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchSecureString\","
          @"\"response\":{"
            @"\"status\":\"UNKNOWN_KEY\""
          @"}"
        @"}"];

    NSError *error = nil;
    NSString *secureString = [ApproovService fetchSecureString:@"missing-key" newDef:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNil(secureString);
}

- (void)testFetchCustomJWTReturnsSignedJWT {
    XCTAssertTrue([self initializeServiceWithComment:@"reinit-custom-jwt"]);

    NSError *error = nil;
    NSString *jwt = [ApproovService fetchCustomJWT:@"{\"role\":\"tester\"}" error:&error];
    NSDictionary *payload = [self decodeJWTBody:jwt];

    XCTAssertNil(error);
    XCTAssertNotNil(jwt);
    XCTAssertEqualObjects(payload[@"role"], @"tester");
}

#pragma mark - Message Signing

- (void)testRequiredBodyDigestFailurePropagatesFromMessageSigning {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService setMessageSigningMode:ApproovMessageSigningModeInstall];
    [ApproovService setMessageSigningBodyDigestRequired:YES];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    request.HTTPMethod = @"POST";
    request.HTTPBodyStream = [NSInputStream inputStreamWithData:[@"payload" dataUsingEncoding:NSUTF8StringEncoding]];

    NSError *error = nil;
    NSURLRequest *updatedRequest = [ApproovService updateRequestWithApproov:request
                                                              sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                      error:&error];

    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"required body digest"]);
    XCTAssertNil([updatedRequest valueForHTTPHeaderField:@"Signature"]);
    XCTAssertNil([updatedRequest valueForHTTPHeaderField:@"Signature-Input"]);
}

#pragma mark - Pinning Challenge Behavior

- (void)testSessionLevelNonServerTrustChallengeUsesDefaultHandling {
    ApproovPinningURLSessionDelegate *delegate = [[ApproovPinningURLSessionDelegate alloc] initWithDelegate:nil];
    NSURLAuthenticationChallenge *challenge = [self authenticationChallengeWithMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    __block NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengeUseCredential;
    __block NSURLCredential *credential = [NSURLCredential credentialWithUser:@"user"
                                                                     password:@"password"
                                                                  persistence:NSURLCredentialPersistenceForSession];

    [delegate URLSession:session didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition receivedDisposition, NSURLCredential *receivedCredential) {
        disposition = receivedDisposition;
        credential = receivedCredential;
    }];
    [session invalidateAndCancel];

    XCTAssertEqual(disposition, NSURLSessionAuthChallengePerformDefaultHandling);
    XCTAssertNil(credential);
}

- (void)testTaskLevelNonServerTrustChallengeUsesDefaultHandling {
    ApproovPinningURLSessionDelegate *delegate = [[ApproovPinningURLSessionDelegate alloc] initWithDelegate:nil];
    NSURLAuthenticationChallenge *challenge = [self authenticationChallengeWithMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://example.com"]];
    __block NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengeUseCredential;
    __block NSURLCredential *credential = [NSURLCredential credentialWithUser:@"user"
                                                                     password:@"password"
                                                                  persistence:NSURLCredentialPersistenceForSession];

    [delegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition receivedDisposition, NSURLCredential *receivedCredential) {
        disposition = receivedDisposition;
        credential = receivedCredential;
    }];
    [session invalidateAndCancel];

    XCTAssertEqual(disposition, NSURLSessionAuthChallengePerformDefaultHandling);
    XCTAssertNil(credential);
}

- (void)testTaskLevelServerTrustChallengeWithoutTrustCancels {
    ApproovPinningURLSessionDelegate *delegate = [[ApproovPinningURLSessionDelegate alloc] initWithDelegate:nil];
    NSURLAuthenticationChallenge *challenge = [self authenticationChallengeWithMethod:NSURLAuthenticationMethodServerTrust];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://example.com"]];
    __block NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengeUseCredential;
    __block NSURLCredential *credential = [NSURLCredential credentialWithUser:@"user"
                                                                     password:@"password"
                                                                  persistence:NSURLCredentialPersistenceForSession];

    [delegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition receivedDisposition, NSURLCredential *receivedCredential) {
        disposition = receivedDisposition;
        credential = receivedCredential;
    }];
    [session invalidateAndCancel];

    XCTAssertEqual(disposition, NSURLSessionAuthChallengeCancelAuthenticationChallenge);
    XCTAssertNil(credential);
}

#pragma mark - Null error pointer crash regression (updateRequestWithApproov:error:)

- (void)testHeaderSubstitutionRejectionWithNullErrorDoesNotCrash {
    // Establish a protected domain so updateRequestWithApproov processes the request.
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService addSubstitutionHeader:@"X-API-Key" requiredPrefix:nil];

    // The directive is operation-specific: fetchApproovToken consumes the scenario (not this
    // directive), then fetchSecureString consumes this directive and returns REJECTED.
    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchSecureString\","
          @"\"response\":{"
            @"\"status\":\"REJECTED\","
            @"\"ARC\":\"test-arc\","
            @"\"rejectionReasons\":\"test-reason\""
          @"}"
        @"}"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self targetURLString]]];
    [request setValue:@"placeholder-key" forHTTPHeaderField:@"X-API-Key"];

    // Pre-fix: writing *error without a nil check crashed when error was NULL.
    NSURLRequest *result = [ApproovService updateRequestWithApproov:request
                                                     sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                             error:NULL];
    XCTAssertNotNil(result);
}

- (void)testQueryParamSubstitutionNetworkFailureWithNullErrorDoesNotCrash {
    XCTAssertTrue([self reinitializeServiceWithTargetHostAndScenarioBody:@""]);
    [ApproovService addSubstitutionQueryParam:@"api-key"];

    [MiniSDKAttesterProxyController setNextAttestationDirectiveJSON:
        @"{"
          @"\"operation\":\"fetchSecureString\","
          @"\"response\":{"
            @"\"status\":\"NO_NETWORK\""
          @"}"
        @"}"];

    NSString *urlWithParam = [[self targetURLString] stringByAppendingString:@"?api-key=placeholder-key"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlWithParam]];

    // Pre-fix: writing *error without a nil check crashed when error was NULL.
    NSURLRequest *result = [ApproovService updateRequestWithApproov:request
                                                     sessionConfig:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                             error:NULL];
    XCTAssertNotNil(result);
}

#pragma mark - Helpers

- (NSString *)targetURLString {
    return [self requiredEnvironmentValueForKey:@"TESTING_REPLY_URL"];
}

- (NSString *)unprotectedURLString {
    return [self requiredEnvironmentValueForKey:@"TESTING_REPLY_URL_UNPROTECTED"];
}

- (NSString *)requiredEnvironmentValueForKey:(NSString *)key {
    NSString *value = [NSProcessInfo processInfo].environment[key];
    XCTAssertNotNil(value, @"%@ environment variable is not set", key);
    return value;
}

- (NSDictionary *)fetchNetworkReplyForRequest:(NSURLRequest *)request {
    XCTestExpectation *expectation = [self expectationWithDescription:@"network request"];
    __block NSData *receivedData = nil;
    __block NSError *requestError = nil;

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [ApproovNSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedData = data;
        requestError = error;
        [expectation fulfill];
    }];
    XCTAssertNotNil(task);
    [task resume];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    [session finishTasksAndInvalidate];

    XCTAssertNil(requestError);
    if (receivedData == nil) {
        return nil;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:receivedData options:0 error:&jsonError];
    XCTAssertNil(jsonError);
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return object;
}

- (NSString *)headerFromReply:(NSDictionary *)reply key:(NSString *)key {
    NSDictionary *headers = reply[@"headers"];
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    id value = headers[key.lowercaseString] ?: headers[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [(NSArray *)value firstObject];
    }
    return nil;
}

- (NSURLAuthenticationChallenge *)authenticationChallengeWithMethod:(NSString *)method {
    NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:@"example.com"
                                                                                  port:443
                                                                              protocol:NSURLProtectionSpaceHTTPS
                                                                                 realm:@"approov-test"
                                                                  authenticationMethod:method];
    ApproovTestChallengeSender *sender = [[ApproovTestChallengeSender alloc] init];
    return [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
                                                      proposedCredential:nil
                                                    previousFailureCount:0
                                                         failureResponse:nil
                                                                   error:nil
                                                                  sender:sender];
}

- (BOOL)reinitializeServiceWithTargetHostAndScenarioBody:(NSString *)scenarioBody {
    NSURL *targetURL = [NSURL URLWithString:[self targetURLString]];
    NSString *targetHost = targetURL.host;
    XCTAssertNotNil(targetHost);
    if (targetHost == nil) {
        return NO;
    }

    NSString *domainsJSON = [NSString stringWithFormat:@"\"protectedDomains\":[\"%@\"]", targetHost];
    NSString *fullBody = scenarioBody.length == 0
        ? domainsJSON
        : [NSString stringWithFormat:@"%@,%@", domainsJSON, scenarioBody];
    NSString *scenarioJSON = [self scenarioJSONWithCaseName:[self uniqueCaseNameWithPrefix:@"target-host"]
                                                       body:fullBody];
    return [self reinitializeServiceWithScenarioJSON:scenarioJSON comment:@"reinit-target-host"];
}

- (void)objcInitializeServiceWithComment:(NSString *)comment error:(NSError **)error {
    [ApproovService initialize:[self validInitialConfig] comment:comment error:error];
}

- (BOOL)initializeServiceWithComment:(NSString *)comment {
    NSError *error = nil;
    [self objcInitializeServiceWithComment:comment error:&error];
    XCTAssertNil(error);
    return error == nil;
}

- (BOOL)reinitializeServiceWithScenarioJSON:(NSString *)scenarioJSON comment:(NSString *)comment {
    [MiniSDKAttesterProxyController reset];
    if (scenarioJSON != nil) {
        [MiniSDKAttesterProxyController loadScenarioJSON:scenarioJSON];
    }
    [ApproovService setLoggingLevel:ApproovLogLevelOff];

    NSError *error = nil;
    [self objcInitializeServiceWithComment:comment error:&error];
    XCTAssertNil(error);
    return error == nil;
}

- (NSString *)uniqueCaseNameWithPrefix:(NSString *)prefix {
    return [NSString stringWithFormat:@"%@-%@", prefix, NSUUID.UUID.UUIDString.lowercaseString];
}

- (NSString *)scenarioJSONWithCaseName:(NSString *)caseName body:(NSString *)body {
    return [NSString stringWithFormat:
        @"{"
          @"\"activeCase\":\"%@\","
          @"\"cases\":{"
            @"\"%@\":{%@}"
          @"}"
        @"}",
        caseName,
        caseName,
        body];
}

- (NSDictionary *)decodeJWTBody:(NSString *)jwt {
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        return nil;
    }

    NSData *data = [self base64URLDecode:parts[1]];
    if (data == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

- (NSData *)base64URLDecode:(NSString *)value {
    NSMutableString *padded = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
        mutableCopy];
    [padded replaceOccurrencesOfString:@"_"
                            withString:@"/"
                               options:0
                                 range:NSMakeRange(0, padded.length)];
    NSUInteger padding = (4 - padded.length % 4) % 4;
    for (NSUInteger index = 0; index < padding; index++) {
        [padded appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:padded options:0];
}

@end
