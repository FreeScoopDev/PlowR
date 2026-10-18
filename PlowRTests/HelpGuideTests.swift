//
//  HelpGuideTests.swift
//  PlowRTests
//

import CryptoKit
import Foundation
import Testing
@testable import PlowR

/// PlowR's help has one source, PlowR/Help/HelpGuide.json: the app bundles
/// it and scripts/help_guide.py makes the website's docs/help.html from it.
/// These tests are what keeps the two in step (the page carries the JSON's
/// hash and its own), and what holds the copy to its rules.
struct HelpGuideTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func repoFile(_ path: String) throws -> Data {
        try Data(contentsOf: Self.root.appendingPathComponent(path))
    }

    private func repoGuide() throws -> HelpGuide {
        try JSONDecoder().decode(HelpGuide.self, from: repoFile(Self.sourcePath))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let sourcePath = "PlowR/Help/HelpGuide.json"
    private static let scriptPath = "scripts/help_guide.py"

    /// The page's `<meta name="…" content="…">` value.
    private static func meta(_ name: String, in page: String) -> String? {
        let open = "<meta name=\"\(name)\" content=\""
        guard let start = page.range(of: open),
              let end = page[start.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(page[start.upperBound..<end])
    }

    /// Whether the page is the one help_guide.py made from this source: the
    /// source's hash matches, and so does the page's own, taken with its
    /// field blank, as the script takes it.
    static func pageIsMade(from source: Data, script: Data, page: String) -> Bool {
        guard let sourceHash = meta("plowr-help-source", in: page),
              let scriptHash = meta("plowr-help-script", in: page),
              let pageHash = meta("plowr-help-page", in: page) else { return false }
        let blanked = page.replacingOccurrences(
            of: "<meta name=\"plowr-help-page\" content=\"\(pageHash)\">",
            with: "<meta name=\"plowr-help-page\" content=\"\">")
        return sourceHash == sha256(source) && scriptHash == sha256(script)
            && pageHash == sha256(Data(blanked.utf8))
    }

    @Test func websitePageIsMadeFromTheSource() throws {
        let source = try repoFile(Self.sourcePath)
        let script = try repoFile(Self.scriptPath)
        let page = try #require(String(data: repoFile("docs/help.html"), encoding: .utf8))
        #expect(Self.pageIsMade(from: source, script: script, page: page),
                "docs/help.html isn't what HelpGuide.json makes: edit the JSON, then run python3 scripts/help_guide.py")
    }

    /// The check above can fail: a page edited by hand, or the source or the
    /// script edited without remaking the page, is caught.
    @Test func aPageSourceOrScriptEditedAloneIsCaught() throws {
        let source = try repoFile(Self.sourcePath)
        let script = try repoFile(Self.scriptPath)
        let page = try #require(String(data: repoFile("docs/help.html"), encoding: .utf8))
        #expect(Self.pageIsMade(from: source, script: script, page: page))
        let handEdited = page.replacingOccurrences(of: "Create a route", with: "Make a route")
        #expect(handEdited != page)
        #expect(!Self.pageIsMade(from: source, script: script, page: handEdited))
        #expect(!Self.pageIsMade(from: source + Data(" ".utf8), script: script, page: page))
        #expect(!Self.pageIsMade(from: source, script: script + Data(" ".utf8), page: page))
    }

    /// The app ships the same file (the PlowR folder is synchronized, so a
    /// resource in it is bundled) and reads it.
    @Test func theAppBundlesTheSameGuide() throws {
        let bundled = try HelpGuide.load(from: .main)
        let repo = try repoGuide()
        #expect(bundled.topics.map(\.id) == repo.topics.map(\.id))
        #expect(bundled.topics.map(\.summary) == repo.topics.map(\.summary))
        #expect(HelpGuide.shared.topics.count == repo.topics.count)
        #expect(!repo.topics.isEmpty)
    }

    @Test func idsAreUniqueAndCopyIsThere() throws {
        let guide = try repoGuide()
        let ids = guide.sections.map(\.id) + guide.topics.map(\.id) + guide.topics.flatMap { $0.tips.map(\.id) }
        #expect(Set(ids).count == ids.count, "Duplicate ids: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
        for topic in guide.topics {
            #expect(!topic.title.isEmpty && !topic.summary.isEmpty, "\(topic.id)")
            #expect(topic.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
                    "\(topic.id) is a web anchor: lower case, digits and dashes")
        }
    }

    /// Each screen with a Help item has something to list.
    @Test(arguments: [HelpScreen.clients, .routes, .schedule, .routeDetail])
    func screensWithAHelpItemHaveTopics(_ screen: HelpScreen) throws {
        #expect(!(try repoGuide()).topics(for: screen).isEmpty)
    }

    /// The JSON as plain values, every field included (`emoji` and the
    /// screenshots are web-only, so `HelpGuide` doesn't decode them).
    private func rawGuide() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: repoFile(Self.sourcePath)) as? [String: Any])
    }

    private static func topics(of guide: [String: Any]) -> [[String: Any]] {
        (guide["sections"] as? [[String: Any]] ?? []).flatMap { $0["topics"] as? [[String: Any]] ?? [] }
    }

    /// Every string in a value, at any depth, skipping the keys given.
    private static func strings(in value: Any, skipping: Set<String> = []) -> [String] {
        switch value {
        case let text as String: return [text]
        case let list as [Any]: return list.flatMap { strings(in: $0, skipping: skipping) }
        case let object as [String: Any]:
            return object.filter { !skipping.contains($0.key) }.flatMap { strings(in: $0.value, skipping: skipping) }
        default: return []
        }
    }

    @Test func everyScreenshotIsInDocs() throws {
        let shots = Self.topics(of: try rawGuide()).flatMap { $0["shots"] as? [[String: Any]] ?? [] }
        #expect(shots.count == 23)
        for shot in shots {
            let file = try #require(shot["file"] as? String)
            #expect(!(shot["alt"] as? String ?? "").isEmpty, "\(file) has no alt text")
            let path = Self.root.appendingPathComponent("docs/help/\(file)").path
            #expect(FileManager.default.fileExists(atPath: path), "docs/help/\(file) is missing")
        }
    }

    /// Tips (from 1.8): a title of five words at most, one short sentence.
    @Test func tipsAreShort() throws {
        for tip in try repoGuide().topics.flatMap(\.tips) {
            #expect(HelpTip.isShort(title: tip.title, message: tip.message), "\(tip.id): \(tip.title) / \(tip.message)")
        }
    }

    @Test(arguments: [
        ("Optimize the order", "Let PlowR put your stops in the shortest order.", true),
        ("One two three four five", "Fine.", true),
        ("One two three four five six", "Too many words in the title.", false),
        ("Two sentences", "Tap Save. Then wait.", false),
        ("Exclaims", "Tap Save! Then wait.", false),
        ("Asks", "Done?", false),
        ("No stop", "No full stop at the end", false),
        ("", "No title.", false),
    ])
    func theTipRuleRejectsLongCopy(_ title: String, _ message: String, _ short: Bool) {
        #expect(HelpTip.isShort(title: title, message: message) == short)
    }

    /// The Service-language guard reads Swift only, so the guide's own copy is
    /// held to it here: outside topics marked snow-only, no snow action and no
    /// snowflake, in any field (the web-only emoji and alt text too), the
    /// guide's and sections' own copy included. Listing snow removal among
    /// the trades is fine. The words follow the guard's COPY and ICON patterns
    /// in .github/workflows/guards.yml: a word added there belongs here too.
    private static let snow = /(Start|Begin|End|Finish|Next|Resume|Complete) (Plow|Snow)|Plow(ing|ed)? (Route|Stop|Job|Complete|History|Day|Done)|Snow (Route|Stop|Job|Day|Done)|\b(Plowed|Plowing|Plow)\b|Snow Plowing|Salting|Shoveling|Roof Snow|snowflake|\.snow\b|❄/

    private static func snowCopy(in guide: [String: Any]) -> [String] {
        var copy = strings(in: guide, skipping: ["sections"])
        for section in guide["sections"] as? [[String: Any]] ?? [] {
            copy += strings(in: section, skipping: ["topics"])
            for topic in section["topics"] as? [[String: Any]] ?? [] where topic["snowOnly"] as? Bool != true {
                copy += strings(in: topic)
            }
        }
        return copy.filter { $0.firstMatch(of: snow) != nil }
    }

    @Test func sharedCopyAvoidsSnowWording() throws {
        #expect(Self.snowCopy(in: try rawGuide()) == [])
    }

    /// The check above can fail: the storm card, made shared, is caught.
    @Test func aSnowTopicMadeSharedIsCaught() throws {
        var guide = try rawGuide()
        var sections = try #require(guide["sections"] as? [[String: Any]])
        for (s, section) in sections.enumerated() {
            var topics = section["topics"] as? [[String: Any]] ?? []
            for (t, topic) in topics.enumerated() where topic["id"] as? String == "storm-card" {
                topics[t]["snowOnly"] = false
            }
            sections[s]["topics"] = topics
        }
        guide["sections"] = sections
        #expect(!Self.snowCopy(in: guide).isEmpty)
    }

    /// Only the markup both the app and the script read the same way:
    /// **bold**, [PRO], and links to https: or mailto:. The app's Markdown
    /// would also read *x*, _x_ and `x`, which the website shows as typed.
    @Test func onlySharedMarkup() throws {
        for text in Self.strings(in: try rawGuide()) {
            let links = text.matches(of: /\[([^\]]+)\]\(([^)]*)\)/)
            for link in links {
                let url = String(link.2)
                #expect(url.hasPrefix("https://") || url.hasPrefix("mailto:"), "\(url)")
            }
            var rest = text.replacing(/\*\*[^*]+\*\*/, with: "")
            rest = rest.replacing(/\[([^\]]+)\]\([^)]*\)/, with: "")
            rest = rest.replacingOccurrences(of: "[PRO]", with: "")
            #expect(rest.firstMatch(of: /[*_`\[\]<>]/) == nil, "Markup the website and the app would show differently: \(text)")
        }
    }

    @Test func markupBecomesText() {
        let text = HelpText.attributed("Tap **Save**, then [Support](https://getplowr.app/support.html). [PRO]")
        #expect(String(text.characters) == "Tap Save, then Support. Pro")
        let save = text.runs.first { String(text[$0.range].characters) == "Save" }
        #expect(save?.inlinePresentationIntent == .stronglyEmphasized)
        let link = text.runs.first { $0.link != nil }
        #expect(link?.link?.absoluteString == "https://getplowr.app/support.html")
    }

    @Test func aTopicLinksToItsPlaceOnTheWeb() throws {
        let guide = try repoGuide()
        let topic = try #require(guide.topic("create-route"))
        #expect(guide.webURL(for: topic).absoluteString == "https://getplowr.app/help.html#create-route")
    }
}
