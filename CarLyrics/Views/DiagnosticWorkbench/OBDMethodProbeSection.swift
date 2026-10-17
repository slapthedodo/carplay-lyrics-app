// MARK: - OBDMethodProbeSection.swift
// 7-Methoden Schnelltest & manuelle Protokollwahl
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDMethodProbeSection: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protokoll-Bruteforce & Schnelltest")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Testet nacheinander alle 7 VAG- und OBD-Protokolle mit Abfrage 0100.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if obd.isProbingProtocols {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.cyan)
                            Text(obd.detailedStatus)
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                            Spacer()
                            Button("Stoppen") {
                                obd.stopProtocolAutoProbe()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        }
                        .padding(.top, 4)
                    } else {
                        Button {
                            obd.runProtocolAutoProbe()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Protokoll-Schnelltest starten")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.black)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Protokoll manuell erzwingen:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(OBDProtocol.allCases) { proto in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proto.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(obd.selectedProtocol == proto ? .cyan : .white)
                                Text("Befehl: \(proto.elmCommand)\(proto.headerCommand != nil ? " + \(proto.headerCommand!)" : "")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if obd.selectedProtocol == proto {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cyan)
                            } else {
                                Button("Aktivieren") {
                                    obd.selectProtocol(proto)
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                if !obd.probeResults.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Testergebnisse (\(obd.probeResults.count) Methoden):")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ForEach(obd.probeResults) { res in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(statusColor(for: res.status))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(res.proto.rawValue)
                                            .font(.system(size: 13, weight: .bold))
                                        Spacer()
                                        if res.responseTimeMs > 0 {
                                            Text("\(res.responseTimeMs) ms")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(res.note.isEmpty ? res.rawResponse : res.note)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(statusColor(for: res.status))

                                    if !res.rawResponse.isEmpty && res.status == .success {
                                        Text("Antwort: \(res.rawResponse)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.green)
                                    }
                                }

                                if res.status == .success && obd.selectedProtocol != res.proto {
                                    Button("Nutzen") {
                                        obd.selectProtocol(res.proto)
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding(14)
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
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
