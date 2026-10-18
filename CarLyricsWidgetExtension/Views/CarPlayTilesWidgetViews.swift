// MARK: - CarPlayTilesWidgetViews.swift
// CarLyrics Widget Extension – The 3 Custom CarPlay & Homescreen Tiles
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit
import AppIntents

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - KACHEL 1: All-in-One Cockpit (Öl + Kühlwasser + 20% größeres G-Meter + Peak)
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
            Button(intent: RefreshWidgetIntent()) {
                ZStack {
                    Color.black
                    VStack(spacing: 3) {
                        Spacer(minLength: 1)

                        // 1. Oben: Öltemperatur & Kühlwasser nebeneinander
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                OilTempBadge(temp: entry.oilTemp, progress: entry.warmupProgress, phase: entry.phase, size: 44)
                                Text("ÖL").font(.system(size: 8, weight: .bold)).foregroundStyle(phaseColor(entry.phase))
                            }
                            VStack(spacing: 2) {
                                CoolantGaugeBadge(temp: entry.coolantTemp, size: 44)
                                Text("WASSER").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                            }
                        }

                        Spacer(minLength: 1)

                        // 2. Mitte davon: G-Kraft Instrument mit Fadenkreuz & lila Bogen
                        VStack(spacing: 1.5) {
                            GForceGaugeBadge(currentG: entry.currentG, maxG: 1.2, size: 62)
                            Text("MOMENTAN").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98).opacity(0.85))
                        }

                        Spacer(minLength: 1)

                        Divider().overlay(Color.white.opacity(0.15))

                        // 3. Unten: Peak-Schrift ZUSAMMEN / ANEINANDER (zentriert)
                        HStack(spacing: 4) {
                            Text("PEAK:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f G", entry.peakG))
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                        }

                        Spacer(minLength: 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .buttonStyle(.plain)
            .widgetURL(URL(string: "carlyrics://cockpit"))

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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - KACHEL 2: Turbo Ladedruck & Ansaugung (Boost, IAT, MAF)
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
            Button(intent: RefreshWidgetIntent()) {
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .buttonStyle(.plain)
            .widgetURL(URL(string: "carlyrics://cockpit"))

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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - KACHEL 3: Live Songtext & Musik (5 Zeilen + Zeiten am Balken)
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
            Button(intent: RefreshWidgetIntent()) {
                ZStack {
                    Color.black
                    VStack(spacing: 3) {
                        // 1. Header: Songtitel & Artist mit ScaleFactor
                        HStack(spacing: 3.5) {
                            Image(systemName: "music.note")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                            Text("\(entry.songTitle) • \(entry.artist)")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer()
                        }

                        Divider().overlay(Color.white.opacity(0.15))

                        Spacer(minLength: 1)

                        // 2. Mitte: Synchrone Lyrics ODER klarer Standby-Zustand
                        let isStandby = entry.currentLine.isEmpty || entry.currentLine == "Bereit zur Fahrt"
                        if isStandby {
                            VStack(spacing: 3) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.green)
                                Text("Bereit zur Fahrt")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .minimumScaleFactor(0.8)
                                Text("Starte Musik auf dem iPhone")
                                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(spacing: 2) {
                                if !entry.previousLine.isEmpty {
                                    Text(entry.previousLine)
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .italic()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }

                                Text(entry.currentLine)
                                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                            )
                                    )

                                if !entry.nextLine.isEmpty {
                                    Text(entry.nextLine)
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .italic()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }

                        Spacer(minLength: 1)

                        Divider().overlay(Color.white.opacity(0.15))

                        // 3. Unten: Zeiten direkt neben dem Balken in einer Reihe
                        HStack(spacing: 4) {
                            Text(entry.currentTimeStr)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 3)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.green, .mint],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(3, geo.size.width * max(0.02, min(1.0, entry.progress))), height: 3)
                                }
                            }
                            .frame(height: 3)

                            Text(entry.totalTimeStr)
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .buttonStyle(.plain)
            .widgetURL(URL(string: "carlyrics://cockpit"))

        default: // .systemMedium
            Button(intent: RefreshWidgetIntent()) {
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
            .buttonStyle(.plain)
        }
    }
}
