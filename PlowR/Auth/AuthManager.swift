import Foundation
import AuthenticationServices
import Security

@Observable
final class AuthManager {
    var isSignedIn = false
    var userID: String = ""
    var operatorName: String = ""
    /// A check is waiting on Apple: the launch check and a return to the app can overlap.
    @ObservationIgnored private var isChecking = false
    /// Bumped by every sign-in and sign-out, so a slow check that answers
    /// afterwards can't undo what the user just did.
    @ObservationIgnored private var generation = 0

    init() {
        checkExistingCredentials()
    }

    func checkExistingCredentials() {
        // One-time migration: move appleUserID from UserDefaults to Keychain
        if let legacy = UserDefaults.standard.string(forKey: "appleUserID") {
            Self.keychainSave(legacy, key: "appleUserID")
            UserDefaults.standard.removeObject(forKey: "appleUserID")
        }

        guard let savedUserID = Self.keychainLoad(key: "appleUserID") else { return }

        isChecking = true
        let started = generation
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: savedUserID) { [weak self] state, error in
            let keep = Self.keepsSession(state: state, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                // Signed in or out by hand while Apple was answering: that stands.
                guard self.generation == started else { return }
                if keep {
                    self.isSignedIn = true
                    self.userID = savedUserID
                    self.operatorName = UserDefaults.standard.string(forKey: "operatorName") ?? ""
                } else {
                    self.isSignedIn = false
                    Self.keychainDelete(key: "appleUserID")
                }
            }
        }
    }

    /// Checks again when the app comes to the front signed out. Started in the
    /// background while the phone was locked (a geofence can do that), PlowR
    /// can't read the saved sign-in from the Keychain, and it didn't look again
    /// once opened, so the user saw the sign-in screen and needed signal.
    func recheckIfSignedOut() {
        guard !isSignedIn, !isChecking else { return }
        checkExistingCredentials()
    }

    /// Whether a saved sign-in survives the check at launch. Only an answer
    /// from Apple ends it: revoked, not found or transferred. An error, such
    /// as no signal on a job site, keeps it. Signing out on an error deleted
    /// the saved ID and locked the user out of their routes until they had
    /// signal to sign in again.
    nonisolated static func keepsSession(state: ASAuthorizationAppleIDProvider.CredentialState, error: Error?) -> Bool {
        guard error == nil else { return true }
        return state == .authorized
    }

    func signIn(userID: String, fullName: PersonNameComponents?) {
        generation += 1
        self.userID = userID
        self.isSignedIn = true
        Self.keychainSave(userID, key: "appleUserID")

        if let name = fullName, let given = name.givenName, !given.isEmpty {
            let formatter = PersonNameComponentsFormatter()
            let nameStr = formatter.string(from: name)
            self.operatorName = nameStr
            UserDefaults.standard.set(nameStr, forKey: "operatorName")
        } else {
            self.operatorName = UserDefaults.standard.string(forKey: "operatorName") ?? ""
        }
    }

    func signOut() {
        generation += 1
        isSignedIn = false
        userID = ""
        operatorName = ""
        Self.keychainDelete(key: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "operatorName")
    }

    // MARK: - Keychain helpers

    private static func keychainSave(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.Scoops.PlowR",
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainLoad(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.Scoops.PlowR",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "com.Scoops.PlowR"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
