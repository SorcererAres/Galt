// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Galt",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Galt",
            dependencies: ["whisper"],
            path: "Sources/Galt"
        ),
        // whisper.cpp 官方预编译框架（Metal GPU 加速）
        .binaryTarget(
            name: "whisper",
            path: "Vendor/whisper.xcframework"
        ),
    ]
)
