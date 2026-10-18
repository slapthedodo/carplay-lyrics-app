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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {

                // ── Top Bar: Status, Musik-Info & Standby-Pill ────────────────
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
                        .padding(.vertical, 3)
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
                    .padding(.vertical, 3.5)
                    .background(Color.yellow.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 4)

                // ── Haupt-Bereich: 2 Spalten Cockpit ──────────────────────────
                HStack(alignment: .top, spacing: 10) {

                    // ── Linke Spalte: Instrumente & Telemetrie ─────────────────
                    VStack(spacing: 8) {
                        // 3er Rundinstrumente
                        HStack(alignment: .center, spacing: 6) {
                            // Öltemperatur
                            VStack(spacing: 2) {
                                OilTempRingView(tempC: obd.effectiveOilTemp, size: 76)
                                Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }

                            // RPM Tachometer zentral
                            VStack(spacing: 2) {
                                RPMTachometerView(rpm: obd.liveRPM, size: 102)
                                Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                                    .font(.system(size: 7, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }

                            // Ladedruck
                            VStack(spacing: 2) {
                                BoostArcView(
                                    boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                                    size: 76
                                )
                                Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        )

                        // G-Kraft + 4 Stats Kacheln
                        HStack(spacing: 8) {
                            // Kompaktes GBall Scope
                            GBallView(
                                x: motion.normalizedX,
                                y: motion.normalizedY,
                                currentG: motion.currentG,
                                maxG: motion.maxG
                            )
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(Color.black.opacity(0.4)))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("G")
                                        .font(.system(size: 8, weight: .black, design: .rounded))
                                        .foregroundStyle(Color(red: 0.68, green: 0.35, blue: 0.98))
                                    Text(motion.currentGFormatted)
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))
                                }
                                HStack(spacing: 4) {
                                    Text("PK")
                                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Text(motion.peakGFormatted)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                }
                                Button {
                                    motion.resetPeak()
                                } label: {
                                    Text("Reset")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                }
                            }

                            Spacer()

                            // 4 Schnelle Telemetrie-Werte
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    quickStat(icon: "speedometer", label: "KM/H", val: "\(obd.liveSpeed)")
                                    quickStat(icon: "thermometer.medium", label: "WASSER", val: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!)°" : "--")
                                }
                                HStack(spacing: 4) {
                                    quickStat(icon: "bolt.fill", label: "VOLT", val: obd.batteryVoltage != nil ? String(format: "%.1f", obd.batteryVoltage!) : "--")
                                    quickStat(icon: "flame.fill", label: "ABGAS", val: obd.estimatedExhaustTemp != nil ? "\(obd.estimatedExhaustTemp!)°" : "--")
                                }
                            }
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        )
                    }
                    .frame(maxWidth: .infinity)

                    // ── Rechte Spalte: Kompaktes Lyrics-Panel & Controls ──────
                    VStack(spacing: 6) {
                        HandyModusLyricsPanel(observer: observer, isCompact: true)

                        HStack(spacing: 8) {
                            Button {
                                motion.calibrate()
                            } label: {
                                Label("G-Nullpunkt", systemImage: "scope")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .buttonStyle(CockpitButtonStyle(color: Color(red: 0.68, green: 0.35, blue: 0.98)))

                            Spacer()

                            if obd.isEnabled && obd.connectionState != .connected {
                                Button {
                                    obd.reconnect()
                                } label: {
                                    Label("OBD Connect", systemImage: "cable.connector")
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .buttonStyle(CockpitButtonStyle(color: .green))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
        }
    }

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
            Image(systemName: icon).font(.system(size: 7.5, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 7.5, weight: .black, design: .rounded)).foregroundStyle(color)
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
        case .connected:   return .green
        case .scanning, .connecting, .initializing: return .orange
        default:           return .red
        }
    }
}
