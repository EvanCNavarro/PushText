// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PushText",
    platforms: [
        // The SHIPPED product floor, and now the build floor too (#16).
        //
        // `SpeechAnalyzer` and `FoundationModels` exist nowhere below macOS 26, and legacy
        // `SFSpeechRecognizer` — throttled, with a 1-minute cap — is not a product. Phase 0 built
        // at v15 against a `MockTranscriptionEngine` because the development machine was on
        // Sequoia with the 15.2 SDK; that is over, and holding a lower floor now would only keep
        // alive an `#if canImport(FoundationModels)` scaffold guarding a configuration nobody
        // can build.
        //
        // Three things move together with this line, and CI does not catch two of them:
        //   - `MIN_SYSTEM_VERSION` in scripts/build-app.sh (Info.plist LSMinimumSystemVersion)
        //   - `runs-on:` in .github/workflows/check.yml AND release.yml — a macos-15 runner
        //     cannot resolve a v26 manifest at all, and release.yml only fires on a tag, so its
        //     failure would surface at the first release rather than in a PR.
        //
        // swift-tools-version is 6.2 because `.v26` does not exist in PackageDescription 6.0.
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PushText", targets: ["PushText"])
    ],
    dependencies: [
        // Shared 400faces macOS design system (tokens + components), same pin as TermTile 0.4.x.
        .package(url: "https://github.com/400faces/MacFaceKit.git", .upToNextMinor(from: "0.4.2"))
    ],
    targets: [
        // Functional core: the dictation state machine, the cleanup drift guard, the dictionary
        // matcher, the history model. Pure Foundation — NO AppKit / ApplicationServices / AVFoundation
        // (enforced by .engine/checks/core-purity.sh). This is where the logic worth testing lives.
        .target(name: "PushTextCore"),
        // System adapters, each behind a protocol port so Core never sees a framework: CGEventTap
        // hotkey, AVAudioEngine capture, SpeechAnalyzer transcription, FoundationModels cleanup,
        // pasteboard injection, TCC probes. UI-free, so it unit-tests.
        .target(name: "PushTextKit", dependencies: ["PushTextCore"]),
        // Thin shell: MenuBarExtra UI + the HUD panel + composition root. Sparkle for auto-updates.
        // The runtime rpath lets the bundled binary find Sparkle.framework that build-app.sh embeds
        // in Contents/Frameworks — linking Sparkle WITHOUT both = dyld crash at launch.
        .executableTarget(
            name: "PushText",
            dependencies: ["PushTextKit", "PushTextCore", "Sparkle",
                           .product(name: "MacFaceKit", package: "MacFaceKit")],
            // The app icon. `.copy` (not `.process`) takes the PNG verbatim — no SVG source, no
            // actool pass. build-app.sh does NOT read it from here (it sips/iconutils the source
            // path in ICON_SRC directly), so this entry is not what makes the .icns; without it
            // SPM warns "found 1 file(s) which are unhandled" on every build, and the copy keeps
            // the icon reachable from Bundle should the branded update dialog ever want it the way
            // TermTile's does. Sparkle's standard dialog reads CFBundleIconFile off the .app.
            resources: [.copy("Resources/AppIcon.png")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]),
        // Local binaryTarget (SPM's remote artifact downloader hangs in some sandboxes). The
        // xcframework is gitignored + vendored by scripts/fetch-sparkle.sh — run it once after clone.
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
        .testTarget(name: "PushTextCoreTests", dependencies: ["PushTextCore"]),
        .testTarget(name: "PushTextKitTests", dependencies: ["PushTextKit"]),
        .testTarget(name: "PushTextTests", dependencies: ["PushText"])
    ]
)
