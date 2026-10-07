import Foundation
import Testing
@testable import PlowR

/// The Request Service link: written by the app, read by the web page and
/// back by the app, with nothing on a server. Everything read is untrusted.
struct RequestLinkTests {
    typealias Link = RequestLink

    @Test func aBusinessLinkRoundTrips() throws {
        let business = Link.Business(name: "Pat's Lawn & Snow", phone: "(603) 555-0100", email: "pat@example.com",
                                     services: ["Snow Removal", "Lawn Care", "Mulch | Edging"],
                                     welcome: "Tell us about your property.")
        let url = try #require(Link.url(for: business))
        #expect(url.absoluteString.hasPrefix("https://getplowr.app/r/#n=") && url.absoluteString.hasSuffix("&v=1"))
        #expect(url.query == nil)                       // all after the #: never sent to the server
        let back = try #require(Link.business(from: url))
        #expect(back.name == business.name && back.phone == business.phone && back.email == business.email)
        #expect(back.services == ["Snow Removal", "Lawn Care", "Mulch / Edging"])
        #expect(back.welcome == business.welcome)
    }

    @Test func aBusinessNeedsANameAndAPhone() {
        #expect(Link.url(for: .init(name: "", phone: "603-555-0100")) == nil)
        #expect(Link.url(for: .init(name: "Pat's", phone: "555")) == nil)
    }

    @Test func aRequestRoundTripsThroughTheAddToPlowRLink() throws {
        let request = Link.Request(name: "Kim Doe 🙂", phone: "+1 603 555 0199", email: "kim@example.com",
                                   address: "12 Main St, Claremont, NH 03743", service: "Snow Removal",
                                   when: .seasonal, notes: "Long driveway.\nGate code 4#21 & dog = friendly")
        let url = try #require(Link.url(for: request))
        #expect(url.absoluteString.hasPrefix("https://getplowr.app/lead/#n=") && url.absoluteString.hasSuffix("&v=1"))
        #expect(Link.request(from: url) == request)
    }

    // What the web page writes: URLSearchParams puts + for a space and
    // %-encodes the rest; fields may come in any order.
    @Test func whatAWebFormWritesIsRead() throws {
        let url = try #require(URL(string: "https://getplowr.app/lead/#t=Back+gate%2C+please&n=Kim+Doe&p=603-555-0199&w=once&a=1+Elm+St&v=1&s=Lawn+Care"))
        let request = try #require(Link.request(from: url))
        #expect(request.name == "Kim Doe" && request.address == "1 Elm St" && request.service == "Lawn Care")
        #expect(request.when == .oneTime && request.notes == "Back gate, please")
    }

    // The page's Open in PlowR button, when the web link doesn't open the app.
    @Test func theAppsOwnLinkIsReadToo() throws {
        let url = try #require(URL(string: "plowr://lead#v=1&n=Kim+Doe&p=6035550199"))
        #expect(Link.request(from: url)?.name == "Kim Doe")
    }

    @Test func onlyOurLinksAreRead() throws {
        for text in ["https://example.com/lead/#n=Kim&p=6035550199",
                     "https://getplowr.app/r/#n=Kim&p=6035550199",              // a business link, not a request
                     "http://getplowr.app/lead/#n=Kim&p=6035550199",
                     "plowr://activeRoute"] {
            #expect(Link.request(from: try #require(URL(string: text))) == nil, "\(text)")
        }
    }

    // Anyone can make a link: what it carries is cut to size and cleaned,
    // and a request with no name or no number to call back is refused.
    @Test func untrustedFieldsAreCleaned() throws {
        let long = String(repeating: "x", count: 5_000)
        let url = try #require(URL(string: "https://getplowr.app/lead/#v=9&n=%20Kim%0D%0ADoe%07%20&p=603-555-0199&a=\(long)&t=\(long)&e=not-an-email&w=weekly&zz=ignored"))
        let request = try #require(Link.request(from: url))      // a later version is still read
        #expect(request.name == "Kim  Doe")
        #expect(request.address.count == Link.Limit.address && request.notes.count == Link.Limit.notes)
        #expect(request.email.isEmpty && request.when == nil)
        #expect(Link.request(from: try #require(URL(string: "https://getplowr.app/lead/#n=Kim&p=12"))) == nil)
        #expect(Link.request(from: try #require(URL(string: "https://getplowr.app/lead/#p=6035550199"))) == nil)
        #expect(Link.request(from: try #require(URL(string: "https://getplowr.app/lead/"))) == nil)
    }

    @Test func aFieldGivenTwiceIsReadOnce() throws {
        let url = try #require(URL(string: "https://getplowr.app/lead/#n=Kim&n=Mallory&p=6035550199"))
        #expect(Link.request(from: url)?.name == "Kim")
    }

