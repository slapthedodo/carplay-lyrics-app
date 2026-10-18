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
                VStack(spacing: 6) {
                    Text(phaseText(displayTemp))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)

                    if !obd.isEnabled || obd.connectionState != .connected {
                        Divider().overlay(Color.white.opacity(0.1))

                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("FAHRZEIT")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(warmup.elapsedFormatted)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }

                            Divider().frame(height: 20).overlay(Color.white.opacity(0.15))

                            VStack(spacing: 2) {
                                Text("NOCH CA.")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                let remMins = max(0, warmup.currentProfile.estimatedMinutesTo80 - Int(warmup.elapsedSeconds / 60))
                                Text(remMins > 0 ? "\(remMins) Min." : "Warm ✓")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(remMins == 0 ? .green : .orange)
                            }

                            Divider().frame(height: 20).overlay(Color.white.opacity(0.15))

                            VStack(spacing: 2) {
                                Text("PROFIL")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(warmup.currentProfile.seasonName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 2)

                        Button {
                            warmup.start(cold: true)
                        } label: {
                            Label("Kaltstart-Timer neu starten", systemImage: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(CockpitButtonStyle(color: .secondary))
                        .padding(.top, 4)
                    } else {
                        // OBD Live Datenübersicht
                        HStack(spacing: 16) {
                            if let coolant = obd.liveCoolantTemp {
                                Text("Kühlwasser: \(coolant)°C")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            if obd.liveRPM > 0 {
                                Text("Drehzahl: \(obd.liveRPM) U/min")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
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
