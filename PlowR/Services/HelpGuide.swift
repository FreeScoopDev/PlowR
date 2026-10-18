import Foundation
import os

/// PlowR's help, from its one source: `PlowR/Help/HelpGuide.json`, bundled
/// with the app. The website's page (`docs/help.html`) is made from the same
/// file by `scripts/help_guide.py`, and tips take their copy from it, so the
/// help is written once. Edit the JSON, then run the script; HelpGuideTests
/// fails a page that wasn't remade.
///
/// Markup in the JSON: `**UI label**`, `[text](https://…)` and `[PRO]` for
/// the Pro badge (`HelpText`).
nonisolated struct HelpGuide: Decodable, Sendable {
    let title: String
    let lede: String
    /// The guide on getplowr.app.
    let web: URL
    let sections: [HelpSection]

    static let resourceName = "HelpGuide"

    /// The bundled guide. A guide that can't be read shows as empty (and is
    /// logged); HelpGuideTests fails before such a build ships.
    static let shared: HelpGuide = {
        do {
            return try load(from: .main)
        } catch {
            Logger(subsystem: "Scoops.PlowR", category: "HelpGuide")
                .error("The help guide couldn't be read: \(error.localizedDescription, privacy: .public)")
            return HelpGuide(title: "PlowR Help", lede: "", web: fallbackWeb, sections: [])
        }
    }()

    private static let fallbackWeb = URL(string: "https://getplowr.app/help.html")
        ?? URL(fileURLWithPath: "/")

    static func load(from bundle: Bundle) throws -> HelpGuide {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(HelpGuide.self, from: Data(contentsOf: url))
    }

    var topics: [HelpTopic] { sections.flatMap(\.topics) }

    /// What a screen's Help item lists, in the guide's order.
    func topics(for screen: HelpScreen) -> [HelpTopic] {
        topics.filter { $0.screens.contains(screen) }
    }

    func topic(_ id: String) -> HelpTopic? {
        topics.first { $0.id == id }
    }

    /// The same topic on the website (each topic is an anchor there).
    func webURL(for topic: HelpTopic) -> URL {
        URL(string: "#\(topic.id)", relativeTo: web)?.absoluteURL ?? web
    }
}

/// How the website lays a section out; the app shows every topic the same way.
nonisolated enum HelpStyle: String, Decodable, Sendable {
    case cards, tips, faq, release
}

nonisolated struct HelpSection: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let style: HelpStyle
    let intro: String?
    let outro: String?
    let topics: [HelpTopic]
}

nonisolated struct HelpTopic: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// One line, for lists; the whole answer for a FAQ or quick tip.
    let summary: String
    /// Where in the app its Help item lists it.
    let screens: [HelpScreen]
    let pro: Bool
    /// Snow-only copy (a storm, a snow trigger), kept apart from the
    /// shared screens' wording (the Service-language guard).
    let snowOnly: Bool
    let lead: String?
    let steps: [String]
    let note: String?
    let bullets: [String]
    /// The tips (from 1.8) that point at this topic.
    let tips: [HelpTip]

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, screens, pro, snowOnly, lead, steps, note, bullets, tips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        screens = try c.decode([HelpScreen].self, forKey: .screens)
        pro = try c.decodeIfPresent(Bool.self, forKey: .pro) ?? false
        snowOnly = try c.decodeIfPresent(Bool.self, forKey: .snowOnly) ?? false
        lead = try c.decodeIfPresent(String.self, forKey: .lead)
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        bullets = try c.decodeIfPresent([String].self, forKey: .bullets) ?? []
        tips = try c.decodeIfPresent([HelpTip].self, forKey: .tips) ?? []
    }
}

/// A tip's copy: a title of five words at most and one short sentence.
nonisolated struct HelpTip: Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let message: String

    /// The rule every tip's copy keeps (HelpGuideTests): a title of at most
    /// five words, and a message of one sentence ending in a full stop.
    static func isShort(title: String, message: String) -> Bool {
        let words = title.split(separator: " ")
        let body = message.dropLast()
        return !words.isEmpty && words.count <= 5
            && message.hasSuffix(".") && message.count <= 120
            && !body.contains(where: { ".!?".contains($0) })
    }
}

/// The screens with a Help item, named in the JSON's `screens`. A name the
/// app doesn't know fails decoding, so HelpGuideTests catches a typo.
nonisolated enum HelpScreen: String, Decodable, CaseIterable, Sendable {
    case home, settings, clients, routes, routeDetail, activeRoute, schedule, documents
}

/// The guide's markup as text the app can show.
nonisolated enum HelpText {
    static func attributed(_ text: String) -> AttributedString {
        let marked = text.replacingOccurrences(of: "[PRO]", with: "**Pro**")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: marked, options: options)) ?? AttributedString(text)
    }
}
