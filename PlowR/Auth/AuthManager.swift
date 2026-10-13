import Foundation
import AuthenticationServices
import Security

/// Where the signed-in Apple user ID is kept between launches.
protocol SavedSignIn {
    func save(_ userID: String)
    func load() -> String?
    func delete()
}

/// The Keychain, on this device only. Save, load and delete share one query,
/// so a delete always finds what a save wrote.
struct KeychainSignIn: SavedSignIn {
    private var item: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrAccount: "appleUserID",
         kSecAttrService: "com.Scoops.PlowR"]
    }

    func save(_ userID: String) {
        guard let data = userID.data(using: .utf8) else { return }
        var query = item
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(item as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> String? {
        var query = item
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        SecItemDelete(item as CFDictionary)
    }
}

@Observable
final class AuthManager {
    var isSignedIn = false
    var userID: String = ""
    var operatorName: String = ""
    /// A check is waiting on Apple: the launch check and a return to the app
    /// can overlap. Observed: a link that opened the app waits for it
    /// (IncomingLinks), since at launch Apple answers after the app is up.
    private(set) var isChecking = false
    /// Bumped by every sign-in and sign-out, so a slow check that answers
    /// afterwards can't undo what the user just did.
    @ObservationIgnored private var generation = 0
    /// The Keychain in the app. Tests pass their own: a test build isn't
    /// signed, so it has no Keychain access (errSecMissingEntitlement).
    private let saved: any SavedSignIn

    init(saved: any SavedSignIn = KeychainSignIn()) {
        self.saved = saved
        checkExistingCredentials()
    }

    func checkExistingCredentials() {
        // One-time migration: move appleUserID from UserDefaults to Keychain
        if let legacy = UserDefaults.standard.string(forKey: "appleUserID") {
            saved.save(legacy)
            UserDefaults.standard.removeObject(forKey: "appleUserID")
        }

        guard let savedUserID = saved.load() else { return }

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
                    self.saved.delete()
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
        saved.save(userID)

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
        saved.delete()
        UserDefaults.standard.removeObject(forKey: "operatorName")
    }
}
