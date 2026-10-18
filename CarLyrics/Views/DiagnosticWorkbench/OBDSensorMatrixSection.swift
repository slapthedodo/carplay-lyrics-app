// MARK: - OBDSensorMatrixSection.swift
// Live-Sensor Kacheln & Steuergeräte-PID Matrix für Bosch MED9.1
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDSensorMatrixSection: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Zündungs- und Bordnetzkarte
                HStack(spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .font(.title)
                        .foregroundStyle(ignitionColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bordnetz & Zündungs-Status:")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(ignitionDescription)
                            .font(.subheadline.bold())
                            .foregroundStyle(ignitionColor)
                    }
                    Spacer()
                    if let v = obd.batteryVoltage {
                        Text(String(format: "%.2f V", v))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Sensor Matrix
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SensorBox(title: "Kühlmittel (01 05)",
                              value: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!) °C" : "—",
                              status: obd.liveCoolantTemp != nil ? .green : .secondary)

                    SensorBox(title: "Öltemperatur (01 5C)",
                              value: obd.liveOilTemp != nil ? "\(obd.liveOilTemp!) °C" : (obd.effectiveOilTemp != nil ? "\(obd.effectiveOilTemp!) °C" : "—"),
                              status: (obd.liveOilTemp != nil || obd.effectiveOilTemp != nil) ? .green : .secondary,
                              badge: obd.liveOilTemp != nil ? "PID 015C" : (obd.effectiveOilTemp != nil ? "EA113 Thermik" : "Warte auf ECU"))

                    SensorBox(title: "Ladedruck Relativ",
                              value: obd.liveBoostBar != nil ? String(format: "%.2f bar", obd.liveBoostBar!) : "—",
                              status: obd.liveBoostBar != nil ? .cyan : .secondary,
                              badge: !obd.hasMAPPID && obd.liveBoostBar != nil ? "EA113 MAF" : nil)

                    SensorBox(title: "Saugrohr MAP (01 0B)",
                              value: obd.liveMAP != nil ? "\(obd.liveMAP!) kPa" : "—",
                              status: obd.liveMAP != nil ? .white : .secondary,
                              badge: !obd.hasMAPPID && obd.liveMAP != nil ? "Berechnet" : nil)

                    SensorBox(title: "Drehzahl (01 0C)",
                              value: "\(obd.liveRPM) U/min",
                              status: obd.liveRPM > 0 ? .green : .secondary)

                    SensorBox(title: "Luftmasse MAF (01 10)",
                              value: obd.liveMAF != nil ? String(format: "%.1f g/s", obd.liveMAF!) : "—",
                              status: obd.liveMAF != nil ? .cyan : .secondary)

                    SensorBox(title: "Ansaugluft IAT (01 0F)",
                              value: obd.liveIAT != nil ? "\(obd.liveIAT!) °C" : "—",
                              status: obd.liveIAT != nil ? .cyan : .secondary)

                    SensorBox(title: "Motorlast (01 04)",
                              value: obd.liveEngineLoad != nil ? "\(obd.liveEngineLoad!) %" : "—",
                              status: obd.liveEngineLoad != nil ? .orange : .secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unterstützte Steuergeräte-PIDs (Bosch MED9.1):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if obd.supportedPIDs.isEmpty {
                        Text("Noch keine PID-Quittung empfangen (Befehl 0100 senden).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 6) {
                            ForEach(Array(obd.supportedPIDs).sorted(), id: \.self) { pid in
                                Text(pidName(for: pid))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.cyan.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }

                    Text("ℹ Hinweis: PID 01 5C (Öltemperatur) wird von Bosch MED9.1 im Standard-OBD nicht geliefert. Die App nutzt dafür das präzise EA113 Modell.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
    }

    private var ignitionColor: Color {
        guard let v = obd.batteryVoltage else { return .secondary }
        if v >= 13.2 { return .blue }
        if v >= 11.8 { return .green }
        return .orange
    }

    private var ignitionDescription: String {
        guard let v = obd.batteryVoltage else { return "Zündung wird geprüft…" }
        if v >= 13.2 { return "Motor läuft & Lichtmaschine lädt" }
        if v >= 11.8 { return "Zündung Stufe 2 aktiv (Steuergerät ansprechbar)" }
        return "⚠️ Zündung evtl. AUS (Stufe 2 einschalten!)"
    }

    private func pidName(for pid: String) -> String {
        switch pid {
        case "0104": return "0104 (Last)"
        case "0105": return "0105 (Kühlmittel)"
        case "010B": return "010B (MAP)"
        case "010C": return "010C (Drehzahl)"
        case "010D": return "010D (Speed)"
        case "010F": return "010F (Ansaugluft)"
        case "0110": return "0110 (Luftmasse)"
        case "0111": return "0111 (Drosselkl.)"
        case "0133": return "0133 (Baro)"
        default:     return pid
        }
    }
}

public struct SensorBox: View {
    let title: String
    let value: String
    let status: Color
    var badge: String? = nil

    public init(title: String, value: String, status: Color, badge: String? = nil) {
        self.title = title
        self.value = value
        self.status = status
        self.badge = badge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(status)
                }
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(status)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
