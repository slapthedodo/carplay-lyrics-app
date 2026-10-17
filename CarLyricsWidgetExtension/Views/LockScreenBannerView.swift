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
