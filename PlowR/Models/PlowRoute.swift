import Foundation
import SwiftData

@Model
final class PlowRoute {
    var id: UUID = UUID()
    var name: String = ""
    var operatorID: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \RouteStop.route) var stops: [RouteStop]?

    var sortedStops: [RouteStop] {
        (stops ?? []).sorted { $0.order < $1.order }
    }

    init(name: String, operatorID: String) {
        self.name = name
        self.operatorID = operatorID
    }
}
