import Foundation

/// A regular expression with the handful of operations the ported JavaScript
/// uses: test, capture groups, and replacing the first match.
struct Pattern {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // The patterns are literals in this module; a bad one is a bug.
        regex = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The capture groups of the first match (nil for a group that didn't
    /// take part), or nil without a match.
    func groups(_ text: String) -> [String?]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    /// `text.replace(pattern, template)` without the `g` flag: first match only.
    func replacingFirst(in text: String, with template: String) -> String {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return text
        }
        let replacement = regex.replacementString(for: match, in: text, offset: 0, template: template)
        return text.replacingCharacters(in: range, with: replacement)
    }
}
