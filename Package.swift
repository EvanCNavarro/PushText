// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PushText",
    platforms: [
        // NOTE — this is deliberately v14, not v26, and it is a PHASE-0 setting.
        //
        // The shipped product floor is macOS 26: SpeechAnalyzer and FoundationModels exist
        // nowhere below it, and legacy SFSpeechRecognizer (throttled, 1-minute cap) is not a
        // product. But the development machine is on Sequoia 15.1 with the 15.2 SDK, and ~70%
        // of this app — hotkey tap, audio capture, text injection, HUD, permissions, packaging —
        // neither needs nor references macOS 26.
        //
        // So: build at v14 today against a MockTranscriptionEngine, keep every macOS 26 call
        // behind `#if canImport(FoundationModels)` + `@available(macOS 26, *)`, and bump this
        // single line to .v26 in Phase 2 once Xcode 26 is installed. Info.plist's
        // LSMinimumSystemVersion moves with it. See PLAN.md §2.5.
        // v15, not v14: AudioRingBuffer uses Synchronization.Atomic (macOS 15+) for a lock-free
        // producer/consumer handoff, because AVAudioSinkNode's block runs on the realtime thread
        // where a lock is a blocking call. The shipped floor is still macOS 26 (PLAN.md sec 2.5);
        // v14 was only ever a Phase 0 convenience and nothing depends on it.
        .macOS(.v15)
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
            // No app icon yet — build-app.sh no-ops when ICON_SRC is absent. Add
            // Sources/PushText/Resources/AppIcon.png plus a `.copy` here once there is art.
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
