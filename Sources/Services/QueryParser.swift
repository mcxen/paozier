import Foundation

/// Parsed query token
enum QueryToken {
    case term(String)       // plain word, may end with * for wildcard
    case phrase(String)     // exact phrase (was in quotes)
    case and
    case or
    case not
}

/// Parses user query into tokens, then generates engine-specific query strings.
/// Supports: "exact phrase", AND/OR/NOT operators, wildcard* prefix matching.
/// Simple queries (no operators) pass through unchanged.
struct QueryParser {

    static func parse(_ input: String) -> [QueryToken] {
        var tokens: [QueryToken] = []
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            // Skip whitespace
            if chars[i].isWhitespace { i += 1; continue }

            // Quoted phrase
            if chars[i] == "\"" {
                i += 1
                var phrase = ""
                while i < chars.count && chars[i] != "\"" {
                    phrase.append(chars[i]); i += 1
                }
                if i < chars.count { i += 1 } // skip closing quote
                if !phrase.isEmpty { tokens.append(.phrase(phrase)) }
                continue
            }

            // Word
            var word = ""
            while i < chars.count && !chars[i].isWhitespace && chars[i] != "\"" {
                word.append(chars[i]); i += 1
            }

            switch word.uppercased() {
            case "AND": tokens.append(.and)
            case "OR": tokens.append(.or)
            case "NOT": tokens.append(.not)
            default: tokens.append(.term(word))
            }
        }
        return tokens
    }

    /// Generate SearchKit query string.
    /// SearchKit: space = implicit AND, supports quotes and *.
    /// Boolean NOT not natively supported — we drop NOT terms for SK.
    static func toSearchKit(_ tokens: [QueryToken]) -> String {
        var parts: [String] = []
        var skipNext = false
        for token in tokens {
            if skipNext { skipNext = false; continue }
            switch token {
            case .term(let t): parts.append(t)
            case .phrase(let p): parts.append("\"\(p)\"")
            case .and: continue // implicit in SK
            case .or: parts.append("|")
            case .not: skipNext = true // SK doesn't support NOT, skip next term
            }
        }
        return parts.joined(separator: " ")
    }

    /// Generate FTS5 MATCH query string.
    /// FTS5: supports AND/OR/NOT, quotes for phrases, * for prefix.
    static func toFTS5(_ tokens: [QueryToken]) -> String {
        var parts: [String] = []
        for token in tokens {
            switch token {
            case .term(let t): parts.append(t)
            case .phrase(let p): parts.append("\"\(p)\"")
            case .and: parts.append("AND")
            case .or: parts.append("OR")
            case .not: parts.append("NOT")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Check if query uses advanced syntax (has operators, quotes, or wildcards)
    static func isAdvanced(_ input: String) -> Bool {
        input.contains("\"") || input.contains("*") ||
        input.range(of: #"\b(AND|OR|NOT)\b"#, options: .regularExpression) != nil
    }
}
