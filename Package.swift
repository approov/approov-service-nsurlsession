// swift-tools-version:5.8
import Foundation
import PackageDescription

// The release tag for this version of ApproovNSURLSession.
let releaseTAG = "dev"

// Production Approov SDK package version used by the public library products.
let sdkVersion: Version = "3.5.3"
let productionApproovPackageName = "approov-ios-sdk"

// TESTING ONLY:
// The mini-SDK is a local test fixture from core-service-layers-testing. It is
// not a production dependency and must only be enabled by CI/local service-layer
// contract tests that set APPROOV_USE_MINI_SDK=1 and APPROOV_MINI_SDK_PATH.
let useMiniSDKForTests = ProcessInfo.processInfo.environment["APPROOV_USE_MINI_SDK"] == "1"
let testingMiniSDKPackageName = "mini-sdk-ios"
let testingMiniSDKPath = ProcessInfo.processInfo.environment["APPROOV_MINI_SDK_PATH"]
let approovPackageName = useMiniSDKForTests ? testingMiniSDKPackageName : productionApproovPackageName
let packagePlatforms: [SupportedPlatform] = [
    .iOS(.v11),
    .watchOS(.v9),
] + (useMiniSDKForTests ? [.macOS(.v13)] : [])

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0"),
]

if useMiniSDKForTests {
    // TESTING ONLY: replaces the production SDK because SwiftPM requires product
    // names to be unique and both packages expose a product named "Approov".
    guard let testingMiniSDKPath, !testingMiniSDKPath.isEmpty else {
        fatalError("APPROOV_MINI_SDK_PATH must be set when APPROOV_USE_MINI_SDK=1")
    }
    packageDependencies.append(.package(name: testingMiniSDKPackageName, path: testingMiniSDKPath))
} else {
    // Production dependency for public SPM consumers.
    packageDependencies.append(.package(url: "https://github.com/approov/approov-ios-sdk.git", exact: sdkVersion))
}

var packageTargets: [Target] = [
    .target(
        name: "ApproovNSURLSessionObjC",
        dependencies: [
            .product(name: "Approov", package: approovPackageName)
        ],
        path: "Sources/ApproovNSURLSessionObjC",
        cSettings: useMiniSDKForTests ? [.define("APPROOV_TESTING")] : nil
    ),
    .target(
        name: "ApproovNSURLSession",
        dependencies: [
            "ApproovNSURLSessionObjC",
            .product(name: "Approov", package: approovPackageName),
            .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
        ],
        path: "Sources/ApproovNSURLSession",
        exclude: ["util/sig/LICENSE"],
        swiftSettings: useMiniSDKForTests ? [.define("APPROOV_TESTING")] : nil
    )
]
if useMiniSDKForTests {
    packageTargets.append(
        .testTarget(
            name: "ApproovNSURLSessionMiniSDKObjCTests",
            dependencies: [
                "ApproovNSURLSession",
                "ApproovNSURLSessionObjC",
                .product(name: "Approov", package: testingMiniSDKPackageName),
                .product(name: "MiniSDKTestSupport", package: testingMiniSDKPackageName)
            ],
            path: "Tests/ApproovNSURLSessionMiniSDKObjCTests",
            cSettings: [.define("APPROOV_TESTING")]
        )
    )
    packageTargets.append(
        .testTarget(
            name: "ApproovNSURLSessionMiniSDKSwiftTests",
            dependencies: [
                "ApproovNSURLSession",
                "ApproovNSURLSessionObjC",
                // The mini SDK and its directive controller, so a Swift test can install a custom
                // service mutator AND steer the fetch results it has to react to. Without these the
                // Swift target could only test the mutator in isolation, never the interceptor path
                // that is supposed to consult it.
                .product(name: "Approov", package: testingMiniSDKPackageName),
                .product(name: "MiniSDKTestSupport", package: testingMiniSDKPackageName)
            ],
            path: "Tests/ApproovNSURLSessionMiniSDKSwiftTests"
        )
    )
}

let package = Package(
    name: "ApproovNSURLSession",
    platforms: packagePlatforms,
    products: [
        .library(
            name: "ApproovNSURLSession",
            targets: ["ApproovNSURLSessionObjC", "ApproovNSURLSession"]
        ),
        .library(
            name: "ApproovNSURLSessionDynamic",
            type: .dynamic,
            targets: ["ApproovNSURLSessionObjC", "ApproovNSURLSession"]
        )
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
