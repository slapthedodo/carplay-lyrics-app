// MARK: - OBDDiagnosticWorkbenchView.swift
// Integriertes Diagnose-Labor & Steuergeräte-Analyse für CarLyrics
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDDiagnosticWorkbenchView: View {
    @ObservedObject var obd: OBDManager
    var isPresentedAsSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var activeSection: Int = 0
    @State private var manualCommand: String = ""
    @State private var showCopiedToast: Bool = false

    public init(obd: OBDManager, isPresentedAsSheet: Bool = false) {
        self.obd = obd
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OBDStatusBarHeader(obd: obd)

                Picker("Bereich", selection: $activeSection) {
                    Text("🚨 Fehler").tag(0)
                    Text("⚡ Öltemp").tag(1)
                    Text("📊 Sensoren").tag(2)
                    Text("💻 Terminal").tag(3)
                    Text("📡 BT").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

                Group {
                    switch activeSection {
                    case 0:
                        OBDDTCCard(obd: obd)
                    case 1:
                        OBDMethodProbeSection(obd: obd)
                    case 2:
                        OBDSensorMatrixSection(obd: obd)
                    case 3:
                        OBDTerminalSection(obd: obd, manualCommand: $manualCommand, showCopiedToast: $showCopiedToast)
                    case 4:
                        OBDBluetoothScannerSection(obd: obd)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("OBD-II Diagnose & Labor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        obd.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    Text("✔ Log in Zwischenablage kopiert!")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.9), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}
