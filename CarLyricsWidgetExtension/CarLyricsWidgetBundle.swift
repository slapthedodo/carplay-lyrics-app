// MARK: - CarLyricsWidgetBundle.swift
// CarLyrics Widget Extension – Entry Point & Telemetrie Widgets
// ─────────────────────────────────────────────────────────────────────────────
// Target membership: CarLyricsWidgetExtension ONLY
// ─────────────────────────────────────────────────────────────────────────────

import WidgetKit
import SwiftUI

@main
struct CarLyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 1. The Dynamic Island & Lock Screen Live Activity
        LyricsActivityWidget()

        // 2. The Home Screen, StandBy & Lock Screen Telemetry Widget
        EngineTelemetryWidget()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Engine Telemetry Widget (Home Screen, StandBy & Lock Screen)
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryTimelineEntry: TimelineEntry {
    let date: Date
    let oilTemp: Int
    let warmupProgress: Double
    let warmupPhase: WarmupPhase
    let peakG: Double
    let currentG: Double
    let songTitle: String
    let artist: String
}

struct TelemetryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryTimelineEntry {
        TelemetryTimelineEntry(
            date: Date(),
            oilTemp: 85,
            warmupProgress: 0.95,
            warmupPhase: .ready,
            peakG: 0.85,
            currentG: 0.0,
            songTitle: "CarLyrics Cockpit",
            artist: "2.0 TFSI Telemetrie"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryTimelineEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryTimelineEntry>) -> Void) {
        let temp = UserDefaults.standard.integer(forKey: "last_oil_temp")
        let actualTemp = temp > 0 ? temp : 82
        let phaseRaw = UserDefaults.standard.string(forKey: "last_warmup_phase") ?? WarmupPhase.ready.rawValue
        let phase = WarmupPhase(rawValue: phaseRaw) ?? .ready
        let peak = UserDefaults.standard.double(forKey: "last_peak_g")
        let actualPeak = peak > 0 ? peak : 0.85
        let song = UserDefaults.standard.string(forKey: "last_song_title") ?? "CarLyrics Ready"
        let artist = UserDefaults.standard.string(forKey: "last_song_artist") ?? "EA888 Sport"

        let progress = min(1.0, max(0.0, Double(actualTemp - 8) / (80.0 - 8.0)))

        let entry = TelemetryTimelineEntry(
            date: Date(),
            oilTemp: actualTemp,
            warmupProgress: progress,
            warmupPhase: phase,
            peakG: actualPeak,
            currentG: 0.0,
            songTitle: song,
            artist: artist
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct EngineTelemetryWidget: Widget {
    let kind: String = "EngineTelemetryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            EngineTelemetryWidgetView(entry: entry)
                .containerBackground(.black.opacity(0.85), for: .widget)
        }
        .configurationDisplayName("2.0 TFSI & G-Force")
        .description("Zeigt Öltemperatur, Warmup-Status und G-Kräfte auf deinem Home- & Sperrbildschirm an.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

struct EngineTelemetryWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryTimelineEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallTelemetryWidgetView(entry: entry)
        case .systemMedium:
            MediumTelemetryWidgetView(entry: entry)
        case .accessoryRectangular:
            LockScreenRectangularWidgetView(entry: entry)
        case .accessoryCircular:
            LockScreenCircularWidgetView(entry: entry)
        case .accessoryInline:
            Text("🌡️ \(entry.oilTemp)°C Öl • \(String(format: "%.1f", entry.peakG))G Peak")
        default:
            SmallTelemetryWidgetView(entry: entry)
        }
    }
}

struct SmallTelemetryWidgetView: View {
    let entry: TelemetryTimelineEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("2.0 TFSI")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.warmupPhase.rawValue)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(phaseColor(entry.warmupPhase))
            }

            Spacer()

            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: entry.warmupProgress)
                    .stroke(phaseColor(entry.warmupPhase), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(entry.oilTemp)°")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(phaseColor(entry.warmupPhase))
                    Text("ÖLTEMP")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            Spacer()

            HStack {
                Text("PEAK")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(String(format: "%.2f", entry.peakG)) G")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
    }
}

struct MediumTelemetryWidgetView: View {
    let entry: TelemetryTimelineEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Oil Gauge
            VStack(spacing: 6) {
                HStack {
                    Text("ÖLTEMPERATUR")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.warmupPhase.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(phaseColor(entry.warmupPhase))
                }

                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: entry.warmupProgress)
                        .stroke(phaseColor(entry.warmupPhase), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(entry.oilTemp)°C")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(phaseColor(entry.warmupPhase))
                        Text(entry.oilTemp < 80 ? "SCHONEN" : "BEREIT")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 68, height: 68)

                Text(entry.oilTemp < 60 ? "Max 2.500 U/min" : (entry.oilTemp < 80 ? "Max 3.500 U/min" : "Feuer frei 🔥"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(phaseColor(entry.warmupPhase))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.white.opacity(0.15))

            // Right: G-Force & Music
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("G-TELEMETRIE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("PEAK \(String(format: "%.2f", entry.peakG))G")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 8) {
                    Image(systemName: "gyroscope")
                        .font(.system(size: 20))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2.0 TFSI Cockpit")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(entry.songTitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack {
                    Capsule()
                        .fill(Color.orange.opacity(0.2))
                        .overlay(
                            GeometryReader { g in
                                Capsule()
                                    .fill(Color.orange)
                                    .frame(width: g.size.width * min(1.0, entry.peakG / 1.35))
                            }
                        )
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
    }
}

struct LockScreenRectangularWidgetView: View {
    let entry: TelemetryTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("🌡️ \(entry.oilTemp)°C Öl")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(entry.warmupPhase.rawValue)")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text("⚡ Peak: \(String(format: "%.2f", entry.peakG))G • 2.0 TFSI")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ProgressView(value: entry.warmupProgress)
                .tint(entry.oilTemp >= 80 ? .green : .orange)
        }
    }
}

struct LockScreenCircularWidgetView: View {
    let entry: TelemetryTimelineEntry

    var body: some View {
        Gauge(value: entry.warmupProgress, in: 0...1) {
            Text("ÖL")
        } currentValueLabel: {
            Text("\(entry.oilTemp)°")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .gaugeStyle(.accessoryCircular)
    }
}
