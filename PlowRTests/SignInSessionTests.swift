//
//  SignInSessionTests.swift
//  PlowRTests
//

import AuthenticationServices
import Testing
@testable import PlowR

/// The sign-in check at launch. Any answer but "authorized", including no
/// answer at all, used to sign the user out and delete the saved ID.
struct SignInSessionTests {

    struct NoSignal: Error {}

    // No signal on a job site must not lock a pro out of their routes.
    @Test(arguments: [ASAuthorizationAppleIDProvider.CredentialState.notFound, .revoked, .transferred, .authorized])
    func anErrorKeepsTheSession(state: ASAuthorizationAppleIDProvider.CredentialState) {
        #expect(AuthManager.keepsSession(state: state, error: NoSignal()))
    }

    @Test func withoutAnErrorOnlyAuthorizedKeepsIt() {
        #expect(AuthManager.keepsSession(state: .authorized, error: nil))
        for state: ASAuthorizationAppleIDProvider.CredentialState in [.revoked, .notFound, .transferred] {
            #expect(!AuthManager.keepsSession(state: state, error: nil), "\(state.rawValue)")
        }
    }
}
