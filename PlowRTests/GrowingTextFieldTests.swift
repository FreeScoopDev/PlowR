import Testing
@testable import PlowR

/// A single-line field that can grow keeps one line: pasted line breaks
/// become ", " (an address must not run together), and Return is told apart.
struct GrowingTextFieldTests {
    @Test func breaksBecomeCommas() {
        #expect(GrowingTextField.singleLine("a\nb") == "a, b")
        #expect(GrowingTextField.singleLine("a\n\nb") == "a, b")
        #expect(GrowingTextField.singleLine("123 Main St\nSpringfield, IL") == "123 Main St, Springfield, IL")
        #expect(GrowingTextField.singleLine("a \r\n b") == "a, b")
    }

    @Test func trailingBreakIsDropped() {
        #expect(GrowingTextField.singleLine("abc\n") == "abc")
        #expect(GrowingTextField.singleLine("\nabc") == "abc")
    }

    @Test func noBreakIsUnchanged() {
        #expect(GrowingTextField.singleLine("abc def") == "abc def")
        #expect(GrowingTextField.singleLine("  spaced ") == "  spaced ")
    }

    @Test func returnIsOnlyATrailingBreak() {
        #expect(GrowingTextField.isReturn("abc\n"))
        #expect(!GrowingTextField.isReturn("a\nb"))
        #expect(!GrowingTextField.isReturn("a\nb\n"))
        #expect(!GrowingTextField.isReturn("abc"))
    }
}
