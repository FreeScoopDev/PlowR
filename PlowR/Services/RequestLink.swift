import Foundation

/// The Request Service link, without a server. A business shares its link
/// (`business`): getplowr.app/r/ with its public details after the `#`. The
/// page there (docs/r/) shows a short form, and Send opens the prospect's
/// own Messages, addressed to the business, with the request and an
/// **Add to PlowR** link (`request`): getplowr.app/lead/ with the request
/// after the `#`. Tapped on the business's phone, that opens PlowR at a
/// filled-in new lead.
///
/// Everything goes after the `#`, which a browser never sends to a server:
/// getplowr.app (GitHub Pages) sees neither the business's details nor the
/// prospect's. Fields are written as a web form writes them (the page's
/// JavaScript uses URLSearchParams), and read the same way: a space may be
/// `+` or `%20`. Everything read from a link is untrusted, from anyone: cut
/// to a sensible length, cleaned of control characters, and only saved when
/// the business taps Save.
nonisolated enum RequestLink {
    static let host = "getplowr.app"
    static let businessPath = "/r/"
    static let leadPath = "/lead/"
    /// The app's own link, when the web link doesn't open PlowR directly:
    /// plowr://lead#… (the page's Open in PlowR button).
    static let appScheme = PlowRLink.scheme
    /// Written into every link, last (Messages takes a final "." as the end
    /// of a sentence, not of the link). A link with any version, or none, is
    /// read for the fields this version knows.
    static let version = 1
    /// The longest link read, or built: about the most the field limits
    /// allow (every character a 4-scalar emoji is about 70 KB). A longer
    /// one isn't real; the app never builds one it couldn't read back.
    static let largestFragment = 80_000

    /// The longest each field is kept, in characters.
    enum Limit {
        static let name = 100
        static let phone = 30
        static let email = 120
        static let address = 200
        static let service = 60
        static let services = 12
        static let welcome = 200
        static let notes = 1_000
    }

    // MARK: - The business's link

    /// What a business's link carries: what's public anyway.
    struct Business: Equatable {
        var name: String
        var phone: String
        var email = ""
        /// Offered on the form, in order.
        var services: [String] = []
        /// An optional line at the top of the form.
        var welcome = ""
    }

    /// The link a business shares; nil without a name and a phone to text.
    static func url(for business: Business) -> URL? {
        let name = clean(business.name, limit: Limit.name), phone = clean(business.phone, limit: Limit.phone)
        guard hasLetterOrDigit(name), phoneDigits(phone) != nil else { return nil }
        // "|" separates them in the link, so a name can't hold one.
        let services = business.services.map { clean($0.replacingOccurrences(of: "|", with: "/"), limit: Limit.service) }
            .filter { !$0.isEmpty }
            .prefix(Limit.services)
        return link(path: businessPath, fields: [
            ("n", name), ("p", phone), ("e", validEmail(business.email)),
            ("s", services.joined(separator: "|")),
            ("w", clean(business.welcome, limit: Limit.welcome)), ("v", "\(version)")
        ])
    }

    /// A business's link read back (the Request Link screen's preview, tests).
    static func business(from url: URL) -> Business? {
        guard let fields = fields(of: url, path: businessPath) else { return nil }
        let name = clean(fields["n"] ?? "", limit: Limit.name), phone = clean(fields["p"] ?? "", limit: Limit.phone)
        guard hasLetterOrDigit(name), phoneDigits(phone) != nil else { return nil }
        let services = (fields["s"] ?? "").split(separator: "|").map { clean(String($0), limit: Limit.service) }
            .filter { !$0.isEmpty }
        return Business(name: name, phone: phone, email: validEmail(fields["e"] ?? ""),
                        services: Array(services.prefix(Limit.services)),
                        welcome: clean(fields["w"] ?? "", limit: Limit.welcome))
    }

    // MARK: - A request (Add to PlowR)

    /// How often the prospect wants the work.
    enum When: String, CaseIterable {
        case oneTime = "once", seasonal = "season", ongoing = "ongoing"

        var title: String {
            switch self {
            case .oneTime: "One time"
            case .seasonal: "For the season"
            case .ongoing: "Ongoing"
            }
        }
    }

    /// What a prospect sent, as the Add to PlowR link carries it.
    struct Request: Equatable {
        var name: String
        var phone: String
        var email = ""
        var address = ""
        var service = ""
        var when: When?
        var notes = ""
    }

    /// The Add to PlowR link for `request` (the web page builds the same;
    /// here for tests and the Request Link screen's preview).
    static func url(for request: Request) -> URL? {
        let cleaned = cleaned(request)
        guard let cleaned else { return nil }
        return link(path: leadPath, fields: [
            ("n", cleaned.name), ("p", cleaned.phone), ("e", cleaned.email),
            ("a", cleaned.address), ("s", cleaned.service), ("w", cleaned.when?.rawValue ?? ""),
            ("t", cleaned.notes), ("v", "\(version)")
        ])
    }

    /// Whether `url` is an Add to PlowR link at all, readable or not: one
    /// that isn't (`request(from:)` nil) was damaged or cut short, and the
    /// business is told so rather than nothing happening.
    static func isLeadLink(_ url: URL) -> Bool {
        isOurs(url, path: leadPath)
    }

    /// The request in an Add to PlowR link: the web link or the app's own.
    /// Nil if it isn't one, or has no name or no phone number to reach them.
    static func request(from url: URL) -> Request? {
        guard let fields = fields(of: url, path: leadPath) else { return nil }
        return cleaned(Request(name: fields["n"] ?? "", phone: fields["p"] ?? "", email: fields["e"] ?? "",
                               address: fields["a"] ?? "", service: fields["s"] ?? "",
                               when: fields["w"].flatMap(When.init(rawValue:)), notes: fields["t"] ?? ""))
    }

    /// `request` cut to size and cleaned; nil without a name and a phone.
    private static func cleaned(_ request: Request) -> Request? {
        let name = clean(request.name, limit: Limit.name), phone = clean(request.phone, limit: Limit.phone)
        guard hasLetterOrDigit(name), phoneDigits(phone) != nil else { return nil }
        return Request(name: name, phone: phone, email: validEmail(request.email),
                       address: clean(request.address, limit: Limit.address),
                       service: clean(request.service, limit: Limit.service), when: request.when,
                       notes: clean(request.notes, limit: Limit.notes, keepingLines: true))
    }

    // MARK: - Reading and writing

    /// The digits of a phone number written as phone numbers are (digits,
    /// any kind of space or dash, + ( ) . /), if there are enough to dial
    /// (7 to 15). Words or an extension ("ext 12") aren't a number to call:
    /// refused.
    static func phoneDigits(_ phone: String) -> String? {
        let allowed = Set("0123456789+()./")
        let ok = !phone.isEmpty && phone.unicodeScalars.allSatisfy { scalar in
            allowed.contains(Character(scalar)) || scalar == "\u{2212}"
                || [.spaceSeparator, .dashPunctuation].contains(scalar.properties.generalCategory)
        }
        guard ok else { return nil }
        let digits = phone.filter(\.isNumber)
        return (7...15).contains(digits.count) ? digits : nil
    }

    /// `email` if it looks like one (something@something.something, no
    /// spaces), else empty.
    static func validEmail(_ email: String) -> String {
        let cleaned = clean(email, limit: Limit.email)
        // No characters that mean something in a link (a mailto: built from
        // it can't gain a subject or body), and no empty parts ("a@b..c").
        let part = #"[^\s@?&#/:'"<>\\]"#
        let ok = cleaned.range(of: "^\(part)+@\(part)+(\\.\(part)+)+$", options: .regularExpression) != nil
            && !cleaned.contains("..")
        return ok ? cleaned : ""
    }

    /// Blank letters (Hangul fillers) that show nothing.
    private static let blankLetters = CharacterSet(charactersIn: "\u{3164}\u{115F}\u{1160}\u{FFA0}")

    /// Text that shows something: a name of only spaces, marks or blank
    /// fillers isn't one.
    static func hasLetterOrDigit(_ text: String) -> Bool {
        let shown: [Unicode.GeneralCategory] = [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                                                .modifierLetter, .otherLetter, .decimalNumber]
        return text.unicodeScalars.contains { shown.contains($0.properties.generalCategory) && !blankLetters.contains($0) }
    }

    /// Invisible characters that change how text reads (direction overrides,
    /// zero-width spaces, a byte-order mark): removed, so a name can't be
    /// made to show as something else. Joiners stay (emoji and many
    /// scripts need them).
    private static let formatting = CharacterSet(charactersIn: "\u{200B}\u{200E}\u{200F}\u{061C}\u{FEFF}")
        .union(CharacterSet(charactersIn: "\u{202A}"..."\u{202E}"))
        .union(CharacterSet(charactersIn: "\u{2066}"..."\u{2069}"))

    /// The most Unicode scalars a field of `limit` characters keeps: a
    /// character is a few scalars at most (an emoji with a skin tone, a
    /// letter with accents), and one with thousands of stacked marks isn't.
    static func scalarLimit(_ limit: Int) -> Int { limit * 4 }

    /// Text as kept: control characters (and line breaks, unless kept) as
    /// spaces, direction overrides and zero-width spaces gone, spaces
    /// trimmed, cut to `limit` characters and `scalarLimit(limit)` scalars.
    static func clean(_ text: String, limit: Int, keepingLines: Bool = false) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars.prefix(scalarLimit(limit) * 2) {
            if keepingLines, scalar == "\n" {
                scalars.append(scalar)
            } else if scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar) {
                scalars.append(" ")
            } else if !formatting.contains(scalar) {
                scalars.append(scalar)
            }
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = String.UnicodeScalarView()
        for character in trimmed.prefix(limit) {
            guard kept.count + character.unicodeScalars.count <= scalarLimit(limit) else { break }
            kept.append(contentsOf: character.unicodeScalars)
        }
        return String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `https://getplowr.app<path>#k=v&…`, empty fields left out.
    private static func link(path: String, fields: [(String, String)]) -> URL? {
        let fragment = fields.filter { !$0.1.isEmpty }
            .map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        guard fragment.utf8.count <= largestFragment else { return nil }
        return URL(string: "https://\(host)\(path)#\(fragment)")
    }

    /// Characters a fragment value keeps as they are: the rest are %-encoded
    /// (UTF-8), so `&`, `=`, `+`, `#` and `|` inside a value can't be misread.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// The keys a link may carry; anything else is ignored unread.
    private static let keys: Set<String> = ["v", "n", "p", "e", "a", "s", "w", "t"]

    /// Whether `url` is a link to `path` on getplowr.app, or the app's own
    /// plowr://lead link.
    private static func isOurs(_ url: URL, path: String) -> Bool {
        let isWeb = url.scheme?.lowercased() == "https" && url.host?.lowercased() == host
            && (url.path == path || url.path + "/" == path)
        let isApp = url.scheme?.lowercased() == appScheme && path == leadPath
            && (url.host?.lowercased() == "lead" || url.path.trimmingCharacters(in: ["/"]) == "lead")
        return isWeb || isApp
    }

    /// The fields after the `#` of one of our links, as a web form writes
    /// them; nil for any other link, or one too long to be real. Never the
    /// query (`?`): that part is sent to the website's server, and nothing
    /// may be read from it, so a page that put details there would fail
    /// here at once, not leak quietly.
    private static func fields(of url: URL, path: String) -> [String: String]? {
        guard isOurs(url, path: path), let raw = url.fragment(percentEncoded: true),
              raw.utf8.count <= largestFragment else { return nil }
        var fields: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first.map(String.init), keys.contains(key), fields[key] == nil else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            fields[key] = value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        return fields
    }
}
