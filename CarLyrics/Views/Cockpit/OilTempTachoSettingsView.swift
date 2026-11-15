// MARK: - OilTempTachoSettingsView.swift
// Tacho Öltemperatur: Multi-Fallback OBD Auslese für VW Golf 5 GTI (Bosch MED9.1)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Probe Status Models
// ─────────────────────────────────────────────────────────────────────────────

public struct OilTempProbeStatus: Identifiable {
    public let id = UUID()
    public let methodName: String
    public let command: String
    public var status: OilTempProbeState
    public var rawResponse: String
    public var parsedValue: Int?

    public init(methodName: String, command: String, status: OilTempProbeState = .pending, rawResponse: String = "", parsedValue: Int? = nil) {
        self.methodName = methodName
        self.command = command
        self.status = status
        self.rawResponse = rawResponse
        self.parsedValue = parsedValue
    }
}

public enum OilTempProbeState {
    case pending, testing, success, failed, noData

    var label: String {
        switch self {
        case .pending:  return "Ausstehend"
        case .testing:  return "Teste…"
        case .success:  return "Erfolg"
        case .failed:   return "Fehler"
        case .noData:   return "Keine Daten"
        }
    }

    var color: Color {
        switch self {
        case .pending:  return .gray
        case .testing:  return .blue
        case .success:  return .green
        case .failed:   return .red
        case .noData:   return .orange
        }
    }

