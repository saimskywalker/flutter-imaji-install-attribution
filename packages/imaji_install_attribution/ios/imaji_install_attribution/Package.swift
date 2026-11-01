// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "imaji_install_attribution",
    platforms: [
        // Flutter's own minimum. AdServices (iOS 14.3+) is always present.
        .iOS("15.0")
    ],
    products: [
        .library(name: "imaji-install-attribution", targets: ["imaji_install_attribution"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "imaji_install_attribution",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AdServices")
            ]
        )
    ]
)
