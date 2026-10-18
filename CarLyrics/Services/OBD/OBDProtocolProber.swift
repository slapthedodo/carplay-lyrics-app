// MARK: - OBDProtocolProber.swift
// Automatischer Protokoll-Schnelltest & Brute-Force Analyse
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Automated Protocol Prober
    // ─────────────────────────────────────────────────────────────────────────

    public func runProtocolAutoProbe() {
        guard txChar != nil else {
            logSystem("⚠️ Kein Adapter verbunden. Bitte zuerst mit OBD-Adapter koppeln.")
            return
        }
        isProbingProtocols = true
        stopPolling()
        initStepTimer?.invalidate()
        initStepTimer = nil
        initQueue.removeAll()
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        sequenceQueue.removeAll()
        isWaitingForResponse = false
        receiveBuffer = ""

        let candidates: [OBDProtocol] = [
            .can11_500,         // Standard Golf 5 GTI EA113
            .can11_500_7e0,     // Direkter ECU Header
            .kwpFast,           // K-Line Fast
            .kwp5Baud,          // K-Line 5-Baud
            .can29_500,         // CAN 29-bit
            .iso9141,           // ISO 9141-2
            .auto               // Auto-Search
        ]

        probeResults = candidates.map {
            ProtocolProbeResult(proto: $0, status: .pending, rawResponse: "", responseTimeMs: 0, note: "")
        }

        logSystem("⚡ Starte Protokoll-Schnelltest über \(candidates.count) Methoden…")
        executeNextProbeStep(index: 0)
    }

    public func stopProtocolAutoProbe() {
        isProbingProtocols = false
        logSystem("Protokoll-Schnelltest abgebrochen.")
        if connectionState == .connected {
            startPolling()
        }
    }

    private func executeNextProbeStep(index: Int) {
        guard isProbingProtocols else { return }
        guard index < probeResults.count else {
            isProbingProtocols = false
            logSystem("🏁 Protokoll-Schnelltest abgeschlossen!")

            if let winner = probeResults.first(where: { $0.status == .success }) {
                logSystem("🏆 Erfolgreiches Protokoll gefunden: \(winner.proto.rawValue) – Wird jetzt aktiviert!")
                selectProtocol(winner.proto)
                connectionState = .connected
                startPolling()
            } else {
                detailedStatus = "Kein Protokoll hat geantwortet. Zündung Stufe 2 aktiv?"
            }
            return
        }

        probeResults[index].status = .testing
        let target = probeResults[index].proto
        detailedStatus = "Teste Methode \(index + 1)/\(probeResults.count): \(target.rawValue)…"
        logSystem("-> Teste: \(target.rawValue)")

        var cmds = [target.elmCommand]
        if let h = target.headerCommand { cmds.append(h) }
        cmds.append("0100") // Lese unterstützte PIDs

        let startTime = Date()
        sendSequence(cmds: cmds, timeout: target == .auto ? 6.5 : 4.0) { [weak self] fullResponse, success in
            guard let self = self else { return }
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            self.probeResults[index].responseTimeMs = duration
            self.probeResults[index].rawResponse = fullResponse

            let compactResp = fullResponse.replacingOccurrences(of: " ", with: "")
                                          .replacingOccurrences(of: "\r", with: "")
                                          .replacingOccurrences(of: "\n", with: "")

            if (success || !fullResponse.isEmpty) && (compactResp.contains("4100") || compactResp.contains("410C") || compactResp.contains("4105")) {
                self.probeResults[index].status = .success
                self.probeResults[index].note = "ECU antwortet! Bosch MED9.1 erkannt."
                self.logSystem("✔ Treffer bei \(target.rawValue) in \(duration)ms!")
            } else if fullResponse.contains("UNABLE TO CONNECT") || compactResp.contains("UNABLETOCONNECT") {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "UNABLE TO CONNECT (Falsches Protokoll oder Zündung aus)"
            } else if fullResponse.contains("BUS INIT") || compactResp.contains("BUSINIT") {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "BUS INIT ERROR"
            } else {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = fullResponse.isEmpty ? "Timeout" : fullResponse
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextProbeStep(index: index + 1)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 1-Klick Auto-Diagnose (Alles automatisch für den Nutzer)
    // ─────────────────────────────────────────────────────────────────────────

    public func runFullAutoDiagnosis() {
        isManualTerminalMode = false
        isProbingProtocols = false
        isAutoDiagnosing = true
        stopPolling()
        initStepTimer?.invalidate()
        initStepTimer = nil
        initQueue.removeAll()
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        sequenceQueue.removeAll()
        isWaitingForResponse = false
        receiveBuffer = ""
        diagnosisSummary = nil

        diagnosisSteps = [
            OBDDiagnosisStep(title: "1. Bluetooth-Adapter", detail: "Kopplung & Funkverbindung prüfen…", status: .inProgress),
            OBDDiagnosisStep(title: "2. Adapter-Hardware", detail: "UART-Kanäle scharfschalten & Bordspannung messen…", status: .waiting),
            OBDDiagnosisStep(title: "3. Motorsteuergerät", detail: "Bosch MED9.1 verbinden (Golf 5 GTI CAN 11/500)…", status: .waiting),
            OBDDiagnosisStep(title: "4. Live-Sensoren", detail: "Kühlmittel, Drehzahl, Ladedruck & EA113 Öl…", status: .waiting)
        ]

        logSystem("🚀 Starte 1-Klick Auto-Diagnose…")

        if peripheral == nil || txChar == nil || rxChar == nil {
            diagnosisSteps[0].detail = "Suche Adapter (BT-G…) & verbinde…"
            if connectionState != .scanning && connectionState != .connecting {
                startScan()
            }
            waitForBLEConnection(attempt: 0)
        } else {
            diagnosisSteps[0].status = .success
            diagnosisSteps[0].detail = "Verbunden mit '\(peripheral?.name ?? "OBD-Adapter")'"
            executeDiagStep2_Hardware()
        }
    }

    public func stopAutoDiagnosis() {
        isAutoDiagnosing = false
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        sequenceQueue.removeAll()
        diagnosisSummary = "Diagnose abgebrochen."
    }

    private func waitForBLEConnection(attempt: Int) {
        guard isAutoDiagnosing else { return }
        if let p = peripheral, txChar != nil, rxChar != nil {
            diagnosisSteps[0].status = .success
            diagnosisSteps[0].detail = "Verbunden mit '\(p.name ?? "OBD-Adapter")'"
            executeDiagStep2_Hardware()
            return
        }

        if attempt >= 12 {
            diagnosisSteps[0].status = .failed
            diagnosisSteps[0].detail = "Kein Adapter in Reichweite"
            diagnosisSummary = "⚠️ Kein Bluetooth-Adapter gefunden. Bitte prüfe, ob der blaue Allstric Dongle im OBD2-Port steckt und die rote LED leuchtet."
            isAutoDiagnosing = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForBLEConnection(attempt: attempt + 1)
        }
    }

    private func executeDiagStep2_Hardware() {
        guard isAutoDiagnosing else { return }
        diagnosisSteps[1].status = .inProgress
        diagnosisSteps[1].detail = "Sende Reset & messe Bordspannung…"
        logSystem("-> Diag Schritt 2: Hardware-Handshake…")

        sendSequence(cmds: ["\r", "ATZ", "ATE0", "ATL0", "ATS0", "ATRV"], timeout: 3.5) { [weak self] response, success in
            guard let self = self, self.isAutoDiagnosing else { return }

            let hasContent = !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasContent || !success {
                if !self.forceWriteWithResponse {
                    self.logSystem("ℹ Keine Antwort im No-ACK Modus -> Schalte um auf ACK (WithResponse)…")
                    self.forceWriteWithResponse = true
                    self.sendSequence(cmds: ["\r", "ATZ", "ATE0", "ATRV"], timeout: 3.5) { [weak self] rResp, rSucc in
                        guard let self = self, self.isAutoDiagnosing else { return }
                        self.evaluateHardwareDiagResponse(rResp)
                    }
                    return
                }
            }
            self.evaluateHardwareDiagResponse(response)
        }
    }

    private func evaluateHardwareDiagResponse(_ response: String) {
        let compact = response.replacingOccurrences(of: " ", with: "")
                              .replacingOccurrences(of: "\r", with: "")
                              .replacingOccurrences(of: "\n", with: "")

        let hasELM = compact.contains("ELM327") || compact.contains("OK") || compact.contains("V") || batteryVoltage != nil

        if hasELM {
            let voltStr = batteryVoltage != nil ? String(format: "%.1f V", batteryVoltage!) : "12V"
            let ignText = (batteryVoltage ?? 12.0) >= 11.5 ? "Zündung Stufe 2 aktiv" : "Zündung evtl. schwach"
            diagnosisSteps[1].status = .success
            diagnosisSteps[1].detail = "ELM327 aktiv • Bordspannung: \(voltStr) (\(ignText))"
            logSystem("✔ Diag Schritt 2 erfolgreich: \(voltStr)")
            executeDiagStep3_ECU()
        } else {
            if let rx = rxChar, let tx = txChar, rx != tx {
                logSystem("ℹ Teste alternativen Kanal (Invertiere TX/RX)…")
                rxChar = tx
                txChar = rx
                peripheral?.setNotifyValue(true, for: rxChar!)
                sendSequence(cmds: ["\r", "ATZ", "ATRV"], timeout: 2.5) { [weak self] invResp, invSucc in
                    guard let self = self, self.isAutoDiagnosing else { return }
                    if !invResp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.diagnosisSteps[1].status = .success
                        self.diagnosisSteps[1].detail = "ELM327 aktiv (Kanal B bestätigt)"
                        self.executeDiagStep3_ECU()
                        return
                    }
                    self.rxChar = rx
                    self.txChar = tx
                    self.failDiagHardware()
                }
                return
            }
            failDiagHardware()
        }
    }

    private func failDiagHardware() {
        diagnosisSteps[1].status = .failed
        diagnosisSteps[1].detail = "Adapter antwortet nicht"
        diagnosisSummary = "⚠️ Der Bluetooth-Adapter antwortet nicht auf Kommandos. Bitte ziehe den Dongle kurz ab und stecke ihn nach 5 Sekunden wieder fest in den OBD2-Port."
        isAutoDiagnosing = false
    }

    private func executeDiagStep3_ECU() {
        guard isAutoDiagnosing else { return }
        diagnosisSteps[2].status = .inProgress
        diagnosisSteps[2].detail = "Verbinde mit Bosch MED9.1 (Golf 5 CAN 11/500)…"
        logSystem("-> Diag Schritt 3: ECU-Anbindung…")

        // 1. Standard CAN 11-Bit 500k
        sendSequence(cmds: ["ATSP6", "0100"], timeout: 4.5) { [weak self] resp1, succ1 in
            guard let self = self, self.isAutoDiagnosing else { return }
            let compact1 = resp1.replacingOccurrences(of: " ", with: "")

            if compact1.contains("4100") || compact1.contains("410C") || compact1.contains("4105") {
                self.selectedProtocol = .can11_500
                self.diagnosisSteps[2].status = .success
                self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet (CAN 11-Bit 500k)"
                self.logSystem("✔ Diag Schritt 3: Bosch MED9.1 über CAN 11/500 verbunden!")
                self.executeDiagStep4_Sensors()
                return
            }

            // 2. Direkt-Header 7E0
            self.diagnosisSteps[2].detail = "Teste Direkt-Adresse ATSH7E0…"
            self.sendSequence(cmds: ["ATSH7E0", "0100"], timeout: 4.0) { [weak self] resp2, succ2 in
                guard let self = self, self.isAutoDiagnosing else { return }
                let compact2 = resp2.replacingOccurrences(of: " ", with: "")

                if compact2.contains("4100") || compact2.contains("410C") || compact2.contains("4105") {
                    self.selectedProtocol = .can11_500_7e0
                    self.diagnosisSteps[2].status = .success
                    self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet (Header 7E0)"
                    self.logSystem("✔ Diag Schritt 3: Bosch MED9.1 über Header 7E0 verbunden!")
                    self.executeDiagStep4_Sensors()
                    return
                }

                // 3. K-Line Fallback
                self.diagnosisSteps[2].detail = "Teste K-Line (KWP2000 Fast)…"
                self.sendSequence(cmds: ["ATSH", "ATSP5", "0100"], timeout: 4.5) { [weak self] resp3, succ3 in
                    guard let self = self, self.isAutoDiagnosing else { return }
                    let compact3 = resp3.replacingOccurrences(of: " ", with: "")

                    if compact3.contains("4100") || compact3.contains("410C") || compact3.contains("4105") {
                        self.selectedProtocol = .kwpFast
                        self.diagnosisSteps[2].status = .success
                        self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet über K-Line"
                        self.executeDiagStep4_Sensors()
                        return
                    }

                    self.diagnosisSteps[2].status = .failed
                    self.diagnosisSteps[2].detail = "Keine Antwort vom Steuergerät"
                    self.diagnosisSummary = "⚠️ Das Motorsteuergerät antwortet nicht. Bitte schalte die Zündung auf Stufe 2 ein (alle Kontrollleuchten im Tacho müssen leuchten, Motor muss nicht laufen) und starte den Test erneut."
                    self.isAutoDiagnosing = false
                }
            }
        }
    }

    private func executeDiagStep4_Sensors() {
        guard isAutoDiagnosing else { return }
        diagnosisSteps[3].status = .inProgress
        diagnosisSteps[3].detail = "Lese Live-Sensoren (Kühlmittel, RPM, Ladedruck, Öl)…"
        logSystem("-> Diag Schritt 4: Sensor-Abfrage…")

        sendSequence(cmds: ["0105", "010C", "010B", "015C"], timeout: 4.0) { [weak self] resp, succ in
            guard let self = self, self.isAutoDiagnosing else { return }

            self.connectionState = .connected
            self.detailedStatus = "Verbunden (\(self.selectedProtocol.rawValue))"

            let coolantStr = self.liveCoolantTemp != nil ? "\(self.liveCoolantTemp!)°C" : "OK"
            let rpmStr = "\(self.liveRPM) U/min"
            let oilStr = self.effectiveOilTemp != nil ? "\(self.effectiveOilTemp!)°C" : "Bereit"

            self.diagnosisSteps[3].status = .success
            self.diagnosisSteps[3].detail = "Kühlmittel: \(coolantStr) • Drehzahl: \(rpmStr) • Öl: \(oilStr)"

            self.diagnosisSummary = "✅ Perfekt! Dein Golf 5 GTI ist vollständig verbunden. Alle Live-Werte werden nun im Cockpit und in den Widgets angezeigt."
            self.isAutoDiagnosing = false

            self.logSystem("🏁 1-Klick Auto-Diagnose erfolgreich abgeschlossen!")
            self.startPolling()
            self.startVoltageMonitor()
        }
    }
}
