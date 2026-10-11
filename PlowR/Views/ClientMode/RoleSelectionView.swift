import SwiftUI

/// The first screen: a business, or someone looking for one. Either can be
/// changed later (Settings → Switch to Client Mode; client mode's menu).
struct RoleSelectionView: View {
    @AppStorage(UserRole.key) private var userRole = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            BrandMark(tagline: "How will you be using PlowR?")
                .padding(.bottom, PlowRLayout.space6 * 2)

            VStack(spacing: PlowRLayout.space3) {
                roleCard(
                    icon: "truck.box.fill",
                    title: "I run a service business",
                    description: "Manage clients, plan routes, build proposals, and track jobs."
                ) {
                    userRole = UserRole.business
                }
                roleCard(
                    icon: "location.magnifyingglass",
                    title: "I'm looking for services",
                    description: "Find local operators and send a detailed request for your property."
                ) {
                    userRole = UserRole.client
                }
            }
            .padding(.horizontal, PlowRLayout.space6)

            Spacer()

            TermsAgreement()
                .padding(.horizontal, PlowRLayout.space6 + PlowRLayout.space4)
                .padding(.bottom, PlowRLayout.space6)
        }
        .frame(maxWidth: .infinity)
        .background(PlowRColor.ground.ignoresSafeArea())
    }

    private func roleCard(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PlowRLayout.space4) {
                IconBadge(systemImage: icon, size: 48)
                VStack(alignment: .leading, spacing: PlowRLayout.space1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(PlowRColor.ink)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .font(.subheadline)
                    .accessibilityHidden(true)
            }
            .padding(PlowRLayout.space4 + PlowRLayout.space1)
            .background(PlowRColor.surface,
                        in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
                .strokeBorder(PlowRColor.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RoleSelectionView()
        .preferredColorScheme(.dark)
}
