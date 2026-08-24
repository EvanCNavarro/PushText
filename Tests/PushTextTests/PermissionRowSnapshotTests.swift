import Testing
import SwiftUI
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore
import MacFaceKit

/// Renders the permission rows to a PNG so the copy and layout can be LOOKED AT (#6, FL-9).
///
/// A passing assertion about `advice.detail` says the string is right; it says nothing about whether
/// three stacked rows fit a 320pt panel, whether the warning colour reads against `Tokens.panel`, or
/// whether the longest sentence wraps to four lines and pushes the action off. Those are the failures
/// a design change actually produces.
///
/// Opt-in via `PUSHTEXT_SNAPSHOT_DIR` so CI - which has no display and no reason to rasterise - skips
/// it entirely.
@Suite("Permission row snapshot")
@MainActor
struct PermissionRowSnapshotTests {

    /// `nonisolated` so the `.enabled(if:)` trait can read it from a Sendable closure - the trait
    /// is evaluated outside the suite's main-actor context.
    nonisolated static var outputDirectory: String? {
        ProcessInfo.processInfo.environment["PUSHTEXT_SNAPSHOT_DIR"]
    }

    @Test("Render every permission state to a PNG",
          .enabled(if: PermissionRowSnapshotTests.outputDirectory != nil))
    func renderStates() throws {
        guard let directory = Self.outputDirectory else { return }

        let states: [(String, PermissionStatus, Permission)] = [
            ("microphone-first", .needsFirstGrant, .microphone),
            ("accessibility-broken", .grantBroken, .accessibility),
            ("postevent-denied", .denied, .postEvent)
        ]
        let rows = states.compactMap { PermissionAdvice.forStatus($0.1, of: $0.2) }
        #expect(rows.count == states.count)

        let view = VStack(alignment: .leading, spacing: Tokens.space) {
            SectionCard("NEEDS ATTENTION") {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, advice in
                    if index > 0 { Divider() }
                    PermissionRow(advice: advice) {}
                }
            }
        }
        .frame(width: 320)
        .padding(Tokens.pad)
        .background(Tokens.panel)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("ImageRenderer produced nothing")
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("permission-rows.png")
        try png.write(to: url)
        print("SNAPSHOT \(url.path) bytes=\(png.count)")
    }
    /// The capture-loss warning above a transcript (#71). Rendered because the failure mode is
    /// layout: three lines of amber over a four-line transcript in a 320pt panel either reads as a
    /// caption or swamps the thing it annotates, and no string assertion can tell which.
    @Test("Render the capture-loss warning above a transcript",
          .enabled(if: PermissionRowSnapshotTests.outputDirectory != nil))
    func renderCaptureWarning() throws {
        guard let directory = Self.outputDirectory else { return }

        let cases: [CaptureHealth] = [
            CaptureHealth(restarts: 1),
            CaptureHealth(restarts: 1, restartFailures: 1),
            CaptureHealth(droppedFrames: 96_000)
        ]
        let view = VStack(alignment: .leading, spacing: Tokens.space) {
            ForEach(Array(cases.enumerated()), id: \.offset) { _, health in
                SectionCard("LAST TRANSCRIPT") {
                    if let warning = AppModel.captureWarning(for: health) {
                        Text(warning)
                            .font(Tokens.caption)
                            .foregroundStyle(Tokens.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Send him the invoice today and let me know when it clears.")
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: 320)
        .padding(Tokens.pad)
        .background(Tokens.panel)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("ImageRenderer produced nothing")
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("capture-warning.png")
        try png.write(to: url)
        print("SNAPSHOT \(url.path) bytes=\(png.count)")
    }

    /// The model-preparation row (#76), rendered because its failure mode is layout: a percentage
    /// that wraps mid-number, or a failure message so long it swamps the section, are both things
    /// only a render shows.
    @Test("Render model preparation, in progress and failed",
          .enabled(if: PermissionRowSnapshotTests.outputDirectory != nil))
    func renderModelPreparation() throws {
        guard let directory = Self.outputDirectory else { return }

        let states: [ModelPreparation] = [
            .preparing(fraction: 0.07),
            .preparing(fraction: 0.64),
            .failed("The Internet connection appears to be offline.")
        ]
        let view = VStack(alignment: .leading, spacing: Tokens.space) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                SectionCard("NEEDS ATTENTION") {
                    if let message = AppModel.preparationMessage(for: state) {
                        Text(message)
                            .font(Tokens.caption)
                            .foregroundStyle(Tokens.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(width: 320)
        .padding(Tokens.pad)
        .background(Tokens.panel)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("ImageRenderer produced nothing"); return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("model-preparation.png")
        try png.write(to: url)
        print("SNAPSHOT \(url.path) bytes=\(png.count)")
    }

}

extension PermissionRowSnapshotTests {

    /// The HUD in every phase (#107, FL-9). Rendered rather than asserted, because the claim is
    /// "during processing the pill shows a spinner where the controls were, and does not change
    /// size" - and neither half of that is visible to a string assertion. A test that checked
    /// `phase == .working` would pass on a version that resized the pill, dropped the waveform, or
    /// rendered the spinner invisible against `Tokens.row`.
    @Test("Render the HUD in resting, recording and working phases",
          .enabled(if: PermissionRowSnapshotTests.outputDirectory != nil))
    func renderHUDPhases() throws {
        guard let directory = Self.outputDirectory else { return }

        let phases: [(String, HUDPhase, Double)] = [
            ("resting", .resting, 0),
            ("recording", .recording, 0.7),
            ("working", .working, 0),
            ("inserting", .inserting, 0)
        ]
        for (name, phase, level) in phases {
            let view = DictationHUDView(phase: phase, level: level, isPresented: true,
                                        onCancel: {}, onConfirm: {})
                .frame(width: 260, height: 90)
                .background(Tokens.panel)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("ImageRenderer produced nothing for \(name)")
                return
            }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("hud-\(name).png")
            try png.write(to: url)
            print("SNAPSHOT \(url.path) bytes=\(png.count)")
        }
    }
}
