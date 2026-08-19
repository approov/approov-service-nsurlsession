# Changelog

## [3.5.5] - 2026-06-24

### Fixed

- Message signing now conforms to the fail-open policy (approov/core-project-approov#564). Every signature-build failure — building the signature base, retrieving or decoding the install/account signature, decoding the ES256 ASN.1/DER signature, or serializing the signature headers — now logs at error and proceeds **unsigned** instead of aborting the request, since the backend is the enforcement point. Only a **required body digest** that cannot be generated or serialized, and an **unsupported or missing signature algorithm**, still fail closed. A **non-required** body digest that cannot be generated or serialized now also fails open, and any signature headers already present on the request (`Signature`, `Signature-Input`, `Signature-Base-Digest`) plus any `Content-Digest` this layer added are removed on every fail-open path, so a request that proceeds unsigned carries no stale or uncovered signing artifacts.
- `setUserProperty` reported the bare `"approov-service-nsurlsession"` lock object instead of a versioned telemetry string; it now reports `approov-service-nsurlsession/<version>` (stamped from the release tag), so the active service-layer version is visible in server logs.
- `updateRequestWithApproov:...error:` wrote through the `error` out-parameter without a nil check in the header/query secure-string substitution paths; a caller passing `NULL` (permitted by the `_Nullable` annotation) would crash on a rejection or network failure. All such writes are now guarded.

### Changed

- Release versioning now uses `dev` placeholders on `main` (Package.swift `releaseTAG`, the podspec `s.version`, and the `setUserProperty` string). A manual `workflow_dispatch` release job stamps the CHANGELOG version into all three and tags that commit; `main` keeps the placeholders so branches inherit them.

### CI

- The release job now runs with `set -euo pipefail` and asserts that the version stamp produced a commit before tagging that exact SHA. Previously a failed `git commit` fell through to `git tag`, tagging the unstamped `HEAD`, pushing it, and still reporting success.
- `verify-release` now also asserts that both README dependency snippets reference the CHANGELOG's version. They are hand-edited rather than stamped, so they were the only version strings that could drift silently.
- **Note on scope:** the release job tags and pushes; SPM consumes tags directly, so SwiftPM releases are fully automated. Publishing the podspec to CocoaPods trunk is **not** automated here and remains a manual `pod trunk push` after the tag exists, since `main` deliberately keeps the `dev` placeholder and cannot be linted.

- Added a `verify-release` check (push/PR) asserting the CHANGELOG top entry and the `dev` placeholders are present, and a manual `release` job (gated on build-and-test) that stamps the version and tags. Tagging stays manual.

### Documentation

- `README.md` gains the two mandatory sections it was missing (`Manifest / Project Changes` and `Initializing ApproovService`), and the initialization example now shows the **empty-config bypass fallback** on failure, without which a failed initialization leaves the layer uninitialized rather than in bypass mode. Added the bundled Approov SDK badge and switched the SwiftPM badge to a live tag version.
- Corrected the hybrid Swift/Objective-C snippet: both `initialize` overloads are `void` with a trailing `NSError**`, so Swift imports them as **throwing** - the previously documented `error:` argument form does not exist.
- `REFERENCE.md` corrected on two contracts it described backwards: initialization state is reset only **after** SDK success, so a failed call leaves the previous state (including bypass mode) intact; and message-signing failures are fail-open as described above, rather than propagated as request failures.

- GitHub-style README: added status badges and an `initialize` failure-handling example (correlation/session id + `getDeviceID` logging on success, unprotected fallback on failure) and a note that initialization must succeed before any protected request. Documented the same on the `initialize` method.


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
- Fixed message-signing error propagation so required body digest failures and other non-SDK signing construction errors fail the request instead of silently forwarding it unsigned.
- Fixed `setApproovTokenPrefix:` so passing `nil` is normalized to an empty prefix rather than producing a `(null)` token header prefix.
- Fixed service-layer behavior so allowed failure/status responses can be surfaced consistently when token generation does not return a normal Approov token.
- Fixed logging behavior so NSURLSession exposes the same practical log level controls as the URLSession service layer.
- Fixed Swift support packaging after removing the legacy `ApproovURLSession` folder.
- Fixed RSA-3072 SPKI header construction: `rsa2048SPKIHeader` bytes were incorrectly used instead of `rsa3072SPKIHeader`, producing corrupt SPKI data for any RSA-3072 certificate and causing silent pinning failures for that key type.
- Fixed substitution header loop reading `prefix` from the original unlocked `substitutionHeaders` dictionary instead of from the already-captured thread-safe copy `subsHeaders`, eliminating a potential data race during concurrent `addSubstitutionHeader:` calls.
- Fixed `ApproovSessionTaskObserver`: replaced five `NSLog` calls with the appropriate `ApproovLog*` macros (`ApproovLogError`, `ApproovLogWarning`, `ApproovLogDebug`) so session task lifecycle events respect the configured service-layer log level rather than always emitting to the system log.
