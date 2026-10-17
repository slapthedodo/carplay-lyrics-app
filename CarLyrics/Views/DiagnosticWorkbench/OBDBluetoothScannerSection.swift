// MARK: - OBDBluetoothScannerSection.swift
// BLE-Gerätesuche & RSSI Signalstärke-Monitor
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDBluetoothScannerSection: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bluetooth LE Scanner")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Alle erkannten Bluetooth-Geräte in Reichweite.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        obd.startScan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Scan")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                if obd.discoveredDevices.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.cyan)
                        Text("Scanne nach Bluetooth-Geräten…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(30)
                } else {
                    ForEach(obd.discoveredDevices) { dev in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dev.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("UUID: \(dev.id.prefix(18))…  RSSI: \(dev.rssi) dBm")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Verbinden") {
                                obd.connectToDevice(id: dev.id)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.15), in: Capsule())
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
    }
}
