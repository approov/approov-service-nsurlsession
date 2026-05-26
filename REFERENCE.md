# Approov NSURLSession Service Layer Reference

This document describes the public contract for the NSURLSession service layer. It is intended to mirror the common service-layer interface used by the shared testing requirements while naming the Objective-C and Swift APIs exposed by this repository.

## Lifecycle and State

### `+initialize:error:`

Initializes the service layer with a non-empty Approov configuration string and enables Approov protection when the native SDK accepts the configuration.

```objective-c
NSError *error = nil;
[ApproovService initialize:configString error:&error];
```

### `+initialize:comment:error:`

Initializes the service layer with an optional comment. The comment is forwarded to the native SDK for supported flows such as `options:...` during first initialization or `reinit...` during supported runtime reinitialization.

```objective-c
NSError *error = nil;
[ApproovService initialize:configString comment:@"reinit:policy-refresh" error:&error];
```

Passing an empty config string enters empty-config bypass mode. In this mode `isInitialized` returns true, `isApproovEnabled` returns false, and the service layer behaves as a normal NSURLSession wrapper without token injection, trace headers, message signing, secure string substitution, secure string fetches, custom JWT fetches, dynamic pinning, or other native Approov SDK calls. All public methods that would otherwise call the platform SDK are guarded in this disabled mode.

An empty-config bootstrap may later be upgraded by calling `initialize` again with a valid non-empty config string. If a non-empty initialization fails after empty-config bypass, the service layer remains initialized but disabled.

### `+isInitialized`

Returns whether the service layer has completed initialization. This returns true for both active Approov protection and empty-config bypass mode.

### `+isApproovEnabled`

Returns whether the native Approov SDK is active and Approov protection is enabled. This returns false before initialization and in empty-config bypass mode.

## Token and Header Configuration

### `+setApproovTokenHeader:` and `+getApproovTokenHeader`

Sets and gets the header used for Approov tokens. The default is `Approov-Token`.

### `+setApproovTokenPrefix:` and `+getApproovTokenPrefix`

Sets and gets the optional prefix placed before the Approov token value. For example, setting `Bearer ` makes the emitted header value `Bearer <token>`.

### `+setApproovTraceIDHeader:` and `+getApproovTraceIDHeader`

Sets and gets the trace ID header used when the SDK returns a trace ID. Pass an empty value to disable trace header emission.

### `+setBindingHeader:` and `+getBindingHeader`

Configures automatic token binding. For protected requests, the service layer reads the named header from the request or from the session configuration's additional headers and forwards that header value to the SDK with `setDataHashInToken`. The request header itself is not modified. If the header is present but empty, the empty value is forwarded. If the header is absent, no data hash is set for that request.

### `+setDataHashInToken:`

Manually sets token binding data for the next token fetch. Use this when automatic request-header binding is not suitable. Manual binding and automatic binding must not be mixed for the same request path: choose either `setBindingHeader` or explicit `setDataHashInToken` and keep the backend validation model consistent.

### `+setUseApproovStatusIfNoToken:`

When enabled, a request that is allowed to proceed without a real Approov token, or a token fetch that returns an empty token, can carry the token fetch status string in the configured token header. This is useful for diagnostics and backend replay evidence. A custom mutator can still block the request before this fallback header is emitted.

## Request Exclusion and Substitution

### `+addExclusionURLRegex:` and `+removeExclusionURLRegex:`

Adds or removes a regular expression used to skip Approov request mutation. A matching URL is forwarded without token headers, trace headers, message signing, or secure string substitution. Exclusion only controls request mutation; a protected host can still exercise the TLS pinning path.

### `+addSubstitutionHeader:requiredPrefix:` and `+removeSubstitutionHeader:`

Registers or removes a header for secure string substitution. The header value is used as the secure string key, optionally after the required prefix. If a secure string resolves to an empty value, the original placeholder remains in place.

### `+addSubstitutionQueryParam:` and `+removeSubstitutionQueryParam:`

Registers or removes a query parameter key for secure string substitution. Substitution removal is immediate and affects subsequent requests.

## Attestation and Token Fetch APIs

### `+precheck:`

Performs a development-time verification check by fetching the `UNKNOWN_KEY` secure string and treating the expected unknown-key response as success. Use `precheck()` during development or diagnostics, not as a runtime health check on every app launch.

### `+fetchToken:error:`

Fetches an Approov token for a URL when automatic interception is not suitable. Returned tokens must never be cached; fetch a fresh token for each protected operation that needs one.

### `+getDeviceID`

Returns the Approov device ID for the current app installation when Approov is enabled. In empty-config bypass mode this returns without calling the native SDK.

### `+getLastARC`

Returns the last Attestation Response Code from the SDK when Approov is enabled. Prefer server-side ARC delivery where possible, and treat this value as diagnostic evidence rather than a primary authorization signal.

### `+setDevKey:`

Sets a development key for simulator or development testing. Development keys must not be used in production builds.

