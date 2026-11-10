//
//  InvoiceAddressTermsTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PlowR

/// A business's mailing address and payment terms (1.9 review): an invoice
/// said "Make check payable to" with nowhere to mail it, and every new one
/// was due in 30 days.
@MainActor
struct InvoiceAddressTermsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func line(_ price: Double) -> ProposalLineItem {
        ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price)
    }

    @discardableResult
    private func profile(_ h: Harness, terms: Int?, operatorID: String = "op") -> BusinessProfile {
        let profile = BusinessProfile(operatorID: operatorID)
        profile.paymentTermsDays = terms
        h.context.insert(profile)
        return profile
    }

    private func day(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    // MARK: The terms a profile gives

    @Test func termsComeFromTheProfile() {
        #expect(InvoiceTerms.days(for: nil) == 30)                       // no profile yet
        let profile = BusinessProfile(operatorID: "op")
        #expect(InvoiceTerms.days(for: profile) == 30)                   // never chosen
        profile.paymentTermsDays = 0
        #expect(InvoiceTerms.days(for: profile) == 0)                    // due on receipt
        profile.paymentTermsDays = 15
        #expect(InvoiceTerms.days(for: profile) == 15)
        profile.paymentTermsDays = -3
        #expect(InvoiceTerms.days(for: profile) == 30)                   // nonsense reads as the default
    }

    @Test func theChoicesAndTheirNames() {
        #expect(InvoiceTerms.choices == [0, 7, 15, 30, 45, 60])
        #expect(InvoiceTerms.choices.map { InvoiceTerms.name(days: $0) }
                == ["Due on receipt", "Net 7", "Net 15", "Net 30", "Net 45", "Net 60"])
    }

    // The builder's starting due date is this one.
    @Test func aDueDateOnTheProfilesTerms() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = BusinessProfile(operatorID: "op")
        profile.paymentTermsDays = 0
        #expect(InvoiceTerms.dueDate(from: now, profile: profile) == InvoiceTerms.dueDate(from: now, days: 0))
        #expect(day(InvoiceTerms.dueDate(from: now, profile: profile)) == day(now))
        profile.paymentTermsDays = nil
        #expect(InvoiceTerms.dueDate(from: now, profile: profile) == InvoiceTerms.dueDate(from: now))
    }

    // MARK: Every new invoice follows the profile

    @Test func recordedAndBilledWorkFollowsTheTerms() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 15)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 15))
    }

    // Another business's terms on the same device aren't used.
    @Test func onlyThisBusinesssTermsAreUsed() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 0, operatorID: "other")
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 30))
    }

    @Test func convertToInvoiceFollowsTheTerms() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 7)
        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        #expect(InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
        #expect(proposal.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 7))
    }

    @Test func aRevisionFollowsTheTerms() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 45)
        let original = Proposal(operatorID: "op", client: h.client)
        original.invoiceNumber = "INV-0001"
        original.invoiceDueDate = InvoiceTerms.dueDate(from: h.clock.addingTimeInterval(-20 * 86_400))
        h.context.insert(original)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(revision.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 45))
    }

    // A contract installment has no due date until it's sent.
    @Test func markSentWithNoDueDateFollowsTheTerms() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 0)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        h.context.insert(invoice)
        DocumentSent.markSent(invoice, in: h.context, now: h.clock)
        #expect(invoice.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 0))
    }

    @Test func theEditScreenShowsADateOnTheTerms() throws {
        let h = try Harness(stopCount: 0)
        profile(h, terms: 60)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        h.context.insert(invoice)
        let edits = DocumentEdits(editing: invoice, now: h.clock)
        #expect(edits.dueDate == InvoiceTerms.dueDate(from: h.clock, days: 60))
        // One that has a date shows it.
        let due = InvoiceTerms.dueDate(from: h.clock, days: 3)
        invoice.invoiceDueDate = due
        #expect(DocumentEdits(editing: invoice, now: h.clock).dueDate == due)
    }

    // MARK: Saved invoices keep their dates

    @Test func changingTheTermsChangesNoSavedInvoice() throws {
        let h = try Harness(stopCount: 0)
        let business = profile(h, terms: nil)
        let draft = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                               now: h.clock, in: h.context)
        let sent = ServiceLog.newDraftInvoice(for: h.client, items: [line(50)], operatorID: "op",
                                              now: h.clock, in: h.context)
        DocumentSent.markSent(sent, in: h.context, now: h.clock)
        let draftDue = draft.invoiceDueDate, sentDue = sent.invoiceDueDate
        #expect(draftDue == InvoiceTerms.dueDate(from: h.clock))
        business.paymentTermsDays = 0
        try h.context.save()
        #expect(draft.invoiceDueDate == draftDue)
        #expect(sent.invoiceDueDate == sentDue)
        // Sending the draft later, before its due day, keeps its date too.
        DocumentSent.markSent(draft, in: h.context, now: h.clock.addingTimeInterval(2 * 86_400))
        #expect(draft.invoiceDueDate == draftDue)
        #expect(DocumentEdits(editing: draft, now: h.clock).dueDate == draftDue)
    }

    // MARK: Never due before it's sent

    @Test func aDraftSentAfterItsDueDayIsDueTheDayItsSent() throws {
        let h = try Harness(stopCount: 0)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        let monday = h.clock.addingTimeInterval(-3 * 86_400)
        invoice.invoiceDueDate = InvoiceTerms.dueDate(from: monday, days: 0)    // due on receipt, Monday
        h.context.insert(invoice)
        DocumentSent.markSent(invoice, in: h.context, now: h.clock)           // sent Thursday
        #expect(invoice.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock, days: 0))
        #expect(invoice.invoiceStatus(now: h.clock) == .sent)                 // not overdue on sending
    }

    @Test func aDueDayOnOrAfterTheSendDayIsKept() throws {
        let h = try Harness(stopCount: 0)
        let sameDay = Proposal(operatorID: "op", client: h.client)
        sameDay.invoiceNumber = "INV-0001"
        let earlyToday = day(h.clock).addingTimeInterval(60)                   // today, before the send time
        sameDay.invoiceDueDate = earlyToday
        h.context.insert(sameDay)
        DocumentSent.markSent(sameDay, in: h.context, now: h.clock)
        #expect(sameDay.invoiceDueDate == earlyToday)

        let later = Proposal(operatorID: "op", client: h.client)
        later.invoiceNumber = "INV-0002"
        let due = InvoiceTerms.dueDate(from: h.clock, days: 15)
        later.invoiceDueDate = due
        h.context.insert(later)
        DocumentSent.markSent(later, in: h.context, now: h.clock)
        #expect(later.invoiceDueDate == due)
    }

    // Only a draft moves: an invoice already out keeps its date when marked again.
    @Test func anInvoiceAlreadySentKeepsAPastDueDate() throws {
        let h = try Harness(stopCount: 0)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        let due = InvoiceTerms.dueDate(from: h.clock.addingTimeInterval(-10 * 86_400), days: 0)
        invoice.invoiceDueDate = due
        invoice.invoiceSentAt = h.clock.addingTimeInterval(-10 * 86_400)
        h.context.insert(invoice)
        DocumentSent.markSent(invoice, in: h.context, now: h.clock)
        #expect(invoice.invoiceDueDate == due)
    }

    // MARK: The terms a document states

    @Test func statedTermsComeFromTheDocumentsOwnDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        func date(_ d: Int, _ hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2027, month: 3, day: d, hour: hour)) ?? .distantPast
        }
        let issued = date(1, 15)
        func stated(_ days: Int) -> String? {
            let due = calendar.date(byAdding: .day, value: days, to: issued) ?? issued
            return InvoiceTerms.statedTerms(issued: issued, due: due, calendar: calendar)
        }
        #expect(stated(0) == "Due on receipt")
        #expect(stated(-2) == "Due on receipt")                               // due before it's dated
        #expect(InvoiceTerms.statedTerms(issued: issued, due: date(1, 6), calendar: calendar) == "Due on receipt")
        #expect(stated(7) == "Net 7")
        #expect(stated(15) == "Net 15")
        #expect(stated(30) == "Net 30")
        #expect(stated(45) == "Net 45")
        #expect(stated(60) == "Net 60")
        #expect(stated(1) == nil)
        #expect(stated(14) == nil)
        #expect(stated(31) == nil)
        #expect(stated(90) == nil)
        // Counted in calendar days, whatever the times.
        #expect(InvoiceTerms.statedTerms(issued: date(1, 23), due: date(16, 0), calendar: calendar) == "Net 15")
    }

    // MARK: Setup

    // Setup asks for the address, not the terms (Net 30 until changed).
    @Test func setupSavesTheAddressOnly() throws {
        let h = try Harness(stopCount: 0)
        var answers = FirstRun.Answers()
        answers.address = "  PO Box 9\nSpringvale \n"
        FirstRun.save(answers, operatorID: "op", in: h.context)
        let saved = BusinessProfiles.current(try h.context.fetch(FetchDescriptor<BusinessProfile>()), operatorID: "op")
        #expect(saved?.address == "PO Box 9\nSpringvale")
        #expect(saved?.paymentTermsDays == nil)
    }

    // MARK: Merging duplicate profiles

    @Test func mergingCarriesTheAddressAndTerms() {
        let keep = BusinessProfile(operatorID: "op")
        let other = BusinessProfile(operatorID: "op")
        other.address = "PO Box 9\nSpringvale"
        other.paymentTermsDays = 15
        BusinessProfiles.fill(keep, from: other)
        #expect(keep.address == "PO Box 9\nSpringvale")
        #expect(keep.paymentTermsDays == 15)

        // What the survivor has is kept; 0 (due on receipt) is a choice.
        let chosen = BusinessProfile(operatorID: "op")
        chosen.address = "12 Example Rd"
        chosen.paymentTermsDays = 0
        BusinessProfiles.fill(chosen, from: other)
        #expect(chosen.address == "12 Example Rd")
        #expect(chosen.paymentTermsDays == 0)
    }

    // MARK: Documents

    private func text(of data: Data) throws -> String {
        let document = try #require(PDFDocument(data: data))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test func theAddressLinesForAHeader() {
        #expect(PDFGenerator.addressLines("PO Box 9\n\n  Springvale  \nUnit 2\nExtra") == ["PO Box 9", "Springvale", "Unit 2"])
        #expect(PDFGenerator.addressLines(" \n ").isEmpty)
        #expect(PDFGenerator.addressLine("PO Box 9\n\nSpringvale\r\nUnit 2") == "PO Box 9, Springvale, Unit 2")
    }

    @Test func anInvoicePrintsTheAddressTermsAndWhereToMailACheck() throws {
        let client = Client(name: "Pat", phone: "", address: "", operatorID: "op")
        let invoice = Proposal(operatorID: "op", client: client)
        invoice.invoiceNumber = "INV-0001"
        invoice.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        invoice.invoiceDueDate = InvoiceTerms.dueDate(from: invoice.createdAt, days: 15)
        let profile = BusinessProfile(operatorID: "op")
        profile.companyName = "Acme Grounds"
        profile.address = "PO Box 9\nSpringvale"
        profile.paymentTermsDays = 0          // changed since: the invoice still says Net 15
        let check = PaymentMethod(operatorID: "op", label: "Check", value: "Acme Grounds", methodType: "check")
        let pdf = try text(of: PDFGenerator.generate(proposal: invoice, profile: profile, paymentMethods: [check],
                                                     madeWithPlowR: false))
        #expect(pdf.contains("PO Box 9"))
        #expect(pdf.contains("Springvale"))
        #expect(pdf.contains("Net 15"))
        #expect(!pdf.contains("Due on receipt"))
        #expect(pdf.contains("Make check payable to: Acme Grounds"))
        #expect(pdf.contains("Mail to: PO Box 9, Springvale"))
    }

    @Test func noAddressPrintsNoMailToLine() throws {
        let client = Client(name: "Pat", phone: "", address: "", operatorID: "op")
        let invoice = Proposal(operatorID: "op", client: client)
        invoice.invoiceNumber = "INV-0001"
        invoice.invoiceDueDate = InvoiceTerms.dueDate(from: invoice.createdAt, days: 0)
        let check = PaymentMethod(operatorID: "op", label: "Check", value: "Acme Grounds", methodType: "check")
        let pdf = try text(of: PDFGenerator.generate(proposal: invoice, profile: BusinessProfile(operatorID: "op"),
                                                     paymentMethods: [check], madeWithPlowR: false))
        #expect(pdf.contains("Due on receipt"))
        #expect(!pdf.contains("Mail to"))
    }

    // The contract and Service Report headers print it on one line.
    @Test func aPageWriterHeaderPrintsTheAddress() throws {
        let profile = BusinessProfile(operatorID: "op")
        profile.companyName = "Acme Grounds"
        profile.phone = "555-0100"
        profile.address = "PO Box 9\nSpringvale"
        let data = PDFPageWriter.document(profile: profile) { page in
            page.header(title: "SERVICE CONTRACT", subtitle: "Pat", profile: profile)
        }
        let pdf = try text(of: data)
        #expect(pdf.contains("PO Box 9, Springvale"))
        #expect(pdf.contains("555-0100"))
    }
}
