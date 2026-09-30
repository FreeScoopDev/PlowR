import SwiftUI

/// "$X due" under a partly paid invoice's total, in a list of documents.
struct BalanceDueCaption: View {
    let document: Proposal

    var body: some View {
        if document.isPartlyPaid {
            Text("\(document.balanceDue.formatted(.currency(code: "USD"))) due")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
