// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EPUBTranslator",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
    ],
    targets: [
        .executableTarget(
            name: "EPUBTranslator",
            dependencies: [
                "ZIPFoundation", 
                "SwiftSoup"
            ],
            path: "EPUBTranslator",
            exclude: [
                "Info.plist", 
                "EPUBTranslator.entitlements",
                "AppIcon.icns"
            ],
            swiftSettings: [
                .define("APPLE_SILICON_NATIVE"),
                .unsafeFlags(["-target", "arm64-apple-macosx27.0"])
            ]
        ),
    ]
)
