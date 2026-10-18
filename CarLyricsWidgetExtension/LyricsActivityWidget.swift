// MARK: - LyricsActivityWidget.swift  (v3 — Modular Dynamic Island & Widget Definitions)
// CarLyrics Widget Extension – ActivityKit Configuration & Widget Declarations
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import WidgetKit
import SwiftUI

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

        // Dynamische Timeline für die nächsten 15 Minuten (im 1-Minuten-Takt):
        // So läuft die Aufwärmkurve auch dann stetig weiter, wenn das iPhone im Ruhezustand ist!
        var entries: [TelemetryEntry] = []
        for minute in 0...15 {
            let entryDate = now.addingTimeInterval(Double(minute * 60))
            let entry = makeEntry(from: storeData, at: entryDate, additionalElapsed: Double(minute * 60))
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 10)))
        completion(timeline)
    }

    private func makeEntry(from data: TelemetrySharedData, at date: Date, additionalElapsed: TimeInterval = 0) -> TelemetryEntry {
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
            
            let savedWidgetStart = UserDefaults.standard.double(forKey: "widget_local_session_start")
            let effectiveStartTime: Double
            if data.sessionStartTime > 0 {
                effectiveStartTime = data.sessionStartTime
                UserDefaults.standard.set(data.sessionStartTime, forKey: "widget_local_session_start")
            } else if savedWidgetStart > 0 && (date.timeIntervalSince1970 - savedWidgetStart) < 2700 {
                effectiveStartTime = savedWidgetStart
            } else {
                effectiveStartTime = date.timeIntervalSince1970
                UserDefaults.standard.set(effectiveStartTime, forKey: "widget_local_session_start")
            }

            let baseElapsed = max(0, date.timeIntervalSince1970 - effectiveStartTime)
            let totalElapsed = baseElapsed + additionalElapsed

            let calcOil = WarmupCalculator.calculateOilTemp(at: totalElapsed, from: sTemp)
            displayTemp = Int(calcOil.rounded())
            displayWater = displayTemp >= 70 ? 90 : max(displayTemp, displayTemp + 8)
            phase = WarmupCalculator.phaseFor(temp: calcOil)
            warmupProgress = WarmupCalculator.warmupProgress(temp: calcOil, startTemp: sTemp)
        }

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
            previousLine   : data.previousLine,
            currentLine    : data.currentLine.isEmpty ? "Bereit zur Fahrt" : data.currentLine,
            nextLine       : data.nextLine,
            nextLine2      : data.nextLine2,
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

                // ── Expanded Leading ──────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        OilTempBadge(
                            temp     : context.state.oilTemp,
                            progress : context.state.oilTemp != nil ? context.state.warmupProgress : 0,
                            phase    : context.state.oilTemp != nil ? context.state.warmupPhase : .cold,
                            size     : 44
                        )

                        if let water = context.state.coolantTemp {
                            Text("Wasser: \(water)°")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Wasser: --")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }

                // ── Expanded Trailing ─────────────────────────────────────────
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        GForceGaugeBadge(
                            currentG : context.state.currentG,
                            maxG     : 1.2,
                            size     : 44
                        )

                        if let boost = context.state.boostBar, boost > 0.05 {
                            Text(String(format: "%.2f bar", boost))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        } else {
                            Text(String(format: "Peak: %.1fG", context.state.peakG))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }

                // ── Expanded Center ───────────────────────────────────────────
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 3) {
                        Text(context.state.songTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(context.state.currentLine.isEmpty ? "♪" : context.state.currentLine)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                // ── Expanded Bottom ───────────────────────────────────────────
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        if !context.state.nextLine.isEmpty {
                            Text(context.state.nextLine)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        WarmupStatusBar(state: context.state)
                            .frame(height: 3)
                    }
                    .padding(.bottom, 6)
                }

            } compactLeading: {
                // ── Dynamic Island Kompakt Links: Öltemperatur mit Thermometer ──
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--°")
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

            } compactTrailing: {
                // ── Dynamic Island Kompakt Rechts: G-Kraft oder Songtext ──
                HStack(spacing: 3) {
                    if context.state.currentG > 0.35 {
                        // Bei Kurven/G-Kräften: Violette G-Kraft mit Fadenkreuz
                        HStack(spacing: 2) {
                            Image(systemName: "scope")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                            Text(String(format: "%.1fG", context.state.currentG))
                                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                        }
                    } else if !context.state.currentLine.isEmpty && context.state.currentLine != "♪" && context.state.currentLine != "Öl- & Telemetrie-Monitor" {
                        // Live synchronisierter Songtext
                        HStack(spacing: 2) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                            Text(context.state.currentLine)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else if !context.state.songTitle.isEmpty && context.state.songTitle != "TFSI 2.0 Telemetrie" {
                        HStack(spacing: 2) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(context.state.songTitle)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        Text(context.state.warmupPhase.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    }
                }
                .frame(maxWidth: 160, alignment: .trailing)

            } minimal: {
                HStack(spacing: 1.5) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--")
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
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

public struct OilTempWidget: Widget {
    public let kind: String = "CarLyrics_OilTempWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            OilTempWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("TFSI Öltemperatur")
        .description("Zeigt die exakte TFSI Öltemperatur und Aufwärmphasen mit Thermometer-Symbol.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

public struct GForceWidget: Widget {
    public let kind: String = "CarLyrics_GForceWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            GForceWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("G-Kraft Telemetrie")
        .description("Zeigt die G-Kräfte im violetten Rundinstrument mit Fadenkreuz-Design an.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

public struct BoostPerformanceWidget: Widget {
    public let kind: String = "CarLyrics_BoostWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            BoostPerformanceWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Kachel 2: Turbo & Luft")
        .description("Ladedruckbalken in Bar sowie Rundinstrumente für Ansaugluft (IAT) und Luftmasse (MAF).")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

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
    }
}
