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

// ── Runde Kühlwasser Anzeige (mit Wassertropfen Symbol & Himmelsblauem Ring) ──
struct CoolantGaugeBadge: View {
    let temp : Int?
    var size : CGFloat = 36

    var body: some View {
        let val = Double(temp ?? 90)
        let frac = min(max((val - 40.0) / 80.0, 0.0), 1.0)
        let skyBlue = Color(red: 0.22, green: 0.74, blue: 0.97)
        let strokeW: CGFloat = size > 50 ? 4.0 : 2.5

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: strokeW)
            Circle()
                .trim(from: 0, to: temp != nil ? frac : 0)
                .stroke(temp != nil ? skyBlue : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: frac)
            VStack(spacing: size > 50 ? 1 : -2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: size > 50 ? 12 : 8, weight: .bold))
                    .foregroundStyle(temp != nil ? skyBlue : .secondary)
                if let temp {
                    Text("\(temp)°")
                        .font(.system(size: size > 50 ? 15 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(skyBlue)
                } else {
                    Text("--")
                        .font(.system(size: size > 50 ? 15 : 10, weight: .bold, design: .monospaced))
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

            // ── OBERE LEISTE: Die 5 Kugeln nebeneinander (ÖL, BOOST, IAT, MAF, G-KRAFT) ──
            HStack(spacing: 0) {
                // Kugel 1: Öltemperatur mit Thermometer & Aufwärmring
                OilTempBadge(
                    temp     : state.oilTemp,
                    progress : state.oilTemp != nil ? state.warmupProgress : 0,
                    phase    : state.oilTemp != nil ? state.warmupPhase : .cold,
                    size     : 42
                )

                Spacer()

                // Kugel 2: Turbo Ladedruck
                BoostGaugeBadge(
                    boost    : state.boostBar,
                    maxBoost : 1.6,
                    size     : 42
                )

                Spacer()

                // Kugel 3: Ansaugluft (IAT)
                IATGaugeBadge(
                    iat  : state.iatTemp,
                    size : 42
                )

                Spacer()

                // Kugel 4: Luftmasse (MAF)
                MAFGaugeBadge(
                    maf  : state.mafVal,
                    size : 42
                )

                Spacer()

                // Kugel 5: G-Kraft Rundinstrument (Fadenkreuz, lila Bogen, G-KRAFT nach User-Bild)
                GForceGaugeBadge(
                    currentG : state.currentG,
                    maxG     : 1.2,
                    size     : 42
                )
            }
            .padding(.horizontal, 4)

            Divider()
                .overlay(Color.white.opacity(0.15))

            // ── MITTLERER BEREICH: Track-Info & Live-Songtext ──
            VStack(alignment: .leading, spacing: 2.5) {
                // Track & Artist Badge
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.green)
                    Text("\(state.songTitle) • \(state.artist)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                // Großer, klarer Live-Songtext (18pt bold)
                Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                // Nächste Zeile dezent
                if !state.nextLine.isEmpty {
                    Text(state.nextLine)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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
            displayWater = data.coolantTemp ?? (liveOil >= 70 ? 90 : max(20, liveOil + 10))
            phase = data.phase
            warmupProgress = data.warmupProgress
        } else {
            // Live dynamische Simulation
            let profile = WarmupCalculator.profileForCurrentDate(date: date)
            let sTemp = data.sessionStartTemp > -20 ? data.sessionStartTemp : profile.ambientTemp
            let baseElapsed = data.sessionStartTime > 0 ? max(0, date.timeIntervalSince1970 - data.sessionStartTime) : 0
            let totalElapsed = baseElapsed + additionalElapsed

            let calcOil = WarmupCalculator.calculateOilTemp(at: totalElapsed, from: sTemp)
            displayTemp = Int(calcOil.rounded())
            displayWater = displayTemp >= 70 ? 90 : max(20, displayTemp + 10)
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
            songTitle      : data.songTitle.isEmpty ? "Kein Song aktiv" : data.songTitle,
            artist         : data.artist.isEmpty ? "Spotify / Musik" : data.artist,
            previousLine2  : data.previousLine2,
            previousLine   : data.previousLine,
            currentLine    : data.currentLine.isEmpty ? "Warte auf Musikwiedergabe…" : data.currentLine,
            nextLine       : data.nextLine,
            nextLine2      : data.nextLine2,
            currentTimeStr : data.currentTimeStr,
            totalTimeStr   : data.totalTimeStr,
            progress       : data.progress
        )
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
                VStack(spacing: 4) {
                    Spacer(minLength: 1)

                    // 1. Oben: Großer Ladedruck & der horizontale Balken
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(entry.boostBar.map { String(format: "%.2f", $0) } ?? "0.00")
                                .font(.system(size: 24, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("BAR")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }

                        Text("LADEDRUCK RELATIV")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)

                        // Horizontaler Ladedruck-Balken bis 1.6 Bar
                        GeometryReader { geo in
                            let boostVal = entry.boostBar ?? 0.0
                            let ratio = min(max(boostVal / 1.6, 0.0), 1.0)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.cyan, Color(red: 0.22, green: 0.74, blue: 0.97), .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(6, geo.size.width * ratio), height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("0.0").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Text("0.8").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Text("1.6 BAR").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 2)

                    Divider().overlay(Color.white.opacity(0.15))

                    // 2. Unten: Ansaugluft & Luftmasse ALS ECHTE RUNDE KUGELN!
                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            IATGaugeBadge(iat: entry.iat, size: 46)
                            Text("ANSAUG")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                        }

                        VStack(spacing: 2) {
                            MAFGaugeBadge(maf: entry.maf, size: 46)
                            Text("MASSE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Spacer(minLength: 1)
                }
                .padding(10)
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
                VStack(spacing: 4) {
                    // 1. Header: NUR Songtitel & Artist (KEIN 'Mitsing-Modus' Text mehr!)
                    HStack(spacing: 3.5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text("\(entry.songTitle) • \(entry.artist)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }

                    Divider().overlay(Color.white.opacity(0.15))

                    Spacer(minLength: 1)

                    // 2. Mitte: Maximal viel Text (5 Zeilen!)
                    VStack(spacing: 2) {
                        if !entry.previousLine2.isEmpty {
                            Text(entry.previousLine2)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                                .italic()
                                .lineLimit(1)
                        }

                        if !entry.previousLine.isEmpty {
                            Text(entry.previousLine)
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .italic()
                                .lineLimit(1)
                        }

                        Text(entry.currentLine.isEmpty ? "♪" : entry.currentLine)
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            )

                        if !entry.nextLine.isEmpty {
                            Text(entry.nextLine)
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                                .italic()
                                .lineLimit(1)
                        }

                        if !entry.nextLine2.isEmpty {
                            Text(entry.nextLine2)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                                .italic()
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 1)

                    Divider().overlay(Color.white.opacity(0.15))

                    // 3. Unten: Zeiten direkt neben dem Balken in einer Reihe!
                    HStack(spacing: 5) {
                        Text(entry.currentTimeStr)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15)).frame(height: 3.5)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .mint],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(3.5, geo.size.width * max(0.02, min(1.0, entry.progress))), height: 3.5)
                            }
                        }
                        .frame(height: 3.5)

                        Text(entry.totalTimeStr)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
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

                    VStack(alignment: .leading, spacing: 3) {
                        if !entry.previousLine.isEmpty {
                            Text(entry.previousLine)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }

                        Text(entry.currentLine.isEmpty ? "♪" : entry.currentLine)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if !entry.nextLine.isEmpty {
                            Text(entry.nextLine)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text(entry.currentTimeStr)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                                Capsule().fill(Color.green).frame(width: max(3, geo.size.width * max(0.02, min(1.0, entry.progress))), height: 3)
                            }
                        }
                        .frame(height: 3)

                        Text(entry.totalTimeStr)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
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
                VStack(spacing: 4) {
                    Spacer(minLength: 1)

                    // 1. Oben: Öltemperatur & Kühlwasser nebeneinander
                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            OilTempBadge(
                                temp     : entry.oilTemp,
                                progress : entry.warmupProgress,
                                phase    : entry.phase,
                                size     : 46
                            )
                            Text("ÖL")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(phaseColor(entry.phase))
                        }

                        VStack(spacing: 2) {
                            CoolantGaugeBadge(
                                temp : entry.coolantTemp,
                                size : 46
                            )
                            Text("WASSER")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                        }
                    }

                    Spacer(minLength: 2)

                    // 2. Mitte davon: 20% größeres G-Kraft Instrument mit Fadenkreuz & lila Bogen
                    VStack(spacing: 1.5) {
                        GForceGaugeBadge(
                            currentG : entry.currentG,
                            maxG     : 1.2,
                            size     : 66
                        )
                        Text("MOMENTAN")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98).opacity(0.85))
                    }

                    Spacer(minLength: 2)

                    Divider().overlay(Color.white.opacity(0.15))

                    // 3. Unten: Peak-Schrift ZUSAMMEN / ANEINANDER (zentriert)
                    HStack(spacing: 4) {
                        Text("PEAK:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f G", entry.peakG))
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                    }

                    Spacer(minLength: 1)
                }
                .padding(10)
            }

        default: // .systemMedium
            ZStack {
                Color.black
                HStack(spacing: 14) {
                    VStack(spacing: 4) {
                        HStack(spacing: 12) {
                            VStack(spacing: 1.5) {
                                OilTempBadge(temp: entry.oilTemp, progress: entry.warmupProgress, phase: entry.phase, size: 48)
                                Text("ÖL").font(.system(size: 8, weight: .bold)).foregroundStyle(phaseColor(entry.phase))
                            }
                            VStack(spacing: 1.5) {
                                CoolantGaugeBadge(temp: entry.coolantTemp, size: 48)
                                Text("WASSER").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                            }
                        }
                        Divider().overlay(Color.white.opacity(0.15))
                        HStack(spacing: 4) {
                            Text("PEAK:").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                            Text(String(format: "%.2f G", entry.peakG)).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                        }
                    }

                    Spacer()

                    VStack(spacing: 3) {
                        GForceGaugeBadge(currentG: entry.currentG, maxG: 1.2, size: 80)
                        Text("MOMENTAN").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                    }
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