    // The link the request page (docs/r/, docs/request-link.js) builds, as
    // URLSearchParams writes it in a browser, v=1 last: what the page
    // writes, the app reads, character for character. Check the page
    // against this same link when either side changes.
    @Test func theRequestPagesLinkIsRead() throws {
        let url = try #require(URL(string: "https://getplowr.app/lead/#n=Kim+Doe+%F0%9F%99%82&p=%2B1+603+555+0199&e=kim%40example.com&a=12+Main+St%2C+Claremont%2C+NH+03743&s=Snow+Removal&w=season&t=Long+driveway.%0AGate+code+4%2321+%26+dog+%3D+friendly+%2B+calm.&v=1"))
        #expect(Link.request(from: url) == Link.Request(
            name: "Kim Doe 🙂", phone: "+1 603 555 0199", email: "kim@example.com",
            address: "12 Main St, Claremont, NH 03743", service: "Snow Removal", when: .seasonal,
            notes: "Long driveway.\nGate code 4#21 & dog = friendly + calm."))
    }

    // Joiners make emoji and many scripts; direction overrides make a name
    // show as something else. The first stay, the second go.
    @Test func joinersStayAndOverridesGo() throws {
        let family = "👨\u{200D}👩\u{200D}👧 Family", persian = "می\u{200C}خواهم", farmer = "👩🏽\u{200D}🌾 Ana"
        for name in [family, persian, farmer] {
            let url = try #require(Link.url(for: Link.Request(name: name, phone: "6035550199")))
            #expect(Link.request(from: url)?.name == name, "\(name)")
        }
        #expect(Link.clean("K\u{202E}moc.evil\u{202C}iM\u{200B}", limit: 100) == "Kmoc.eviliM")
        for blank in ["\u{3164}", "\u{FE0F}", "\u{034F}", "\u{0301}\u{0301}"] {
            #expect(Link.url(for: Link.Request(name: blank, phone: "6035550199")) == nil)
        }
        #expect(Link.url(for: Link.Request(name: "   ", phone: "6035550199")) == nil)
    }

    // A "character" can hold thousands of stacked marks: the limit is on
    // scalars too, so a field stays the size it says.
    @Test func stackedMarksDontBreakTheLimit() {
        let zalgo = String(repeating: "e" + String(repeating: "\u{0301}", count: 50), count: 100)
        let name = Link.clean(zalgo, limit: Link.Limit.name)
        #expect(name.unicodeScalars.count <= Link.scalarLimit(Link.Limit.name))
        #expect(Link.clean(String(repeating: "👩🏽\u{200D}🌾", count: 200), limit: 100).count == 100)   // 4 scalars each
    }

    // A phone is written as phone numbers are; words or an extension aren't
    // a number to call.
    @Test func phoneNumbersAreNumbers() {
        #expect(Link.phoneDigits("(603) 555-0100") == "6035550100")
        #expect(Link.phoneDigits("+44 20 7946 0958") == "442079460958")
        #expect(Link.phoneDigits("Call me at 6035550100 or visit") == nil)
        #expect(Link.phoneDigits("603-555-0100 ext 1234") == nil)
        #expect(Link.phoneDigits("1234567890123456") == nil)          // 16 digits
        #expect(Link.phoneDigits("123456") == nil)
        for written in ["030/1234567", "603\u{00A0}555\u{00A0}0100", "603\u{2011}555\u{2011}0100", "603–555–0100"] {
            #expect(Link.phoneDigits(written) != nil, "\(written)")
        }
    }

    @Test func emailsLookLikeEmails() throws {
        #expect(Link.validEmail("pat@example.com") == "pat@example.com")
        for bad in ["@", "pat@", "pat@example", "javascript:alert(1)", "pat @example.com", "a@b.c?body=hi", "a@b..c"] {
            #expect(Link.validEmail(bad).isEmpty, "\(bad)")
        }
        let business = Link.Business(name: "Pat's", phone: "6035550100", email: "javascript:alert(1)")
        let link = try #require(Link.url(for: business))
        #expect(Link.business(from: link)?.email.isEmpty == true)
    }

    // Messages takes a final "." as the end of a sentence: links end with v=1.
    @Test func linksEndWithTheVersion() throws {
        let url = try #require(Link.url(for: Link.Request(name: "Kim", phone: "6035550199", notes: "Long driveway.")))
        #expect(url.absoluteString.hasSuffix("&v=1"))
    }

    // Only what's after the #: the ?query is sent to the website's server,
    // and nothing is read from it.
    @Test func theQueryIsNeverRead() throws {
        for text in ["https://getplowr.app/lead/?n=Kim&p=6035550199", "plowr://lead?n=Kim&p=6035550199",
                     "https://evilgetplowr.app/lead/#n=Kim&p=6035550199",
                     "https://getplowr.app.evil.com/lead/#n=Kim&p=6035550199"] {
            #expect(Link.request(from: try #require(URL(string: text))) == nil, "\(text)")
        }
    }

    @Test func aDamagedLeadLinkIsStillKnownAsOne() throws {
        let cut = try #require(URL(string: "https://getplowr.app/lead/#n=Kim"))
        #expect(Link.isLeadLink(cut) && Link.request(from: cut) == nil)
        #expect(!Link.isLeadLink(try #require(URL(string: "https://getplowr.app/r/#n=Kim"))))
    }

    @Test func aHugeLinkIsntRead() throws {
        let url = try #require(URL(string: "https://getplowr.app/lead/#n=Kim&p=6035550199&t=" + String(repeating: "x", count: 90_000)))
        #expect(Link.request(from: url) == nil)
    }

    @Test func aBusinessLinkIsCheckedWhenRead() throws {
        #expect(Link.business(from: try #require(URL(string: "https://getplowr.app/r/#n=Pat&v=1"))) == nil)
        let many = (1...20).map { "S\($0)" }.joined(separator: "%7C")
        let link = try #require(URL(string: "https://getplowr.app/r/#n=Pat&p=6035550100&s=\(many)"))
        #expect(Link.business(from: link)?.services.count == Link.Limit.services)
    }

    // Whatever the app builds, it can read back: a link too long to read
    // isn't built.
    @Test func whatIsBuiltCanBeRead() throws {
        let emoji = String(repeating: "👩🏽\u{200D}🌾", count: 1_000)
        let full = Link.Request(name: emoji, phone: "6035550199", email: "kim@example.com", address: emoji,
                                service: emoji, when: .ongoing, notes: emoji)
        if let url = Link.url(for: full) { #expect(Link.request(from: url) != nil) }
        let plain = try #require(Link.url(for: Link.Request(name: "Kim", phone: "6035550199", notes: "Hi.")))
        #expect(Link.request(from: plain) != nil)
    }
}
