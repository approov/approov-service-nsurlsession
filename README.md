# Approov Service for NSURLSession

![Swift Package Manager](https://img.shields.io/github/v/tag/approov/approov-service-nsurlsession?logo=swift&logoColor=white&label=SwiftPM)
![CocoaPods](https://img.shields.io/cocoapods/v/approov-service-nsurlsession?logo=cocoapods&logoColor=white&label=CocoaPods)
![Platform](https://img.shields.io/badge/platform-iOS%2011%2B%20%7C%20watchOS%209%2B-lightgrey?logo=apple&logoColor=white)
![Approov SDK](https://img.shields.io/badge/Approov%20SDK-3.5.3-6f42c1?logo=apple&logoColor=white)
![Message Signing](https://img.shields.io/badge/Message%20Signing-RFC%209421-1f6feb)
![Build](https://github.com/approov/approov-service-nsurlsession/actions/workflows/build_and_test.yml/badge.svg)

A wrapper for the [Approov SDK](https://github.com/approov/approov-ios-sdk) to enable easy integration when using [`NSURLSession`](https://developer.apple.com/documentation/foundation/nsurlsession) for making the API calls that you wish to protect with Approov. If this is not your situation then check if there is a more relevant [quickstart guide](https://approov.io/docs/latest/approov-integration-examples/backend-api/) available.

This page provides all the steps for integrating Approov into your app. Additionally, a step-by-step tutorial guide using our [Shapes App Example](https://github.com/approov/quickstart-ios-objectivec-nsurlsession/blob/master/SHAPES-EXAMPLE.md) is also available.

To follow this guide you should have received an onboarding email for a trial or paid [Approov](https://www.approov.io) account.

Note that the minimum requirements are iOS 11 and watchOS 9. You cannot use Approov in apps that support platform versions older than these.

## Adding the Approov Service Dependency

### CocoaPods

> **CocoaPods is end of life.** New integrations should use [Swift Package Manager](#swift-package-manager)
> below. CocoaPods releases of this layer are published manually and remain available for existing
> integrations.

The Approov integration is available via [`CocoaPods`](https://cocoapods.org/). This allows inclusion into the project by simply specifying a dependency in the `Podfile` for the app:

```
target 'YourApplication' do
    use_frameworks!
    platform :ios, '11.0'
    pod 'approov-service-nsurlsession', '3.5.5'
end
```

Then install the dependency:

```bash
pod install
```

After installation, open the generated `.xcworkspace` file in Xcode rather than the original `.xcodeproj`.

### Swift Package Manager

Alternatively, you can add the dependency using Swift Package Manager. Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/approov/approov-service-nsurlsession.git", from: "3.5.5"),
]
```

Or add it via Xcode: File → Add Package Dependencies → enter `https://github.com/approov/approov-service-nsurlsession.git`.

This package is an open source wrapper layer that allows you to easily use Approov with `NSURLSession`. This has a further dependency to the closed source [Approov SDK](https://github.com/approov/approov-ios-sdk).

## Manifest / Project Changes

The Approov SDK is distributed as an `xcframework` and needs no manual embedding: both the CocoaPods
and Swift Package Manager integrations above pull it in as a transitive dependency
([`approov-ios-sdk`](https://github.com/approov/approov-ios-sdk)), and it is code-signed by Approov.

| Requirement | Value |
|---|---|
| Minimum deployment target | iOS 11, watchOS 9 |
| Bundled Approov SDK | 3.5.3 (SwiftPM pins it exactly; CocoaPods allows `~> 3.5.3`) |
| Swift toolchain | 5.9 or later |
| Networking entitlement | none beyond the standard outbound network access an app already has |

No `Info.plist` keys, capabilities or App Transport Security exceptions are required. Pinning is
applied at runtime from the Approov account configuration, so do **not** add `NSPinnedDomains`.

If your app is a mixed Swift and Objective-C target consuming the package through SwiftPM, read
[Hybrid App Module Conflict Warning](#hybrid-app-module-conflict-warning-spm) before writing the
initialization call: the module-qualified form differs.

## Initializing ApproovService

`ApproovService` must be initialized **before any network request** is made through
`ApproovNSURLSession`. Initialize it once at app startup. The configuration string parameter is a
custom string that configures your Approov account access, provided in your Approov onboarding email
(it looks like `#123456#K/XPlLtfcwnWkzv99Wj5VmAxo4CrU267J1KlQyoz8Qo=`).

Check the `error` out-parameter. On success, confirm the layer is enabled and log the Approov device
ID together with an app-generated session or correlation id, so a given install can be correlated
across your app logs, your backend and the Approov metrics. On failure, log the event and then
**re-initialize with an empty configuration string** to enter bypass mode explicitly: the service
stays usable and every request goes out unprotected, with the backend remaining the enforcement
point. Without that second call the service is left uninitialized rather than in bypass mode.

```ObjectiveC
#import "ApproovNSURLSession.h"

// App-generated id to correlate this install/session across your own logs and
// backend. Use a UUID, or any session/user identifier you have — NOT an Approov secret.
NSString *correlationId = [[NSUUID UUID] UUIDString];

NSError *error = nil;
[ApproovService initialize:@"<enter-your-config-string-here>" error:&error];
if (error != nil) {
    // Initialization failed. Log it, then enter bypass mode explicitly so the app still works;
    // requests then go out without Approov protection.
    NSLog(@"Approov init failed (session=%@); continuing unprotected: %@", correlationId, error.localizedDescription);
    NSError *bypassError = nil;
    [ApproovService initialize:@"" error:&bypassError];
    if (bypassError != nil) {
        NSLog(@"Approov bypass-mode initialization also failed (session=%@): %@", correlationId, bypassError.localizedDescription);
    }
} else if ([ApproovService isApproovEnabled]) {
    NSLog(@"Approov initialized; deviceID=%@ session=%@", [ApproovService getDeviceID], correlationId);
}

NSURLSession *defaultSession = [ApproovNSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
```

> Swift callers use `try ApproovService.initialize("<config>")` inside a `do/catch`, and on failure
> call `try? ApproovService.initialize("")` to enter bypass mode. On success log
> `ApproovService.getDeviceID()` with your correlation id. In mixed Swift/Objective-C apps see
> [Hybrid App Module Conflict Warning](#hybrid-app-module-conflict-warning-spm) for the
> module-qualified call.

## Using ApproovNSURLSession

The `ApproovNSURLSession` class mimics the interface of the `NSURLSession` class provided by Apple but includes Approov protection. The simplest way to use `ApproovNSURLSession` is to find and replace all the `NSURLSession` with `ApproovNSURLSession`.

Initialize `ApproovService` first, once at app startup, as shown in
[Initializing ApproovService](#initializing-approovservice) above.

```ObjectiveC
#import "ApproovNSURLSession.h"

NSURLSession *defaultSession = [ApproovNSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
```

For API domains that are configured to be protected with an Approov token, this adds the `Approov-Token` header and pins the connection. This may also substitute header values when using secrets protection.

## Checking It Works

Initially you won't have set which API domains to protect, so the interceptor will not add anything. It will have called Approov though and made contact with the Approov cloud service. You will see logging from Approov saying `UNKNOWN_URL`.

Your Approov onboarding email should contain a link allowing you to access [Live Metrics Graphs](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs). After you've run your app with Approov integration you should be able to see the results in the live metrics within a minute or so. At this stage you could even release your app to get details of your app population and the attributes of the devices they are running upon.

## Next Steps

To actually protect your APIs and/or secrets there are some further steps. Approov provides two different options for protection:

* [API PROTECTION](https://github.com/approov/quickstart-ios-objectivec-nsurlsession/blob/master/API-PROTECTION.md): You should use this if you control the backend API(s) being protected and are able to modify them to ensure that a valid Approov token is being passed by the app. An [Approov Token](https://approov.io/docs/latest/approov-usage-documentation/#approov-tokens) is short lived cryptographically signed JWT proving the authenticity of the call.

* [SECRETS PROTECTION](https://github.com/approov/quickstart-ios-objectivec-nsurlsession/blob/master/SECRETS-PROTECTION.md): This allows app secrets, including API keys for 3rd party services, to be protected so that they no longer need to be included in the released app code. These secrets are only made available to valid apps at runtime.

Note that it is possible to use both approaches side-by-side in the same app.

See [REFERENCE](https://github.com/approov/approov-service-nsurlsession/blob/main/REFERENCE.md) for a complete list of all of the `ApproovService` methods, [USAGE](https://github.com/approov/approov-service-nsurlsession/blob/main/USAGE.md) for detailed usage examples, and [CHANGELOG](https://github.com/approov/approov-service-nsurlsession/blob/main/CHANGELOG.md) for version history.

## Delegates

The `ApproovNSURLSession` implementation supports network delegates in much the same way the `NSURLSession` class does with one exception: we do not support a task specific delegate since we already implement a session delegate. Unfortunately, this means if you need to use a task specific delegate in order to provide specific authentication, like this:

```ObjectiveC
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
    NSURLCredential *credential))completionHandler;
```

it will not be called. Instead, you can use the session level delegate:

```ObjectiveC
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
    NSURLCredential *credential))completionHandler
```

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

Requests with replayable bodies include a generated `Content-Digest` header in the signature base. You can require body digest generation, causing the request to fail if a required digest cannot be safely generated:

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

## Hybrid App Module Conflict Warning (SPM)

If you are developing a hybrid app (for instance, you are migrating an existing Objective-C app that uses `NSURLSession` to Swift/URLSession, or are using both service layers simultaneously) and integrate both the [`approov-service-nsurlsession`](https://github.com/approov/approov-service-nsurlsession) and [`approov-service-urlsession`](https://github.com/approov/approov-service-urlsession) libraries using Swift Package Manager, you will encounter a class name collision because both libraries define a class named `ApproovService`.

### The Issue
Due to Swift Package Manager and the Swift compiler's bridging rules, if you call `ApproovService.initialize(...)` without a module prefix, the compiler may resolve `ApproovService` to `ApproovURLSessionPackage.ApproovService` (the Swift URLSession layer's own class) instead of `ApproovNSURLSessionObjC.ApproovService`, since both modules export that name.

### Consequences
If the compiler resolves `ApproovService` to the Swift URLSession module's class, the Objective-C `ApproovService` remains uninitialized (`isInitialized` remains `NO`). Consequently, any requests made through `ApproovNSURLSession` will silently bypass all Approov protections (no tokens will be fetched or injected, no message signing will occur, and dynamic pinning will be skipped).

### Solution
To prevent this, you must explicitly qualify all references to the Objective-C service layer class in your Swift code by using the `ApproovNSURLSessionObjC` module prefix:

```swift
import ApproovNSURLSession
import ApproovNSURLSessionObjC
import ApproovURLSessionPackage

// Initialize the Objective-C service layer. Both initializers are declared as `void` with a
// trailing NSError** out-parameter, so Swift imports them as THROWING - there is no `error:`
// argument to pass. On failure, enter bypass mode explicitly (see Initializing ApproovService).
do {
    try ApproovNSURLSessionObjC.ApproovService.initialize("YOUR_CONFIG_STRING")
} catch {
    print("Approov init failed, continuing unprotected: \(error)")
    try? ApproovNSURLSessionObjC.ApproovService.initialize("")
}

// Enable message signing in the Objective-C layer
ApproovNSURLSessionObjC.ApproovService.setMessageSigningMode(.install)

// Add substitution headers in the Objective-C layer
ApproovNSURLSessionObjC.ApproovService.addSubstitutionHeader("Api-Key", requiredPrefix: "")
```
