// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Galt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Galt",
            dependencies: ["whisper", "sherpa-onnx", "onnxruntime", "opus", "COpusShim"],
            path: "Sources/Galt",
            swiftSettings: [
                // 打开 sherpa-onnx 本地引擎（SenseVoice / Paraformer）真实实现
                .define("GALT_SHERPA"),
            ],
            linkerSettings: [
                // 静态库 libsherpa-onnx.a 依赖 C++ 运行时；onnxruntime 由 binaryTarget 提供
                .linkedLibrary("c++"),
            ]
        ),
        // whisper.cpp 官方预编译框架（Metal GPU 加速）
        .binaryTarget(
            name: "whisper",
            path: "Vendor/whisper.xcframework"
        ),
        // sherpa-onnx 官方预编译静态框架（v1.13.3，macOS universal2）
        .binaryTarget(
            name: "sherpa-onnx",
            path: "Vendor/sherpa-onnx.xcframework"
        ),
        // onnxruntime 1.24.4 动态库（osx-arm64），由 dylib 现场打包为 xcframework，SPM 负责嵌入与 rpath
        .binaryTarget(
            name: "onnxruntime",
            path: "Vendor/onnxruntime.xcframework"
        ),
        // libopus 静态库（osx-arm64，来自 Homebrew opus 1.6.1，BSD 许可）：火山上传走 Opus 压缩
        .binaryTarget(
            name: "opus",
            path: "Vendor/opus.xcframework"
        ),
        // libopus 的 C shim：包装 opus_encoder_ctl 这类变参函数供 Swift 调用，并自带 opus 头
        .target(
            name: "COpusShim",
            path: "Sources/COpusShim"
        ),
    ]
)
