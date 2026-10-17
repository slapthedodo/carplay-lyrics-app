// MARK: - LyricsActivityWidget.swift  (v2 — Telemetrie-Edition)
// CarLyrics Widget Extension
// Dynamic Island (Compact / Expanded / Minimal) + Lock Screen / CarPlay Banner
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widget entry
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in

            // ── Lock Screen / CarPlay Banner ──────────────────────────────
            LockScreenBannerView(state: context.state)

        } dynamicIsland: { context in
            DynamicIsland {

                // ── Expanded ─────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        OilTempBadge(
                            temp     : context.state.oilTemp,
                            progress : context.state.oilTemp != nil ? context.state.warmupProgress : 0,
                            phase    : context.state.oilTemp != nil ? context.state.warmupPhase : .cold
                        )
                        .frame(width: 44, height: 44)

                        if let water = context.state.coolantTemp {
                            Text("Wasser: \(water)°")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Wasser: --")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        GForceCompact(
                            currentG: context.state.currentG,
                            peakG   : context.state.peakG
                        )
                        .frame(width: 56)

                        if let boost = context.state.boostBar, boost > 0.05 {
                            Text(String(format: "%.2f bar", boost))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        // Track info
                        Text(context.state.songTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Current lyric line
                        Text(context.state.currentLine.isEmpty
                             ? "♪" : context.state.currentLine)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // Next line preview
                        if !context.state.nextLine.isEmpty {
                            Text(context.state.nextLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        // Warmup status bar
                        WarmupStatusBar(state: context.state)
                            .frame(height: 3)
                    }
                    .padding(.bottom, 6)
                }

            } compactLeading: {
                // ── Oil Temp Badge (Sauber formatiert, niemals abgeschnitten) ──
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--°")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

            } compactTrailing: {
                // ── Live Songtext & Telemetrie Switch in der Dynamic Island ──
                HStack(spacing: 3) {
                    if context.state.currentG > 0.35 {
                        // Bei sportlicher Beschleunigung/Kurve: Live G-Meter
                        Text(String(format: "%.1fG", context.state.currentG))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(context.state.currentG))
                            .contentTransition(.numericText())
                    } else if let boost = context.state.boostBar, boost > 0.15 {
                        // Bei Turbo Ladedruck: bar anzeigen
                        Text(String(format: "%.1fb", boost))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    } else if !context.state.currentLine.isEmpty && context.state.currentLine != "♪" && context.state.currentLine != "Öl- & Telemetrie-Monitor" {
                        // Live synchronisierter Songtext Zeile für Zeile!
                        HStack(spacing: 2) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                            Text(context.state.currentLine)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else if !context.state.songTitle.isEmpty && context.state.songTitle != "TFSI 2.0 Telemetrie" {
                        // Songtitel wenn gerade Textpause
                        HStack(spacing: 2) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(context.state.songTitle)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        // Ruhezustand: G-Kraft
                        Text(String(format: "%.1fG", context.state.currentG))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 160, alignment: .trailing)

            } minimal: {
                HStack(spacing: 1) {
                    if let temp = context.state.oilTemp {
                        Text("\(temp)°")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(phaseColor(context.state.warmupPhase))
                    } else {
                        Text("--")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Lock Screen / CarPlay Banner  (primary presentation)
// ─────────────────────────────────────────────────────────────────────────────

/// High-contrast layout for in-car glanceability:
///   Row 1 — Sport Telemetry Bar (temp + progress + G-force)
///   Row 2 — Current lyric (20 pt bold)
///   Row 3 — Next lyric (15 pt, subdued)
///   Row 4 — Song progress bar
struct LockScreenBannerView: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Telemetry bar ─────────────────────────────────────────────
            TelemetryBar(state: state)

            Divider().overlay(Color.white.opacity(0.15))

            // ── Current lyric — 20 pt bold ────────────────────────────────
            Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // ── Next lyric ────────────────────────────────────────────────
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            // ── Song progress bar ─────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * state.progress, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.88))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Bar
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryBar: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {

            // Oil temp badge
            OilTempBadge(
                temp     : state.oilTemp,
                progress : state.oilTemp != nil ? state.warmupProgress : 0,
                phase    : state.oilTemp != nil ? state.warmupPhase : .cold
            )
            .frame(width: 40, height: 40)

            // Warmup label
            VStack(alignment: .leading, spacing: 1) {
                if let _ = state.oilTemp {
                    Text(state.warmupPhase.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(phaseColor(state.warmupPhase))
                    Text(state.warmupPhase.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("OBD-II AKTIV")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Warte auf Live-Daten…")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Boost & G-Force column
            VStack(alignment: .trailing, spacing: 1) {
                if let boost = state.boostBar, boost > 0.05 {
                    Text(String(format: "%.2f BAR", boost))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                Text(String(format: "%.2f G", state.currentG))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(gColor(state.currentG))
                Text("PEAK \(String(format: "%.2f", state.peakG))G")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Oil Temp Badge (ring + °C label)
// ─────────────────────────────────────────────────────────────────────────────

struct OilTempBadge: View {
    let temp     : Int?
    let progress : Double
    let phase    : WarmupPhase

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: temp != nil ? progress : 0)
                .stroke(temp != nil ? phaseColor(phase) : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            if let temp {
                Text("\(temp)°")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(phaseColor(phase))
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Force Compact (for expanded trailing)
// ─────────────────────────────────────────────────────────────────────────────

struct GForceCompact: View {
    let currentG : Double
    let peakG    : Double

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", currentG))
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .foregroundStyle(gColor(currentG))
                .contentTransition(.numericText())
            Text("G")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("↑\(String(format: "%.2f", peakG))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Warmup Status Bar
// ─────────────────────────────────────────────────────────────────────────────

struct WarmupStatusBar: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(phaseColor(state.warmupPhase))
                    .frame(width: geo.size.width * state.warmupProgress)
                    .animation(.easeOut(duration: 0.5), value: state.warmupProgress)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Color helpers (usable in Widget Extension without UIColor)
// ─────────────────────────────────────────────────────────────────────────────

func phaseColor(_ phase: WarmupPhase) -> Color {
    switch phase {
    case .cold:    return .blue
    case .warming: return .orange
    case .ready:   return .green
    }
}

func gColor(_ g: Double) -> Color {
    switch g {
    case ..<0.3:  return .white
    case ..<0.6:  return .yellow
    case ..<0.9:  return .orange
    default:      return .red
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TelemetryCockpitWidget (Home Screen & Lock Screen Widgets)
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryEntry: TimelineEntry {
    let date        : Date
    let oilTemp     : Int?
    let coolantTemp : Int?
    let boostBar    : Double?
    let currentG    : Double
    let peakG       : Double
    let phase       : WarmupPhase
}

struct TelemetryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryEntry {
        TelemetryEntry(date: Date(), oilTemp: 85, coolantTemp: 90, boostBar: 1.15, currentG: 0.35, peakG: 0.95, phase: .ready)
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryEntry>) -> Void) {
        let tempObj = UserDefaults.standard.object(forKey: "widget_oil_temp")
        let displayTemp: Int? = tempObj as? Int
        let boostObj = UserDefaults.standard.object(forKey: "widget_boost_bar")
        let displayBoost: Double? = boostObj as? Double
        let waterObj = UserDefaults.standard.object(forKey: "widget_coolant_temp")
        let displayWater: Int? = waterObj as? Int

        let effTemp = displayTemp ?? 82
        let phase: WarmupPhase = effTemp < 60 ? .cold : (effTemp < 80 ? .warming : .ready)

        let entry = TelemetryEntry(
            date        : Date(),
            oilTemp     : displayTemp,
            coolantTemp : displayWater ?? (displayTemp != nil ? 90 : nil),
            boostBar    : displayBoost,
            currentG    : 0.28,
            peakG       : 0.85,
            phase       : phase
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 15)))
        completion(timeline)
    }
}

struct TelemetryWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.system(size: 8))
                    Text(entry.oilTemp != nil ? "\(entry.oilTemp!)°" : "--")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "gauge.with.needle").font(.system(size: 9))
                    Text("TFSI 2.0 TELEMETRIE").font(.system(size: 8, weight: .bold))
                }
                Text(entry.oilTemp != nil ? "Öl: \(entry.oilTemp!)°C (\(entry.phase.rawValue))" : "Öl: -- (Warte auf OBD)")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "Boost: %@ • Peak: %.1fG", entry.boostBar.map { String(format: "%.2fb", $0) } ?? "--", entry.peakG))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text("TFSI: \(entry.oilTemp.map { "\($0)°C" } ?? "--") Öl • Boost \(entry.boostBar.map { String(format: "%.1fb", $0) } ?? "--")")

        case .systemSmall:
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    HStack {
                        Label("TFSI 2.0", systemImage: "gauge.with.needle")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(entry.phase.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(phaseColor(entry.phase))
                    }

                    HStack(spacing: 12) {
                        OilTempBadge(temp: entry.oilTemp, progress: entry.oilTemp != nil ? Double(entry.oilTemp!) / 90.0 : 0, phase: entry.phase)
                            .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.boostBar.map { String(format: "%.2f", $0) } ?? "--")
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("BAR BOOST")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("PEAK \(String(format: "%.1f", entry.peakG))G")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.coolantTemp != nil ? "Wasser \(entry.coolantTemp!)°" : "Wasser --")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }

        default: // .systemMedium
            ZStack {
                Color.black
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "engine.combustion.fill").foregroundStyle(.cyan)
                            Text("2.0 TFSI Cockpit").font(.headline).foregroundStyle(.white)
                        }
                        Text(entry.phase.label)
                            .font(.system(size: 9))
                            .foregroundStyle(phaseColor(entry.phase))
                            .lineLimit(1)

                        HStack(spacing: 14) {
                            VStack(alignment: .leading) {
                                Text("ÖLTEMP").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text(entry.oilTemp != nil ? "\(entry.oilTemp!) °C" : "-- °C")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(phaseColor(entry.phase))
                            }
                            VStack(alignment: .leading) {
                                Text("WASSER").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text(entry.coolantTemp != nil ? "\(entry.coolantTemp!) °C" : "-- °C")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading) {
                                Text("LADEDRUCK").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text(entry.boostBar.map { String(format: "%.2f b", $0) } ?? "-- b")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text("G-KRÄFTE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        Text(String(format: "%.2fG", entry.currentG))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(entry.currentG))
                        Text("MAX \(String(format: "%.1f", entry.peakG))G")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(14)
            }
        }
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
        .configurationDisplayName("TFSI 2.0 Telemetrie")
        .description("Zeigt Öltemperatur, Kühlwasser, Ladedruck und G-Kräfte auf Home- und Sperrbildschirm.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Previews
// ─────────────────────────────────────────────────────────────────────────────

#Preview("Lock Screen – Warming", as: .content,
         using: LyricsAttributes(trackId: "preview")) {
    LyricsActivityWidget()
} contentStates: {
    LyricsAttributes.ContentState(
        currentLine    : "Caught in a landslide",
        nextLine       : "No escape from reality",
        songTitle      : "Bohemian Rhapsody",
        artist         : "Queen",
        progress       : 0.35,
        isPlaying      : true,
        currentG       : 0.42,
        peakG          : 0.81,
        gVectorX       : -0.3,
        gVectorY       : 0.27,
        oilTemp        : 67,
        warmupProgress : 0.68,
        warmupPhase    : .warming,
        isEngineWarm   : false
    )
    LyricsAttributes.ContentState(
        currentLine    : "Open your eyes",
        nextLine       : "Look up to the skies and see",
        songTitle      : "Bohemian Rhapsody",
        artist         : "Queen",
        progress       : 0.60,
        isPlaying      : true,
        currentG       : 0.08,
        peakG          : 0.81,
        oilTemp        : 90,
        warmupProgress : 1.0,
        warmupPhase    : .ready,
        isEngineWarm   : true
    )
}
