// MARK: - LyricsActivityWidget.swift  (v3 — Modular Cockpit & Telemetrie Edition)
// CarLyrics Widget Extension
// Dynamic Island + Lock Screen Live Activity + Dedicated Modular Widgets
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Color & Style Helpers
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
    default:      return Color(red: 0.68, green: 0.35, blue: 0.98) // signature purple
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Reusable Gauges & Badges
// ─────────────────────────────────────────────────────────────────────────────

// ── Runde G-Kraft Anzeige nach User-Design (mit Fadenkreuz, lila Bogen, 'G-KRAFT', Zahl und 'G') ──
struct GForceGaugeBadge: View {
    let currentG : Double
    var maxG     : Double = 1.2
    var size     : CGFloat = 48

    var body: some View {
        let ratio = min(max(currentG / max(0.4, maxG), 0.0), 1.0)
        let purpleColor = Color(red: 0.68, green: 0.35, blue: 0.98) // #ae5bf7

        ZStack {
            // Schwarzer runder Hintergrund
            Circle()
                .fill(Color.black.opacity(0.85))

            // Äußerer feiner Ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: size > 60 ? 3 : 2)

            // 4 Fadenkreuz-Markierungen (12, 3, 6, 9 Uhr)
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: size > 60 ? 1.5 : 1, height: size > 60 ? 6 : (size > 40 ? 4 : 3))
                    .offset(y: -(size / 2 - (size > 60 ? 3 : 2)))
                    .rotationEffect(.degrees(Double(deg)))
            }

