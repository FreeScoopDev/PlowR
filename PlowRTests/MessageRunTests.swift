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
struct MessageRunTests {
    private let ids = (0..<5).map { _ in UUID() }

    @Test func everyoneSentFinishes() {
        var run = MessageRun(ids)
        #expect(run.current == ids[0])
        for next in ids.dropFirst() {
            #expect(run.finish(.sent) == .compose(next))
        }
        #expect(run.finish(.sent) == .finished)
        #expect(run.sent == ids)
        #expect(run.current == nil)
    }

    @Test func aCancelledTextStopsTheRunAndKeepsTheRest() {
        var run = MessageRun(ids)
        _ = run.finish(.sent)
        _ = run.finish(.sent)
        #expect(run.finish(.cancelled) == .stopped(unsent: Array(ids[2...])))
        #expect(run.sent == Array(ids[..<2]))
        #expect(run.stoppedNote(failed: false)
                == "A text was cancelled. Sent to 2 of 5. The 3 not sent yet are still selected: tap Send to carry on.")
    }

    @Test func aFailedTextStopsItToo() {
        var run = MessageRun(ids)
        #expect(run.finish(.failed) == .stopped(unsent: ids))
        #expect(run.sent.isEmpty)
        #expect(run.stoppedNote(failed: true).hasPrefix("A text didn't send."))
    }

    @Test func anEmptyRunIsFinished() {
        var run = MessageRun([])
        #expect(run.current == nil)
        #expect(run.finish(.sent) == .finished)
    }

    // Messages' own results: only a text that went counts as sent.
    @Test func onlyASentTextCountsAsSent() {
        #expect(MessageOutcome(.sent) == .sent)
        #expect(MessageOutcome(.cancelled) == .cancelled)
        #expect(MessageOutcome(.failed) == .failed)
    }
}
