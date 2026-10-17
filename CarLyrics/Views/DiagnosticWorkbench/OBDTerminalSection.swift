// MARK: - OBDTerminalSection.swift
// Live-Terminal für AT-Kommandos, HEX-Frames & ACK-Modus
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDTerminalSection: View {
    @ObservedObject var obd: OBDManager
    @Binding var manualCommand: String
    @Binding var showCopiedToast: Bool

    private let quickCommands = [
        "ATZ", "ATI", "ATRV", "ATDP",
        "ATSP6", "ATSP5", "ATSP0", "ATSH7E0",
        "0100", "0105", "010C", "010B", "0110", "015C",
        "2104", "2186"
    ]

    public init(obd: OBDManager, manualCommand: Binding<String>, showCopiedToast: Binding<Bool>) {
        self.obd = obd
        self._manualCommand = manualCommand
        self._showCopiedToast = showCopiedToast
    }

    public var body: some View {
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
                TextField("Befehl (z.B. ATRV, ATSP6, 0100)", text: $manualCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .onSubmit {
                        obd.sendManualCommand(manualCommand)
                        manualCommand = ""
                    }

                Button("Senden") {
                    obd.sendManualCommand(manualCommand)
                    manualCommand = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding(.horizontal)

            // Terminal Konsole
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if obd.terminalEntries.isEmpty {
                        Text("Noch keine Daten im Terminal. Verbinde einen Adapter oder sende einen Befehl.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(20)
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