### `+setInstallAttrsInToken:`

Sets install attributes to be included in subsequent token fetches when supported by the SDK.

## Secure Strings and Custom JWT

### `+fetchSecureString:newDef:error:`

Fetches, defines, or deletes a secure string. Pass `nil` for `newDef` to fetch, a value to define, or an empty string to delete according to the native SDK contract. Returned secure strings must not be cached longer than necessary.

### `+fetchCustomJWT:error:`

Fetches a custom JWT for the supplied JSON payload string. The caller is responsible for supplying valid JSON and handling SDK errors such as rejection, network failure, disabled service, or malformed payload.

## Message Signing

### `+setMessageSigningMode:` and `+getMessageSigningMode`

Configures automatic message signing for protected requests. Supported modes are:

- `ApproovMessageSigningModeDisabled`
- `ApproovMessageSigningModeInstall`
- `ApproovMessageSigningModeAccount`

Message signing is applied after token injection and secure string substitution. If signing fails, the request proceeds with the Approov mutation that was already applied, but without signature headers.

### `+setMessageSigningBodyDigestEnabled:` and `+getMessageSigningBodyDigestEnabled`

Controls whether repeatable request bodies may receive a `Content-Digest` header for message signing. Body digest generation is enabled by default.

### `+setMessageSigningBodyDigestRequired:` and `+getMessageSigningBodyDigestRequired`

Controls strict body digest enforcement. When required, signed requests that do not expose a repeatable body fail closed for signing rather than silently signing without a digest. Streaming or one-shot bodies cannot be pre-digested without buffering and should be treated carefully.

### `+getAccountMessageSignature:`

Returns a signature using the account message-signing key.

### `+getInstallMessageSignature:`

Returns a signature using the install message-signing key.

### `+getMessageSignature:`

Deprecated compatibility alias for account message signing. New code should call `getAccountMessageSignature:` or `getInstallMessageSignature:` explicitly.

## Service Mutator and Decision Override

The Swift `ApproovServiceMutator` protocol provides the mutator API for this service layer. Swift callers install a custom mutator through:

```swift
ApproovServiceMutatorBridge.shared.serviceMutator = MyApproovServiceMutator()
```

Use `ApproovServiceMutatorBridge.shared.resetServiceMutator()` to restore the default mutator. The default mutator is fail-closed except for successful token fetches and documented allowed no-service fallback paths. Custom mutators can override token-fetch decisions, modify the final URLRequest after Approov processing, observe request mutation metadata, and decide whether pinning should process a request through `handlePinningShouldProcessRequest`.

Objective-C integrations normally use the default bridge behavior. Advanced Objective-C projects that need a custom mutator should provide the Swift bridge in their app target and expose the required configuration to Objective-C.

## Pinning and NSURLSession

Use `ApproovNSURLSession` to create sessions that apply Approov request mutation and dynamic pinning.

```objective-c
NSURLSession *session = [ApproovNSURLSession sessionWithConfiguration:
    [NSURLSessionConfiguration defaultSessionConfiguration]];
```

Dynamic pins are fetched and applied by the native SDK. Valid pins allow the TLS handshake to continue. Invalid pins abort the connection. Pinning-only protection applies TLS pin validation without adding an Approov token, trace ID, or message signature. Excluded protected URLs skip request mutation only; they still use the pinned session delegate unless a custom pinning mutator elects to skip pinning for that request.

When SDK configuration changes include new pins, the service layer must use the updated pin set on subsequent handshakes. Integration tests should prove valid pins, invalid pins, accept-any pins, pinning-only policy, excluded protected URLs that still pin, and dynamic pin update behavior against real TLS endpoints.

## Obsolete, Deprecated, and Unsupported APIs

### `+prefetch`

Obsolete. The native SDK manages prefetching automatically after initialization. This method remains for source compatibility.

### `+setProceedOnNetworkFailure:`

Obsolete. Prefer the Swift `ApproovServiceMutator` decision override API for status-specific allow/block behavior. This method remains for source compatibility.

### Legacy mutator aliases

Legacy names such as `setApproovInterceptorExtensions` or `setServiceMutator` from other service layers map conceptually to the Swift `ApproovServiceMutatorBridge.shared.serviceMutator` property in this repository.

### Logging

The service layer exposes `+setLoggingLevel:` and `+getLoggingLevel` to control service-layer diagnostics independently from SDK/account diagnostics. Supported levels are `ApproovLogLevelOff`, `ApproovLogLevelError`, `ApproovLogLevelWarning`, `ApproovLogLevelInfo`, and `ApproovLogLevelDebug`.

The default is `ApproovLogLevelInfo`, which keeps request outcome diagnostics visible while suppressing debug-level configuration chatter. Set `ApproovLogLevelError` or `ApproovLogLevelOff` in production when routine token, substitution, and pinning diagnostics should be suppressed. Set `ApproovLogLevelDebug` only for development or integration evidence because it includes configuration changes and detailed pin matching events.
