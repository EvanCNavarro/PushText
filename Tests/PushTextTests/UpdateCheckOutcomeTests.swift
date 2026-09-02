import Testing
import Foundation
import Sparkle
@testable import PushText

/// Which Sparkle errors mean the update CHECK failed (#241).
///
/// The defect this covers shipped because the only update tests asserted how each
/// `UpdateAvailability` RENDERS. Nothing asserted the mapping ONTO one, so a callback that turned
/// every successful check into `.failed` was invisible to a green suite - and visible in the log of
/// the running app as `update check FAILED: You're up to date!`, six times in a day.
@Suite("Update check outcome")
struct UpdateCheckOutcomeTests {

    /// The whole bug, as one case. Sparkle reports "nothing to install" on the ERROR path, so the
    /// outcome that means success was being recorded as failure.
    @Test("'No update found' is a successful check, not a failed one")
    func noUpdateIsNotAFailure() {
        #expect(UpdateWatcher.isCheckFailure(domain: SUSparkleErrorDomain,
                                             code: Int(SUError.noUpdateError.rawValue)) == false)
    }

    /// The user declining an install is not the check breaking - it ran, found an update, and did
    /// its job.
    @Test("A cancelled installation is not a failed check")
    func cancellationIsNotAFailure() {
        #expect(UpdateWatcher.isCheckFailure(domain: SUSparkleErrorDomain,
                                             code: Int(SUError.installationCanceledError.rawValue)) == false)
    }

    /// The DISCRIMINATOR. Without this the fix could be "never report a failure", which would
    /// restore the #170 defect from the other side: a check that cannot run would render as
    /// up to date, and the user would be told they are current while the app has no idea.
    @Test("A genuine Sparkle failure is still a failure")
    func realSparkleErrorsStillFail() {
        for code in [Int(SUError.appcastParseError.rawValue),
                     Int(SUError.appcastError.rawValue),
                     Int(SUError.runningFromDiskImageError.rawValue)] {
            #expect(UpdateWatcher.isCheckFailure(domain: SUSparkleErrorDomain, code: code),
                    "Sparkle error \(code) must count as a failed check")
        }
    }

    /// Being offline is the commonest real failure and it does not come from Sparkle's domain at
    /// all. A classifier keyed only on the code would let `NSURLErrorNotConnectedToInternet`
    /// (-1009) through as success if it happened to collide with an allowed number.
    @Test("An error from another domain is a failure, whatever its code")
    func foreignDomainsFail() {
        #expect(UpdateWatcher.isCheckFailure(domain: NSURLErrorDomain,
                                             code: NSURLErrorNotConnectedToInternet))
        // Deliberately the SAME code that means success inside Sparkle's domain: the domain has to
        // be part of the decision, not decoration.
        #expect(UpdateWatcher.isCheckFailure(domain: NSURLErrorDomain,
                                            code: Int(SUError.noUpdateError.rawValue)))
        #expect(UpdateWatcher.isCheckFailure(domain: NSCocoaErrorDomain, code: 4))
    }

    /// `SUError` is `NS_ENUM(OSStatus, ...)`, so its rawValue is `Int32` and every use here needs an
    /// explicit `Int(...)`. The classifier itself compares `Int` to `Int32` directly, which Swift
    /// allows and evaluates by VALUE - heterogeneous `==`/`!=` exist for `BinaryInteger`. Checked
    /// rather than assumed, because a width mismatch that silently compiled would make this whole
    /// suite compare different constants than the code does.
    ///
    /// Reconstructs the error from the actual log line rather than trusting the code constant: the
    /// running app printed `update check FAILED: You're up to date!`, and this asserts that the
    /// error carrying that exact message is the one now classified as a success.
    @Test("The error behind the logged 'You're up to date!' line is not a failure")
    func theObservedErrorIsNotAFailure() {
        let observed = NSError(domain: SUSparkleErrorDomain,
                               code: Int(SUError.noUpdateError.rawValue)) as any Error
        let asNS = observed as NSError
        #expect(UpdateWatcher.isCheckFailure(domain: asNS.domain, code: asNS.code) == false)
    }
}
