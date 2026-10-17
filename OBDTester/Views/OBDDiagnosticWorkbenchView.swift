// MARK: - OBDDiagnosticWorkbenchView.swift (OBD Tester Standalone Edition)
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
                    Text("⚡ Methoden").tag(0)
                    Text("📊 Sensoren").tag(1)
                    Text("💻 Terminal").tag(2)
                    Text("📡 BT-Geräte").tag(3)
                    Text("📖 Ratgeber").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

                Group {
                    switch activeSection {
                    case 0:
                        OBDMethodProbeSection(obd: obd)
                    case 1:
                        OBDSensorMatrixSection(obd: obd)
                    case 2:
                        OBDTerminalSection(obd: obd, manualCommand: $manualCommand, showCopiedToast: $showCopiedToast)
                    case 3:
                        OBDBluetoothScannerSection(obd: obd)
                    case 4:
                        OBDVAGGuideSection()
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Subviews
// ─────────────────────────────────────────────────────────────────────────────

struct OBDStatusBarHeader: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
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

struct OBDMethodProbeSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
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

    private func statusColor(for status: ProtocolProbeResult.ProbeStatus) -> Color {
        switch status {
        case .success: return .green
        case .testing: return .yellow
        case .failed:  return .red
        case .noData:  return .orange
        case .timeout: return .secondary
        case .pending: return .gray.opacity(0.5)
        }
    }
}

struct OBDSensorMatrixSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "car.side.fill")
                        .font(.title2)
                        .foregroundStyle(ignitionColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bordspannung / Zündungs-Status")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(obd.batteryVoltage != nil ? String(format: "%.1f V", obd.batteryVoltage!) : "Nicht ausgelesen")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(ignitionColor)
                        Text(ignitionDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SensorBox(title: "Kühlmittel (01 05)",
                              value: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!) °C" : "—",
                              status: obd.liveCoolantTemp != nil ? .green : .secondary)

                    SensorBox(title: "Öltemperatur (01 5C)",
                              value: obd.liveOilTemp != nil ? "\(obd.liveOilTemp!) °C" : "Modell",
                              status: obd.liveOilTemp != nil ? .green : .cyan,
                              badge: obd.liveOilTemp != nil ? "PID 015C" : "EA113 Sim")

                    SensorBox(title: "Ladedruck Relativ",
                              value: obd.liveBoostBar != nil ? String(format: "%.2f bar", obd.liveBoostBar!) : "—",
                              status: obd.liveBoostBar != nil ? .cyan : .secondary)

                    SensorBox(title: "Saugrohr MAP (01 0B)",
                              value: obd.liveMAP != nil ? "\(obd.liveMAP!) kPa" : "—",
                              status: obd.liveMAP != nil ? .white : .secondary)

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

struct SensorBox: View {
    let title: String
    let value: String
    let status: Color
    var badge: String? = nil

    var body: some View {
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

struct OBDTerminalSection: View {
    @ObservedObject var obd: OBDManager
    @Binding var manualCommand: String
    @Binding var showCopiedToast: Bool

    private let quickCommands = [
        "ATZ", "ATI", "ATRV", "ATDP",
        "ATSP6", "ATSP5", "ATSP0", "ATSH7E0",
        "0100", "0105", "010C", "010B", "0110", "015C",
        "2104", "2186"
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Manueller Modus", isOn: $obd.isManualTerminalMode)
                    .font(.caption.bold())
                    .labelsHidden()
                Text(obd.isManualTerminalMode ? "Manueller Modus (Polling AUS)" : "Auto-Polling AKTIV")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(obd.isManualTerminalMode ? .orange : .secondary)

                Spacer()

                Button {
                    obd.copyTerminalLogToClipboard()
                    withAnimation { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopiedToast = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Log kopieren")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.12), in: Capsule())
                }

                Button {
                    obd.clearTerminalLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)

            HStack {
                Toggle("ACK Mode", isOn: $obd.forceWriteWithResponse)
                    .labelsHidden()
                Text(obd.forceWriteWithResponse ? "BLE Write: mit ACK (WithResponse)" : "BLE Write: Schnell (WithoutResponse)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickCommands, id: \.self) { cmd in
                        Button {
                            obd.sendManualCommand(cmd)
                        } label: {
                            Text(cmd)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(chipColor(for: cmd), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Befehl senden (z.B. ATRV, 0100, ATSP6)…", text: $manualCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    obd.sendManualCommand(manualCommand)
                    manualCommand = ""
                } label: {
                    Text("Senden")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .disabled(manualCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if obd.terminalEntries.isEmpty {
                        Text("// Terminal bereit. Sende einen Befehl oder starte den Schnelltest.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(obd.terminalEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(entry.timestamp)]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Text(entry.direction == .tx ? "TX >" : (entry.direction == .rx ? "RX <" : "SYS:"))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(entry.direction == .tx ? .cyan : (entry.direction == .rx ? .green : .white))

                                Text(entry.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(textColor(for: entry))
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    private func chipColor(for cmd: String) -> Color {
        if cmd.hasPrefix("ATSP") { return .indigo.opacity(0.6) }
        if cmd.hasPrefix("AT") { return .blue.opacity(0.5) }
        if cmd.hasPrefix("21") || cmd.hasPrefix("22") { return .purple.opacity(0.6) }
        return .cyan.opacity(0.5)
    }

    private func textColor(for entry: OBDTerminalEntry) -> Color {
        switch entry.style {
        case .success: return .green
        case .error:   return .red
        case .warning: return .orange
        case .normal:  return entry.direction == .tx ? .cyan : .white
        }
    }
}

struct OBDBluetoothScannerSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
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
                            .padding(.horizontal, 10)
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

struct OBDVAGGuideSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GuideCard(title: "1. Warum stand vorher 'obd bereit' aber keine Werte?",
                          content: "Der blaue ELM327 Mini verbindet sich sofort über Bluetooth mit deinem iPhone. Die Meldung 'obd bereit' hieß bisher nur, dass der Funk-Chip antwortete.\n\nDas Steuergerät im Auto antwortete jedoch nicht, weil billige Adapter beim automatischen Protokollsuchlauf (AT SP 0) oft hängen bleiben oder ein Timeout erzeugen.")

                GuideCard(title: "2. Zündschlüssel auf Stufe 2 drehen!",
                          content: "Die OBD-Dose hat Dauerplus (+12V von der Batterie), weshalb der Adapter immer leuchtet. Das Motorsteuergerät (Bosch MED9.1) schaltet sich jedoch erst ein, wenn der Zündschlüssel auf Stufe 2 gedreht wird (alle Kontrollleuchten im Tacho leuchten)!\n\nPrüfe im Reiter 'Sensoren' die Bordspannung: Bei Zündung Stufe 2 liegt sie typischerweise bei 12.0V – 12.6V.")

                GuideCard(title: "3. Empfohlenes Protokoll: CAN 11-Bit 500k",
                          content: "Der VW Golf 5 GTI EA113 (Motorcode AXX, BWA, BYD) nutzt für das Bosch MED9.1 Steuergerät standardmäßig:\n• Protokoll: ISO 15765-4 CAN 11-Bit 500k (Befehl: ATSP6)\n• Falls es nicht klappt: Wähle 'CAN 11-Bit 500k + 7E0 Header'\n• Falls dein Fahrzeug ein frühes Gateway hat: Wähle 'KWP2000 Fast (ATSP5)'.")

                GuideCard(title: "4. Besonderheit bei der Öltemperatur",
                          content: "Standard OBD-II PID 01 5C wird von der Bosch MED9.1 Software nicht standardmäßig geliefert (meldet 'NO DATA').\n\nDas ist normal bei VW EA113! CarLyrics nutzt dafür das integrierte, hochpräzise thermische Trägheitsmodell oder VAG Messwertblock 134.")
            }
            .padding()
        }
    }
}

struct GuideCard: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.cyan)
            Text(content)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
