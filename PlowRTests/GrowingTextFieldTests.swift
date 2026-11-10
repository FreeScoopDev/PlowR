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

    // Return is one break typed into the text, wherever the cursor was;
    // the field then keeps the old text and ends editing.
    @Test func returnIsOneTypedBreak() {
        #expect(GrowingTextField.isReturn(old: "abc", new: "abc\n"))
        #expect(GrowingTextField.isReturn(old: "123 Main St", new: "123 Main\n St"))
        #expect(GrowingTextField.isReturn(old: "", new: "\n"))
        // A paste, even one ending in a break, isn't Return.
        #expect(!GrowingTextField.isReturn(old: "abc", new: "abcx\n"))
        #expect(!GrowingTextField.isReturn(old: "", new: "a\nb"))
        // One extra character that isn't a break isn't Return.
        #expect(!GrowingTextField.isReturn(old: "abc", new: "abcd"))
    }
}
