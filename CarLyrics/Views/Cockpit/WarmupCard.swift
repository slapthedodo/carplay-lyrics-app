// MARK: - WarmupCard.swift
// Motor-Temperatur Anzeige (OBD Live vs. EA113 Thermik-Modell)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct WarmupCard: View {
    @ObservedObject var warmup : WarmupManager
    @ObservedObject var obd    : OBDManager

    public init(warmup: WarmupManager, obd: OBDManager) {
        self.warmup = warmup
        self.obd = obd
    }

    public var displayTemp: Int? {
        if obd.isEnabled {
            if obd.connectionState == .connected {
                return obd.liveOilTemp ?? obd.liveCoolantTemp.map { max(20, $0 - 8) }
            }
            return nil
        }
        return warmup.oilTempInt
    }

    public var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Label("Motor-Temperatur", systemImage: "thermometer.medium")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if obd.isEnabled {
                        if obd.connectionState == .connected {
                            Text("LIVE OBD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        } else if obd.connectionState == .scanning {
                            Text("SUCHE ADAPTER…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else if obd.connectionState == .connecting || obd.connectionState == .initializing {
                            Text("VERBINDE…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text("OBD GETRENNT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("2.0 TFSI SIMULATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                // Gauge (0 bis 110 °C)
                Gauge(value: Double(max(0, displayTemp ?? 0)), in: 0...110) {
                    Text("Temperatur")
                } currentValueLabel: {
                    Text(displayTemp != nil ? "\(displayTemp!)°C" : "-- °C")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)
                } minimumValueLabel: {
                    Text("0°").font(.caption2)
                } maximumValueLabel: {
                    Text("110°").font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(displayTemp != nil ? Gradient(colors: [.blue, .orange, .green]) : Gradient(colors: [.secondary.opacity(0.3)]))
                .frame(width: 120, height: 120)

                // Phasenhinweis & Saison-Modell
                VStack(spacing: 4) {
                    Text(phaseText(displayTemp))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)

                    if !obd.isEnabled || obd.connectionState != .connected {
                        Text("Safety-Modell: \(warmup.currentProfile.seasonName) • ca. \(warmup.currentProfile.estimatedMinutesTo80) Min. bis 80°C")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tempColor(_ t: Int) -> Color {
        if t < 60 { return .blue }
        if t < 80 { return .orange }
        return .green
    }

    private func phaseText(_ t: Int?) -> String {
        guard let t else {
            if obd.connectionState == .scanning {
                return "OBD aktiviert – Suche nach Bluetooth-Adapter…"
            } else if obd.connectionState == .connecting || obd.connectionState == .initializing {
                return "OBD verbindet – Lese Steuergerät aus…"
            } else {
                return "OBD aktiviert – Warte auf Adapter & Daten…"
            }
        }
        if t < 60 { return "Kaltstart – Max. 2.500 U/min, kein Ladedruck!" }
        if t < 80 { return "Öl wärmt auf – Gemäßigt fahren" }
        return "90°C erreicht – Voller Ladedruck frei! 🏁"
    }
}
