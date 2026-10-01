import SwiftUI

/// Days of the week to pick, Sunday first, numbered 1 (Sunday) to 7
/// (Saturday) as RecurrenceRule numbers them. Add Visit's repeat and a
/// contract's visits use the same one.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = selection.contains(weekday)
                Button {
                    if selected { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(Calendar(identifier: .gregorian).veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(selected ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(selected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar(identifier: .gregorian).standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
                if weekday < 7 { Spacer() }
            }
        }
        .padding(.vertical, 4)
    }
}
