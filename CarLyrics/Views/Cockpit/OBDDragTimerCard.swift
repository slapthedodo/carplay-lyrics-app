// MARK: - OBDDragTimerCard.swift
// 0–100 km/h Drag Timer mit automatischer Launch-Erkennung & High-Speed Prio
// Platziert im Setup / Settings Tab
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDDragTimerCard: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var timer = OBDPerformanceTimer.shared

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("0–100 km/h Drag Timer", systemImage: "stopwatch.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Spacer()
                            if timer.isDedicatedSpeedPollingRequired {
                                Text("⚡ 100% PRIO SPEED")
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
                                .font(.system(size: 54, weight: .black, design: .monospaced))
                                .foregroundStyle(timer.state == .completed ? .green : .white)
                            Text(timer.state == .running ? "ZEIT LÄUFT… (100% OBD PRIO)" : (timer.state == .completed ? "0–100 GEMESSEN" : "BEREIT FÜR LAUNCH"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
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
