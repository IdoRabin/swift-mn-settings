// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MNSettings",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MNSettings",
            targets: ["MNSettings"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        
        // In-House pakcages
//        .package(url: "https://gitlab.com/ido_r_demos/MNUtils.git", from:"0.0.2"),
        .package(path: "../../MNUtils/MNUtils"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "MNSettings",
            dependencies: [
                // In-House pakcages
                .product(name: "MNUtils", package: "MNUtils"),
            ],
            swiftSettings: [
                // Enables better optimizations when building in Release
                // .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
                
                .define("PRODUCTION", .when(configuration: .release)),
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "MNSettingsTests",
            dependencies: ["MNSettings"],
            swiftSettings: [
                .define("DEBUG"),
                .define("TESTING"),
            ]
        ),
        
    ]
)
