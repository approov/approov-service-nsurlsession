# Usage

This document describes the features and functionality of the Approov Service for NSURLSession. It provides details on how to interact with the service layer and customize its behavior to suit your application's needs, specifically through the `ApproovServiceMutator`. For a basic integration example, please refer to the [Quickstart guide](https://github.com/approov/quickstart-ios-objectivec-nsurlsession).

## Basic setup

Initialize the service once before creating protected sessions:

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

Set the service-layer logging level before sending requests:

```objective-c
[ApproovService setLoggingLevel:ApproovLogLevelError];
```

Available levels are `ApproovLogLevelOff`, `ApproovLogLevelError`, `ApproovLogLevelWarning`, `ApproovLogLevelInfo`, and `ApproovLogLevelDebug`. The default is `ApproovLogLevelInfo`, which keeps request outcome diagnostics visible while suppressing debug-level configuration chatter. Use `ApproovLogLevelDebug` for development evidence when you need configuration, substitution, token-fetch, and pin-matching diagnostics. Use `ApproovLogLevelError` or `ApproovLogLevelOff` when routine request diagnostics should not appear in production logs.

# Approov Service Mutator

The `ApproovServiceMutator` allows you to customize the behavior of the Approov NSURLSession layer at key points in the request lifecycle. You can override specific methods to tailor the handling of attestations and requests while retaining the default behavior for other cases.

## Why use a mutator

- Centralize app-specific policy without forking the service layer.
- Add telemetry on rejections or network failures.
- Adjust behavior when token or secure string fetches fail.
- Add or rewrite headers after Approov processing.
- Customize pinning decisions per request.

For URL exclusions, prefer `addExclusionURLRegex:` because exclusions are handled by the Objective-C request path before token fetching and mutation.

## Default Behavior

By default, the `ApproovService` processes requests based on the attestation status. It relies on the underlying SDK to provide a proof of attestation, which is a cryptographically signed JWT token. Requesting this attestation typically returns the token immediately; however, a network connection to the Approov cloud is required upon app launch or when the token is nearing expiration.

