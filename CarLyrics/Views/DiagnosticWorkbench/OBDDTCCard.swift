// MARK: - OBDDTCCard.swift
// Fehlerspeicher-Diagnose & Löschen (OBDeleven-Funktionalität) für CarLyrics
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDDTCCard: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var scanner = OBDDTCScanner.shared
    @State private var showClearConfirmation: Bool = false

    public init(obd: OBDManager) {
        self.obd = obd
    }

    private var orangeColor: Color { Color(red: 1.0, green: 0.6, blue: 0.1) }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ── Header & Aktionen ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Fehlerspeicher (DTC)", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.yellow)
                            Spacer()
                            if scanner.isScanning || scanner.isClearing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            }
                        }

                        Text("Liest gespeicherte Fehler (Mode 03) und Vorlauffehler (Mode 07) direkt aus dem Bosch MED9.1 Motorsteuergerät aus.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(scanner.statusMessage)
                            .font(.caption.bold())
                            .foregroundStyle(scanner.storedCodes.isEmpty ? .green : .orange)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await scanner.startScan(obd: obd)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(scanner.isScanning ? "Scanne…" : "Fehler auslesen")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(CockpitButtonStyle(color: .cyan))
                            .disabled(obd.connectionState != .connected || scanner.isScanning || scanner.isClearing)

                            Button {
                                showClearConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text(scanner.isClearing ? "Lösche…" : "Löschen")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(CockpitButtonStyle(color: .red))
                            .disabled(obd.connectionState != .connected || scanner.isScanning || scanner.isClearing)
                        }

                        if obd.connectionState != .connected {
                            HStack {
                                Image(systemName: "wifi.slash")
                                    .font(.caption)
                                Text("OBD nicht verbunden – erst mit Dongle koppeln")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Gefundene Fehler ──
                if !scanner.storedCodes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Gefundene Fehlercodes (\(scanner.storedCodes.count))", systemImage: "list.clipboard.fill")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                Spacer()
                            }

                            ForEach(scanner.storedCodes) { dtc in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(dtc.code)
                                            .font(.system(.subheadline, design: .monospaced, weight: .black))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))

                                        Text(dtc.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                            .lineLimit(2)

                                        Spacer()

                                        if dtc.isPending {
                                            Text("Pending")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.orange)
                                                .padding(4)
                                                .background(Color.orange.opacity(0.2), in: Capsule())
                                        }
                                    }

                                    Text(dtc.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                } else if !scanner.isScanning && scanner.lastScanDate != nil {
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fehlerspeicher sauber!")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Text("Keine Fehler im Motorsteuergerät hinterlegt.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ── Info-Card ──
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Typische EA113 Schwachstellen", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Group {
                            DTCInfoRow(code: "P0299", desc: "SUV / Schubumluftventil Membran gerissen")
                            DTCInfoRow(code: "P2187", desc: "PCV / Kurbelgehäuseentlüftung undicht")
                            DTCInfoRow(code: "P0087", desc: "HD-Pumpe Becherstößel verschlissen")
                            DTCInfoRow(code: "P0300", desc: "Zündspulen / Zündkerzen Aussetzer")
                        }
                    }
                }
            }
            .padding()
        }
        .confirmationDialog("Fehlerspeicher wirklich löschen?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Fehler löschen & MKL zurücksetzen", role: .destructive) {
                Task {
                    await scanner.clearDTCs(obd: obd)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Sendet Mode 04 an das Motorsteuergerät. Dadurch wird der Fehlerspeicher gelöscht und die Motorkontrollleuchte (MKL) zurückgesetzt.")
        }
    }
}

private struct DTCInfoRow: View {
    let code: String
    let desc: String

    var body: some View {
        HStack {
            Text(code)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 55, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
