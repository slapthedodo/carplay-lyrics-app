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
                // ── Öltemperatur Anzeige (Klartext ÖL + Temp) ──
                HStack(spacing: 2) {
                    Text("ÖL")
                        .font(.system(size: 9, weight: .black, design: .rounded))
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
                    Text("ÖL")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(context.state.oilTemp != nil ? phaseColor(context.state.warmupPhase) : .secondary)
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
        VStack(alignment: .leading, spacing: 8) {

            // ── Telemetry bar (3 Rundinstrumente: Öltemp, Boost, G-Ball + Telemetrie) ──
            TelemetryBar(state: state)

            Divider().overlay(Color.white.opacity(0.15))

            // ── Current lyric — 18 pt bold ────────────────────────────────
            Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // ── Next lyric ────────────────────────────────────────────────
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.88))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Bar (3 Rundinstrumente: Öl, Boost, G-Ball + Ansaugung)
// ─────────────────────────────────────────────────────────────────────────────

struct MiniGBallWidgetView: View {
    let x        : Double
    let y        : Double
    let currentG : Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 38, height: 38)
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                .frame(width: 20, height: 20)

            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 38, height: 0.8)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 0.8, height: 38)

            Circle()
                .fill(gColor(currentG))
                .frame(width: 6, height: 6)
                .shadow(color: gColor(currentG).opacity(0.8), radius: 2)
                .offset(
                    x: CGFloat(min(max(x, -1.0), 1.0)) * 14,
                    y: CGFloat(min(max(-y, -1.0), 1.0)) * 14
                )
        }
        .frame(width: 40, height: 40)
    }
}

// ── Runde Ladedruck Anzeige ──
struct BoostGaugeBadge: View {
    let boost: Double?
    var maxBoost: Double = 1.6

    var body: some View {
        let val = boost ?? 0.0
        let frac = min(max(val / maxBoost, 0.0), 1.0)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: boost != nil ? frac : 0)
                .stroke(val > 0.8 ? Color.orange : (val > 0.1 ? Color.green : Color.cyan),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: frac)
            VStack(spacing: -1) {
                Text("BOOST")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(boost != nil ? Color.cyan : .secondary)
                if let boost {
                    Text(String(format: "%.1f", boost))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(val > 0.8 ? Color.orange : (val > 0.1 ? Color.green : Color.cyan))
                } else {
                    Text("--")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
    }
}

// ── Runde Öltemperatur Anzeige (ohne verwirrendes Symbol, klare Typografie) ──
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
            VStack(spacing: -1) {
                Text("ÖL")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(temp != nil ? phaseColor(phase) : .secondary)
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
        .frame(width: 40, height: 40)
    }
}

struct TelemetryBar: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {

            // 1. Rundinstrument: Öltemperatur
            OilTempBadge(
                temp     : state.oilTemp,
                progress : state.oilTemp != nil ? state.warmupProgress : 0,
                phase    : state.oilTemp != nil ? state.warmupPhase : .cold
            )

            // 2. Rundinstrument: Ladedruck (relative bar)
            BoostGaugeBadge(boost: state.boostBar)

            // 3. Rundinstrument: G-Ball Fadenkreuz
            MiniGBallWidgetView(x: state.gVectorX, y: state.gVectorY, currentG: state.currentG)

            Spacer()

            // 4. Echtzeit Telemetrie: Ansaugluft (IAT), Luftmasse (MAF), G-Force
            VStack(alignment: .trailing, spacing: 1) {
                if let iat = state.iatTemp {
                    Text("IAT \(iat)°C")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                } else if let water = state.coolantTemp {
                    Text("H2O \(water)°")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let maf = state.mafVal {
                    Text(String(format: "MAF %.0fg/s", maf))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 3) {
                    Text(String(format: "%.2fG", state.currentG))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(gColor(state.currentG))
                    Text("PK \(String(format: "%.1f", state.peakG))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        let tempObj = appGroup?.object(forKey: "widget_oil_temp") ?? UserDefaults.standard.object(forKey: "widget_oil_temp")
        let displayTemp: Int? = tempObj as? Int
        let boostObj = appGroup?.object(forKey: "widget_boost_bar") ?? UserDefaults.standard.object(forKey: "widget_boost_bar")
        let displayBoost: Double? = boostObj as? Double
        let waterObj = appGroup?.object(forKey: "widget_coolant_temp") ?? UserDefaults.standard.object(forKey: "widget_coolant_temp")
        let displayWater: Int? = waterObj as? Int

        // Intelligenter Fallback für Home- & Sperrbildschirm-Widgets, damit NIEMALS nur Striche "--" stehen:
        // Wenn der User das Widget hinzufügt oder OBD gerade getrennt ist,
        // zeigen wir realistische Standby-TFSI-Werte oder gespeicherte letzte Werte
        let effTemp = displayTemp ?? 85
        let effWater = displayWater ?? 90
        let effBoost = displayBoost ?? 0.0
        let phase: WarmupPhase = effTemp < 60 ? .cold : (effTemp < 80 ? .warming : .ready)

        let entry = TelemetryEntry(
            date        : Date(),
            oilTemp     : effTemp,
            coolantTemp : effWater,
            boostBar    : effBoost,
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
                VStack(spacing: -1) {
                    Text("ÖL")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("\(entry.oilTemp ?? 85)°")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("ÖL").font(.system(size: 8, weight: .black, design: .rounded)).foregroundStyle(.cyan)
                    Text("TFSI 2.0 TELEMETRIE").font(.system(size: 8, weight: .bold))
                }
                Text("Öl: \(entry.oilTemp ?? 85)°C (\(entry.phase.rawValue))")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "Boost: %@ • Peak: %.1fG", entry.boostBar.map { String(format: "%.2fb", $0) } ?? "0.00b", entry.peakG))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text("TFSI: \(entry.oilTemp.map { "\($0)°C" } ?? "85°C") ÖL • Boost \(entry.boostBar.map { String(format: "%.1fb", $0) } ?? "0.0b")")

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
