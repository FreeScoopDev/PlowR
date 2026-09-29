//
//  MessageRunTests.swift
//  PlowRTests
//

import Foundation
import MessageUI
import Testing
@testable import PlowR

/// Texting route clients one at a time (MassMessageView). Cancelling a
/// client's text used to open the next client's, with no way to stop and no
/// record of who had been sent it.
@MainActor
struct MessageRunTests {
    private let people = (0..<5).map { MessageRun.Recipient(id: UUID(), phone: "555-010\($0)") }
    private var ids: [UUID] { people.map(\.id) }

    @Test func everyoneSentFinishes() {
        var run = MessageRun(people)
        #expect(run.current == people[0])
        for next in people.dropFirst() {
            #expect(run.finish(.sent) == .compose(next))
        }
        #expect(run.finish(.sent) == .finished)
        #expect(run.sent == ids)
        #expect(run.current == nil)
    }

    @Test func aCancelledTextStopsTheRunAndKeepsTheRest() {
        var run = MessageRun(people)
        _ = run.finish(.sent)
        _ = run.finish(.sent)
        #expect(run.finish(.cancelled) == .stopped(unsent: Array(ids[2...])))
        #expect(run.sent == Array(ids[..<2]))
        #expect(run.stoppedNote(failed: false) == "A text was cancelled. Sent to 2 of 5. "
                + "The 3 clients not texted yet are still selected: tap Send to carry on.")
    }

    @Test func aFailedTextStopsItToo() {
        var run = MessageRun(people)
        #expect(run.finish(.failed) == .stopped(unsent: ids))
        #expect(run.sent.isEmpty)
        #expect(run.stoppedNote(failed: true).hasPrefix("A text didn't send."))
    }

    @Test func oneClientLeftReadsRight() {
        var run = MessageRun(Array(people[..<2]))
        _ = run.finish(.sent)
        _ = run.finish(.cancelled)
        #expect(run.stoppedNote(failed: false) == "A text was cancelled. Sent to 1 of 2. "
                + "The 1 client not texted yet is still selected: tap Send to carry on.")
    }

    @Test func anEmptyRunIsFinished() {
        var run = MessageRun([])
        #expect(run.current == nil)
        #expect(run.finish(.sent) == .finished)
    }

    // The screen's whole step after a text: a client texted leaves the
    // selection at once, so nothing (a stall, another Send) can text them
    // twice, and the run it keeps has moved on.
    @Test func aSentTextMovesOnAndDeselectsThatClient() {
        let step = MessageRun.step(MessageRun(people), outcome: .sent, selection: Set(ids))
        #expect(step.action == .composeNext)
        #expect(step.run?.current == people[1])
        #expect(step.selection == Set(ids.dropFirst()))
        #expect(step.note == nil)
    }

    @Test func theLastSentTextClosesTheScreen() {
        let step = MessageRun.step(MessageRun([people[0]]), outcome: .sent, selection: [ids[0]])
        #expect(step.action == .close)
        #expect(step.run == nil)
        #expect(step.selection.isEmpty)
    }

    @Test func aCancelStopsAndLeavesOnlyTheUntextedSelected() {
        var run = MessageRun(people)
        _ = run.finish(.sent)
        let step = MessageRun.step(run, outcome: .cancelled, selection: Set(ids))
        #expect(step.action == .stay)
        #expect(step.run == nil)
        #expect(step.selection == Set(ids.dropFirst()))
        #expect(step.note?.hasPrefix("A text was cancelled. Sent to 1 of 5.") == true)
    }

    // Messages' own results: only a text that went counts as sent.
    @Test func onlyASentTextCountsAsSent() {
        #expect(MessageOutcome(.sent) == .sent)
        #expect(MessageOutcome(.cancelled) == .cancelled)
        #expect(MessageOutcome(.failed) == .failed)
    }
}
