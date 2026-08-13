// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DictateMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DictateMacCore", targets: ["DictateMacCore"]),
        .executable(name: "DictateMac", targets: ["DictateMac"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.1.0"
        )
    ],
    targets: [
        .target(name: "DictateMacCore"),
        .executableTarget(
            name: "DictateMac",
            dependencies: [
                "DictateMacCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .testTarget(
            name: "DictateMacCoreTests",
            dependencies: ["DictateMacCore"]
        )
    ]
)
