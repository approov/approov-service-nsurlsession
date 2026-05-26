# Approov NSURLSession Usage Guide

This guide shows the service-layer flows covered by the shared test requirements.

## Initialization

Initialize once before creating protected sessions:

```objective-c
NSError *error = nil;
[ApproovService initialize:approovConfigString comment:@"options:debug" error:&error];
if (error != nil) {
    NSLog(@"Approov initialization failed: %@", error.localizedDescription);
}
```

For local bypass or tests that should behave like a normal NSURLSession wrapper, initialize with an empty config string:

```objective-c
NSError *error = nil;
[ApproovService initialize:@"" comment:@"local bypass" error:&error];
NSAssert([ApproovService isInitialized], @"service layer should be initialized");
NSAssert(![ApproovService isApproovEnabled], @"Approov should be disabled");
```

Empty-config bypass performs no token injection, trace headers, message signing, secure string substitution, secure string fetches, custom JWT fetches, or dynamic pinning.

## Creating a Protected Session

Use `ApproovNSURLSession` anywhere you would normally create an `NSURLSession` for protected API traffic:

```objective-c
NSURLSessionConfiguration *configuration =
    [NSURLSessionConfiguration ephemeralSessionConfiguration];
NSURLSession *session = [ApproovNSURLSession sessionWithConfiguration:configuration];

NSURL *url = [NSURL URLWithString:@"https://api.example.com/orders"];
NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                    completionHandler:^(NSData *data,
                                                        NSURLResponse *response,
                                                        NSError *error) {
    // Handle the response.
}];
[task resume];
```

## Token and Trace Headers

The default token header is `Approov-Token`. Configure custom names and prefixes before sending requests:

```objective-c
[ApproovService setApproovTokenHeader:@"Authorization"];
[ApproovService setApproovTokenPrefix:@"Bearer "];
[ApproovService setApproovTraceIDHeader:@"X-Approov-TraceID"];
```

When a token is available, the backend sees `Authorization: Bearer <token>`. If trace IDs are enabled by policy, the backend sees `X-Approov-TraceID`.

For diagnostics or backend replay tests, allow a fetch status to appear in the token header when a mutator allows the request to proceed without a token, or when a fetch returns no token:

```objective-c
[ApproovService setApproovTokenHeader:@"Approov-Token"];
[ApproovService setApproovTokenPrefix:@"Bearer "];
[ApproovService setUseApproovStatusIfNoToken:YES];
```

## Automatic Token Binding

Bind Approov tokens to an existing request header, commonly `Authorization`:

```objective-c
[ApproovService setBindingHeader:@"Authorization"];

NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/profile"]];
[request setValue:@"Bearer user-session-token" forHTTPHeaderField:@"Authorization"];
```

The service layer reads the `Authorization` value, forwards it to the SDK with `setDataHashInToken`, and leaves the original header unchanged.

## Manual Token Binding

Use manual binding only when there is no suitable request header:

```objective-c
[ApproovService setBindingHeader:@""];
[ApproovService setDataHashInToken:@"user-session-token"];
```

Do not mix manual `setDataHashInToken` and automatic `setBindingHeader` for the same request path. The backend should validate one consistent binding model.

## Exclusions

Exclude URLs that must pass through without Approov request mutation:

```objective-c
[ApproovService addExclusionURLRegex:@"^https://api\\.example\\.com/public/.*$"];
```

Remove exclusions when no longer needed:

```objective-c
[ApproovService removeExclusionURLRegex:@"^https://api\\.example\\.com/public/.*$"];
```

Exclusions skip token headers, trace headers, message signing, and secure string substitution. They do not by themselves disable TLS pinning for a protected host.

## Secure String Substitution

Substitute a header value from a secure string key:

```objective-c
[ApproovService addSubstitutionHeader:@"Api-Key" requiredPrefix:@"approov:"];

NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/secure"]];
[request setValue:@"approov:prod-api-key" forHTTPHeaderField:@"Api-Key"];
```

Substitute a query parameter:

```objective-c
[ApproovService addSubstitutionQueryParam:@"api_key"];
NSURL *url = [NSURL URLWithString:@"https://api.example.com/search?api_key=prod-api-key"];
```

Remove substitutions immediately when a flow no longer needs them:

```objective-c
[ApproovService removeSubstitutionHeader:@"Api-Key"];
[ApproovService removeSubstitutionQueryParam:@"api_key"];
```

If a secure string resolves to an empty value, the original placeholder remains in the outgoing request.

## Direct Secure Strings and Custom JWT

Fetch a secure string directly:

```objective-c
NSError *error = nil;
NSString *value = [ApproovService fetchSecureString:@"prod-api-key" newDef:nil error:&error];
```

Fetch a custom JWT:

