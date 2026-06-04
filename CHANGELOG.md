# Changelog

## [3.5.4] - 2026-05-28

### Added

- Added automatic HTTP message signing support for protected NSURLSession requests.
- Added configurable message signing modes for install and account signatures (`ApproovMessageSigningModeDisabled`, `ApproovMessageSigningModeInstall`, `ApproovMessageSigningModeAccount`).
- Added optional and required request body digest handling for message signing via `setMessageSigningBodyDigestEnabled:` and `setMessageSigningBodyDigestRequired:`.
- Added Swift `ApproovServiceMutatorBridge` for custom mutator support, message signing integration, and pinning decision delegation.
- Added status-token fallback support via `setUseApproovStatusIfNoToken:`, allowing configured non-token Approov statuses to be sent in the token header when no token is available.
- Added `isInitialized` and `isApproovEnabled` to distinguish bypass mode (initialized but no SDK protection) from active Approov protection.
- Added service-layer logging controls: `setLoggingLevel:` / `getLoggingLevel` with levels `ApproovLogLevelOff`, `ApproovLogLevelError`, `ApproovLogLevelWarning`, `ApproovLogLevelInfo` (default), and `ApproovLogLevelDebug`.
- Added `getAccountMessageSignature:` and `getInstallMessageSignature:` for explicit per-key-type signing.
- Added `setApproovTraceIDHeader:` / `getApproovTraceIDHeader` for trace ID header control.

### Changed

- Simplified `initialize:comment:error:` — removed all service-layer re-initialization guards (`reinit`/`options:` comment prefix checks, same-config short-circuit, different-config early error). The service layer now forwards the config to the platform SDK and only resets internal state on success.
- Restores the empty-config reinitialization bypass guard (ignoring empty config after valid config).
- Automatically resets the custom service mutator back to the default mutator on any successful initialization.
- Moved Swift support files out of the legacy `ApproovURLSession` folder into `ApproovNSURLSessionSwift`.
- Updated package source paths to reflect the current Swift support folder layout.
- Updated REFERENCE.md with request lifecycle, mutator behavior, message signing, logging, pinning, and initialization contract documentation.

### Deprecated

- `setProceedOnNetworkFailure:` is now a no-op and logs a deprecation warning. Network failure behavior should be controlled via `ApproovServiceMutatorBridge`. The method is retained for source compatibility only.
- `getMessageSignature:` is deprecated in favour of `getAccountMessageSignature:` or `getInstallMessageSignature:`.
- `prefetch` is obsolete; the native SDK manages prefetching automatically after initialization.

### Fixed

- Fixed `initialize:comment:error:` to correctly capture and log the platform SDK boolean return (`NO` = already initialized with same config, treated as success).
- Fixed `setProceedOnNetworkFailure:` behavior: network failures are now always fail-closed. Callers relying on the old allow-through behavior must migrate to a custom `ApproovServiceMutator`.
- Fixed message signing: signing is now skipped for non-success token fetch paths. Signing requires token artifacts (the public key for install signing; the `mksid` for account signing) that are only available on a successful token fetch. A backend receiving a request with no Approov token has no key material to verify any signature.
- Fixed service-layer behavior so allowed failure/status responses can be surfaced consistently when token generation does not return a normal Approov token.
- Fixed logging behavior so NSURLSession exposes the same practical log level controls as the URLSession service layer.
- Fixed Swift support packaging after removing the legacy `ApproovURLSession` folder.
- Fixed RSA-3072 SPKI header construction: `rsa2048SPKIHeader` bytes were incorrectly used instead of `rsa3072SPKIHeader`, producing corrupt SPKI data for any RSA-3072 certificate and causing silent pinning failures for that key type.
- Fixed substitution header loop reading `prefix` from the original unlocked `substitutionHeaders` dictionary instead of from the already-captured thread-safe copy `subsHeaders`, eliminating a potential data race during concurrent `addSubstitutionHeader:` calls.
- Fixed `ApproovSessionTaskObserver`: replaced five `NSLog` calls with the appropriate `ApproovLog*` macros (`ApproovLogError`, `ApproovLogWarning`, `ApproovLogDebug`) so session task lifecycle events respect the configured service-layer log level rather than always emitting to the system log.
