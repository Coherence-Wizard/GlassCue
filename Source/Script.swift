import Foundation

enum ScriptText {
    static func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    static func plain(_ markdown: String) -> String {
        var s = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        s = replace(s, "\\A---[ \\t]*\\n[\\s\\S]*?\\n---[ \\t]*(?:\\n|$)", "")
        s = replace(s, "(?s)%%.*?%%|<!--.*?-->", "")
        s = replace(s, "(?m)^```[^\\n]*\\n[\\s\\S]*?^```[ \\t]*$", "")
        s = replace(s, "!\\[\\[[^\\]]+\\]\\]|!\\[[^\\]]*\\]\\([^)]*\\)", "")
        s = replace(s, "\\[\\[[^\\]|]+\\|([^\\]]+)\\]\\]", "$1")
        s = replace(s, "\\[\\[([^\\]#]+)(?:#[^\\]]*)?\\]\\]", "$1")
        s = replace(s, "\\[([^\\]]+)\\]\\([^)]*\\)", "$1")
        s = replace(s, "(?m)^\\s*>\\s*\\[![^\\]]+\\][+-]?\\s*", "")
        s = replace(s, "(?m)^[ \\t]*(?:#{1,6}[ \\t]+|>[ \\t]*|[-*+][ \\t]+(?:\\[[ xX]\\][ \\t]+)?|[0-9]+[.)][ \\t]+)", "")
        s = replace(s, "(?m)^\\s*(?:---+|___+|\\*\\*\\*+)[ \\t]*$", "")
        s = replace(s, "(?m)[ \\t]+\\^[a-zA-Z0-9-]+[ \\t]*$", "")
        for marker in ["**", "__", "~~", "==", "`"] { s = s.replacingOccurrences(of: marker, with: "") }
        s = replace(s, "(?<!\\w)[*_]([^\\n*_]+)[*_](?!\\w)", "$1")
        s = replace(s, "\\n{3,}", "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Word {
        let value: String
        let range: NSRange
    }
    static func words(_ text: String) -> [Word] {
        let pattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}]+)?")
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            let value = ns.substring(with: $0.range).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")).replacingOccurrences(of: "’", with: "'")
            return Word(value: value, range: $0.range)
        }
    }
}

/// Matches a recent spoken phrase, not elapsed time or voice volume. No match means no movement.
/// Search is forward-only; the reader can explicitly click a word or rewind to repeat a passage.
final class PhraseFollower {
    private(set) var words: [ScriptText.Word] = []
    private(set) var cursor = -1
    private var previous = ""
    private var index: [String: [Int]] = [:]
    private let common: Set<String> = ["a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at", "is", "it", "i", "you", "we", "that", "this", "for", "with", "be", "as"]
    init(_ text: String) { reset(text) }
    func reset(_ text: String) {
        words = ScriptText.words(text); cursor = -1; previous = ""; index = [:]
        for (i, word) in words.enumerated() { index[word.value, default: []].append(i) }
    }
    func seek(_ position: Int) { cursor = max(-1, min(position, words.count - 1)); previous = "" }
    func newUtterance() { previous = "" }

    @discardableResult func ingest(_ transcript: String) -> Int? {
        guard transcript != previous else { return nil }
        previous = transcript
        let spoken = ScriptText.words(transcript).map(\.value)
        guard spoken.count >= 2, let last = spoken.last else { return nil }
        var best: (end: Int, score: Double)?
        for end in index[last, default: []] where end > cursor {
            let gap = end - cursor
            let minimum = gap > 18 ? 4 : 2
            guard spoken.count >= minimum else { continue }
            for count in minimum...min(10, spoken.count) {
                let phrase = Array(spoken.suffix(count))
                let contentCount = phrase.filter { !common.contains($0) }.count
                guard contentCount >= (gap > 18 ? 2 : 1) else { continue }
                let allowance = count >= 8 ? 2 : (count >= 5 ? 1 : 0)
                for length in max(2, count - allowance)...(count + allowance) {
                    let start = end - length + 1
                    guard start >= 0 else { continue }
                    let segment = words[start...end].map(\.value)
                    let errors = Self.distance(phrase, segment)
                    guard errors <= allowance, !(gap > 18 && count - errors < 4) else { continue }
                    let score = Double(count) - Double(errors) * 1.8 - Double(gap) * 0.008
                    if best == nil || score > best!.score { best = (end, score) }
                }
            }
        }
        guard let best, best.score > 0 else { return nil }
        cursor = best.end
        return cursor
    }
    static func distance(_ a: [String], _ b: [String]) -> Int {
        var row = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                next[j + 1] = min(row[j + 1] + 1, next[j] + 1, row[j] + (left == right ? 0 : 1))
            }
            row = next
        }
        return row[b.count]
    }
}
