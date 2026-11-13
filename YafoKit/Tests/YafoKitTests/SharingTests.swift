import CloudKit
import Foundation
import Testing
@testable import YafoKit

@Suite struct SharingErrorTests {
    /// Core Data meldet nur „Failed to accept some shares“; der Grund steckt verschachtelt darin.
    @Test func reasonUnwrapsNestedCloudKitError() {
        let share = CKRecord.ID(recordName: "share")
        let ck = CKError(.permissionFailure)
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [share: ck]])
        let wrapper = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSLocalizedFailureReasonErrorKey: "Failed to accept some shares",
            NSUnderlyingErrorKey: partial
        ])
        let reason = FamilySharing.reason(for: wrapper)
        #expect(reason.contains("already been used"))
        #expect(reason.contains("CKError \(CKError.Code.permissionFailure.rawValue)"))
    }

    @Test func reasonWithoutCloudKitErrorKeepsDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 42)
        #expect(FamilySharing.reason(for: error).contains("NSCocoaErrorDomain 42"))
    }
}
