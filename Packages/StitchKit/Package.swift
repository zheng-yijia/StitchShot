// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StitchKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "StitchCore", targets: ["StitchCore"]),
        .library(name: "PhotoLibraryKit", targets: ["PhotoLibraryKit"]),
        .library(name: "StitchEngine", targets: ["StitchEngine"]),
        .library(name: "ScrollCaptureKit", targets: ["ScrollCaptureKit"]),
        .library(name: "ImageEditorKit", targets: ["ImageEditorKit"])
    ],
    targets: [
        .target(name: "StitchCore"),
        .target(name: "PhotoLibraryKit", dependencies: ["StitchCore"]),
        .target(name: "StitchEngine", dependencies: ["StitchCore"]),
        .target(name: "ScrollCaptureKit", dependencies: ["StitchCore"]),
        .target(name: "ImageEditorKit", dependencies: ["StitchCore"]),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"]),
        .testTarget(name: "StitchEngineTests", dependencies: ["StitchEngine"]),
        .testTarget(name: "ImageEditorKitTests", dependencies: ["ImageEditorKit"])
    ]
)
