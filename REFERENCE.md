# Approov NSURLSession Service Layer Reference

This document describes the public contract for the NSURLSession service layer. It is intended to mirror the common service-layer interface used by the shared testing requirements while naming the Objective-C and Swift APIs exposed by this repository.

## Lifecycle and State

### `+initialize:error:`

Initializes the service layer using the 2-argument form. Equivalent to `+initialize:comment:error:` with a `nil` comment.

```objective-c
NSError *error = nil;
[ApproovService initialize:configString error:&error];
```

### `+initialize:comment:error:`

Initializes the service layer and optionally the native Approov SDK. On every call the service layer resets all internal state before forwarding to the SDK — there are no service-layer same-config or reinit guards. The SDK itself determines whether a repeated initialization is compatible and returns `NO` with a `nil` error when it was already initialized with the same configuration. Any real failure (different-config conflict, malformed config, SDK error, or a missing runtime bridge) produces a non-nil `NSError` and leaves the service layer uninitialized.

```objective-c
NSError *error = nil;
[ApproovService initialize:configString comment:nil error:&error];
if (error != nil) {
    // initialization failed — service layer is uninitialized
}
```

#### Bridge Lookup Failures (Hybrid Architecture)

Due to the hybrid Swift/Objective-C architecture of the `approov-service-nsurlsession` service layer itself, the Objective-C core (`ApproovService`) relies on dynamic class lookup (`NSClassFromString(@"ApproovServiceMutatorBridge")`) to load request mutation and decision logic from the Swift module. This class lookup can fail at runtime in 3 concrete scenarios:
1. **Dead Code Stripping**: The linker strips the Swift target (`ApproovNSURLSession`) or its classes because no Swift symbols are statically/directly referenced in the application source code.
2. **Target Misconfiguration / Missing Linkage**: The main application target is not configured to link against the Swift product target `ApproovNSURLSession` or package library.
3. **Missing `@objc` Attribute**: Swift runtime namespacing prevents `NSClassFromString` from resolving the class name if the `@objc(ApproovServiceMutatorBridge)` decorator is missing or removed from the Swift source.

#### Production Fail-Safe Recommendation

> [!WARNING]
> Crashing the application due to an initialization failure would render a released production application unusable. If this is a released production application, the recommended option is to handle any initialization error by logging the error to your telemetry and safely continuing execution without Approov protection.
> 
> Because initialization did not complete, `isInitialized` and `isApproovEnabled` evaluate to `NO`. In this state, all subsequent requests made via `ApproovNSURLSession` will automatically bypass Approov protection and proceed unprotected, keeping the application functional for your users.

**`config` parameter:** Pass a non-empty Approov configuration string for full SDK protection, or `@""` for empty-config bypass mode. The parameter is `_Nonnull`; passing `nil` is a compile-time error.

**`comment` parameter:** Forwarded to the native SDK as-is. `nil` and `@""` are semantically distinct at the native SDK level and must not be substituted for each other. Pass `nil` for a standard initialization. Use a `reinit...` comment for supported runtime re-initialization flows.

Passing an empty config string enters empty-config bypass mode. In this mode `isInitialized` returns true, `isApproovEnabled` returns false, and the service layer behaves as a normal NSURLSession wrapper without token injection, trace headers, message signing, secure string substitution, secure string fetches, custom JWT fetches, dynamic pinning, or other native Approov SDK calls. All public methods that would otherwise call the platform SDK are guarded in this disabled mode.

An empty-config bootstrap may later be upgraded by calling `initialize` again with a valid non-empty config string. If a non-empty initialization fails after an empty-config bypass, the service layer becomes uninitialized. Callers must re-initialize before using the service layer again.

### Re-initialization advisory

Once the service layer is initialized with a valid configuration, re-initializing with the same configuration is unnecessary. The native SDK is a process singleton and its state does not change on repeated same-config calls. Calling `initialize:` while requests are in flight resets the service layer's substitution headers, exclusion URLs, and task observer, which may cause concurrent requests to lose header substitutions or to proceed without an Approov token. The one intended upgrade path is from empty-config bypass mode to a valid configuration — for example, when a configuration string becomes available after app launch. This transition is safe because no tasks are tracked and no swizzle is in place during bypass mode.

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

Message signing is applied after token injection and secure string substitution, **only when the token fetch returns a `Success` status**. A non-success fetch (such as a network failure that the mutator allows through) does not produce signing because the required token artifacts — the public key embedded in the Approov token for install signing, or the `mksid` for account signing — are only available on a successful fetch. Without those artifacts the backend has no key material to verify any signature. If the SDK cannot provide an install or account signature, the request proceeds unsigned and the backend decides whether to accept it. Other signing failures, including required body digest failures, unsupported signing algorithms, ASN.1 decode failures, or header serialization failures, are propagated as request failures.

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

Deprecated. This method is now a no-op and logs a deprecation warning. It has no effect on request behavior. Use the Swift `ApproovServiceMutator` decision override API for status-specific allow/block behavior. Network failures are fail-closed by default and can be overridden only through a custom mutator.

### Legacy mutator aliases

Legacy names such as `setApproovInterceptorExtensions` or `setServiceMutator` from other service layers map conceptually to the Swift `ApproovServiceMutatorBridge.shared.serviceMutator` property in this repository.

### Logging

The service layer exposes `+setLoggingLevel:` and `+getLoggingLevel` to control service-layer diagnostics independently from SDK/account diagnostics. Supported levels are `ApproovLogLevelOff`, `ApproovLogLevelError`, `ApproovLogLevelWarning`, `ApproovLogLevelInfo`, and `ApproovLogLevelDebug`.

The default is `ApproovLogLevelInfo`, which keeps request outcome diagnostics visible while suppressing debug-level configuration chatter. Set `ApproovLogLevelError` or `ApproovLogLevelOff` in production when routine token, substitution, and pinning diagnostics should be suppressed. Set `ApproovLogLevelDebug` only for development or integration evidence because it includes configuration changes and detailed pin matching events.
