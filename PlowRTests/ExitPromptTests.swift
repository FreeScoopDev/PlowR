import Foundation
import Testing
@testable import PlowR

/// Leaving a stop's job-site area only offers the text to the next client,
/// once the phone has stayed out; it never completes the stop (Joe,
/// 2026-10-18). Before, an exit with the next client set to skip texts, or
/// on a device that can't text, completed the stop with no tap.
struct ExitPromptTests {
    let stop = UUID()
    let exitedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func left(at time: Date?) -> SiteTimes {
        var site = SiteTimes()
        site.arrivedAt = exitedAt.addingTimeInterval(-600)
        site.leftAt = time
        return site
    }

    func offer(currentStopID: UUID?? = nil, site: SiteTimes? = nil, hasNextStop: Bool = true,
               canText: Bool = true, isPresentingSomething: Bool = false, after seconds: TimeInterval) -> Bool {
        ExitPrompt.shouldOffer(exitStopID: stop.uuidString, exitedAt: exitedAt,
                               currentStopID: currentStopID ?? stop, site: site ?? left(at: exitedAt),
                               hasNextStop: hasNextStop, canText: canText,
                               isPresentingSomething: isPresentingSomething,
                               now: exitedAt.addingTimeInterval(seconds))
    }

    @Test func offersOnceThePhoneHasStayedOut() {
        #expect(!offer(after: 0))
        #expect(!offer(after: ExitPrompt.delay - 1))
        #expect(offer(after: ExitPrompt.delay))
        #expect(offer(after: 5 * 60))
    }

    @Test func aWobbleBackInOffersNothing() {
        // Back in: SiteTimes clears leftAt.
        #expect(!offer(site: left(at: nil), after: ExitPrompt.delay))
        // Out again since: that newer exit is the one to wait on.
        #expect(!offer(site: left(at: exitedAt.addingTimeInterval(20)), after: ExitPrompt.delay))
    }

    @Test func aNextClientWhoSkipsTextsIsNeverOffered() {
        // Covers a device that can't text too: the screen passes both as canText.
        #expect(!offer(canText: false, after: ExitPrompt.delay))
        #expect(!offer(canText: false, after: 5 * 60))
    }

    @Test func onlyForTheStopStillCurrent() {
        #expect(!offer(currentStopID: .some(UUID()), after: ExitPrompt.delay))
        #expect(!offer(currentStopID: .some(nil), after: ExitPrompt.delay))
    }

    @Test func notOnTheLastStopOrOverAnotherSheet() {
        #expect(!offer(hasNextStop: false, after: ExitPrompt.delay))
        #expect(!offer(isPresentingSomething: true, after: ExitPrompt.delay))
    }

    @Test func anOldExitIsNotOffered() {
        #expect(offer(after: ExitPrompt.maxAge))
        #expect(!offer(after: ExitPrompt.maxAge + 1))
    }

    /// The route screen's exit handling must only open the prompt: nothing
    /// else in it may complete, pass or skip a stop.
    @Test func theRouteScreenNeverCompletesOnAnExit() throws {
        let source = try String(contentsOfFile: Self.routeScreenPath, encoding: .utf8)
        let start = try #require(source.range(of: ".task(id: SiteMonitor.shared.lastExit)"))
        let end = try #require(source.range(of: "openNotifyPrompt()", range: start.upperBound..<source.endIndex))
        let handler = source[start.lowerBound..<end.upperBound]
        for call in ["advance(", "triggerNotifyPrompt(", "completeCurrentStop", "passCurrentStop"] {
            #expect(!handler.contains(call), "exit handler calls \(call)")
        }
        #expect(!source.contains("onChange(of: SiteMonitor.shared.lastExit"))
    }

    static let routeScreenPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("PlowR/Views/ActiveRoute/ActiveRouteView.swift").path
}
