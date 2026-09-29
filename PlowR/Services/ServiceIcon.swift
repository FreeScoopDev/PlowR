import Foundation

/// The SF Symbol for a service, from words in its name. Used on the route
/// screen and on the proposal PDF, which each had their own copy.
///
/// It matched any part of the name, so "service" hit "ice" and gave "Lawn
/// Service" and "Tree Service" a snowflake, and "street" hit "tree". Now each
/// keyword must start a word: "Salting" and "De-icing" still match.
///
/// `nonisolated`: a pure lookup, used while drawing the PDF.
nonisolated enum ServiceIcon {
    /// Checked in order; the first rule with a word that starts with one of
    /// its keywords wins.
    static let rules: [(keywords: [String], symbol: String)] = [
        (["snow", "plow"], "snowflake"),
        (["ice", "icing", "deic", "salt"], "thermometer.snowflake"),
        (["lawn", "mow"], "leaf.fill"),
        (["tree", "landscap", "mulch", "plant", "shrub"], "tree.fill"),
        (["walk", "sidewalk", "shovel", "path"], "figure.walk"),
        (["driv", "clean", "wash"], "sparkles"),
        (["edg", "hedge", "trim"], "scissors"),
        (["haul", "debris", "remov"], "trash.fill"),
        (["fert", "seed", "overseed"], "drop.fill")
    ]

    static let fallback = "wrench.and.screwdriver.fill"

    static func symbol(for name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        for rule in rules where words.contains(where: { word in rule.keywords.contains { word.hasPrefix($0) } }) {
            return rule.symbol
        }
        return fallback
    }
}
