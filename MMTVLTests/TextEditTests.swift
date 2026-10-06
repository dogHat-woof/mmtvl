import Testing
@testable import MMTVL

struct TextEditTests {
    @Test func diffs() {
        #expect(TextEdit.between("", "abc") == TextEdit(deletions: 0, insertion: "abc"))
        #expect(TextEdit.between("abc", "ab") == TextEdit(deletions: 1, insertion: ""))
        #expect(TextEdit.between("teh", "the") == TextEdit(deletions: 2, insertion: "he"))
        #expect(TextEdit.between("abc", "abc").isEmpty)
        #expect(TextEdit.between("a👍🏽", "a") == TextEdit(deletions: 1, insertion: ""))
        #expect(TextEdit.between("abc", "") == TextEdit(deletions: 3, insertion: ""))
    }
}
