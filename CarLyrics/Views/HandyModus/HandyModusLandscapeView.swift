// MARK: - HandyModusLandscapeView.swift
// Widescreen Racing Cockpit für den Querformat-Einsatz im Handy-Halter
// Inspiriert vom Hochkantformat: Gauges, G-Kräfte, Lyrics & 8-Tile Stats Matrix
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLandscapeView: View {
    @ObservedObject public var observer : MusicObserver
    @ObservedObject public var obd      : OBDManager
    @ObservedObject public var motion   : MotionManager
    @ObservedObject public var warmup   : WarmupManager

    internal let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public init(observer: MusicObserver,
                obd:      OBDManager,
                motion:   MotionManager,
                warmup:   WarmupManager) {
        self.observer = observer
        self.obd      = obd
        self.motion   = motion
        self.warmup   = warmup
    }

    public var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let leadPad = max(insets.leading, 12)
            let trailPad = max(insets.trailing, 12)
            let bottomPad = max(insets.bottom, 6)
            let topPad = max(insets.top, 4)

            let usableW = geo.size.width - leadPad - trailPad
            let usableH = geo.size.height - topPad - bottomPad

            let topBarH: CGFloat = 24
            let vSpacing: CGFloat = 6
            let hSpacing: CGFloat = 10
            let availableH = max(260, usableH - topBarH - vSpacing)

            let leftW = (usableW - hSpacing) * 0.48
            let rightW = (usableW - hSpacing) * 0.52

            let gaugesCardH = availableH * 0.54
            let gForceCardH = availableH * 0.46 - vSpacing
            let lyricsCardH = availableH * 0.58
            let statsCardH  = availableH * 0.42 - vSpacing

            VStack(spacing: vSpacing) {
                // ── Top Bar (CarPlay & OBD Status) ───────────────────────────
                topBar
                    .frame(width: usableW, height: topBarH)

                // ── Two-Column Cockpit Layout ─────────────────────────────────
                HStack(alignment: .top, spacing: hSpacing) {
                    // Linke Spalte: Gauges (oben) + G-Kräfte (unten)
                    VStack(spacing: vSpacing) {
                        landscapeGaugesCard(width: leftW, height: gaugesCardH)
                        landscapeGForceCard(width: leftW, height: gForceCardH)
                    }
                    .frame(width: leftW, height: availableH)

                    // Rechte Spalte: Lyrics (oben) + Stats Grid (unten)
                    VStack(spacing: vSpacing) {
                        landscapeLyricsCard(width: rightW, height: lyricsCardH)
                        landscapeStatsMatrix(width: rightW, height: statsCardH)
                    }
                    .frame(width: rightW, height: availableH)
                }
                .frame(width: usableW, height: availableH)
            }
            .padding(.leading, leadPad)
            .padding(.trailing, trailPad)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(
            Group {
                if obd.isColdOverloaded {
                    ColdEngineOverloadFlashOverlay(title: obd.coldOverloadMessage, detail: obd.coldOverloadDetail)
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 1. Top Status Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var topBar: some View {
        HStack(spacing: 8) {
            connectionPill(label: obdLabel, color: obdPillColor, icon: "cable.connector")

            if !obd.isEnabled {
                connectionPill(label: "SIMULATION", color: .cyan, icon: "waveform")
            }

            Spacer()

            if !observer.currentTrackTitle.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8))
                        .foregroundStyle(.cyan)
                    Text("\(observer.currentTrackTitle) • \(observer.currentArtist)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.yellow)
                Text("Kein Standby")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.85))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 2. Left Column: Main Gauges Card (Öl + RPM + Boost)
    // ─────────────────────────────────────────────────────────────────────────

    private func landscapeGaugesCard(width: CGFloat, height: CGFloat) -> some View {
        let rpmSize   = min(118, height * 0.70)
        let ringSize  = min(86, height * 0.54)

        return HStack(alignment: .center, spacing: 0) {
            // Öltemperatur links
            VStack(spacing: 2) {
                OilTempRingView(tempC: obd.effectiveOilTemp, size: ringSize)
                Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)

            // RPM Tacho Mitte (Hero)
            VStack(spacing: 2) {
                RPMTachometerView(rpm: obd.liveRPM, size: rpmSize)
                Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)

            // Ladedruck rechts
            VStack(spacing: 2) {
                BoostArcView(
                    boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                    size: ringSize
                )
                Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 3. Left Column: G-Kräfte Scope Card (GBall + Badge + Readouts)
    // ─────────────────────────────────────────────────────────────────────────

    private func landscapeGForceCard(width: CGFloat, height: CGFloat) -> some View {
        let gBallSize = min(72, height * 0.56)
        let badgeSize = min(66, height * 0.52)

        return VStack(spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(purple)
                Text("G-KRÄFTE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(purple.opacity(0.85))

                Spacer()

                // Kalibrieren Button (1s Mittelwert)
                Button {
                    motion.calibrate()
                } label: {
                    if motion.isCalibrating {
                        HStack(spacing: 2.5) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(purple)
                            Text("1s…")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(purple)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(purple.opacity(0.2), in: Capsule())
                    } else {
                        HStack(spacing: 2.5) {
                            Image(systemName: "scope")
                            Text("Nullpunkt")
                        }
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(purple.opacity(0.95))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(purple.opacity(0.14), in: Capsule())
                    }
                }
                .disabled(motion.isCalibrating)

                // Peak Reset
                Button {
                    motion.resetPeak()
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Peak")
                    }
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }

            // Scope & Readouts Row
            HStack(alignment: .center, spacing: 8) {
                // GBall View
                GBallView(
                    x: motion.normalizedX,
                    y: motion.normalizedY,
                    currentG: motion.currentG,
                    maxG: motion.maxG
                )
                .frame(width: gBallSize, height: gBallSize)
                .background(Circle().fill(Color.black.opacity(0.45)))

                // 2x2 Numeric Readouts
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        LandscapeGValueItem(label: "AKTUELL", val: motion.currentGFormatted, color: gColor(motion.currentG, maxG: motion.maxG))
                        LandscapeGValueItem(label: "PEAK", val: motion.peakGFormatted, color: .orange)
                    }
                    HStack(spacing: 6) {
                        LandscapeGValueItem(label: "LATERAL", val: String(format: "%.2fG", abs(motion.gX)), color: purple.opacity(0.85))
                        LandscapeGValueItem(label: "LÄNGS", val: String(format: "%.2fG", abs(motion.gY)), color: purple.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity)

                // G-Badge Gauge
                GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: badgeSize)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(purple.opacity(0.22), lineWidth: 1)
                )
        )
    }
}
