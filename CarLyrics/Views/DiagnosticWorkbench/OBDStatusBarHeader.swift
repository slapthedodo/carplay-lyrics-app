// MARK: - OBDStatusBarHeader.swift
// Status-Kopfzeile mit Verbindungszustand, Voltmeter & Hauptschalter
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDStatusBarHeader: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(obd.connectionState.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(obd.detailedStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let v = obd.batteryVoltage {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f V", v))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(voltageBgColor(v), in: Capsule())
                    .foregroundStyle(.white)
                }

                Toggle("", isOn: $obd.isEnabled)
                    .labelsHidden()
                    .tint(.green)
                    .onChange(of: obd.isEnabled) { _, enabled in
                        if enabled { obd.enableOBD() } else { obd.disableOBD() }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemBackground))
        }
    }

    private var statusColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected: return .green
        case .connecting, .initializing, .searchingECU: return .orange
        default: return .red
        }
    }

    private func voltageBgColor(_ v: Double) -> Color {
        if v >= 13.2 { return .blue.opacity(0.8) }
        if v >= 11.8 { return .green.opacity(0.8) }
        return .orange.opacity(0.8)
    }
}
