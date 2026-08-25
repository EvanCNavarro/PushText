import Testing
import Foundation
@testable import PushTextCore

/// Whether binding Globe will fight macOS (#176).
@Suite("Globe key conflict")
struct GlobeKeyConflictTests {

    @Test("Do Nothing is the only setting that does not conflict")
    func doNothingIsClear() {
        #expect(GlobeKeyConflict.conflict(fnUsageType: 0) == nil)
    }

    @Test("Every other setting conflicts, and names itself")
    func othersConflict() {
        #expect(GlobeKeyConflict.conflict(fnUsageType: 1) == .changeInputSource)
        #expect(GlobeKeyConflict.conflict(fnUsageType: 2) == .showEmoji)
        #expect(GlobeKeyConflict.conflict(fnUsageType: 3) == .startDictation)
        #expect(GlobeKeyAction.startDictation.describedForUser == "Start Dictation")
    }

    /// The case that decides whether this warning is useful at all. An ABSENT key means the factory
    /// default, and on a Mac with a Globe key the factory default is not "Do Nothing" - so reading
    /// absence as harmless would silence the warning on exactly the machines that need it.
    @Test("An absent setting is treated as a conflict, not as clear")
    func absentIsNotClear() {
        #expect(GlobeKeyConflict.conflict(fnUsageType: nil) != nil)
    }

    /// A value we do not recognise is a macOS version that added an action. Guessing "fine" there
    /// is the same failure as the absent case.
    @Test("An unknown value is treated as a conflict")
    func unknownIsNotClear() {
        #expect(GlobeKeyConflict.conflict(fnUsageType: 99) != nil)
    }
}
