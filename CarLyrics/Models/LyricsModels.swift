// MARK: - LyricsModels.swift  (v2 — Telemetrie-Edition)
// CarLyrics – shared model types: App-Target + Widget Extension.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import ActivityKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: LRC Line
// ─────────────────────────────────────────────────────────────────────────────

public struct LRCLine: Identifiable, Equatable {
    public let id    = UUID()
    public let time  : TimeInterval
    public let text  : String
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Parsed Lyrics
// ─────────────────────────────────────────────────────────────────────────────

public struct ParsedLyrics: Equatable {
    public let lines      : [LRCLine]
    public let trackTitle : String
    public let artist     : String

    public func activeIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var idx = 0
        for (i, line) in lines.enumerated() {
            if line.time <= time { idx = i } else { break }
        }
        return idx
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Warmup Phase
// ─────────────────────────────────────────────────────────────────────────────

public enum WarmupPhase: String, Codable, Hashable, CaseIterable {
    case cold    = "KALT"
    case warming = "AUFWÄRMEN"
    case ready   = "BEREIT"

    public var label: String {
        switch self {
        case .cold:    return "Kaltstart – Max. 2.500 U/min, kein Ladedruck"
        case .warming: return "Öl wärmt auf – Gemäßigt fahren"
        case .ready:   return "90 °C – Voller Ladedruck frei! 🏁"
        }
    }

    /// Hex accent string for SF Symbol / tint — decoded in both targets
    public var colorToken: String {
        switch self {
        case .cold:    return "blue"
        case .warming: return "orange"
        case .ready:   return "green"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Lyrics Status
// ─────────────────────────────────────────────────────────────────────────────

public enum LyricsStatus: Equatable {
    case idle
    case loading
    case loaded
    case error(String)

    public var label: String {
        switch self {
        case .idle:           return "Kein Song aktiv"
        case .loading:        return "Lade Songtext…"
        case .loaded:         return "Synchronisiert"
        case .error(let msg): return "Fehler: \(msg)"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: ActivityKit – Live Activity Attributes  (v2)
// ─────────────────────────────────────────────────────────────────────────────

public struct LyricsAttributes: ActivityAttributes {

    // Static — set once at Activity.request(…)
    public var trackId: String

    public init(trackId: String) {
        self.trackId = trackId
    }

    // Dynamic — updated on line-change OR telemetry tick (max every 2–3 s)
    public struct ContentState: Codable, Hashable {

        // ── Lyrics ───────────────────────────────────────────────────────────
        public var currentLine : String
        public var nextLine    : String
        public var songTitle   : String
        public var artist      : String
        public var progress    : Double   // 0.0 … 1.0
        public var isPlaying   : Bool

        // ── G-Force Telemetry ────────────────────────────────────────────────
        public var currentG    : Double   // combined lateral+longitudinal G
        public var peakG       : Double   // session maximum
        public var gVectorX    : Double   // lateral  (-1 … +1)
        public var gVectorY    : Double   // longitudinal (-1 … +1)

        // ── Engine Warm-Up & OBD Telemetry ───────────────────────────────────
        public var oilTemp         : Int?         // °C (nil = wartet auf OBD)
        public var coolantTemp     : Int?         // °C (nil = wartet auf OBD)
        public var boostBar        : Double?      // Bar (relative boost, nil = nicht aktiv/kein Sensor)
        public var warmupProgress  : Double       // 0.0 … 1.0
        public var warmupPhase     : WarmupPhase
        public var isEngineWarm    : Bool         // oilTemp >= 80°C

        // ─────────────────────────────────────────────────────────────────────
        public init(
            currentLine    : String       = "",
            nextLine       : String       = "",
            songTitle      : String       = "",
            artist         : String       = "",
            progress       : Double       = 0,
            isPlaying      : Bool         = true,
            currentG       : Double       = 0,
            peakG          : Double       = 0,
            gVectorX       : Double       = 0,
            gVectorY       : Double       = 0,
            oilTemp        : Int?         = 20,
            coolantTemp    : Int?         = 90,
            boostBar       : Double?      = nil,
            warmupProgress : Double       = 0,
            warmupPhase    : WarmupPhase  = .cold,
            isEngineWarm   : Bool         = false
        ) {
            self.currentLine    = currentLine
            self.nextLine       = nextLine
            self.songTitle      = songTitle
            self.artist         = artist
            self.progress       = progress
            self.isPlaying      = isPlaying
            self.currentG       = currentG
            self.peakG          = peakG
            self.gVectorX       = gVectorX
            self.gVectorY       = gVectorY
            self.oilTemp        = oilTemp
            self.coolantTemp    = coolantTemp
            self.boostBar       = boostBar
            self.warmupProgress = warmupProgress
            self.warmupPhase    = warmupPhase
            self.isEngineWarm   = isEngineWarm
        }

        public static let placeholder = ContentState(
            currentLine : "♪ Loading lyrics …",
            nextLine    : "",
            songTitle   : "CarLyrics",
            artist      : "",
            oilTemp     : 20,
            coolantTemp : 90,
            boostBar    : nil,
            warmupPhase : .cold
        )
    }
}
