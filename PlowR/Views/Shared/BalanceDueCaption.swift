import SwiftUI

/// "$X due" under a partly paid invoice's total, in a list of documents.
struct BalanceDueCaption: View {
    let document: Proposal

    var body: some View {
        if document.isPartlyPaid {
            Text("\(Money.text(document.balanceDue)) due")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PlowRColor.Status.owed.text)
        }
    }
}
