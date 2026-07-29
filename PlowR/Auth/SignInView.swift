import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    Text("PlowR")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Route management for\nservice professionals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                                authManager.signIn(
                                    userID: credential.user,
                                    fullName: credential.fullName,
                                    email: credential.email
                                )
                            }
                        case .failure:
                            break
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)

                    Text("Your data is stored privately in your iCloud account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    #if DEBUG
                    Button("Skip Sign In (Dev Only)") {
                        authManager.signIn(userID: "dev-user", fullName: nil, email: nil)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    #endif
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager())
        .preferredColorScheme(.dark)
}