            // Lila Bogen / Fortschrittsanzeige
            Circle()
                .trim(from: 0.0, to: CGFloat(max(0.04, ratio * 0.75)))
                .stroke(
                    LinearGradient(
                        colors: [purpleColor.opacity(0.4), purpleColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size > 60 ? 4.5 : (size > 40 ? 3.0 : 2.2), lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // Text & Fadenkreuz-Layout
            VStack(spacing: size > 70 ? 2 : (size > 40 ? 0 : -1)) {
                // Weißes Fadenkreuz Icon (wie im Bild)
                Image(systemName: "scope")
                    .font(.system(size: max(8, size * 0.17), weight: .bold))
                    .foregroundStyle(.white)

                Text("G-KRAFT")
                    .font(.system(size: max(5, size * 0.085), weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text(String(format: "%.1f", currentG))
                    .font(.system(size: max(9.5, size * 0.22), weight: .heavy, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text("G")
                    .font(.system(size: max(4.5, size * 0.075), weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}

// ── Runde Öltemperatur Anzeige (mit Thermometer Symbol) ──
struct OilTempBadge: View {
    let temp     : Int?
    let progress : Double
    let phase    : WarmupPhase
    var size     : CGFloat = 36

    var body: some View {
        let strokeW: CGFloat = size > 50 ? 4.0 : 2.5
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: strokeW)
            Circle()
                .trim(from: 0, to: temp != nil ? progress : 0)
                .stroke(temp != nil ? phaseColor(phase) : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            VStack(spacing: size > 50 ? 1 : -2) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: size > 50 ? 14 : 8, weight: .bold))
                    .foregroundStyle(temp != nil ? phaseColor(phase) : .secondary)
                if let temp {
                    Text("\(temp)°")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(phaseColor(phase))
                } else {
                    Text("--")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// ── Runde Ladedruck Anzeige ──
struct BoostGaugeBadge: View {
    let boost    : Double?
    var maxBoost : Double = 1.6
    var size     : CGFloat = 36

    var body: some View {
        let val = boost ?? 0.0
        let frac = min(max(val / maxBoost, 0.0), 1.0)
        let strokeW: CGFloat = size > 50 ? 4.0 : 2.5

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: strokeW)
            Circle()
                .trim(from: 0, to: boost != nil ? frac : 0)
                .stroke(val > 0.8 ? Color.orange : (val > 0.1 ? Color.green : Color.cyan),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: frac)
            VStack(spacing: size > 50 ? 1 : -1) {
                Text("BAR")
                    .font(.system(size: size > 50 ? 9 : 7, weight: .black, design: .rounded))
                    .foregroundStyle(boost != nil ? Color.cyan : .secondary)
                if let boost {
                    Text(String(format: "%.1f", boost))
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(val > 0.8 ? Color.orange : (val > 0.1 ? Color.green : Color.cyan))
                } else {
                    Text("--")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// ── Runde Ansaugluft (IAT) Anzeige ──
struct IATGaugeBadge: View {
    let iat  : Int?
    var size : CGFloat = 36

    var body: some View {
        let val = Double(iat ?? 20)
        let frac = min(max((val - 10.0) / 60.0, 0.0), 1.0)
        let iatColor = val > 50 ? Color.orange : Color.cyan
        let strokeW: CGFloat = size > 50 ? 4.0 : 2.5

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: strokeW)
            Circle()
                .trim(from: 0, to: iat != nil ? frac : 0)
                .stroke(iatColor, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: frac)
            VStack(spacing: size > 50 ? 1 : -1) {
                Text("IAT")
                    .font(.system(size: size > 50 ? 9 : 7, weight: .black, design: .rounded))
                    .foregroundStyle(iat != nil ? iatColor : .secondary)
                if let iat {
                    Text("\(iat)°")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(iatColor)
                } else {
                    Text("--")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// ── Runde Luftmasse (MAF) Anzeige ──
struct MAFGaugeBadge: View {
    let maf  : Double?
    var size : CGFloat = 36

    var body: some View {
        let val = maf ?? 0.0
        let frac = min(max(val / 220.0, 0.0), 1.0)
        let mafColor = val > 150 ? Color(red: 0.68, green: 0.35, blue: 0.98) : (val > 60 ? Color.white : Color.secondary)
        let strokeW: CGFloat = size > 50 ? 4.0 : 2.5

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: strokeW)
            Circle()
                .trim(from: 0, to: maf != nil ? frac : 0)
                .stroke(mafColor, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: frac)
            VStack(spacing: size > 50 ? 1 : -1) {
                Text("MAF")
                    .font(.system(size: size > 50 ? 9 : 7, weight: .black, design: .rounded))
                    .foregroundStyle(maf != nil ? Color.white : .secondary)
                if let maf {
                    Text(String(format: "%.0f", maf))
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    Text("--")
                        .font(.system(size: size > 50 ? 17 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// ── Warmup Status Balken ──
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
// MARK: - Live Activity Widget (Dynamic Island & Lock Screen Banner)
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsActivityWidget: Widget {

    var body: some WidgetConfiguration {
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
// MARK: Lock Screen Banner (Groß & Sauber Skaliert)
// ─────────────────────────────────────────────────────────────────────────────

struct LockScreenBannerView: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── OBERE LEISTE: Öltemperatur + Telemetrie + G-Kraft ──
            HStack(alignment: .center, spacing: 10) {

                // 1. Öltemperatur (Sehr groß, fett, sofort lesbar)
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(phaseColor(state.warmupPhase))

                    VStack(alignment: .leading, spacing: -2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            if let temp = state.oilTemp {
                                Text("\(temp)")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(phaseColor(state.warmupPhase))
                                Text("°C")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(phaseColor(state.warmupPhase).opacity(0.8))
                            } else {
                                Text("--")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("°C")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(state.warmupPhase.rawValue)
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundStyle(phaseColor(state.warmupPhase))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(phaseColor(state.warmupPhase).opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(phaseColor(state.warmupPhase).opacity(0.3), lineWidth: 1)
                        )
                )

                // 2. Telemetrie Pillen (Kühlwasser & Turbo Boost)
                VStack(alignment: .leading, spacing: 4) {
                    // Wasser
                    HStack(spacing: 3) {
                        Text("Wasser:")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(state.coolantTemp != nil ? "\(state.coolantTemp!)°" : "--°")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(state.coolantTemp != nil ? (state.coolantTemp! >= 80 ? .green : .cyan) : .secondary)
                    }

                    // Boost
                    HStack(spacing: 3) {
                        Text("Boost:")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(state.boostBar.map { String(format: "%.2fb", $0) } ?? "0.00b")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                Spacer()

                // 3. User G-Kraft Badge (Lila Rundinstrument mit Scope & Bogen nach Bild)
                GForceGaugeBadge(currentG: state.currentG, maxG: 1.2, size: 48)
            }

            Divider()
                .overlay(Color.white.opacity(0.15))

            // ── MITTLERER BEREICH: Track-Info & Riesiger Live-Songtext ──
            VStack(alignment: .leading, spacing: 3) {
                // Track & Artist Badge
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                    Text("\(state.songTitle) • \(state.artist)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                // Großer, fetter, hochkontrastiger Live-Songtext (20pt!)
                Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)

                // Nächste Zeile dezent
                if !state.nextLine.isEmpty {
                    Text(state.nextLine)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            // ── UNTERE LEISTE: Fortschrittsbalken ──
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3.5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0.02, min(1.0, state.progress)), height: 3.5)
                }
            }
            .frame(height: 3.5)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

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
    let currentLine    : String
    let nextLine       : String
    let progress       : Double
}

struct TelemetryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryEntry {
        TelemetryEntry(
            date           : Date(),
            oilTemp        : 85,
            coolantTemp    : 90,
            boostBar       : 1.15,
            currentG       : 0.35,
            peakG          : 0.95,
            iat            : 24,
            maf            : 142.0,
            phase          : .ready,
            warmupProgress : 1.0,
            songTitle      : "Bohemian Rhapsody",
            artist         : "Queen",
            currentLine    : "Is this the real life? Is this just fantasy?",
            nextLine       : "Caught in a landslide, no escape from reality",
            progress       : 0.35
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryEntry>) -> Void) {
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        let def = UserDefaults.standard

        let tempObj = appGroup?.object(forKey: "widget_oil_temp") ?? def.object(forKey: "widget_oil_temp")
        let displayTemp: Int = (tempObj as? Int) ?? 85

        let boostObj = appGroup?.object(forKey: "widget_boost_bar") ?? def.object(forKey: "widget_boost_bar")
        let displayBoost: Double = (boostObj as? Double) ?? 0.0

        let waterObj = appGroup?.object(forKey: "widget_coolant_temp") ?? def.object(forKey: "widget_coolant_temp")
        let displayWater: Int = (waterObj as? Int) ?? (displayTemp >= 70 ? 90 : max(20, displayTemp + 10))

        let gObj = appGroup?.object(forKey: "widget_current_g") ?? def.object(forKey: "widget_current_g")
        let displayG: Double = (gObj as? Double) ?? 0.28

        let peakGObj = appGroup?.object(forKey: "widget_peak_g") ?? def.object(forKey: "widget_peak_g")
        let displayPeakG: Double = (peakGObj as? Double) ?? 0.85

        let iatObj = appGroup?.object(forKey: "widget_iat") ?? def.object(forKey: "widget_iat")
        let displayIAT: Int = (iatObj as? Int) ?? 24

        let mafObj = appGroup?.object(forKey: "widget_maf") ?? def.object(forKey: "widget_maf")
        let displayMAF: Double = (mafObj as? Double) ?? 142.0

        let songTitle = (appGroup?.string(forKey: "widget_song_title") ?? def.string(forKey: "widget_song_title")) ?? "Bohemian Rhapsody"
        let artist = (appGroup?.string(forKey: "widget_artist") ?? def.string(forKey: "widget_artist")) ?? "Queen"
        let currentLine = (appGroup?.string(forKey: "widget_current_line") ?? def.string(forKey: "widget_current_line")) ?? "Is this the real life? Is this just fantasy?"
        let nextLine = (appGroup?.string(forKey: "widget_next_line") ?? def.string(forKey: "widget_next_line")) ?? "Caught in a landslide, no escape from reality"
        let progress = (appGroup?.double(forKey: "widget_song_progress") ?? def.double(forKey: "widget_song_progress"))

        let phase: WarmupPhase = displayTemp < 60 ? .cold : (displayTemp < 80 ? .warming : .ready)
        let warmupProgress = min(max(Double(displayTemp) / 80.0, 0.0), 1.0)

        let entry = TelemetryEntry(
            date           : Date(),
            oilTemp        : displayTemp,
            coolantTemp    : displayWater,
            boostBar       : displayBoost,
            currentG       : displayG,
            peakG          : displayPeakG,
            iat            : displayIAT,
            maf            : displayMAF,
            phase          : phase,
            warmupProgress : warmupProgress,
            songTitle      : songTitle,
            artist         : artist,
            currentLine    : currentLine,
            nextLine       : nextLine,
            progress       : progress > 0 ? progress : 0.35
        )

        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 15)))
        completion(timeline)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 1. WIDGET: Öltemperatur & Warmup Monitor
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
        }
    }
}

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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 2. WIDGET: G-Kraft & Fahrdynamik (User-Design mit Lila Bogen & Scope)
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

                    // User G-Kraft Instrument in Groß (Größe 90)
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
        }
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 3. WIDGET: Turbo Ladedruck & Ansaugung (Boost, IAT, MAF)
// ─────────────────────────────────────────────────────────────────────────────

struct BoostPerformanceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Text("BAR")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.cyan)
                    Text(entry.boostBar.map { String(format: "%.1f", $0) } ?? "0.0")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle").font(.system(size: 8)).foregroundStyle(.cyan)
                    Text("TFSI 2.0 TURBO").font(.system(size: 8, weight: .bold))
                }
                Text("Ladedruck: \(entry.boostBar.map { String(format: "%.2f bar", $0) } ?? "0.00 bar")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text("IAT: \(entry.iat ?? 24)°C • MAF: \(String(format: "%.0f", entry.maf ?? 142)) g/s")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text("🚀 Boost: \(entry.boostBar.map { String(format: "%.2f bar", $0) } ?? "0.00 bar") • IAT: \(entry.iat ?? 24)°C")

        case .systemSmall:
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    HStack {
                        Label("TURBO", systemImage: "gauge.with.needle")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text("TFSI 2.0")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    BoostGaugeBadge(boost: entry.boostBar, maxBoost: 1.6, size: 62)

                    Spacer()

                    HStack {
                        Text("IAT: \(entry.iat ?? 24)°C")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("MAF: \(String(format: "%.0f", entry.maf ?? 142))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
            }

        default: // .systemMedium: 3 Rundanzeigen nebeneinander (Boost, IAT, MAF)
            ZStack {
                Color.black
                VStack(spacing: 10) {
                    HStack {
                        Label("TURBO & ANSAUGUNG", systemImage: "gauge.with.needle")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text("VW TFSI 2.0 EA113")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 24) {
                        BoostGaugeBadge(boost: entry.boostBar, maxBoost: 1.6, size: 60)
                        IATGaugeBadge(iat: entry.iat, size: 60)
                        MAFGaugeBadge(maf: entry.maf, size: 60)
                    }
                }
                .padding(14)
            }
        }
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
        .configurationDisplayName("Turbo Ladedruck")
        .description("Zeigt Ladedruck (bar), Ansauglufttemperatur (IAT) und Luftmasse (MAF).")
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
// MARK: - 4. WIDGET: Live Songtext & Musik
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TelemetryEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note").font(.system(size: 8)).foregroundStyle(.green)
                    Text("\(entry.songTitle) • \(entry.artist)").font(.system(size: 8, weight: .bold)).lineLimit(1)
                }
                Text(entry.currentLine)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(2)
            }

        case .accessoryInline:
            Text("🎵 \(entry.songTitle): \(entry.currentLine)")

        case .systemSmall:
            ZStack {
                Color.black
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.green)
                        Text(entry.songTitle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Text(entry.artist)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(entry.currentLine)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    Spacer()

                    Capsule().fill(Color.green).frame(height: 3)
                }
                .padding(12)
            }

        default: // .systemMedium
            ZStack {
                Color.black
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.green)
                        Text("\(entry.songTitle) • \(entry.artist)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("LIVE LYRICS")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Text(entry.currentLine)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !entry.nextLine.isEmpty {
                        Text(entry.nextLine)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(Color.green).frame(width: geo.size.width * entry.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                .padding(14)
            }
        }
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
        .configurationDisplayName("Live Songtext")
        .description("Zeigt den synchronisierten Live-Songtext von Spotify auf dem Sperr- und Homescreen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 5. WIDGET: All-in-One Cockpit (Öl + Ladedruck + G-Kraft)
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryWidgetEntryView: View {
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
                    Image(systemName: "thermometer.medium").font(.system(size: 8)).foregroundStyle(.cyan)
                    Text("TFSI 2.0 TELEMETRIE").font(.system(size: 8, weight: .bold))
                }
                Text("Öl: \(entry.oilTemp ?? 85)°C (\(entry.phase.rawValue))")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "Boost: %@ • Peak: %.1fG", entry.boostBar.map { String(format: "%.2fb", $0) } ?? "0.00b", entry.peakG))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            Text("TFSI: \(entry.oilTemp ?? 85)°C ÖL • Boost \(entry.boostBar.map { String(format: "%.1fb", $0) } ?? "0.0b")")

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
                        OilTempBadge(
                            temp     : entry.oilTemp,
                            progress : entry.warmupProgress,
                            phase    : entry.phase,
                            size     : 50
                        )

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
                        Text("Wasser \(entry.coolantTemp ?? 90)°")
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
                                Text("\(entry.oilTemp ?? 85) °C")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(phaseColor(entry.phase))
                            }
                            VStack(alignment: .leading) {
                                Text("WASSER").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                Text("\(entry.coolantTemp ?? 90) °C")
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

                    GForceGaugeBadge(
                        currentG : entry.currentG,
                        maxG     : 1.2,
                        size     : 72
                    )
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
        .configurationDisplayName("TFSI 2.0 Cockpit")
        .description("Das Renncockpit mit Öltemperatur, Ladedruck und G-Kräften vereint.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
