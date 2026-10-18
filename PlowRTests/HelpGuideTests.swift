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
        try JSONDecoder().decode(HelpGuide.self, from: repoFile("PlowR/Help/HelpGuide.json"))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

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
    static func pageIsMade(from source: Data, page: String) -> Bool {
        guard let sourceHash = meta("plowr-help-source", in: page),
              let pageHash = meta("plowr-help-page", in: page) else { return false }
        let blanked = page.replacingOccurrences(
            of: "<meta name=\"plowr-help-page\" content=\"\(pageHash)\">",
            with: "<meta name=\"plowr-help-page\" content=\"\">")
        return sourceHash == sha256(source) && pageHash == sha256(Data(blanked.utf8))
    }

    @Test func websitePageIsMadeFromTheSource() throws {
        let source = try repoFile("PlowR/Help/HelpGuide.json")
        let page = try #require(String(data: repoFile("docs/help.html"), encoding: .utf8))
        #expect(Self.pageIsMade(from: source, page: page),
                "docs/help.html isn't what HelpGuide.json makes: edit the JSON, then run python3 scripts/help_guide.py")
    }

    /// The check above can fail: a page edited by hand, or a source edited
    /// without remaking the page, is caught.
    @Test func aPageOrSourceEditedAloneIsCaught() throws {
        let source = try repoFile("PlowR/Help/HelpGuide.json")
        let page = try #require(String(data: repoFile("docs/help.html"), encoding: .utf8))
        let handEdited = page.replacingOccurrences(of: "Create a route", with: "Make a route")
        #expect(handEdited != page)
        #expect(!Self.pageIsMade(from: source, page: handEdited))
        var editedSource = source
        editedSource.append(contentsOf: Array(" ".utf8))
        #expect(!Self.pageIsMade(from: editedSource, page: page))
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

    @Test func everyScreenshotIsInDocs() throws {
        let source = try #require(String(data: repoFile("PlowR/Help/HelpGuide.json"), encoding: .utf8))
        let files = source.matches(of: /"file": "([^"]+)"/).map { String($0.1) }
        #expect(!files.isEmpty)
        for file in files {
            let path = Self.root.appendingPathComponent("docs/help/\(file)").path
            #expect(FileManager.default.fileExists(atPath: path), "docs/help/\(file) is missing")
        }
    }

    /// Tips (from 1.8): a title of five words at most, one short sentence.
    @Test func tipsAreShort() throws {
        for tip in try repoGuide().topics.flatMap(\.tips) {
            #expect(tip.title.split(separator: " ").count <= 5, "\(tip.id): \(tip.title)")
            #expect(tip.message.hasSuffix("."), "\(tip.id)")
            #expect(!tip.message.dropLast().contains(". "), "\(tip.id) is one sentence")
        }
    }

    /// The Service-language guard reads Swift only, so the guide's own copy is
    /// held to it here: a topic not marked snow-only names no snow action and
    /// shows no snowflake. (Listing snow removal among the trades is fine.)
    @Test func sharedTopicsAvoidSnowWording() throws {
        let snow = /(Start|Begin|End|Finish|Next|Resume|Complete) (Plow|Snow)|Plow(ing|ed)? (Route|Stop|Job|Complete|History|Day|Done)|Snow (Route|Stop|Job|Day|Done)|\b(Plowed|Plowing|Plow)\b|Snow Plowing|Salting|Shoveling|Roof Snow|snowflake|❄/
        for topic in try repoGuide().topics where !topic.snowOnly {
            let copy = [topic.title, topic.summary, topic.lead ?? "", topic.note ?? ""]
                + topic.steps + topic.bullets + topic.tips.flatMap { [$0.title, $0.message] }
            for line in copy {
                #expect(line.firstMatch(of: snow) == nil, "\(topic.id): \(line)")
            }
        }
    }

    @Test func markupBecomesText() {
        let text = HelpText.attributed("Tap **Save**, then [Support](https://getplowr.app/support.html). [PRO]")
        #expect(String(text.characters) == "Tap Save, then Support. PRO")
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
