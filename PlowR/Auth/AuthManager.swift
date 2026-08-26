import Foundation
import AuthenticationServices
import Security

@Observable
final class AuthManager {
    var isSignedIn = false
    var userID: String = ""
    var operatorName: String = ""

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

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: savedUserID) { [weak self] state, _ in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    self?.isSignedIn = true
                    self?.userID = savedUserID
                    self?.operatorName = UserDefaults.standard.string(forKey: "operatorName") ?? ""
                default:
                    self?.isSignedIn = false
                    Self.keychainDelete(key: "appleUserID")
                }
            }
        }
    }

    func signIn(userID: String, fullName: PersonNameComponents?, email: String?) {
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
