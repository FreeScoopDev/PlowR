//
//  TermsAgreement.swift
//  PlowR
//

import SwiftUI

/// The line that makes choosing a role, or signing in, agreeing to the Terms
/// and the Privacy Policy. "By using PlowR you agree" on a web page alone
/// (browsewrap) is often not enforced; a line at the step itself is.
struct TermsAgreement: View {
    var body: some View {
        Text("By continuing, you agree to PlowR's [Terms of Service](https://getplowr.app/terms-of-service.html) and [Privacy Policy](https://getplowr.app/privacy-policy.html).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    TermsAgreement().padding()
}