```objective-c
NSError *error = nil;
NSString *payload = @"{\"sub\":\"user-123\",\"scope\":\"orders:read\"}";
NSString *jwt = [ApproovService fetchCustomJWT:payload error:&error];
```

Returned tokens, JWTs, and secure strings should be used for the immediate operation and not cached as long-lived credentials.

## Development Precheck

Use `precheck` during development to confirm SDK wiring and account reachability:

```objective-c
NSError *error = nil;
[ApproovService precheck:&error];
if (error != nil) {
    NSLog(@"Approov precheck failed: %@", error.localizedDescription);
}
```

Do not call `precheck()` on every production app launch.

## Message Signing

Enable install message signing:

```objective-c
[ApproovService setMessageSigningMode:ApproovMessageSigningModeInstall];
```

Enable account message signing:

```objective-c
[ApproovService setMessageSigningMode:ApproovMessageSigningModeAccount];
```

Disable automatic message signing:

```objective-c
[ApproovService setMessageSigningMode:ApproovMessageSigningModeDisabled];
```

Repeatable POST, PUT, and PATCH bodies include `Content-Digest` by default when signing can safely read the body:

```objective-c
[ApproovService setMessageSigningBodyDigestEnabled:YES];
[ApproovService setMessageSigningBodyDigestRequired:NO];
```

Disable body digest generation entirely:

```objective-c
[ApproovService setMessageSigningBodyDigestEnabled:NO];
```

Require body digests for signed requests that carry bodies:

```objective-c
[ApproovService setMessageSigningBodyDigestRequired:YES];
```

When required mode is enabled and the request body cannot be safely replayed, signing fails closed for that request rather than creating a signature without a digest.

Manual signature APIs are also available:

```objective-c
NSString *accountSignature = [ApproovService getAccountMessageSignature:@"message"];
NSString *installSignature = [ApproovService getInstallMessageSignature:@"message"];
```

The older `getMessageSignature:` method is a deprecated account-signing compatibility alias.

## Swift Service Mutator

Install a custom mutator from Swift when the default fail-closed behavior needs project-specific decisions:

```swift
final class MyApproovServiceMutator: ApproovServiceMutator {
    func handleInterceptorFetchTokenResult(_ result: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        return result.status == .success
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        var updated = request
        updated.setValue("ios", forHTTPHeaderField: "X-Client")
        return updated
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        return request.url?.host != "debug.example.com"
    }
}

ApproovServiceMutatorBridge.shared.serviceMutator = MyApproovServiceMutator()
```

Reset to the default mutator:

```swift
ApproovServiceMutatorBridge.shared.resetServiceMutator()
```

## Pinning Integration

Use the pinned `ApproovNSURLSession` for protected hosts. Pinning-only policy validates TLS pins without adding token, trace, or signature artifacts. Excluded protected URLs still use the pinned session delegate unless your Swift mutator skips pinning for that request.

Real pinning evidence should be gathered against configured Approov test endpoints for valid pins, invalid pins, accept-any pins, pinning-only policy, excluded protected URLs, and dynamic pin updates.

## Running the Verification Suites

Run the local green contract suite:

```bash
tests/ios/run_all_tests.sh
```

Run the documentation audit:

```bash
tests/ios/run_docs_audit.sh
```

Run backend replay integration tests with the real SDK and echo workers:

```bash
export APPROOV_CONFIG="<test account config>"
export APPROOV_DEV_KEY="<optional simulator development key>"
export TESTING_REPLY_URL="https://replay.example.test"
export TESTING_REPLY_URL_UNPROTECTED="https://replay-unprotected.example.test"
export TESTING_REPLY_URL_PINNING_ONLY="https://pinning-only.example.test"
tests/ios/run_backend_replay_tests.sh
```

Run real pinning integration tests:

```bash
export APPROOV_CONFIG="<test account config>"
export TESTING_REPLY_URL="https://replay.example.test"
export TESTING_REPLY_URL_PINNING_ONLY="https://pinning-only.example.test"
export TESTING_REPLY_URL_INVALID_PIN="https://invalid-pin.example.test"
export TESTING_REPLY_URL_ACCEPT_ANY="https://accept-any.example.test"
export TESTING_REPLY_URL_DYNAMIC_PIN_UPDATE="https://dynamic-pin.example.test"
export APPROOV_DYNAMIC_PIN_UPDATE_EXPECTED="success"
tests/ios/run_pinning_integration_tests.sh
```

Run every verification layer:

```bash
tests/ios/run_full_verification.sh
```

When integration environment variables are not available, use skip mode to validate runner wiring without claiming backend or pinning evidence:

```bash
ALLOW_INTEGRATION_SKIPS=1 tests/ios/run_backend_replay_tests.sh
ALLOW_INTEGRATION_SKIPS=1 tests/ios/run_pinning_integration_tests.sh
```
