import XCTest
@testable import AgendaHOF

final class SubscriptionLogicTests: XCTestCase {
    
    // MARK: - Helpers
    
    // Mock de UserProfile
    func makeProfile(role: UserRole = .owner, isActive: Bool = true, clinicId: String? = nil) -> UserProfile {
        return UserProfile(
             id: "user1",
             role: role,
             clinicId: clinicId,
             isActive: isActive,
             createdAt: Date(),
             updatedAt: Date()
        )
    }
    
    // Mock de UserSubscription
    func makeSubscription(status: SubscriptionStatus, nextBilling: Date?, planId: String = "pro_monthly", discount: Int? = nil, isCourtesy: Bool = false) -> UserSubscription {
        return UserSubscription(
            id: UUID().uuidString,
            userId: "user1",
            planId: planId,
            status: status,
            discountPercentage: isCourtesy ? 100 : discount,
            currentPeriodStart: Date(),
            currentPeriodEnd: Date(),
            nextBillingDate: nextBilling,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    // MARK: - Step 1: Staff Checks
    
    func testStaff_Inactive_IsBlocked() {
        let profile = makeProfile(role: .staff, isActive: false, clinicId: "clinic1")
        let result = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        XCTAssertTrue(result.isStaff)
        XCTAssertEqual(result.access?.hasActiveSubscription, false) // Blocked
    }
    
    func testStaff_ActiveWithClinic_RedirectsToClinicId() {
        let profile = makeProfile(role: .staff, isActive: true, clinicId: "targetClinic")
        let result = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        XCTAssertTrue(result.isStaff)
        XCTAssertEqual(result.targetUserId, "targetClinic")
        XCTAssertNil(result.access) // Nil means "Proceed to next step"
    }
    
    func testStaff_WithoutClinic_IsBlocked() {
        let profile = makeProfile(role: .staff, isActive: true, clinicId: nil)
        let result = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        XCTAssertTrue(result.isStaff)
        XCTAssertEqual(result.access?.hasActiveSubscription, false) // Blocked
    }
    
    func testOwner_ProceedsToSelfCheck() {
        let profile = makeProfile(role: .owner)
        let result = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        XCTAssertFalse(result.isStaff)
        XCTAssertNil(result.targetUserId)
        XCTAssertNil(result.access) // Proceed
    }
    
    // MARK: - Step 3: Subscription Validation
    
    func testSubscription_Active_WithinGracePeriod_IsValid() {
        let now = Date()
        // Expired 3 days ago (Grace is 5)
        let billingDate = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        
        let sub = makeSubscription(status: .active, nextBilling: billingDate)
        
        XCTAssertTrue(SubscriptionLogic.validateSubscription(sub, referenceDate: now))
    }
    
    func testSubscription_Active_OutsideGracePeriod_IsInvalid() {
        let now = Date()
        // Expired 6 days ago (Grace is 5)
        let billingDate = Calendar.current.date(byAdding: .day, value: -6, to: now)!
        
        let sub = makeSubscription(status: .active, nextBilling: billingDate)
        
        XCTAssertFalse(SubscriptionLogic.validateSubscription(sub, referenceDate: now))
    }
    
    func testSubscription_PendingCancellation_BeforeBilling_IsValid() {
        let now = Date()
        // Billing in future
        let billingDate = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        
        let sub = makeSubscription(status: .pendingCancellation, nextBilling: billingDate)
        
        XCTAssertTrue(SubscriptionLogic.validateSubscription(sub, referenceDate: now))
    }
    
    func testSubscription_PendingCancellation_AfterBilling_IsInvalid() {
        let now = Date()
        // Billing passed yesterday
        let billingDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        
        let sub = makeSubscription(status: .pendingCancellation, nextBilling: billingDate)
        
        XCTAssertFalse(SubscriptionLogic.validateSubscription(sub, referenceDate: now))
    }
    
    func testSubscription_Courtesy_AlwaysValidIfActive() {
        let sub = makeSubscription(status: .active, nextBilling: nil, isCourtesy: true)
        XCTAssertTrue(SubscriptionLogic.validateSubscription(sub))
    }
    
    // MARK: - Step 4: Revoked Courtesy
    
    func testRevokedCourtesy_Detected() {
        let sub = makeSubscription(status: .cancelled, nextBilling: nil, isCourtesy: true)
        XCTAssertTrue(SubscriptionLogic.checkRevokedCourtesy([sub]))
    }
    
    func testCancelledPaid_NotRevokedCourtesy() {
        let sub = makeSubscription(status: .cancelled, nextBilling: nil, isCourtesy: false)
        XCTAssertFalse(SubscriptionLogic.checkRevokedCourtesy([sub]))
    }
    
    // MARK: - Step 5: Trial
    
    func testTrial_Within7Days_IsValid() {
        let now = Date()
        let createdAt = Calendar.current.date(byAdding: .day, value: -5, to: now)! // 5 days old (Trial is 7)
        
        let result = SubscriptionLogic.checkTrial(createdAt: createdAt, trialEndDateMetadata: nil, referenceDate: now)
        XCTAssertTrue(result.isInTrial)
    }
    
    func testTrial_After7Days_IsExpired() {
        let now = Date()
        let createdAt = Calendar.current.date(byAdding: .day, value: -8, to: now)! // 8 days old
        
        let result = SubscriptionLogic.checkTrial(createdAt: createdAt, trialEndDateMetadata: nil, referenceDate: now)
        XCTAssertFalse(result.isInTrial)
    }
    
    func testTrial_WithMetadataExtension_Recalculates() {
        let now = Date()
        let createdAt = Calendar.current.date(byAdding: .day, value: -20, to: now)! // Old user
        
        // Metadata says trial until tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let isoDate = ISO8601DateFormatter().string(from: tomorrow)
        
        let result = SubscriptionLogic.checkTrial(createdAt: createdAt, trialEndDateMetadata: isoDate, referenceDate: now)
        XCTAssertTrue(result.isInTrial)
    }
}