Note that the SDK only knows if an attestation token has been obtained; it cannot determine if the token is valid. Token validity is checked by your backend. The default behavior is described in more detail in the official documentation section [Approov Token Fetch Results](https://approov.io/docs/latest/approov-usage-documentation/#approov-token-fetch-results) and is summarized below:

| Approov Fetch Status | Action | Result |
| :--- | :--- | :--- |
| **Success** | Proceed | The request is sent with the configured Approov token header. |
| **No Network / Poor Network / MITM Detected** | Fail closed by default | The request returns a networking error unless `setProceedOnNetworkFailure:` or a custom mutator explicitly allows fallback. |
| **Rejection / Permanent Error** | Fail closed | The request returns an error and should be treated as rejected or permanently unavailable. |
| **No Approov Service** | Proceed without a normal token | The request is sent without an Approov token unless `setUseApproovStatusIfNoToken:YES` is enabled to send the status in the token header. |
| **Unknown URL / Unprotected URL** | Proceed without Approov artifacts | The request is sent without token, trace, secure string substitution, or message-signing artifacts. |

## Customizing Request Handling with Mutators

You may want to modify this behavior to suit specific app requirements. A common use case is handling `NO_APPROOV_SERVICE` statuses.

### Prevent Access Without a Token

The standard behavior for statuses like `NO_APPROOV_SERVICE` is to proceed with the request without adding an Approov token. This might occur, for example, if a device cannot connect to the Approov cloud due to a restricted network environment. You may wish to prevent this behavior to ensure that only requests with valid proof of attestation reach your backend API, allowing you to explicitly handle this case within your application.

Override `handleInterceptorFetchTokenResult` to enforce this policy:

```swift
import Approov
import Foundation

final class EnforceTokenMutator: ApproovServiceMutator {
    func handleInterceptorFetchTokenResult(_ result: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        if result.status == .noApproovService {
            throw ApproovServiceError.networkingError(
                message: "Approov service unavailable for \(url)"
            )
        }

        return try ApproovServiceMutatorDefault.shared
            .handleInterceptorFetchTokenResult(result, url: url)
    }
}

ApproovServiceMutatorBridge.shared.serviceMutator = EnforceTokenMutator()
```

### Allow Access Without Token

Conversely, if the device could not obtain proof of attestation because of a `NO_NETWORK` or `POOR_NETWORK` response from the SDK, the default behavior is to fail the request unless network fallback is enabled. You may prefer to let the request attempt the connection to your backend without a normal Approov token so the server can return a custom response.

Use a mutator to allow the request to continue, and optionally enable status-token fallback so the backend can see the failure reason in the configured token header:

```objective-c
[ApproovService setUseApproovStatusIfNoToken:YES];
```

```swift
import Approov
import Foundation

final class OfflineFallbackMutator: ApproovServiceMutator {
    func handleInterceptorFetchTokenResult(_ result: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        if result.status == .noNetwork || result.status == .poorNetwork {
            return true
        }

        return try ApproovServiceMutatorDefault.shared
            .handleInterceptorFetchTokenResult(result, url: url)
    }
}

ApproovServiceMutatorBridge.shared.serviceMutator = OfflineFallbackMutator()
```

### Add Custom Headers Using a Mutator

You can override `handleInterceptorProcessedRequest` to add additional headers or modify the request after Approov has processed it. This hook is invoked from the message-signing processed-request bridge, so enable message signing if you want this hook to run for outgoing requests. If message signing is enabled, compose with `ApproovDefaultMessageSigning` so signing remains in place.

```swift
import Foundation

final class ClientHeaderMutator: ApproovServiceMutator {
    private let signer: ApproovServiceMutator

    init() {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
        signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        var updated = try signer.handleInterceptorProcessedRequest(request, changes: changes)
        updated.setValue("ios", forHTTPHeaderField: "Client-Platform")
        return updated
    }
}

ApproovServiceMutatorBridge.shared.serviceMutator = ClientHeaderMutator()
```

## How to Use a Custom Mutator in Your Application

Create a mutator, then install it once during app startup, after Approov initialization and before sending protected requests:

```swift
final class MyMutator: ApproovServiceMutator {
    // Override only the hooks you need.
}

ApproovServiceMutatorBridge.shared.serviceMutator = MyMutator()
```

Reset to the default mutator:

```swift
ApproovServiceMutatorBridge.shared.resetServiceMutator()
```

## Message Signing

It is possible to sign HTTP requests using Approov to ensure message integrity and authenticity. There are two types of message signing available:

1. [Installation Message Signing](https://ext.approov.io/docs/latest/approov-usage-documentation/#installation-message-signing): Uses an installation-specific key held on the device to sign requests. This provides strong non-repudiation because the signing key never leaves the device and is unique to that specific installation.
2. [Account Message Signing](https://ext.approov.io/docs/latest/approov-usage-documentation/#account-message-signing): Uses a shared account-specific secret key to sign requests. This key is delivered to the SDK only upon successful attestation.

Advantages of message signing:

- Integrity: Ensures that the request parameters, headers, body, and URL have not been tampered with during transit.
- Authenticity: Proves that the request originated from a genuine, attested application instance.

Message signing is not enabled unless you opt in. A signature is only added when:

- The request already has the configured Approov token header.
- The request is processed by the message signing bridge.
- A default or host-specific `SignatureParametersFactory` is configured.

### Enable with default settings

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

### Customize behavior

For advanced Swift integrations, configure an `ApproovDefaultMessageSigning` mutator directly:

```swift
let factory = SignatureParametersFactory()
    .setUseAccountMessageSigning()
    .setAddCreated(true)
    .setExpiresLifetime(60)

let signer = ApproovDefaultMessageSigning()
    .setDefaultFactory(factory)
    .putHostFactory(hostName: "api.example.com", factory: factory)

ApproovServiceMutatorBridge.shared.serviceMutator = signer
```

Manual signature APIs are also available:

```objective-c
NSString *accountSignature = [ApproovService getAccountMessageSignature:@"message"];
NSString *installSignature = [ApproovService getInstallMessageSignature:@"message"];
```

The older `getMessageSignature:` method is a deprecated account-signing compatibility alias.

## Token Binding

[Token Binding](https://ext.approov.io/docs/latest/approov-usage-documentation/#token-binding) allows you to bind the Approov token to a specific piece of data, such as an OAuth token or a user session identifier. This adds an extra layer of security by ensuring that the Approov token can only be used in conjunction with the bound data. The `ApproovService` calculates a hash of the binding data locally and includes this hash in the Approov token claims.

The actual binding data is never sent to the Approov cloud service; only the hash is transmitted.

To set up automatic token binding, specify a header name. The value of this header in your requests will be used for the binding.

### Example: Bind to Authorization Header

```objective-c
[ApproovService setBindingHeader:@"Authorization"];

NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/profile"]];
[request setValue:@"Bearer user-session-token" forHTTPHeaderField:@"Authorization"];
```

If the value of the binding header changes, for example because the user logs in and gets a new OAuth token, the SDK automatically invalidates the current Approov token and fetches a new one with the updated binding on the next request.

Use manual binding only when there is no suitable request header:

```objective-c
[ApproovService setBindingHeader:@""];
[ApproovService setDataHashInToken:@"user-session-token"];
```

Do not mix manual `setDataHashInToken` and automatic `setBindingHeader` for the same request path. The backend should validate one consistent binding model.

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

## Pinning Integration

Use the pinned `ApproovNSURLSession` for protected hosts. Pinning-only policy validates TLS pins without adding token, trace, or signature artifacts. Excluded protected URLs still use the pinned session delegate unless your Swift mutator skips pinning for that request.

Real pinning evidence should be gathered against configured Approov test endpoints for valid pins, invalid pins, accept-any pins, pinning-only policy, excluded protected URLs, and dynamic pin updates.

## Real-world examples

### Policy-driven mutator

This example demonstrates how to customize the `ApproovServiceMutator` to apply different options to API requests based on the hostname.

```swift
import Approov
import Foundation

final class CustomLogic: ApproovServiceMutator {
    private let signer: ApproovServiceMutator
    private let allowOfflineForHosts: Set<String>
    private let skipPinningHosts: Set<String>

    init(allowOfflineForHosts: Set<String> = ["status.example.com"],
         skipPinningHosts: Set<String> = ["metrics.example.com"]) {
        let factory = ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()
        self.signer = ApproovDefaultMessageSigning().setDefaultFactory(factory)
        self.allowOfflineForHosts = allowOfflineForHosts
        self.skipPinningHosts = skipPinningHosts
    }

    func handleInterceptorFetchTokenResult(_ result: ApproovTokenFetchResult,
                                           url: String) throws -> Bool {
        let host = URL(string: url)?.host
        if (result.status == .noNetwork || result.status == .poorNetwork),
           let host = host,
           allowOfflineForHosts.contains(host) {
            return true
        }

        return try ApproovServiceMutatorDefault.shared
            .handleInterceptorFetchTokenResult(result, url: url)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest,
                                           changes: ApproovRequestMutations) throws -> URLRequest {
        var updated = try signer.handleInterceptorProcessedRequest(request, changes: changes)
        updated.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        return updated
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return true
        }
        return !skipPinningHosts.contains(host)
    }
}

ApproovServiceMutatorBridge.shared.serviceMutator = CustomLogic()
```

### Log rejections with ARC and device ID to your telemetry

An important part of your security strategy is to monitor and analyze rejections. Ideally, the server response would be customized to include the ARC and device ID in the response body or headers. However, if this is not possible, you can obtain these values from the `ApproovService` and log them to your telemetry directly from your application code.

```objective-c
NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                        completionHandler:^(NSData *data,
                                                            NSURLResponse *response,
                                                            NSError *error) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode >= 400) {
        NSString *arc = [ApproovService getLastARC];
        NSString *deviceID = [ApproovService getDeviceID];
        NSLog(@"Request rejected with ARC: %@, device ID: %@, status: %ld",
              arc, deviceID, (long)httpResponse.statusCode);
    }
}];
[task resume];
```

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

## Tips

- Keep mutator logic fast and side-effect safe. These hooks run on the request path.
- Use `ApproovServiceMutatorDefault.shared` to preserve the existing behavior and layer your changes on top.
- If you override multiple hooks, keep them focused for easier testing and maintenance.
- Use `addExclusionURLRegex:` for URL-level bypasses and `handlePinningShouldProcessRequest` for pinning-specific policy.
