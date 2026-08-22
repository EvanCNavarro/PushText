import Testing
@testable import PushTextCore

/// Flag snapshots as macOS actually reports them in a `flagsChanged` event: the union mask for the
/// modifier CLASS, OR'd with a device-dependent bit per physical key.
///
/// Values read from `IOKit/hidsystem/IOLLEvent.h` (macOS 15.2 SDK), not from memory.
private enum Flags {
    static let none: UInt64 = 0
    static let altUnion: UInt64 = 0x0008_0000     // NX_ALTERNATEMASK - set for EITHER Option key
    static let ctrlUnion: UInt64 = 0x0004_0000    // NX_CONTROLMASK
    static let shiftUnion: UInt64 = 0x0002_0000   // NX_SHIFTMASK
    static let leftAlt: UInt64 = 0x0000_0020      // NX_DEVICELALTKEYMASK
    static let rightAlt: UInt64 = 0x0000_0040     // NX_DEVICERALTKEYMASK
    static let leftShift: UInt64 = 0x0000_0002    // NX_DEVICELSHIFTKEYMASK
    static let rightCtrl: UInt64 = 0x0000_2000    // NX_DEVICERCTLKEYMASK - NOT adjacent to left ctrl

    /// Right Option alone.
    static let rightAltOnly = altUnion | rightAlt
    /// Left Option alone.
    static let leftAltOnly = altUnion | leftAlt
    /// Both Option keys down at once.
    static let bothAlts = altUnion | leftAlt | rightAlt
}

@Suite("ModifierGate edge detection")
struct ModifierGateTests {

    @Test("A clean press and release of the bound key produces both edges")
    func pressAndRelease() {
        var gate = ModifierGate(binding: .rightOption)
        #expect(!gate.isDown)

        let down = gate.update(flags: Flags.rightAltOnly)
        #expect(down == .pressed)
        #expect(gate.isDown)

        let up = gate.update(flags: Flags.none)
        #expect(up == .released)
        #expect(!gate.isDown)
    }

    /// THE test this type exists for.
    ///
    /// Hold left Option, then tap right Option. When right Option lifts, `NX_ALTERNATEMASK` is STILL
    /// SET because left Option is still down — so an implementation watching the union mask sees no
    /// change and never emits a release. The dictation never ends and the microphone stays open.
    ///
    /// Asserting the release arrives *while the union bit is still set* is what makes this test
    /// impossible to pass with a union-mask implementation.
    @Test("Right Option's release is seen even while left Option stays held")
    func rightReleaseVisibleWhileLeftHeld() {
        var gate = ModifierGate(binding: .rightOption)

        // Left Option goes down first. Not our key - no edge.
        #expect(gate.update(flags: Flags.leftAltOnly) == nil)
        #expect(!gate.isDown)

        // Right Option joins it.
        #expect(gate.update(flags: Flags.bothAlts) == .pressed)

        // Right Option lifts; left is STILL DOWN, so the union bit is still set.
        #expect(Flags.leftAltOnly & Flags.altUnion != 0, "precondition: union bit still set here")
        #expect(gate.update(flags: Flags.leftAltOnly) == .released)
        #expect(!gate.isDown)
    }

    @Test("Repeated identical flag snapshots produce no duplicate edges")
    func noDuplicateEdges() {
        var gate = ModifierGate(binding: .rightOption)
        #expect(gate.update(flags: Flags.rightAltOnly) == .pressed)
        #expect(gate.update(flags: Flags.rightAltOnly) == nil)
        #expect(gate.update(flags: Flags.rightAltOnly) == nil)
        #expect(gate.isDown)
    }

    @Test("Unrelated modifiers moving while the bound key is held produce no edge")
    func unrelatedModifiersIgnored() {
        var gate = ModifierGate(binding: .rightOption)
        #expect(gate.update(flags: Flags.rightAltOnly) == .pressed)

        // Shift goes down, then Control, then both lift. Right Option never moves.
        #expect(gate.update(flags: Flags.rightAltOnly | Flags.shiftUnion | Flags.leftShift) == nil)
        #expect(gate.update(flags: Flags.rightAltOnly | Flags.shiftUnion | Flags.leftShift | Flags.ctrlUnion) == nil)
        #expect(gate.update(flags: Flags.rightAltOnly) == nil)
        #expect(gate.isDown)
    }

    /// Right Control's device bit is 0x2000, not 0x2. Doubling left Control's 0x1 gives 0x2, which is
    /// left SHIFT — so a symmetry guess here binds the wrong physical key.
    @Test("Right Control keys off 0x2000, and left Shift does not trigger it")
    func rightControlUsesItsOwnBit() {
        var gate = ModifierGate(binding: .rightControl)
        #expect(gate.binding.deviceMask == 0x0000_2000)

        // Left Shift down: 0x2 is set. Must NOT read as right Control.
        #expect(gate.update(flags: Flags.shiftUnion | Flags.leftShift) == nil)
        #expect(!gate.isDown)

        #expect(gate.update(flags: Flags.ctrlUnion | Flags.rightCtrl) == .pressed)
    }

    @Test("isHeld looks only at the bound key's bit",
          arguments: [
            (Flags.rightAltOnly, true),
            (Flags.bothAlts, true),
            (Flags.leftAltOnly, false),
            (Flags.altUnion, false),          // union set, no device bit - not our key
            (Flags.none, false)
          ])
    func isHeldIgnoresEverythingElse(flags: UInt64, expected: Bool) {
        let gate = ModifierGate(binding: .rightOption)
        #expect(gate.isHeld(in: flags) == expected)
    }

    /// The union mask alone cannot identify a side. Stated as a behavioural assertion so it fails
    /// if someone "simplifies" the gate to compare `NX_ALTERNATEMASK`.
    /// Note the second half: asserting only that left Option produces `nil` would ALSO pass on an
    /// implementation that never fires at all, so the same gate must then fire for its own key.
    @Test("A gate bound to right Option ignores left Option entirely")
    func leftOptionNeverTriggersRightBinding() {
        var gate = ModifierGate(binding: .rightOption)
        #expect(gate.update(flags: Flags.leftAltOnly) == nil)
        #expect(gate.update(flags: Flags.none) == nil)
        #expect(!gate.isDown)

        // Same gate, its own key: proves the nils above were discrimination, not inertia.
        #expect(gate.update(flags: Flags.rightAltOnly) == .pressed)
    }

    @Test("Every selectable binding has a distinct device mask and keycode")
    func selectableBindingsAreDistinct() {
        let masks = HotkeyBinding.selectable.map(\.deviceMask)
        let codes = HotkeyBinding.selectable.map(\.keyCode)
        #expect(Set(masks).count == masks.count)
        #expect(Set(codes).count == codes.count)
        #expect(!masks.contains(0), "a zero mask would match every flag snapshot")
    }

    @Test("A gate constructed as already-down reports the release it would otherwise miss")
    func recoversFromStartingDown() {
        // The tap can be installed while the user already holds the key.
        var gate = ModifierGate(binding: .rightOption, isDown: true)
        #expect(gate.update(flags: Flags.none) == .released)
    }
}
