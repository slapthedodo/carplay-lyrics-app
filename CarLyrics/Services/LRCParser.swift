// MARK: - LRCParser.swift
// CarLyrics – pure parser for the LRC lyric format.
// ─────────────────────────────────────────────────────────────────────────────
//
// Supported timestamp formats:
//   [mm:ss.xx]   [mm:ss.xxx]   [mm:ss]
//
// Extended LRC tags (artist, title, album …) are silently ignored.
// Multiple timestamps on one line are expanded into individual LRCLines.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public struct LRCParser {

    private static let lineRegex = try! NSRegularExpression(
        pattern: #"(\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\])"#
    )

    private static let tagRegex = try! NSRegularExpression(
        pattern: #"^\[(?:ti|ar|al|by|offset|length|re|ve):.*\]$"#,
        options: .caseInsensitive
    )

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Parse raw LRC text into a sorted array of LRCLines.
    public static func parse(_ raw: String,
                             title: String = "",
                             artist: String = "") -> ParsedLyrics {
        var lines: [LRCLine] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip LRC tag lines ([ti:…], [ar:…], etc.)
            let tagRange = NSRange(trimmed.startIndex..., in: trimmed)
            if tagRegex.firstMatch(in: trimmed, range: tagRange) != nil { continue }

            // Find all timestamp matches
            let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = lineRegex.matches(in: trimmed, range: fullRange)
            guard !matches.isEmpty else { continue }

            // The lyric text follows the last timestamp
            let lastMatchEnd = matches.last.flatMap {
                Range($0.range, in: trimmed)
            }?.upperBound ?? trimmed.startIndex

            let text = String(trimmed[lastMatchEnd...])
                .trimmingCharacters(in: .whitespaces)

            // Every timestamp becomes an individual LRCLine
            for match in matches {
                if let seconds = parseTimestamp(match, in: trimmed) {
                    lines.append(LRCLine(time: seconds, text: text))
                }
            }
        }

        lines.sort { $0.time < $1.time }
        return ParsedLyrics(lines: lines, trackTitle: title, artist: artist)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static func parseTimestamp(_ match: NSTextCheckingResult,
                                       in source: String) -> TimeInterval? {
        // Group 2 → minutes, Group 3 → seconds, Group 4 → centiseconds/milliseconds
        func capture(_ idx: Int) -> String? {
            let r = match.range(at: idx)
            guard r.location != NSNotFound,
                  let range = Range(r, in: source) else { return nil }
            return String(source[range])
        }

        guard let minStr = capture(2), let secStr = capture(3),
              let minutes = Double(minStr), let seconds = Double(secStr) else {
            return nil
        }

        var frac: Double = 0
        if let fracStr = capture(4), let fracVal = Double(fracStr) {
            // Normalize centiseconds (2 digits) or milliseconds (3 digits)
            frac = fracStr.count == 3 ? fracVal / 1000.0 : fracVal / 100.0
        }

        return minutes * 60 + seconds + frac
    }
}
