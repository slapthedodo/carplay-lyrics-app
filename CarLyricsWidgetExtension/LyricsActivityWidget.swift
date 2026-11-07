// MARK: - LyricsActivityWidget.swift  (v3 — Modular Dynamic Island & Widget Definitions)
// CarLyrics Widget Extension – ActivityKit Configuration & Widget Declarations
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import MediaPlayer

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Gemeinsamer Timeline Entry & Provider für alle Widgets
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryEntry: TimelineEntry {
    let date           : Date
    let oilTemp        : Int?
    let coolantTemp    : Int?
    let boostBar       : Double?
    let currentG       : Double
    let peakG          : Double
    let iat            : Int?
    let maf            : Double?
    let phase          : WarmupPhase
    let warmupProgress : Double
    let songTitle      : String
    let artist         : String
    let previousLine2  : String
    let previousLine   : String
    let currentLine    : String
    let nextLine       : String
    let nextLine2      : String
    let currentTimeStr : String
    let totalTimeStr   : String
    let progress       : Double
}

struct TelemetryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryEntry {
        TelemetryEntry(
            date           : Date(),
            oilTemp        : 85,
            coolantTemp    : 90,
            boostBar       : 1.20,
            currentG       : 0.90,
            peakG          : 1.25,
            iat            : 24,
            maf            : 142.0,
            phase          : .ready,
            warmupProgress : 1.0,
            songTitle      : "TFSI Telemetrie",
            artist         : "CarLyrics Cockpit",
            previousLine2  : "",
            previousLine   : "",
            currentLine    : "Bereit zur Fahrt",
            nextLine       : "",
            nextLine2      : "",
            currentTimeStr : "0:00",
            totalTimeStr   : "0:00",
            progress       : 0.0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryEntry) -> Void) {
        let storeData = TelemetrySharedStore.load()
        completion(makeEntry(from: storeData, at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryEntry>) -> Void) {
        let storeData = TelemetrySharedStore.load()
        let now = Date()

        // ──────────────────────────────────────────────────────────────────
        // Pre-Scheduled Lyrics Timeline:
        // Liest alle LRC-Zeilen aus der App Group und erstellt für JEDE Zeile
        // einen Timeline-Entry mit exaktem Zeitpunkt. WidgetKit schaltet
        // automatisch zwischen Entries um — OHNE Reload-Budget zu verbrauchen!
        // ──────────────────────────────────────────────────────────────────

        if let lrcData = TelemetrySharedStore.loadLyrics(),
           storeData.isPlaying {
            let currentPosition = lrcData.playbackPosition + (now.timeIntervalSince1970 - lrcData.playbackTimestamp)
            var entries: [TelemetryEntry] = []

            for (i, line) in lrcData.lines.enumerated() {
                let delay = line.timestamp - currentPosition
                // Nur zukünftige Zeilen + aktuelle Zeile (bis zu 2s in der Vergangenheit)
                guard delay >= -2.0 else { continue }
                // Maximal 100 Entries (WidgetKit Performance-Limit)
                guard entries.count < 100 else { break }

                let entryDate = now.addingTimeInterval(max(0, delay))
                let prevLine = i > 0 ? lrcData.lines[i - 1].text : ""
                let nextLineText = (i + 1 < lrcData.lines.count) ? lrcData.lines[i + 1].text : ""
                let nextLine2Text = (i + 2 < lrcData.lines.count) ? lrcData.lines[i + 2].text : ""

                entries.append(makeEntry(
                    from: storeData,
                    at: entryDate,
                    overridePrevLine: prevLine,
                    overrideCurrentLine: line.text,
                    overrideNextLine: nextLineText,
                    overrideNextLine2: nextLine2Text
                ))
            }

            if !entries.isEmpty {
                // .atEnd → WidgetKit fragt erst nach neuem Timeline wenn alle Entries durch sind
                let timeline = Timeline(entries: entries, policy: .atEnd)
                completion(timeline)
                return
            }
        }

        // ── Musik läuft aber (noch) keine LRC-Daten vorhanden ──
        // Snapshot der aktuellen Daten zeigen, .never Policy wartet auf nächsten
        // expliziten reloadTimelines() Aufruf (passiert wenn Lyrics fertig geladen sind)
        if storeData.isPlaying {
            let entry = makeEntry(from: storeData, at: now)
            let timeline = Timeline(entries: [entry], policy: .never)
            completion(timeline)
            return
        }

        // ── Kein Song aktiv: Warmup-Simulation ──
        var entries: [TelemetryEntry] = []
        for minute in 0...15 {
            let entryDate = now.addingTimeInterval(Double(minute * 60))
            let entry = makeEntry(from: storeData, at: entryDate, additionalElapsed: Double(minute * 60))
            entries.append(entry)
        }
        // Kurze Refresh-Policy damit neue Songs schnell erkannt werden
        let timeline = Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 2)))
        completion(timeline)
    }

    private func makeEntry(from data: TelemetrySharedData, at date: Date, additionalElapsed: TimeInterval = 0,
                           overridePrevLine: String? = nil, overrideCurrentLine: String? = nil,
                           overrideNextLine: String? = nil, overrideNextLine2: String? = nil) -> TelemetryEntry {
        let displayTemp: Int
        let displayWater: Int
        let phase: WarmupPhase
        let warmupProgress: Double

        if let liveOil = data.oilTemp, liveOil > 0 {
            displayTemp = liveOil
            displayWater = data.coolantTemp ?? (liveOil >= 70 ? 90 : max(liveOil, liveOil + 8))
            phase = data.phase
            warmupProgress = data.warmupProgress
        } else {
            // Live dynamische Simulation mit lokaler Widget-Session Speicherung
            let profile = WarmupCalculator.profileForCurrentDate(date: date)
            let sTemp = data.sessionStartTemp > -20 ? data.sessionStartTemp : profile.ambientTemp
            
            // App Group statt UserDefaults.standard für Widget-lokale Session
            let widgetDefaults = UserDefaults(suiteName: TelemetrySharedStore.appGroupId)
            let savedWidgetStart = widgetDefaults?.double(forKey: "widget_local_session_start") ?? 0
            let effectiveStartTime: Double
            if data.sessionStartTime > 0 {
                effectiveStartTime = data.sessionStartTime
                widgetDefaults?.set(data.sessionStartTime, forKey: "widget_local_session_start")
            } else if savedWidgetStart > 0 && (date.timeIntervalSince1970 - savedWidgetStart) < 2700 {
                effectiveStartTime = savedWidgetStart
            } else {
                effectiveStartTime = date.timeIntervalSince1970
                widgetDefaults?.set(effectiveStartTime, forKey: "widget_local_session_start")
            }

            let baseElapsed = max(0, date.timeIntervalSince1970 - effectiveStartTime)
            let totalElapsed = baseElapsed + additionalElapsed

            let calcOil = WarmupCalculator.calculateOilTemp(at: totalElapsed, from: sTemp)
            displayTemp = Int(calcOil.rounded())
            displayWater = displayTemp >= 70 ? 90 : max(displayTemp, displayTemp + 8)
            phase = WarmupCalculator.phaseFor(temp: calcOil)
            warmupProgress = WarmupCalculator.warmupProgress(temp: calcOil, startTemp: sTemp)
        }

        // Lyrics: Override aus Pre-Scheduled Timeline oder Fallback aus storeData
        let finalPrevLine = overridePrevLine ?? data.previousLine
        let finalCurrentLine = overrideCurrentLine ?? (data.currentLine.isEmpty ? "Bereit zur Fahrt" : data.currentLine)
        let finalNextLine = overrideNextLine ?? data.nextLine
        let finalNextLine2 = overrideNextLine2 ?? data.nextLine2

        return TelemetryEntry(
            date           : date,
            oilTemp        : displayTemp,
            coolantTemp    : displayWater,
            boostBar       : data.boostBar,
            currentG       : data.currentG,
            peakG          : data.peakG,
            iat            : data.iat,
            maf            : data.maf,
            phase          : phase,
            warmupProgress : warmupProgress,
            songTitle      : data.songTitle.isEmpty ? "TFSI Telemetrie" : data.songTitle,
            artist         : data.artist.isEmpty ? "CarLyrics Cockpit" : data.artist,
            previousLine2  : data.previousLine2,
            previousLine   : finalPrevLine,
            currentLine    : finalCurrentLine,
            nextLine       : finalNextLine,
            nextLine2      : finalNextLine2,
            currentTimeStr : data.currentTimeStr,
            totalTimeStr   : data.totalTimeStr,
            progress       : data.progress
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Live Activity Widget (Dynamic Island & Lock Screen Banner)
// ─────────────────────────────────────────────────────────────────────────────

public struct LyricsActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in

            // ── Lock Screen Banner (Groß, perfekt skaliert, hochkontrastig) ──
            LockScreenBannerView(state: context.state)

        } dynamicIsland: { context in
            DynamicIsland {

                // ── Expanded Leading: Öltemperatur Badge mit Ring ─────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        OilTempBadge(
                            temp     : context.state.oilTemp,
                            progress : context.state.oilTemp != nil ? context.state.warmupProgress : 0,
                            phase    : context.state.oilTemp != nil ? context.state.warmupPhase : .cold,
                            size     : 48
                        )
                    }
                    .padding(.leading, 6)
                }

                // ── Expanded Trailing: Kühlwasser & Motorzustand ──────────────
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        if let water = context.state.coolantTemp {
                            Text("Wasser: \(water)°C")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        } else {
                            Text("Wasser: --")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let boost = context.state.boostBar, boost > 0.05 {
                            Text(String(format: "%.2f bar", boost))
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text(context.state.isEngineWarm ? "BETRIEBSWARM" : "KALTLAUF")
                                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(phaseColor(context.state.warmupPhase))
                        }
                    }
                    .padding(.trailing, 6)
                }

                // ── Expanded Center: Öltemperatur & Phase (Keine Lyrics) ─────
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            if let temp = context.state.oilTemp {
                                Text("\(temp)°C")
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundStyle(phaseColor(context.state.warmupPhase))
                            }
                            Text(context.state.warmupPhase.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(phaseColor(context.state.warmupPhase))
                        }
                    }
                }

                // ── Expanded Bottom: Warmup & Motordaten (KEINE Lyrics) ───────
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        WarmupStatusBar(state: context.state)
                            .frame(height: 4)

                        HStack {
                            Text("VW Golf 5 GTI • EA113 2.0 TFSI")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                            Text(context.state.isEngineWarm ? "✓ Feuer frei (Warm)" : "⚠ Warmfahren (< 3000 RPM)")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(context.state.isEngineWarm ? .green : .yellow)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.bottom, 4)
                }

            } compactLeading: {
                // ── Dynamic Island Kompakt: Öltemperatur einseitig ──
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--°")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

            } compactTrailing: {
                // Leer! Lyrics komplett entfernt, Dynamic Island ist einseitig!
                EmptyView()

            } minimal: {
                HStack(spacing: 1.5) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget Configurations
// ─────────────────────────────────────────────────────────────────────────────

public struct LyricsWidget: Widget {
    public let kind: String = "CarLyrics_LyricsWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            LyricsWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Kachel 3: Purer Songtext")
        .description("5 Zeilen synchronisierter Live-Songtext zum Mitsingen mit Zeitanzeige am Fortschrittsbalken.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

public struct TelemetryCockpitWidget: Widget {
    public let kind: String = "TelemetryCockpitWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            TelemetryWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Kachel 1: Thermik & G-Kraft")
        .description("Öltemperatur, Kühlwasser, vergrößertes G-Meter und Spitzenwert (Peak).")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Interactive Widget Audio Playback Intents (iOS 17 & 18)
// ─────────────────────────────────────────────────────────────────────────────

public struct TogglePlaybackIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Wiedergabe umschalten"
    public static var description = IntentDescription("Startet oder pausiert Musik direkt im Widget.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        let spotifyToken = appGroup?.string(forKey: "spotify_access_token") ?? ""

        if !spotifyToken.isEmpty {
            let isPlaying = TelemetrySharedStore.load().isPlaying
            let endpoint = isPlaying ? "https://api.spotify.com/v1/me/player/pause" : "https://api.spotify.com/v1/me/player/play"
            if let url = URL(string: endpoint) {
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("Bearer \(spotifyToken)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 2.0
                _ = try? await URLSession.shared.data(for: req)
            }
        } else {
            let player = MPMusicPlayerController.systemMusicPlayer
            if player.playbackState == .playing {
                player.pause()
            } else {
                if player.nowPlayingItem == nil {
                    let query = MPMediaQuery.songs()
                    if let items = query.items, !items.isEmpty {
                        player.setQueue(with: query)
                        try? await player.prepareToPlay()
                    }
                }
                player.play()
            }
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "CarLyrics_LyricsWidget")
        return .result()
    }
}

public struct SkipNextTrackIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Nächster Titel"
    public static var description = IntentDescription("Springt zum nächsten Song.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        let spotifyToken = appGroup?.string(forKey: "spotify_access_token") ?? ""

        if !spotifyToken.isEmpty, let url = URL(string: "https://api.spotify.com/v1/me/player/next") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(spotifyToken)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 2.0
            _ = try? await URLSession.shared.data(for: req)
        } else {
            MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "CarLyrics_LyricsWidget")
        return .result()
    }
}

public struct SkipPreviousTrackIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource = "Vorheriger Titel"
    public static var description = IntentDescription("Springt zum vorherigen Song.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        let spotifyToken = appGroup?.string(forKey: "spotify_access_token") ?? ""

        if !spotifyToken.isEmpty, let url = URL(string: "https://api.spotify.com/v1/me/player/previous") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(spotifyToken)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 2.0
            _ = try? await URLSession.shared.data(for: req)
        } else {
            let player = MPMusicPlayerController.systemMusicPlayer
            if player.currentPlaybackTime > 3.0 {
                player.skipToBeginning()
            } else {
                player.skipToPreviousItem()
            }
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "CarLyrics_LyricsWidget")
        return .result()
    }
}

public struct RefreshWidgetIntent: AppIntent {
    public static var title: LocalizedStringResource = "Widget aktualisieren"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}


