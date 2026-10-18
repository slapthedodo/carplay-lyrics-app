// MARK: - LockScreenBannerView.swift
// CarLyrics Widget Extension – High-Contrast Lock Screen Live Activity Banner
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit
import ActivityKit

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

            // ── MITTLERER BEREICH: Öltemperatur & Aufwärmstatus ──
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let temp = state.oilTemp {
                            Text("\(temp)°C")
                                .font(.system(size: 26, weight: .black, design: .monospaced))
                                .foregroundStyle(phaseColor(state.warmupPhase))
                        } else {
                            Text("--°C")
                                .font(.system(size: 26, weight: .black, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text("ÖLTEMPERATUR")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Text(state.warmupPhase.rawValue)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(phaseColor(state.warmupPhase))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let water = state.coolantTemp {
                        Text("Kühlwasser: \(water)°C")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    Text(state.isEngineWarm ? "✓ Betriebsbereit" : "⚠ Schonend fahren")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(state.isEngineWarm ? .green : .yellow)
                }
            }
            .padding(.vertical, 4)

            // ── UNTERE LEISTE: Aufwärm-Fortschrittsbalken ──
            WarmupStatusBar(state: state)
                .frame(height: 4)
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
