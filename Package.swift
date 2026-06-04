// swift-tools-version:5.8
import Foundation
import PackageDescription

// The release tag for this version of ApproovNSURLSession
let releaseTAG = "3.5.4"
// SDK package version (used for both iOS and watchOS)
let sdkVersion: Version = "3.5.3"
let useMiniSDK = ProcessInfo.processInfo.environment["APPROOV_USE_MINI_SDK"] == "1"
let miniSDKPath = ProcessInfo.processInfo.environment["APPROOV_MINI_SDK_PATH"] ?? "../core-service-layers-testing/mini-sdk/ios"

let approovPackageName = useMiniSDK ? "mini-sdk-ios" : "approov-ios-sdk"
let packagePlatforms: [SupportedPlatform] = [
    .iOS(.v11),
    .watchOS(.v9),
]

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0"),
]
if useMiniSDK {
    packageDependencies.append(.package(name: "mini-sdk-ios", path: miniSDKPath))
} else {
    packageDependencies.append(.package(url: "https://github.com/approov/approov-ios-sdk.git", exact: sdkVersion))
}

var packageTargets: [Target] = [
    .target(
        name: "ApproovNSURLSessionObjC",
        dependencies: [
            .product(name: "Approov", package: approovPackageName)
        ],
        path: "Sources/ApproovNSURLSessionObjC"
    ),
    .target(
        name: "ApproovNSURLSession",
        dependencies: [
            "ApproovNSURLSessionObjC",
            .product(name: "Approov", package: approovPackageName),
            .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
        ],
        path: "Sources/ApproovNSURLSession",
        exclude: ["util/sig/LICENSE"]
    )
]

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
