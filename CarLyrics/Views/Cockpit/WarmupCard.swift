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
                return obd.effectiveOilTemp ?? warmup.oilTempInt
            }
            return warmup.oilTempInt
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
                            if obd.liveOilTemp != nil {
                                Text("LIVE ÖL (OBD)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                            } else if obd.effectiveOilTemp != nil {
                                Text("LIVE ECU (EA113)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            } else {
                                Text("WARTE AUF ECU-DATEN…")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                        } else if obd.connectionState == .scanning {
                            Text("SUCHE ADAPTER…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else if obd.connectionState == .connecting || obd.connectionState == .initializing || obd.connectionState == .searchingECU {
                            Text("VERBINDE ECU…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text("EA113 SIMULATION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("2.0 TFSI SIMULATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
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
            } else if obd.connectionState == .connecting || obd.connectionState == .initializing || obd.connectionState == .searchingECU {
                return "OBD verbindet – Lese Steuergerät aus…"
            } else {
                return "OBD aktiviert – Warte auf Adapter & Daten…"
            }
        }
        if obd.isEnabled && obd.connectionState == .connected {
            if t < 60 { return "Kaltstart (ECU) – Max. 2.500 U/min, kein Ladedruck!" }
            if t < 80 { return "Öl wärmt auf (ECU) – Gemäßigt fahren" }
            return "Betriebstemperatur erreicht – Voller Ladedruck frei! 🏁"
        }
        if t < 60 { return "Kaltstart – Max. 2.500 U/min, kein Ladedruck!" }
        if t < 80 { return "Öl wärmt auf – Gemäßigt fahren" }
        return "90°C erreicht – Voller Ladedruck frei! 🏁"
    }
}
