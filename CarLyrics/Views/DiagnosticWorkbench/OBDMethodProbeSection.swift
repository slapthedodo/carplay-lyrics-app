// MARK: - OBDMethodProbeSection.swift
// 7-Methoden Schnelltest & manuelle Protokollwahl
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDMethodProbeSection: View {
    @ObservedObject var obd: OBDManager
    @State private var showAdvancedProtocols: Bool = false

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ─────────────────────────────────────────────────────────────
                // 1-Klick Auto-Diagnose Hero Card (Testknopf für alles)
                // ─────────────────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("1-Klick Auto-Diagnose")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            Text("Prüft Bluetooth, Adapter-Hardware, Bosch MED9.1 & Live-Sensoren vollautomatisch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if obd.isAutoDiagnosing {
                        Button {
                            obd.stopAutoDiagnosis()
                        } label: {
                            HStack {
                                ProgressView()
                                    .tint(.black)
                                Text("Diagnose läuft… (Tippen zum Stoppen)")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                        }
                    } else {
                        Button {
                            obd.runFullAutoDiagnosis()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("🚀 Jetzt alles automatisch testen & verbinden")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                            .shadow(color: .cyan.opacity(0.35), radius: 8, y: 3)
                        }
                    }

                    // Live Schritt-für-Schritt Diagnoseanzeige
                    if !obd.diagnosisSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(obd.diagnosisSteps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    stepIcon(for: step.status)
                                        .frame(width: 20, height: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text(step.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(stepDetailColor(for: step.status))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Diagnose-Zusammenfassung & Hilfestellung
                    if let summary = obd.diagnosisSummary {
                        let isSuccess = summary.contains("✅")
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(isSuccess ? .green : .orange)
                                Text(summary)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSuccess ? .green : .orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !isSuccess {
                                // Erneut versuchen Button
                                Button {
                                    obd.runFullAutoDiagnosis()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Erneut versuchen")
                                            .fontWeight(.bold)
                                    }
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.black)
                                }

                                // BLE Debug-Info wenn vorhanden
                                if let debug = obd.diagnosisBLEDebug {
                                    DisclosureGroup("🔍 Technische Details (fürs Debugging)") {
                                        Text(debug)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 4)
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .accentColor(.secondary)
                                }

                                // 7-Methoden Test als Fallback CTA
                                Button {
                                    showAdvancedProtocols = true
                                    obd.runProtocolAutoProbe()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bolt.horizontal.circle")
                                        Text("Fallback: 7-Methoden Test starten")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((isSuccess ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                // ─────────────────────────────────────────────────────────────
                // Erweiterte Experten-Optionen (Standardmäßig eingeklappt)
                // ─────────────────────────────────────────────────────────────
                DisclosureGroup("Erweiterte Protokolle & 7-Methoden Test", isExpanded: $showAdvancedProtocols) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nur nötig, wenn die 1-Klick Auto-Diagnose fehlschlägt.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            obd.runProtocolAutoProbe()
                        } label: {
                            HStack {
                                Image(systemName: "bolt.horizontal.circle")
                                Text(obd.isProbingProtocols ? "Testet (\(obd.detailedStatus))…" : "7-Methoden Schnelltest ausführen")
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.cyan)
                        }

                        if !obd.probeResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Testergebnisse (\(obd.probeResults.count) Methoden):")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if obd.isProbingProtocols {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.cyan)
                                    }
                                }

                                ForEach(obd.probeResults) { res in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Circle()
                                                .fill(statusColor(for: res.status))
                                                .frame(width: 8, height: 8)
                                            Text(res.proto.rawValue)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if res.responseTimeMs > 0 {
                                                Text("\(res.responseTimeMs) ms")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                            if res.status == .success && obd.selectedProtocol != res.proto {
                                                Button("Aktivieren") {
                                                    obd.selectProtocol(res.proto)
                                                }
                                                .font(.caption2.bold())
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                            }
                                        }

                                        Text(res.note.isEmpty ? (res.rawResponse.isEmpty ? "Warte auf Test…" : res.rawResponse) : res.note)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(statusColor(for: res.status))
                                            .padding(.leading, 12)
                                    }
                                    .padding(.vertical, 3)
                                    Divider()
                                }
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Divider()

                        ForEach(OBDProtocol.allCases) { proto in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proto.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(obd.selectedProtocol == proto ? .cyan : .white)
                                    Text("Befehl: \(proto.elmCommand)\(proto.headerCommand != nil ? " + \(proto.headerCommand!)" : "")")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if obd.selectedProtocol == proto {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.cyan)
                                } else {
                                    Button("Wählen") {
                                        obd.selectProtocol(proto)
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .accentColor(.cyan)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func stepIcon(for status: OBDDiagnosisStep.StepStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.8)
                .tint(.cyan)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .warning:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func stepDetailColor(for status: OBDDiagnosisStep.StepStatus) -> Color {
        switch status {
        case .waiting: return .secondary
        case .inProgress: return .cyan
        case .success: return .green.opacity(0.85)
        case .failed: return .red.opacity(0.9)
        case .warning: return .orange
        }
    }

    private func statusColor(for s: ProtocolProbeResult.ProbeStatus) -> Color {
        switch s {
        case .pending: return .secondary
        case .testing: return .orange
        case .success: return .green
        case .failed:  return .red
        case .noData:  return .yellow
        }
    }
}
