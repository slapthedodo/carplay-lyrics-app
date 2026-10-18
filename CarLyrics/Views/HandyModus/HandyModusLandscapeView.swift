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
        HStack(spacing: 12) {
            // ── LINKE SPALTE: Instrumente & Gauges (RPM, Boost, Öl, G-Force) ──
            VStack(spacing: 8) {
                // Haupt-Gauges nebeneinander
                HStack(alignment: .center, spacing: 6) {
                    // Öltemperatur
                    VStack(spacing: 2) {
                        OilTempRingView(tempC: obd.effectiveOilTemp, size: 90)
                        Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    // RPM Tacho (zentral im Cockpit)
                    VStack(spacing: 2) {
                        RPMTachometerView(rpm: obd.liveRPM, size: 120)
                        Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    // Ladedruck
                    VStack(spacing: 2) {
                        BoostArcView(
                            boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                            size: 90
                        )
                        Text(obd.liveMAP != nil ? "MAP" : "MAF BERECHN.")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )

                // Untere Leiste: G-Force Scope + Schnell-Stats
                HStack(spacing: 8) {
                    // Kompaktes G-Force Scope
                    GBallView(
                        x: motion.normalizedX,
                        y: motion.normalizedY,
                        currentG: motion.currentG,
                        maxG: motion.maxG
                    )
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(Color.black.opacity(0.4)))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("G-KRAFT")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                            Text(motion.currentGFormatted)
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))
                        }
                        HStack(spacing: 6) {
                            Text("PEAK")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(motion.peakGFormatted)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                        Button {
                            motion.resetPeak()
                        } label: {
                            Text("Reset")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }

                    Spacer()

                    // Quick-Stats Kacheln
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            quickStat(icon: "speedometer", label: "KM/H", val: "\(obd.liveSpeed)")
                            quickStat(icon: "thermometer.medium", label: "WASSER", val: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!)°" : "--")
                        }
                        HStack(spacing: 6) {
                            quickStat(icon: "bolt.fill", label: "VOLT", val: obd.batteryVoltage != nil ? String(format: "%.1f", obd.batteryVoltage!) : "--")
                            quickStat(icon: "flame.fill", label: "ABGAS", val: obd.estimatedExhaustTemp != nil ? "\(obd.estimatedExhaustTemp!)°" : "--")
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
            }
            .frame(maxWidth: .infinity)

            // ── RECHTE SPALTE: Lyrics Panel & Cockpit-Steuerung ──
            VStack(spacing: 8) {
                // Großes Lyrics-Panel
                HandyModusLyricsPanel(observer: observer)
                    .frame(maxHeight: .infinity)

                // Footer mit Reconnect & Nullpunkt
                HStack(spacing: 8) {
                    Button {
                        motion.calibrate()
                    } label: {
                        Label("G-Nullpunkt", systemImage: "scope")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(CockpitButtonStyle(color: Color(red: 0.68, green: 0.35, blue: 0.98)))

                    Spacer()

                    if obd.isEnabled && obd.connectionState != .connected {
                        Button {
                            obd.reconnect()
                        } label: {
                            Label("OBD Connect", systemImage: "cable.connector")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(CockpitButtonStyle(color: .green))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func quickStat(icon: String, label: String, val: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 0) {
                Text(val)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 6.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
