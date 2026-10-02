import Foundation

// Release versions (`0.6.0`, `v0.6.1`, `0.6.1-dev+3f2a1c`) for the update
// notice, ported from the GNOME extension's versions.js.

public enum Versions {
    private static let release = Pattern(#"^(\d+)\.(\d+)\.(\d+)"#)

    public static func parse(_ text: String) -> [Int]? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") {
            trimmed.removeFirst()
        }
        guard let groups = release.groups(trimmed) else {
            return nil
        }
        let numbers = groups.compactMap { $0.flatMap { Int($0) } }
        return numbers.count == 3 ? numbers : nil
    }

    public static func compare(_ a: String, _ b: String) -> Int {
        guard let left = parse(a), let right = parse(b) else {
            return 0
        }
        for (l, r) in zip(left, right) where l != r {
            return l < r ? -1 : 1
        }
        return 0
    }

    /// A development build of 0.6.0 is not behind release 0.6.0. An install
    /// with no version at all is behind any release.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard parse(candidate) != nil else {
            return false
        }
        guard parse(installed) != nil else {
            return true
        }
        return compare(candidate, installed) > 0
    }
}
