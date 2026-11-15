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
        public var previousLine: String
        public var currentLine : String
        public var nextLine    : String
        public var nextLine2   : String
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
        public var iatTemp         : Int?         // °C Ansaugluft (nil = nicht aktiv)
        public var mafVal          : Double?      // g/s Luftmasse (nil = nicht aktiv)
        public var warmupProgress  : Double       // 0.0 … 1.0
        public var warmupPhase     : WarmupPhase
        public var isEngineWarm    : Bool         // oilTemp >= 80°C

        // ─────────────────────────────────────────────────────────────────────
        public init(
            previousLine: String = "", currentLine: String = "", nextLine: String = "", nextLine2: String = "",
            songTitle: String = "", artist: String = "", progress: Double = 0, isPlaying: Bool = true,
            currentG: Double = 0, peakG: Double = 0, gVectorX: Double = 0, gVectorY: Double = 0,
            oilTemp: Int? = 20, coolantTemp: Int? = 90, boostBar: Double? = nil,
            iatTemp: Int? = nil, mafVal: Double? = nil, warmupProgress: Double = 0,
            warmupPhase: WarmupPhase = .cold, isEngineWarm: Bool = false
        ) {
            self.previousLine = previousLine; self.currentLine = currentLine
            self.nextLine = nextLine; self.nextLine2 = nextLine2
            self.songTitle = songTitle; self.artist = artist
            self.progress = progress; self.isPlaying = isPlaying
            self.currentG = currentG; self.peakG = peakG
            self.gVectorX = gVectorX; self.gVectorY = gVectorY
            self.oilTemp = oilTemp; self.coolantTemp = coolantTemp
            self.boostBar = boostBar; self.iatTemp = iatTemp
            self.mafVal = mafVal; self.warmupProgress = warmupProgress
            self.warmupPhase = warmupPhase; self.isEngineWarm = isEngineWarm
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Warmup Calculator (EA113 2.0 TFSI Physics & Seasonal Engine)
// ─────────────────────────────────────────────────────────────────────────────

public struct WarmupCalculator {
    public struct SeasonalProfile {
        public let ambientTemp          : Double   // Konservative Starttemperatur
        public let lambda               : Double   // Konservativer Aufheizkoeffizient
        public let estimatedMinutesTo80 : Int      // Warmfahrzeit in Minuten
        public let seasonName           : String   // z.B. "Tiefwinter (Frost)"

        public init(ambientTemp: Double, lambda: Double, estimatedMinutesTo80: Int, seasonName: String) {
            self.ambientTemp = ambientTemp
            self.lambda = lambda
            self.estimatedMinutesTo80 = estimatedMinutesTo80
            self.seasonName = seasonName
        }
    }

    public static func profileForCurrentDate(date: Date = Date()) -> SeasonalProfile {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let hour = calendar.component(.hour, from: date)
        let isNightOrEarlyMorning = (hour < 8 || hour >= 22)
        let nightOffset: Double = isNightOrEarlyMorning ? -2.0 : 0.0

        switch month {
        case 1:  return SeasonalProfile(ambientTemp: max(-5.0, 2.0 + nightOffset), lambda: 0.0019, estimatedMinutesTo80: 20, seasonName: "Tiefwinter (Frostschutz)")
        case 2:  return SeasonalProfile(ambientTemp: max(-4.0, 3.0 + nightOffset), lambda: 0.0020, estimatedMinutesTo80: 19, seasonName: "Spätwinter")
        case 3:  return SeasonalProfile(ambientTemp: max(0.0, 6.0 + nightOffset), lambda: 0.00215, estimatedMinutesTo80: 17, seasonName: "Vorfrühling (Kaltphase)")
        case 4:  return SeasonalProfile(ambientTemp: max(3.0, 9.0 + nightOffset), lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Frühling")
        case 5:  return SeasonalProfile(ambientTemp: max(8.0, 14.0 + nightOffset), lambda: 0.00245, estimatedMinutesTo80: 14, seasonName: "Milder Frühling")
        case 6:  return SeasonalProfile(ambientTemp: max(12.0, 18.0 + nightOffset), lambda: 0.0026, estimatedMinutesTo80: 13, seasonName: "Frühsommer")
        case 7:  return SeasonalProfile(ambientTemp: max(15.0, 21.0 + nightOffset), lambda: 0.0027, estimatedMinutesTo80: 12, seasonName: "Hochsommer")
        case 8:  return SeasonalProfile(ambientTemp: max(14.0, 20.0 + nightOffset), lambda: 0.0027, estimatedMinutesTo80: 12, seasonName: "Hochsommer")
        case 9:  return SeasonalProfile(ambientTemp: max(9.0, 15.0 + nightOffset), lambda: 0.0025, estimatedMinutesTo80: 14, seasonName: "Spätsommer")
        case 10: return SeasonalProfile(ambientTemp: max(3.0, 9.0 + nightOffset), lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Herbst")
        case 11: return SeasonalProfile(ambientTemp: max(0.0, 5.0 + nightOffset), lambda: 0.0021, estimatedMinutesTo80: 18, seasonName: "Spätherbst (Nasskalt)")
        case 12: return SeasonalProfile(ambientTemp: max(-5.0, 2.0 + nightOffset), lambda: 0.0019, estimatedMinutesTo80: 20, seasonName: "Winterbeginn")
        default: return SeasonalProfile(ambientTemp: 10.0, lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Standard")
        }
    }

    public static func calculateOilTemp(at t: TimeInterval, from sTemp: Double, targetTemp: Double = 90.0, lambda: Double? = nil) -> Double {
        guard t > 0 else { return sTemp }
        let baseLambda = lambda ?? profileForCurrentDate().lambda
        let effectiveLambda: Double
        if t < 120 {
            effectiveLambda = baseLambda * (0.6 + 0.4 * (t / 120.0))
        } else {
            effectiveLambda = baseLambda
        }
        let newTemp = targetTemp - (targetTemp - sTemp) * exp(-effectiveLambda * t)
        return min(max(newTemp, sTemp), targetTemp)
    }

    public static func phaseFor(temp: Double) -> WarmupPhase {
        if temp < 60 { return .cold }
        if temp < 80 { return .warming }
        return .ready
    }

    public static func warmupProgress(temp: Double, startTemp: Double) -> Double {
        let span = max(10.0, 85.0 - startTemp)
        return max(0, min((temp - startTemp) / span, 1.0))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Centralized Telemetry Shared Store (App Group & Dual Fallback)
// ─────────────────────────────────────────────────────────────────────────────

public struct TelemetrySharedData: Codable {
    public var oilTemp          : Int?
    public var coolantTemp      : Int?
    public var boostBar         : Double?
    public var currentG         : Double
    public var peakG            : Double
    public var iat              : Int?
    public var maf              : Double?
    public var phase            : WarmupPhase
    public var warmupProgress   : Double
    public var songTitle        : String
    public var artist           : String
    public var previousLine2    : String
    public var previousLine     : String
    public var currentLine      : String
    public var nextLine         : String
    public var nextLine2        : String
    public var currentTimeStr   : String
    public var totalTimeStr     : String
    public var progress         : Double
    public var isPlaying        : Bool
    public var sessionStartTime : Double
    public var sessionStartTemp : Double
    public var updatedAt        : Date

    public init(
        oilTemp: Int? = nil, coolantTemp: Int? = nil, boostBar: Double? = nil,
        currentG: Double = 0.0, peakG: Double = 0.0, iat: Int? = nil, maf: Double? = nil,
        phase: WarmupPhase = .cold, warmupProgress: Double = 0.0,
        songTitle: String = "", artist: String = "", previousLine2: String = "",
        previousLine: String = "", currentLine: String = "", nextLine: String = "",
        nextLine2: String = "", currentTimeStr: String = "0:00", totalTimeStr: String = "0:00",
        progress: Double = 0.0, isPlaying: Bool = false,
        sessionStartTime: Double = 0, sessionStartTemp: Double = 20, updatedAt: Date = Date()
    ) {
        self.oilTemp = oilTemp; self.coolantTemp = coolantTemp; self.boostBar = boostBar
        self.currentG = currentG; self.peakG = peakG; self.iat = iat; self.maf = maf
        self.phase = phase; self.warmupProgress = warmupProgress
        self.songTitle = songTitle; self.artist = artist
        self.previousLine2 = previousLine2; self.previousLine = previousLine
        self.currentLine = currentLine; self.nextLine = nextLine; self.nextLine2 = nextLine2
        self.currentTimeStr = currentTimeStr; self.totalTimeStr = totalTimeStr
        self.progress = progress; self.isPlaying = isPlaying
        self.sessionStartTime = sessionStartTime; self.sessionStartTemp = sessionStartTemp
        self.updatedAt = updatedAt
    }
}

public enum TelemetrySharedStore {
    /// Einzige App Group ID — muss in BEIDEN .entitlements Dateien stehen!
    public static let appGroupId = "group.com.carlyrics"
    public static let jsonFileName = "telemetry_store.json"
    public static let lrcFileName  = "lyrics_lines.json"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Telemetry Save (Main App → App Group)
    // ─────────────────────────────────────────────────────────────────────

    public static func save(_ data: TelemetrySharedData) {
        guard let group = sharedDefaults else { return }
        let enc = try? JSONEncoder().encode(data)

        // 1. App Group UserDefaults (primärer Kanal)
        if let enc { group.set(enc, forKey: "carlyrics_telemetry_payload") }
        group.set(data.songTitle, forKey: "widget_song_title")
        group.set(data.artist, forKey: "widget_artist")
        group.set(data.currentLine, forKey: "widget_current_line")
        group.set(data.previousLine, forKey: "widget_prev_line")
        group.set(data.nextLine, forKey: "widget_next_line")
        group.set(data.nextLine2, forKey: "widget_next_line2")
        group.set(data.previousLine2, forKey: "widget_prev_line2")
        group.set(data.currentTimeStr, forKey: "widget_cur_time_str")
        group.set(data.totalTimeStr, forKey: "widget_tot_time_str")
        group.set(data.progress, forKey: "widget_song_progress")
        group.set(data.isPlaying, forKey: "widget_is_playing")
        group.set(data.oilTemp ?? 0, forKey: "widget_oil_temp")
        group.set(data.coolantTemp ?? 0, forKey: "widget_coolant_temp")
        group.set(data.boostBar ?? 0, forKey: "widget_boost_bar")
        group.set(data.currentG, forKey: "widget_current_g")
        group.set(data.peakG, forKey: "widget_peak_g")
        group.set(data.iat ?? 0, forKey: "widget_iat")
        group.set(data.maf ?? 0, forKey: "widget_maf")
        group.set(data.phase.rawValue, forKey: "widget_warmup_phase")
        group.set(data.warmupProgress, forKey: "widget_warmup_progress")
        group.set(data.sessionStartTime, forKey: "carlyrics_warmup_started_at")
        group.set(data.sessionStartTemp, forKey: "carlyrics_warmup_start_temp")
        // Cross-Process Flush erzwingen — ohne synchronize() liest das Widget veraltete Daten!
        group.synchronize()

        // 2. Shared Container JSON (Backup-Kanal)
        if let enc, let dir = containerURL {
            let fileURL = dir.appendingPathComponent(jsonFileName)
            try? enc.write(to: fileURL, options: .atomic)
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Telemetry Load (Widget Extension ← App Group)
    // ─────────────────────────────────────────────────────────────────────

    public static func load() -> TelemetrySharedData {
        // NICHT Activity<>.activities abfragen — gibt im Widget-Prozess IMMER [] zurück!
        // NICHT UserDefaults.standard verwenden — ist zwischen App und Widget NICHT geteilt!

        // 1. App Group JSON Datei (zuverlässigster Kanal)
        if let dir = containerURL {
            let fileURL = dir.appendingPathComponent(jsonFileName)
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(TelemetrySharedData.self, from: data) {
                return decoded
            }
        }

        // 2. App Group UserDefaults (Backup)
        if let group = sharedDefaults {
            group.synchronize() // Neuesten Stand von cfprefsd holen
            if let data = group.data(forKey: "carlyrics_telemetry_payload"),
               let decoded = try? JSONDecoder().decode(TelemetrySharedData.self, from: data) {
                return decoded
            }
        }

        // 3. Fallback: Dynamische Standby-Werte (wenn App noch nie Daten geschrieben hat)
        let now = Date()
        let profile = WarmupCalculator.profileForCurrentDate(date: now)

        // Warmup-Timestamps aus App Group lesen (nicht UserDefaults.standard!)
        let sTime = sharedDefaults?.double(forKey: "carlyrics_warmup_started_at") ?? 0
        let sTempSaved = sharedDefaults?.double(forKey: "carlyrics_warmup_start_temp") ?? 0

        let sTemp = (sTempSaved > -20 && sTempSaved != 0) ? sTempSaved : profile.ambientTemp
        let baseTime = (sTime > 0) ? sTime : now.timeIntervalSince1970
        let elapsed = max(0, now.timeIntervalSince1970 - baseTime)

        let calculatedTemp = WarmupCalculator.calculateOilTemp(at: elapsed, from: sTemp)
        let intTemp = Int(calculatedTemp.rounded())
        let phase = WarmupCalculator.phaseFor(temp: calculatedTemp)
        let progress = WarmupCalculator.warmupProgress(temp: calculatedTemp, startTemp: sTemp)
        let waterTemp = calculatedTemp >= 70 ? 90 : max(intTemp, intTemp + 8)

        return TelemetrySharedData(
            oilTemp: intTemp,
            coolantTemp: waterTemp,
            boostBar: 0.0,
            currentG: 0.0,
            peakG: 0.0,
            iat: 20,
            maf: 3.5,
            phase: phase,
            warmupProgress: progress,
            songTitle: "TFSI Telemetrie",
            artist: "CarLyrics Cockpit",
            previousLine2: "",
            previousLine: "",
            currentLine: "Bereit zur Fahrt",
            nextLine: "",
            nextLine2: "",
            currentTimeStr: "--:--",
            totalTimeStr: "--:--",
            progress: 0.0,
            isPlaying: false,
            sessionStartTime: baseTime,
            sessionStartTemp: sTemp,
            updatedAt: now
        )
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: LRC Lyrics Lines (für Pre-Scheduled Widget Timelines)
    // ─────────────────────────────────────────────────────────────────────

    /// Codable Lyrics-Zeile für App Group Serialisierung
    public struct WidgetLyricLine: Codable {
        public var timestamp: TimeInterval
        public var text: String
        public init(timestamp: TimeInterval, text: String) {
            self.timestamp = timestamp
            self.text = text
        }
    }

    /// Hauptapp schreibt alle LRC-Zeilen bei Song-Start in die App Group
    public static func saveLyrics(_ lines: [WidgetLyricLine], playbackPosition: TimeInterval, playbackTimestamp: TimeInterval) {
        guard let group = sharedDefaults else { return }
        if let encoded = try? JSONEncoder().encode(lines) {
            group.set(encoded, forKey: "widget_lrc_lines")
        }
        group.set(playbackPosition, forKey: "widget_playback_position")
        group.set(playbackTimestamp, forKey: "widget_playback_timestamp")
        group.synchronize()

        // Auch als JSON-Datei im Container
        if let dir = containerURL, let encoded = try? JSONEncoder().encode(lines) {
            let fileURL = dir.appendingPathComponent(lrcFileName)
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    /// Widget Extension liest LRC-Zeilen aus App Group
    public static func loadLyrics() -> (lines: [WidgetLyricLine], playbackPosition: TimeInterval, playbackTimestamp: TimeInterval)? {
        guard let group = sharedDefaults else { return nil }
        group.synchronize()

        var lines: [WidgetLyricLine]?

        // Primär: UserDefaults
        if let data = group.data(forKey: "widget_lrc_lines") {
            lines = try? JSONDecoder().decode([WidgetLyricLine].self, from: data)
        }

        // Fallback: Container JSON
        if lines == nil, let dir = containerURL {
            let fileURL = dir.appendingPathComponent(lrcFileName)
            if let data = try? Data(contentsOf: fileURL) {
                lines = try? JSONDecoder().decode([WidgetLyricLine].self, from: data)
            }
        }

        guard let lines, !lines.isEmpty else { return nil }
        let pos = group.double(forKey: "widget_playback_position")
        let ts = group.double(forKey: "widget_playback_timestamp")
        return (lines, pos, ts)
    }

    /// Playback-Position aktualisieren (bei Seek, Pause, Resume)
    public static func updatePlaybackPosition(_ position: TimeInterval, isPlaying: Bool) {
        guard let group = sharedDefaults else { return }
        group.set(position, forKey: "widget_playback_position")
        group.set(Date().timeIntervalSince1970, forKey: "widget_playback_timestamp")
        group.set(isPlaying, forKey: "widget_is_playing")
        group.synchronize()
    }
}