    var icon: String {
        switch self {
        case .pending:  return "circle"
        case .testing:  return "circle.dotted"
        case .success:  return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .noData:   return "exclamationmark.triangle.fill"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: OilTempTachoSettingsView
// ─────────────────────────────────────────────────────────────────────────────

public struct OilTempTachoSettingsView: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    private var orangeColor: Color { Color(red: 1.0, green: 0.6, blue: 0.1) }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Erklärung & Toggle ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Tacho Öltemperatur", systemImage: "thermometer.medium")
                            .font(.headline)
                            .foregroundStyle(orangeColor)

                        Text("Versucht die echte Öltemperatur direkt vom Steuergerät (Bosch MED9.1) zu lesen – mit \(OBDManager.oilTempProbeMethods.count) verschiedenen Methoden als Fallback. Viel besser als die errechnete Schätzung!")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Echte Öltemp aktivieren")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(obd.tachoOilTempEnabled ? "OBD-Auslese aktiv" : "Verwendet errechnete Schätzung")
                                    .font(.caption)
                                    .foregroundStyle(obd.tachoOilTempEnabled ? .green : .secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { obd.tachoOilTempEnabled },
                                set: { obd.tachoOilTempEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(orangeColor)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                        if let temp = obd.tachoOilTempValue {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Echte Öltemperatur: \(temp)°C")
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                    if !obd.tachoOilTempMethod.isEmpty {
                                        Text("Methode: \(obd.tachoOilTempMethod)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        } else if obd.tachoOilTempEnabled && !obd.isMeasuringTachoOilTemp {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.orange)
                                Text("Noch kein Wert – OBD verbinden und \"Jetzt messen\" drücken")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            Task {
                                await obd.startTachoOilTempProbe()
                            }
                        } label: {
                            HStack {
                                if obd.isMeasuringTachoOilTemp {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                    Text("Messe…")
                                        .fontWeight(.bold)
                                } else {
                                    Image(systemName: "thermometer.and.liquid.waves")
                                    Text("Jetzt messen (\(OBDManager.oilTempProbeMethods.count) Methoden testen)")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(CockpitButtonStyle(color: orangeColor))
                        .disabled(obd.connectionState != .connected || obd.isMeasuringTachoOilTemp)

                        if obd.connectionState != .connected {
                            HStack {
                                Image(systemName: "wifi.slash")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text("OBD nicht verbunden – erst mit ELM327 koppeln")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // ── Fallback Methoden Status ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Fallback-Methoden (\(OBDManager.oilTempProbeMethods.count) Versuche)", systemImage: "list.bullet.clipboard")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Jede Methode wird der Reihe nach ausprobiert. Die erste erfolgreiche wird dauerhaft verwendet. Inklusive KWP2000 Messwertblöcke (OBDeleven / VCDS Block 134) & Multidecoder = maximale Chance!")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if obd.tachoOilTempProbeStatus.isEmpty {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text("Noch kein Test durchgeführt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(obd.tachoOilTempProbeStatus) { probe in
                                ProbeStatusRow(probe: probe)
                            }
                        }
                    }
                }

                // ── Methoden Erklärung ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Was wird getestet?", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Group {
                            MethodInfoRow(num: 1, name: "VW TP 2.0 Tacho (0x17 + MWB 50) ★★★",
                                desc: "VW Gateway-Handshake via CAN 0x200! Liest Tacho-Geber G266.")
                            MethodInfoRow(num: 2, name: "VW TP 2.0 Motor (0x01 + MWB 134) ★★★",
                                desc: "VW Gateway-Handshake via CAN 0x200! Liest Motor-MWB 134.")
                            MethodInfoRow(num: 3, name: "Cluster UDS (0x714 + DID 202F) ★★★",
                                desc: "UDS-Direktabfrage Tacho (für weiße MFAs / Facelift).")
                            MethodInfoRow(num: 4, name: "OBD Standard PID 015C",
                                desc: "SAE-Standard.")
                            MethodInfoRow(num: 5, name: "KWP2000 MWB 134 + 1089 ★★★",
                                desc: "OBDeleven & VCDS Methode! Liest Block 134 (Geber G266 Öltemperatur).")
                            MethodInfoRow(num: 6, name: "KWP2000 MWB 134 direkt",
                                desc: "Block 134 ohne Session-Wechsel.")
                            MethodInfoRow(num: 4, name: "KWP2000 MWB 005 + 1089",
                                desc: "Block 005 Motorbetriebsdaten inkl. Öltemp.")
                            MethodInfoRow(num: 5, name: "KWP2000 MWB 005 direkt",
                                desc: "Block 005 Direktabfrage.")
                            MethodInfoRow(num: 6, name: "Cluster 0x760 + MWB 050",
                                desc: "Tacho KWP2000 Geber-Auslese.")
                            MethodInfoRow(num: 7, name: "VAG Mode22 7E0+1106 ★",
                                desc: "Torque Pro MED9.1 Top-Favorit (16-Bit Kelvin/0.1°C).")
                            MethodInfoRow(num: 8, name: "VAG Mode22 7E0+115C ★",
                                desc: "Häufigste VAG MED9.1 Öltemp-Adresse.")
                            MethodInfoRow(num: 9, name: "VAG Mode22 7E0+11BE",
                                desc: "Standard VAG UDS ReadDataByIdentifier.")
                            MethodInfoRow(num: 10, name: "VAG Mode22 7E0+1152",
                                desc: "Car Scanner VAG Profil Standard.")
                            MethodInfoRow(num: 11, name: "VAG Mode22 7E0+F43C",
                                desc: "Zweithäufigster VAG Öltemp-DID auf MED9.x.")
                            MethodInfoRow(num: 12, name: "VAG Mode22 1C1F",
                                desc: "PQ35 Instrument-Cluster-Kanal (kein Header).")
                            MethodInfoRow(num: 13, name: "VAG Mode22 7E0+1C1F",
                                desc: "1C1F mit explizitem ECU-Header 7E0.")
                            MethodInfoRow(num: 14, name: "Cluster 0x760+1C1F ★",
                                desc: "Standard VAG MK5 Instrument-Cluster Diagnose-Adresse!")
                            MethodInfoRow(num: 15, name: "Broadcast 7DF+015C",
                                desc: "Alle ECUs gleichzeitig antworten lassen.")
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wichtiger Hinweis", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)

                        Text("Motor muss LAUFEN damit der Sensor aktiv ist! Bosch MED9.1 auf dem EA113 (Golf 5 GTI) gibt PID 015C im Standard-OBD nicht immer frei – deshalb 18 Fallbacks mit automatischem 16-Bit/8-Bit Multidecoder. Methode 2 (1106), 3 (115C) und 14 (Cluster 0x760) sind die Top-Kandidaten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

private struct ProbeStatusRow: View {
    let probe: OilTempProbeStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: probe.status.icon)
                .foregroundStyle(probe.status.color)
                .font(.system(size: 16))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(probe.methodName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    if let val = probe.parsedValue {
                        Text("\(val)°C")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        Text(probe.status.label)
                            .font(.caption2)
                            .foregroundStyle(probe.status.color)
                    }
                }
                if !probe.rawResponse.isEmpty {
                    Text(probe.rawResponse)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("CMD: \(probe.command)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
}

private struct MethodInfoRow: View {
    let num: Int
    let name: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num)")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.white.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
