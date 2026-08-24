// swift-tools-version: 6.0

// The core, as one download.
//
// This package holds no source. It names a zip on the depot and the checksum of that
// zip. SwiftPM fetches it when Xcode resolves the project. Inside is janitor-app
// compiled for both Mac architectures, with the UniFFI-generated Swift compiled in, so
// `import JanitorKit` reaches the real Rust worker.
//
// It is a package rather than an .xcframework in the project because a remote binary is
// something only SwiftPM fetches. An Xcode target links an .xcframework it can already
// see on disk, and nothing else.
//
// WHY THIS IS NOT A DEPENDENCY ON THE CORE'S REPOSITORY
//
// Xcode would clone Circuit-Stitch/Janitor and find a Cargo workspace. Building it needs
// a Rust toolchain, and it would compile the AWS SDK and aws-lc-sys from cold on every
// clean build. Xcode Cloud has no cargo cache. Fetching one zip is what keeps the Rust
// out of the Apple build entirely (ADR 0035).
//
// WORKING AGAINST A LOCAL BUILD
//
// Set JANITORKIT_LOCAL=1 and the package points at the sibling Janitor checkout instead:
//
//     cd ../Janitor && ./scripts/build-xcframework.sh
//     JANITORKIT_LOCAL=1 xcodegen generate
//     JANITORKIT_LOCAL=1 xcodebuild -scheme Janitor …
//
// That is how the boundary is widened and the shell is fixed up in one pass, without a
// publish between every change. It needs Janitor checked out beside this repository.
//
// UPDATING THE VERSION
//
//   1. Tag kit-v<version> in Circuit-Stitch/Janitor.
//   2. The publish workflow prints the checksum of the bytes it published.
//   3. Put the version and that checksum below, and commit.
//
// A version is published once and never overwritten, so the two lines below describe
// exactly one sequence of bytes forever.

import Foundation
import PackageDescription

// The checksum below is from a local run of scripts/build-xcframework.sh. A CI build is
// not byte-identical to a local one, so replace it with the number the publish workflow
// prints for the tag. Until Janitor#104 publishes, JANITORKIT_LOCAL=1 is the only route
// that resolves.
let version = "0.1.0"
let checksum = "9fe6a74be8bb8822d41c4e0ab5e69f082a814eda2386c195d074705c5c45521d"

let local = ProcessInfo.processInfo.environment["JANITORKIT_LOCAL"] == "1"

let kit: Target = local
    ? .binaryTarget(
        name: "JanitorKit",
        path: "../../Janitor/build/apple/JanitorKit.xcframework"
    )
    : .binaryTarget(
        name: "JanitorKit",
        url: "https://depot.circuitstitch.com/open/swift/janitor/\(version)/JanitorKit.xcframework.zip",
        checksum: checksum
    )

let package = Package(
    name: "JanitorKit",
    platforms: [
        // The floor the slice was built against. A consumer may set its own no lower.
        .macOS(.v15),
    ],
    products: [
        .library(name: "JanitorKit", targets: ["JanitorKit"]),
    ],
    targets: [kit]
)
