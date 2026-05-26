# Approov Service for NSURLSession 

A wrapper for the [Approov SDK](https://github.com/approov/approov-ios-sdk) to enable easy integration when using [`NSURLSession`](https://developer.apple.com/documentation/foundation/nsurlsession) for making the API calls that you wish to protect with Approov. In order to use this you will need a trial or paid [Approov](https://www.approov.io) account.

See the [Quickstart](https://github.com/approov/quickstart-ios-objectivec-nsurlsession) for usage instructions.

## Message Signing

Message signing is opt-in. Protected requests can be signed after the Approov token and any secure string substitutions have been applied:

```objective-c
[ApproovService setMessageSigningMode:ApproovMessageSigningModeInstall];
```

To use account message signing instead:

```objective-c
[ApproovService setMessageSigningMode:ApproovMessageSigningModeAccount];
```

The legacy `getMessageSignature:` method remains available as a compatibility alias for account message signing. New integrations should call `getAccountMessageSignature:` or `getInstallMessageSignature:` when generating signatures manually.

Requests with replayable bodies include a generated `Content-Digest` header in the signature base. You can require body digest generation, causing signing to be skipped if a body cannot be safely read:

```objective-c
[ApproovService setMessageSigningBodyDigestRequired:YES];
```

## Service Mutator

The Swift `ApproovServiceMutator` protocol is available for advanced integrations that need to customize interceptor behavior. The default mutator is `ApproovDefaultMessageSigning`, but Swift callers can replace it:

```swift
ApproovServiceMutatorBridge.shared.serviceMutator = MyApproovServiceMutator()
```

Custom mutators can decide whether to proceed after token fetch failures and can modify the final `URLRequest` after Approov has added its token.

## Token Fetch Status Header

If a request is allowed to proceed without an Approov token, or a token fetch returns no token, the service can place the token fetch status in the configured Approov token header. This is useful for demos and diagnostics where the backend needs to see why a token was not available:

```objective-c
[ApproovService setApproovTokenPrefix:@"Bearer "];
[ApproovService setUseApproovStatusIfNoToken:YES];
```

For example, if the SDK reports `MITM_DETECTED` and the mutator allows the request to proceed, the outgoing `Approov-Token` header becomes `Bearer MITM_DETECTED`. If the mutator blocks the request, no fallback token header is emitted.
