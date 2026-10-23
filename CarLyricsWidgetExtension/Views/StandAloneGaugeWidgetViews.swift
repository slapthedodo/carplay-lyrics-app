// MARK: - StandAloneGaugeWidgetViews.swift
// CarLyrics Widget Extension – Standalone Focus Gauge Views (Öltemperatur & G-Kraft)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 1. WIDGET VIEW: Öltemperatur & Warmup Monitor
// ─────────────────────────────────────────────────────────────────────────────

struct OilTempWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(phaseColor(entry.phase))
                    Text("\(entry.oilTemp ?? 85)°")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 8))
                        .foregroundStyle(phaseColor(entry.phase))
                    Text("TFSI ÖLTEMPERATUR").font(.system(size: 8, weight: .bold))
                }
                Text("Öl: \(entry.oilTemp ?? 85)°C (\(entry.phase.rawValue))")
                    .font(.system(size: 11, weight: .semibold))
                Text("Wasser: \(entry.coolantTemp ?? 90)°C • Aufwärmung \(Int(entry.warmupProgress * 100))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text("🌡️ TFSI Öl: \(entry.oilTemp ?? 85)°C • \(entry.phase.rawValue)")

        case .systemSmall:
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    HStack {
                        Label("TFSI ÖL", systemImage: "thermometer.medium")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(phaseColor(entry.phase))
                        Spacer()
                        Text(entry.phase.rawValue)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(phaseColor(entry.phase))
                    }

                    Spacer()

                    OilTempBadge(
                        temp     : entry.oilTemp,
                        progress : entry.warmupProgress,
                        phase    : entry.phase,
                        size     : 62
                    )

                    Spacer()

                    HStack {
                        Text("Wasser: \(entry.coolantTemp ?? 90)°C")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(entry.warmupProgress * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(phaseColor(entry.phase))
                    }
                }
                .padding(12)
            }
            .widgetURL(URL(string: "carlyrics://cockpit"))

        default: // .systemMedium
            ZStack {
                Color.black
                HStack(spacing: 16) {
                    OilTempBadge(
                        temp     : entry.oilTemp,
                        progress : entry.warmupProgress,
                        phase    : entry.phase,
                        size     : 76
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "engine.combustion.fill").foregroundStyle(.cyan)
                            Text("2.0 TFSI Warmup").font(.headline).foregroundStyle(.white)
                        }

                        Text(entry.phase.label)
                            .font(.system(size: 9.5))
                            .foregroundStyle(phaseColor(entry.phase))
                            .lineLimit(2)

                        WarmupStatusBar(state: LyricsAttributes.ContentState(
                            warmupProgress: entry.warmupProgress,
                            warmupPhase: entry.phase
                        ))
                        .frame(height: 4)

                        HStack(spacing: 12) {
                            Text("Öl: \(entry.oilTemp ?? 85)°C")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(phaseColor(entry.phase))
                            Text("Wasser: \(entry.coolantTemp ?? 90)°C")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(14)
            }
            .widgetURL(URL(string: "carlyrics://cockpit"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 2. WIDGET VIEW: G-Kraft & Fahrdynamik (User-Design mit Lila Bogen & Scope)
// ─────────────────────────────────────────────────────────────────────────────

struct GForceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryEntry

    var body: some View {
        let purpleColor = Color(red: 0.68, green: 0.35, blue: 0.98)

        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "scope")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%.1f", entry.currentG))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Text("G")
                        .font(.system(size: 6, weight: .bold))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(purpleColor)
                    Text("G-KRAFT TELEMETRIE").font(.system(size: 8, weight: .bold))
                }
                Text(String(format: "Aktuell: %.2fG", entry.currentG))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(purpleColor)
                Text(String(format: "Spitzenwert (Peak): %.2fG", entry.peakG))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text(String(format: "🎯 G-Kraft: %.1fG • Max %.1fG", entry.currentG, entry.peakG))

        case .systemSmall:
            ZStack {
                Color.black
                VStack(spacing: 6) {
                    HStack {
                        Label("G-METER", systemImage: "scope")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundStyle(purpleColor)
                        Spacer()
                        Text(String(format: "MAX %.1fG", entry.peakG))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // User G-Kraft Instrument in Groß (Größe 88)
                    GForceGaugeBadge(
                        currentG : entry.currentG,
                        maxG     : 1.2,
                        size     : 88
                    )

                    Spacer()

                    Text(entry.currentG > 0.6 ? "SPORTLICHE DYNAMIK" : "NORMALBETRIEB")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(purpleColor)
                }
                .padding(12)
            }
            .widgetURL(URL(string: "carlyrics://cockpit"))

        default: // .systemMedium
            ZStack {
                Color.black
                HStack(spacing: 16) {
                    GForceGaugeBadge(
                        currentG : entry.currentG,
                        maxG     : 1.2,
                        size     : 92
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "scope").foregroundStyle(purpleColor)
                            Text("Fahrdynamik G-Kraft").font(.headline).foregroundStyle(.white)
                        }

                        Text("Quer- und Längsbeschleunigung im violetten Fadenkreuz.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text(String(format: "%.2fG", entry.currentG))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(purpleColor)
                            }

                            VStack(alignment: .leading) {
                                Text("PEAK").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text(String(format: "%.2fG", entry.peakG))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(14)
            }
            .widgetURL(URL(string: "carlyrics://cockpit"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Standalone Gauge Widget Configurations
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
        .contentMarginsDisabled()
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
        .contentMarginsDisabled()
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
        .contentMarginsDisabled()
    }
}

