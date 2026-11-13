// MARK: - OBDPerformanceCard.swift
// 0–100 km/h Drag Timer & Stage 1 Virtual Dyno (268,9 PS / 395 Nm)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDPerformanceCard: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var timer = OBDPerformanceTimer.shared
    @ObservedObject private var dyno  = EA113DynoCalculator.shared

    public init(obd: OBDManager) {
        self.obd = obd
    }

    private var orangeColor: Color { Color(red: 1.0, green: 0.6, blue: 0.1) }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── 1. Virtual Dyno: Leistung & Drehmoment (Stage 1) ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Stage 1 Dyno (Prüfstand)", systemImage: "bolt.fill")
                                .font(.headline)
                                .foregroundStyle(orangeColor)
                            Spacer()
                            Text("Ziel: 268,9 PS / 395 Nm")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(.secondary)
                        }

                        // Live Werte Grid
                        HStack(spacing: 12) {
                            // Leistung
                            VStack(spacing: 4) {
                                Text("LEISTUNG")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text("\(dyno.livePS)")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundStyle(orangeColor)
                                Text("PS (Peak: \(dyno.peakPS))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                            // Drehmoment
                            VStack(spacing: 4) {
                                Text("DREHMOMENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text("\(dyno.liveNm)")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundStyle(.cyan)
                                Text("Nm (Peak: \(dyno.peakNm))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }

                        HStack {
                            Text("Berechnet live aus Luftmasse (MAF), Drehzahl & Ladedruck.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Peaks Reset") {
                                dyno.resetPeaks()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                        }
                    }
                }

                // ── 2. 0–100 km/h Drag Timer ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("0–100 km/h Drag Timer", systemImage: "stopwatch.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Spacer()
                            if timer.isDedicatedSpeedPollingRequired {
                                Text("⚡ HIGH-SPEED PRIO")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2), in: Capsule())
                            }
                        }

                        // Status Banner
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(timer.state.rawValue)
                                .font(.subheadline.bold())
                                .foregroundStyle(statusColor)
                            Spacer()
                            Text("\(timer.liveSpeed) km/h")
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(10)
                        .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        // Großes Zeitdisplay
                        VStack(spacing: 4) {
                            Text(timeDisplayString)
                                .font(.system(size: 52, weight: .black, design: .monospaced))
                                .foregroundStyle(timer.state == .completed ? .green : .white)
                            Text(timer.state == .running ? "ZEIT LÄUFT…" : (timer.state == .completed ? "0–100 GEMESSEN" : "BEREIT FÜR LAUNCH"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                        // Zwischenzeiten & Bestzeiten
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("0–60 km/h")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(timer.timeTo60.map { String(format: "%.2f s", $0) } ?? "--")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Letzter Lauf")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(timer.last0to100.map { String(format: "%.2f s", $0) } ?? "--")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bestzeit 🏆")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(timer.best0to100.map { String(format: "%.2f s", $0) } ?? "--")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.yellow)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Anleitung & Bedienung
                        HStack {
                            Text("Bleibe kurz bei 0 km/h stehen (schaltet automatisch 'Launch bereit' ein). Sobald du losfährst, stoppt die App die Zeit mit 100% Sensor-Priorität!")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Scharf") {
                                timer.manualArm()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var statusColor: Color {
        switch timer.state {
        case .disabled:  return .secondary
        case .idle:      return .secondary
        case .armed:     return .green
        case .running:   return .yellow
        case .completed: return .cyan
        case .aborted:   return .red
        }
    }

    private var timeDisplayString: String {
        switch timer.state {
        case .running:
            return String(format: "%.2f s", timer.currentElapsedTime)
        case .completed:
            return String(format: "%.2f s", timer.timeTo100 ?? timer.currentElapsedTime)
        default:
            if let last = timer.last0to100 {
                return String(format: "%.2f s", last)
            }
            return "0.00 s"
        }
    }
}
