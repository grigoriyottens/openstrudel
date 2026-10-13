// swift-tools-version: 6.0
import PackageDescription

// The same pinned runtime used by OpenRamble, with Mac, iOS and Simulator slices.
let package = Package(
    name: "ParakeetRuntime",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "ParakeetRuntime", targets: ["CTranscribe"])],
    targets: [.binaryTarget(
        name: "CTranscribe",
        url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.3/TranscribeCpp.xcframework.zip",
        checksum: "944be4d5232f39c99608f676a2ddda2516e0ed3c9fb6db50685ffa8d20a8b9c9"
    )]
)
