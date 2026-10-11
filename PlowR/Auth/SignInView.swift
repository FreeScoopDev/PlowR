import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UserRole.key) private var userRole = ""
    /// Sign in with Apple failed for a reason other than Cancel: say so.
    /// It was ignored, and the button just did nothing.
    @State private var signInFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // The role chosen on the screen before: back to change it.
                Button {
                    userRole = ""
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: PlowRLayout.minTapTarget)
                }
                .padding(.horizontal, PlowRLayout.space4)
                Spacer()
            }

            Spacer()

            BrandMark(tagline: "Routes, clients and invoices for\nsnow, lawn and landscaping crews")

            Spacer()

            VStack(spacing: PlowRLayout.space3) {
                SignInWithAppleButton(.signIn) { request in
                    // The name greets the business in Settings. No email: PlowR has no
                    // use for it, so it doesn't ask.
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            authManager.signIn(
                                userID: credential.user,
                                fullName: credential.fullName
                            )
                        }
                    case .failure(let error):
                        signInFailed = !SignInFailure.isCancel(error)
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: PlowRLayout.gloveTapTarget)
                .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))

                Text("Your data is kept in your private iCloud, not on our servers.")
                    .font(.caption)
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .multilineTextAlignment(.center)

                TermsAgreement()

                #if DEBUG
                Button("Skip Sign In (Dev Only)") {
                    authManager.signIn(userID: "dev-user", fullName: nil)
                }
                .font(.caption)
                .foregroundStyle(PlowRColor.inkSecondary)
                #endif
            }
            .padding(.horizontal, PlowRLayout.space6 + PlowRLayout.space4)
            .padding(.bottom, PlowRLayout.space6 * 2)
        }
        .frame(maxWidth: .infinity)
        .background(PlowRColor.ground.ignoresSafeArea())
        .alert("Couldn't Sign In", isPresented: $signInFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple's sign-in didn't finish. Check you're online and signed in to your Apple Account in the Settings app, then try again.")
        }
    }
}

/// Sign in with Apple's outcomes: Cancel is the user's choice, anything
/// else is a failure to explain.
enum SignInFailure {
    static func isCancel(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

#Preview {
    SignInView()
        .environment(AuthManager())
        .preferredColorScheme(.dark)
}
