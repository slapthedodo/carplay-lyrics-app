// MARK: - WidgetGaugeBadges.swift
// CarLyrics Widget Extension – Reusable Circular Instruments & Badges
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit

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
