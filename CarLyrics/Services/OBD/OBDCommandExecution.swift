// MARK: - OBDCommandExecution.swift
// Low-Level Befehlsausführung, Handshake-Sequenz & Watchdog für ELM327
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Low-Level Command Execution
    // ─────────────────────────────────────────────────────────────────────────

    internal func sendCommandRaw(_ cmd: String) {
        guard let p = peripheral, let tx = txChar else {
            logSystem("⚠️ Kein Bluetooth TX Characteristic gefunden.")
            return
        }
        let cleanCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullCmd = cleanCmd.isEmpty ? "\r" : (cleanCmd + "\r")
        if let data = fullCmd.data(using: .utf8) ?? fullCmd.data(using: .ascii) {
            let writeType: CBCharacteristicWriteType
            if forceWriteWithResponse {
                writeType = tx.properties.contains(.write) ? .withResponse : .withoutResponse
            } else {
                writeType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            }
            logTx("\(cmd) (\(writeType == .withoutResponse ? "no-ack" : "ack"))")
            p.writeValue(data, for: tx, type: writeType)
            isWaitingForResponse = true
            lastCommandSentTime = Date()
            lastCommandSent = cmd
        }
    }

    internal func sendSequence(cmds: [String], timeout: TimeInterval, completion: @escaping @MainActor (String, Bool) -> Void) {
        sequenceQueue = cmds
        sequenceAccumulated = ""
        sequenceCompletion = completion
        sendNextInSequence(timeout: timeout)
    }

    internal func sendNextInSequence(timeout: TimeInterval) {
        sequenceTimer?.invalidate()
        sequenceTimer = nil

        guard !sequenceQueue.isEmpty else {
            let comp = sequenceCompletion
            sequenceCompletion = nil
            pendingSequenceHandler = nil
            let finalAccumulated = sequenceAccumulated
            Task { @MainActor in
                comp?(finalAccumulated, !finalAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            return
        }

        let nextCmd = sequenceQueue.removeFirst()

        // Leere Befehle oder reines "\r" (Wakeup-Flush) sofort senden ohne auf Prompt zu warten
        if nextCmd.isEmpty || nextCmd == "\r" {
            sendCommandRaw("\r")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.sendNextInSequence(timeout: timeout)
            }
            return
        }

        sendCommandRaw(nextCmd)

        // Befehlsspezifischer Timeout
        let cmdTimeout: TimeInterval
        if nextCmd == "ATZ" || nextCmd == "0100" || nextCmd == "ATSP0" {
            cmdTimeout = max(timeout, 2.5)
        } else {
            cmdTimeout = min(timeout, 2.0)
        }

        sequenceTimer = Timer.scheduledTimer(withTimeInterval: cmdTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isWaitingForResponse = false
                self.logSystem("⏱ Timeout auf '\(nextCmd)' in Sequenz")

                // Falls noch weitere Befehle in der Queue sind, nicht abbrechen sondern nächsten Befehl testen!
                if !self.sequenceQueue.isEmpty {
                    self.sendNextInSequence(timeout: timeout)
                } else {
                    let comp = self.sequenceCompletion
                    self.sequenceCompletion = nil
                    self.pendingSequenceHandler = nil
                    let finalAccumulated = self.sequenceAccumulated
                    comp?(finalAccumulated, !finalAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }

        pendingSequenceHandler = { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.sequenceAccumulated += " " + response
                // Nach ATZ braucht der Chip 450ms Erholungszeit für den internen Reboot
                let delay = (nextCmd == "ATZ") ? 0.45 : 0.08
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sendNextInSequence(timeout: timeout)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Robust Initialization Sequence
    // ─────────────────────────────────────────────────────────────────────────

    internal func startRobustInitSequence() {
        connectionWatchdogTimer?.invalidate()
        connectionState = .initializing
        detailedStatus = "Initialisiere ELM327 Hardware…"
        logSystem("Starte saubere ELM327 Handshake-Sequenz…")

        // 1. Carriage Return zum Leeren von Puffer-Resten & Wecken des Adapters
        // 2. ATZ (Reset Chip)
        // 3. ATE0 (Echo aus)
        // 4. ATL0 (Linefeeds aus)
        // 5. ATS0 (Leerzeichen aus für maximalen Durchsatz)
        // 6. ATH0 (Headers standardmäßig aus)
        // 7. ATAT2 (Aggressives adaptives Timing für minimale Latenz)
        // 8. ATST19 (100ms Timeout statt 400ms Standard — beschleunigt fehlende PIDs um Faktor 4)
        // 9. ATRV (Bordspannung messen zur Zündungs-Verifizierung!)
        // 10. ATI  (ELM327 Firmware-Version auslesen)
        // 11. Ausgewähltes Protokoll setzen (z.B. ATSP6)
        // 12. Prüfen mit 0100 (ECU Suche)
        var sequence = ["\r", "ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATAT2", "ATST19", "ATRV", "ATI", selectedProtocol.elmCommand]
        if let header = selectedProtocol.headerCommand {
            sequence.append(header)
        }
        sequence.append("0100") // Probe ECU

        initQueue = sequence
        sendNextInitCommand()
    }

    internal func sendInitCommands(_ cmds: [String]) {
        initQueue.append(contentsOf: cmds)
        if !isWaitingForResponse {
            sendNextInitCommand()
        }
    }

    internal func sendNextInitCommand() {
        initStepTimer?.invalidate()
        initStepTimer = nil

        // Guard: falls initQueue leer ist, sind wir fertig mit der Init-Sequenz
        guard !initQueue.isEmpty else {
            isInitializingUART = false
            connectionWatchdogTimer?.invalidate()

            let hasAnyResponse = batteryVoltage != nil || !elmFirmware.isEmpty || !supportedPIDs.isEmpty || liveCoolantTemp != nil
            if hasAnyResponse {
                connectionState = .connected
                detailedStatus = "Verbunden (\(selectedProtocol.rawValue))"
                logSystem("✔ ELM327 initialisiert. Starte kontinuierliche Sensorabfrage.")
                startPolling()
                startVoltageMonitor()
            } else {
                connectionState = .error
                detailedStatus = "Keine Antwort vom Adapter (Zündung an?)"
                logSystem("⚠️ ELM327 Hardware antwortet nicht auf Befehle.")
            }
            return
        }

        let nextCmd = initQueue.removeFirst()
        if nextCmd == "0100" {
            connectionState = .searchingECU
            detailedStatus = "Verbinde mit Steuergerät (Bosch MED9.1)…"
        } else {
            detailedStatus = "Initialisiere ELM327 (\(nextCmd.isEmpty || nextCmd == "\r" ? "Wakeup" : nextCmd))…"
        }

        let delay: Double
        if lastCommandSent == "ATZ" {
            delay = 0.45 // 450ms Erholungspause nach Reset für Allstric / BK3231 Clone
        } else if nextCmd == "\r" {
            delay = 0.15
        } else {
            delay = 0.08
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.sendCommandRaw(nextCmd)

            let waitTime: TimeInterval
            if nextCmd == "0100" {
                waitTime = (self.selectedProtocol == .auto) ? 7.0 : 2.5
            } else if nextCmd == "ATZ" {
                waitTime = 2.4
            } else {
                waitTime = 1.5
            }

            self.initStepTimer = Timer.scheduledTimer(withTimeInterval: waitTime, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.connectionState == .initializing || self.connectionState == .searchingECU {
                        let bufInfo = self.receiveBuffer.isEmpty ? "leer" : "'\(self.receiveBuffer)'"
                        self.logSystem("ℹ Timeout bei Befehl \(nextCmd) [Puffer: \(bufInfo)] – fahre fort.")
                        if !self.forceWriteWithResponse && (nextCmd == "ATZ" || nextCmd == "ATE0") {
                            self.forceWriteWithResponse = true
                            self.logSystem("ℹ Wechsle automatisch zu Write-with-Response (ACK-Modus)…")
                        }
                        self.isWaitingForResponse = false
                        self.sendNextInitCommand()
                    }
                }
            }
        }
    }

    internal func startConnectionWatchdog() {
        connectionWatchdogTimer?.invalidate()
        connectionWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 14.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.connectionState == .connecting {
                    self.logSystem("⚠ Verbindungs-Watchdog: Adapter reagiert nicht beim Koppeln. Starte Scan neu…")
                    self.reconnect()
                }
            }
        }
    }
}
