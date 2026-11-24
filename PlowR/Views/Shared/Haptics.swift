import UIKit

/// PlowR's haptics, one pattern everywhere: a status change that worked
/// (completed, sent, paid, a route made) gets `success`; a lighter change
/// (skipped) gets `selection`. A record changed with nothing felt or seen
/// left a fast operator, often in gloves, unsure the tap took.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
