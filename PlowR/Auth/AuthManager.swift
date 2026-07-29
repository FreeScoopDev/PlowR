import Foundation
import AuthenticationServices

@Observable
final class AuthManager {
    var isSignedIn = false
    var userID: String = ""
    var operatorName: String = ""

    init() {
        checkExistingCredentials()
    }

    func checkExistingCredentials() {
        guard let savedUserID = UserDefaults.standard.string(forKey: "appleUserID") else {
            return
        }

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
                    UserDefaults.standard.removeObject(forKey: "appleUserID")
                }
            }
        }
    }

    func signIn(userID: String, fullName: PersonNameComponents?, email: String?) {
        self.userID = userID
        self.isSignedIn = true
        UserDefaults.standard.set(userID, forKey: "appleUserID")

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
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "operatorName")
    }
}
