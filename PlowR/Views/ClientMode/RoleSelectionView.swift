import SwiftUI

struct RoleSelectionView: View {
    @AppStorage("userRole") private var userRole = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "snowflake")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                Text("PlowR")
                    .font(.largeTitle.bold())
                Text("How will you be using PlowR?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)

            VStack(spacing: 16) {
                roleCard(
                    icon: "truck.box.fill",
                    title: "I run a service business",
                    description: "Manage clients, plan routes, build proposals, and track jobs.",
                    color: .blue
                ) {
                    userRole = "operator"
                }
                roleCard(
                    icon: "location.magnifyingglass",
                    title: "I'm looking for services",
                    description: "Find local operators and send a detailed request for your property.",
                    color: .green
                ) {
                    userRole = "client"
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func roleCard(icon: String, title: String, description: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RoleSelectionView()
        .preferredColorScheme(.dark)
}
