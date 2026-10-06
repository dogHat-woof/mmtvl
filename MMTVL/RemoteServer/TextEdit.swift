/// What to post to turn the last phone field value into the new one (L7).
nonisolated struct TextEdit: Equatable, Sendable {
    var deletions: Int
    var insertion: String

    /// Common prefix by Character: deletions = old.count − prefix, insertion = new.dropFirst(prefix).
    static func between(_ old: String, _ new: String) -> TextEdit {
        var prefix = 0
        for (a, b) in zip(old, new) {
            guard a == b else { break }
            prefix += 1
        }
        return TextEdit(deletions: old.count - prefix, insertion: String(new.dropFirst(prefix)))
    }

    var isEmpty: Bool { deletions == 0 && insertion.isEmpty }
}
