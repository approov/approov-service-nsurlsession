# Changelog

## Unreleased - NSURLSession Service Layer Updates

This summarizes the current `nsurlsession-message-signing` branch updates since the `3.5.3` baseline.

### Added

- Added automatic HTTP message signing support for protected NSURLSession requests.
- Added configurable message signing modes for install and account signatures.
- Added optional and required request body digest handling for message signing.
- Added Swift support for message signing, including default signing behavior and service mutator bridging.
- Added status-token fallback support via `setUseApproovStatusIfNoToken`, allowing configured non-token Approov statuses to be sent in the token header when no token is available.
- Added NSURLSession service-layer logging controls aligned with URLSession behavior:
  - `ApproovLogLevelOff`
  - `ApproovLogLevelError`
  - `ApproovLogLevelWarning`
  - `ApproovLogLevelInfo`
  - `ApproovLogLevelDebug`
- Added local verification coverage for native service behavior, message signing behavior, mini-SDK contract behavior, and documentation/API consistency.

### Changed

- Merged the failure-reason/status-token work into `nsurlsession-message-signing`, so the message-signing branch now includes the latest failure-token and logging parity changes.
- Moved Swift support files out of the legacy `ApproovURLSession` folder into `ApproovNSURLSessionSwift`.
- Updated package source paths so the NSURLSession service layer uses the current Swift support folder layout.
- Updated service documentation with request lifecycle, mutator behavior, message signing, logging, pinning, and verification guidance.
- Removed the tracked `ApproovURLSession` folder from the active branch.

### Fixed

- Fixed service-layer behavior so allowed failure/status responses can be surfaced consistently when token generation does not return a normal Approov token.
- Fixed logging behavior so NSURLSession exposes the same practical log level controls as the URLSession service layer.
- Fixed Swift support packaging after removing the legacy URLSession folder.
- Addressed PR review issues around the public Swift API surface and safer message-signing utility behavior.

### Verification

The following local checks have passed on this branch:

- `tests/ios/run_native_tests.sh`
- `tests/ios/run_message_signing_tests.sh`
- `tests/ios/run_docs_audit.sh`
- `tests/ios/run_all_tests.sh`

The full backend replay and pinning integration tests require live integration environment variables such as `APPROOV_CONFIG`, `TESTING_REPLY_URL`, and `TESTING_REPLY_URL_PINNING_ONLY`.
