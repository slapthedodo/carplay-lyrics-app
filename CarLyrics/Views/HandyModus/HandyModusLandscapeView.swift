// MARK: - HandyModusLandscapeView.swift
// Widescreen Racing Cockpit für den Querformat-Einsatz im Handy-Halter
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLandscapeView: View {
    @ObservedObject public var observer : MusicObserver
    @ObservedObject public var obd      : OBDManager
    @ObservedObject public var motion   : MotionManager
    @ObservedObject public var warmup   : WarmupManager

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
            let w = geo.size.width
            let h = geo.size.height
            let leftW  = w * 0.45
            let rightW = w * 0.55
            let topBarH: CGFloat = 26

            VStack(spacing: 0) {
                // ── Top Bar ───────────────────────────────────────────────────
                topBar
                    .frame(width: w, height: topBarH)
                    .padding(.horizontal, 12)

                // ── Main Two-Column Area ──────────────────────────────────────
                HStack(alignment: .top, spacing: 0) {
                    leftPanel(width: leftW, height: h - topBarH)
                        .frame(width: leftW, height: h - topBarH)

                    rightPanel(width: rightW, height: h - topBarH)
                        .frame(width: rightW, height: h - topBarH)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .overlay(
            Group {
                if obd.isColdOverloaded {
                    ColdEngineOverloadFlashOverlay(title: obd.coldOverloadMessage, detail: obd.coldOverloadDetail)
                }
            }
        )
    }

    // ── Top Bar ───────────────────────────────────────────────────────────────

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
                        .font(.system(size: 8.5))
                        .foregroundStyle(.cyan)
                    Text("\(observer.currentTrackTitle) • \(observer.currentArtist)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
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
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
    }

    // ── Left Panel: Gauges + G-Ball ───────────────────────────────────────────

    private func leftPanel(width: CGFloat, height: CGFloat) -> some View {
        let rpmSize   = height * 0.42
        let smallSize = height * 0.30
        let gBallSize = height * 0.22

        return VStack(spacing: height * 0.04) {
            // Gauge row
            HStack(alignment: .center, spacing: width * 0.04) {
                // Öltemperatur
                VStack(spacing: 2) {
                    OilTempRingView(tempC: obd.effectiveOilTemp, size: smallSize)
                    Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                        .font(.system(size: 6.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }

                // RPM
                VStack(spacing: 2) {
                    RPMTachometerView(rpm: obd.liveRPM, size: rpmSize)
                    Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }

                // Boost
                VStack(spacing: 2) {
                    BoostArcView(
                        boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                        size: smallSize
                    )
                    Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                        .font(.system(size: 6.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.vertical, height * 0.025)
            .padding(.horizontal, width * 0.04)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1))
            )

            // G-Ball row
            HStack(spacing: 10) {
                GBallView(
                    x: motion.normalizedX,
                    y: motion.normalizedY,
                    currentG: motion.currentG,
                    maxG: motion.maxG
                )
                .frame(width: gBallSize, height: gBallSize)
                .background(Circle().fill(Color.black.opacity(0.4)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("G")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                        Text(motion.currentGFormatted)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))
                    }
                    HStack(spacing: 4) {
                        Text("PK")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(motion.peakGFormatted)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 4) {
                        Button { motion.calibrate() } label: {
                            Text(motion.isCalibrating ? "1s…" : "Nullpunkt")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color(red: 0.68, green: 0.35, blue: 0.98).opacity(0.12), in: Capsule())
                        }
                        .disabled(motion.isCalibrating)

                        Button { motion.resetPeak() } label: {
                            Text("Reset")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // ── Right Panel: Lyrics + Quick Stats ────────────────────────────────────

    private func rightPanel(width: CGFloat, height: CGFloat) -> some View {
        let lyricsH  = height * 0.65
        let statsH   = height * 0.35

        return VStack(spacing: 0) {
            // Lyrics panel — top 65%
            HandyModusLyricsPanel(observer: observer, isCompact: true)
                .frame(maxWidth: .infinity)
                .frame(height: lyricsH)

            // Quick stats grid + controls — bottom 35%
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    quickStat(icon: "speedometer",        label: "KM/H",   val: "\(obd.liveSpeed)")
                    quickStat(icon: "thermometer.medium", label: "WASSER", val: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!)°" : "--")
                    quickStat(icon: "bolt.fill",          label: "VOLT",   val: obd.batteryVoltage != nil ? String(format: "%.1f", obd.batteryVoltage!) : "--")
                    quickStat(icon: "flame.fill",         label: "ABGAS",  val: obd.estimatedExhaustTemp != nil ? "\(obd.estimatedExhaustTemp!)°" : "--")
                }

                if obd.isEnabled && obd.connectionState != .connected {
                    HStack {
                        Spacer()
                        Button { obd.reconnect() } label: {
                            Label("OBD Connect", systemImage: "cable.connector")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .buttonStyle(CockpitButtonStyle(color: .green))
                        Spacer()
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .frame(height: statsH)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // ── Helper Views ──────────────────────────────────────────────────────────

    private func quickStat(icon: String, label: String, val: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 0) {
                Text(val)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func connectionPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
    }

    private var obdLabel: String {
        guard obd.isEnabled else { return "OBD AUS" }
        switch obd.connectionState {
        case .connected:   return "OBD LIVE"
        case .scanning:    return "SUCHE…"
        case .connecting:  return "VERBINDET…"
        default:           return "OBD GETRENNT"
        }
    }

    private var obdPillColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected:                              return .green
        case .scanning, .connecting, .initializing:  return .orange
        default:                                      return .red
        }
    }

    private func gColor(_ g: Double, maxG: Double) -> Color {
        let ratio = maxG > 0 ? g / maxG : 0
        switch ratio {
        case ..<0.5: return .green
        case 0.5..<0.75: return .yellow
        default: return .red
        }
    }
}
