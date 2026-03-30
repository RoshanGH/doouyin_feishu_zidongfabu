// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DouyinUploader",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "DouyinUploader",
            path: "Sources",
            resources: [
                .copy("Resources"),
                .copy("JS")
            ]
        ),
        .testTarget(
            name: "DouyinUploaderTests",
            dependencies: ["DouyinUploader"],
            path: "Tests"
        )
    ]
)
