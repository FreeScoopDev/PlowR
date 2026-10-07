// The Request Service link's rules, for both pages (r/ and lead/). The app
// reads the same format with the same rules (PlowR/Services/RequestLink.swift):
// change one, change the other.
(function (root) {
    "use strict";
    var LIMITS = { name: 100, phone: 30, email: 120, address: 200, service: 60, services: 12, welcome: 200, notes: 1000 };
    var WHEN = { once: "One time", season: "For the season", ongoing: "Ongoing" };
    var LARGEST_FRAGMENT = 80000;
    // Invisible characters that change how text reads; joiners stay.
    var FORMATTING = /[\u200B\u200E\u200F\u061C\uFEFF\u202A-\u202E\u2066-\u2069]/g;
    var BLANK_LETTERS = /[\u3164\u115F\u1160\uFFA0]/g;

    function graphemes(text) {
        if (typeof Intl !== "undefined" && Intl.Segmenter) {
            return Array.from(new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text),
                              function (s) { return s.segment; });
        }
        return Array.from(text);
    }

    /// Control characters (and line breaks, unless kept) as spaces,
    /// direction overrides and zero-width spaces gone, trimmed, cut to
    /// `limit` characters and `limit * 4` code points.
    function clean(text, limit, keepLines) {
        text = Array.from(String(text == null ? "" : text)).slice(0, limit * 8).join("");
        text = keepLines ? text.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000B-\u001F\u007F-\u009F\u2028\u2029]/g, " ")
                         : text.replace(/[\u0000-\u001F\u007F-\u009F\u2028\u2029]/g, " ");
        text = text.replace(FORMATTING, "").trim();
        var kept = "", count = 0;
        var parts = graphemes(text).slice(0, limit);
        for (var i = 0; i < parts.length; i++) {
            var size = Array.from(parts[i]).length;
            if (count + size > limit * 4) break;
            kept += parts[i]; count += size;
        }
        return kept.trim();
    }

    /// The digits of a phone number written as one (digits, any space or
    /// dash, + ( ) . /), 7 to 15 of them; words or an extension refused.
    function phoneDigits(phone) {
        phone = String(phone || "");
        if (!phone || !/^[0-9+()./\p{Zs}\p{Pd}\u2212]+$/u.test(phone)) return null;
        var d = phone.replace(/[^0-9]/g, "");
        return d.length >= 7 && d.length <= 15 ? d : null;
    }

    function validEmail(email) {
        email = clean(email, LIMITS.email);
        // Nothing with a meaning in a link, and no empty parts ("a@b..c").
        var ok = /^[^\s@?&#\/:'"<>\\]+@[^\s@?&#\/:'"<>\\]+(\.[^\s@?&#\/:'"<>\\]+)+$/.test(email);
        return ok && email.indexOf("..") < 0 ? email : "";
    }

    function hasLetterOrDigit(text) {
        // Letters and digits that show: not marks, not blank fillers.
        return /[\p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nd}]/u.test(String(text).replace(BLANK_LETTERS, ""));
    }

    function when(value) {
        return Object.prototype.hasOwnProperty.call(WHEN, value) ? WHEN[value] : "";
    }

    /// The fields after the #, or null if there are too many to be real.
    function fields() {
        var raw = location.hash.replace(/^#/, "");
        return raw.length > LARGEST_FRAGMENT ? null : new URLSearchParams(raw);
    }

    /// A link to the app's format: fields in order, empty ones left out, v=1 last
    /// (Messages takes a final "." as the end of a sentence, not of the link).
    function link(path, values) {
        var params = new URLSearchParams();
        Object.keys(values).forEach(function (key) { if (values[key]) params.set(key, values[key]); });
        params.set("v", "1");
        return "https://getplowr.app" + path + "#" + params.toString();
    }

    root.RequestLink = { LIMITS: LIMITS, WHEN: WHEN, clean: clean, phoneDigits: phoneDigits, validEmail: validEmail,
                         hasLetterOrDigit: hasLetterOrDigit, when: when, fields: fields, link: link };
})(window);
