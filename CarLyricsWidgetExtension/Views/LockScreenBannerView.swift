// MARK: - LockScreenBannerView.swift
// CarLyrics Widget Extension – High-Contrast Lock Screen Live Activity Banner (Groß & 3-Zeilen Lyrics)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit
import ActivityKit

struct LockScreenBannerView: View {
    let state: LyricsAttributes.ContentState

    private var hasLyrics: Bool {
        let text = state.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text != "♪" && text != "Öl- & Telemetrie-Monitor" && text != "Bereit zur Fahrt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {

            // ── OBERE LEISTE: Die 5 Kugeln nebeneinander (ÖL, BOOST, IAT, MAF, G-KRAFT) ──
            HStack(spacing: 0) {
                // Kugel 1: Öltemperatur mit Thermometer & Aufwärmring
                OilTempBadge(
                    temp     : state.oilTemp,
                    progress : state.oilTemp != nil ? state.warmupProgress : 0,
                    phase    : state.oilTemp != nil ? state.warmupPhase : .cold,
                    size     : 38
                )

                Spacer()

                // Kugel 2: Turbo Ladedruck
                BoostGaugeBadge(
                    boost    : state.boostBar,
                    maxBoost : 1.6,
                    size     : 38
                )

                Spacer()

                // Kugel 3: Ansaugluft (IAT)
                IATGaugeBadge(
                    iat  : state.iatTemp,
                    size : 38
                )

                Spacer()

                // Kugel 4: Luftmasse (MAF)
                MAFGaugeBadge(
                    maf  : state.mafVal,
                    size : 38
                )

                Spacer()

                // Kugel 5: G-Kraft Rundinstrument
                GForceGaugeBadge(
                    currentG : state.currentG,
                    maxG     : 1.2,
                    size     : 38
                )
            }
            .padding(.horizontal, 4)

            Divider()
                .overlay(Color.white.opacity(0.12))

            // ── MITTLERER BEREICH: Track-Info & 3-Zeilen Synchrone Lyrics ──
            if hasLyrics {
                VStack(alignment: .leading, spacing: 3) {
                    // Song Header
                    HStack(spacing: 5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.cyan)

                        Text("\(state.songTitle) • \(state.artist)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)

                        Spacer()

                        if state.progress > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                    Capsule()
                                        .fill(Color.cyan)
                                        .frame(width: max(4, geo.size.width * CGFloat(state.progress)))
                                }
                            }
                            .frame(width: 44, height: 3.5)
                        }
                    }

                    // 3-Zeilen Synchrones Mitsing-Panel
                    lyrics3LinesBlock
                }
                .padding(.vertical, 1)
            } else {
                // Standby / Kein Track / Telemetrie-Fokus
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            if let temp = state.oilTemp {
                                Text("\(temp)°C")
                                    .font(.system(size: 24, weight: .black, design: .monospaced))
                                    .foregroundStyle(phaseColor(state.warmupPhase))
                            } else {
                                Text("--°C")
                                    .font(.system(size: 24, weight: .black, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text("ÖLTEMPERATUR")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }

                        Text(state.warmupPhase.rawValue)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(phaseColor(state.warmupPhase))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let water = state.coolantTemp {
                            Text("Wasser: \(water)°C")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        Text(state.isEngineWarm ? "✓ Feuer frei" : "⚠ Warmfahren")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(state.isEngineWarm ? .green : .yellow)
                    }
                }
                .padding(.vertical, 3)
            }

            // ── UNTERE LEISTE: Aufwärm-Fortschrittsbalken & Empfehlung ──
            VStack(spacing: 3) {
                WarmupStatusBar(state: state)
                    .frame(height: 3.5)

                HStack {
                    Text(state.oilTemp != nil ? "\(state.oilTemp!)°C Öltemperatur • EA113 2.0 TFSI" : "VW Golf 5 GTI Telemetrie")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))

                    Spacer()

                    Text(state.isEngineWarm ? "✓ Warm (100%)" : "⚠ Schonend fahren")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(state.isEngineWarm ? .green : .yellow)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // ── 3-Zeilen Synchrone Lyrics Komponente ──────────────────────────────────
    @ViewBuilder
    private var lyrics3LinesBlock: some View {
        let prev = state.previousLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let curr = state.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let nxt = state.nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let nxt2 = state.nextLine2.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 2) {
            if !prev.isEmpty {
                // Zeile 1: Vorherige Zeile
                Text(prev)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)

                // Zeile 2: AKTIVE Zeile (Hervorgehoben, groß & gestochen scharf)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4, height: 4)
                    Text(curr)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.cyan.opacity(0.5), radius: 5, x: 0, y: 0)
                        .lineLimit(1)
                }

                // Zeile 3: Nächste Zeile
                if !nxt.isEmpty {
                    Text(nxt)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            } else {
                // Am Songanfang: Zeile 1 ist aktiv!
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4, height: 4)
                    Text(curr)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.cyan.opacity(0.5), radius: 5, x: 0, y: 0)
                        .lineLimit(1)
                }

                if !nxt.isEmpty {
                    Text(nxt)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                if !nxt2.isEmpty {
                    Text(nxt2)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
        }
    }
}

// ── 3-Zeilen Synchrone Lyrics für Dynamic Island Expanded Bottom ──────────────
struct DynamicIsland3LineLyricsView: View {
    let state: LyricsAttributes.ContentState

    private var hasLyrics: Bool {
        let text = state.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text != "♪" && text != "Öl- & Telemetrie-Monitor" && text != "Bereit zur Fahrt"
    }

    var body: some View {
        if hasLyrics {
            let prev = state.previousLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let curr = state.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let nxt = state.nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let nxt2 = state.nextLine2.trimmingCharacters(in: .whitespacesAndNewlines)

            VStack(alignment: .leading, spacing: 1.5) {
                if !prev.isEmpty {
                    Text(prev)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 3.5, height: 3.5)
                        Text(curr)
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.cyan.opacity(0.45), radius: 4, x: 0, y: 0)
                            .lineLimit(1)
                    }

                    if !nxt.isEmpty {
                        Text(nxt)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 3.5, height: 3.5)
                        Text(curr)
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.cyan.opacity(0.45), radius: 4, x: 0, y: 0)
                            .lineLimit(1)
                    }

                    if !nxt.isEmpty {
                        Text(nxt)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    if !nxt2.isEmpty {
                        Text(nxt2)
                            .font(.system(size: 9.5, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }
}
