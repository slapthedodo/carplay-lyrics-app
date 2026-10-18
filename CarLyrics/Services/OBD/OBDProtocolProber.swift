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
                self.probeResults[index].note = "UNABLE TO CONNECT → Falsches Protokoll oder Zündung noch nicht bereit"
            } else if fullResponse.contains("BUS INIT") || compactResp.contains("BUSINIT") {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "BUS INIT ERROR → K-Line Hardware-Problem"
            } else if fullResponse.contains("NO DATA") || compactResp.contains("NODATA") {
                self.probeResults[index].status = .noData
                self.probeResults[index].note = "NO DATA → CAN-Bus läuft, Steuergerät antwortet nicht auf 0100 (Zündung an?)"
            } else if fullResponse.isEmpty {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "Timeout → Adapter sendet nichts zurück (falsche TX/RX Kanäle?)"
            } else {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "Unbekannte Antwort: \(fullResponse.prefix(60))"
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
            diagnosisSteps[0].detail = "Verbunden mit '\(p.name ?? "OBD-Adapter")' (Kanäle bereit)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.executeDiagStep2_Hardware()
            }
            return
        }

        if let p = peripheral {
            diagnosisSteps[0].detail = "Gekoppelt mit '\(p.name ?? "OBDII")' • Schalte Funkkanäle frei…"
        }

        if attempt >= 16 {
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

        // BLE-Debug-Info zusammenstellen
        let pName = peripheral?.name ?? "?"
        let txUUID = txChar?.uuid.uuidString ?? "?"
        let rxUUID = rxChar?.uuid.uuidString ?? "?"
        let txProps = txChar != nil ? "WriteWR:\(txChar!.properties.contains(.writeWithoutResponse)) Write:\(txChar!.properties.contains(.write)) Notify:\(txChar!.properties.contains(.notify))" : "?"
        diagnosisBLEDebug = "Gerät: \(pName)\nTX-Char: \(txUUID) [\(txProps)]\nRX-Char: \(rxUUID)\nModus: \(forceWriteWithResponse ? "ACK (WithResponse)" : "no-ACK (WithoutResponse)")"
        logSystem("BLE-Info: TX=\(txUUID) RX=\(rxUUID)")

        // Versuch 1: Standard no-ACK (WriteWithoutResponse)
        diagnosisSteps[1].detail = "Versuch 1/6: Sende ohne ACK…"
        tryHardwareSequence(attemptLabel: "1/6 (no-ACK)", useACK: false, cmds: ["\r", "ATZ", "ATE0", "ATRV"]) { [weak self] got1 in
            guard let self = self, self.isAutoDiagnosing else { return }
            if got1 { self.onHardwareSuccess(); return }

            // Versuch 2: Mit ACK (WriteWithResponse)
            self.diagnosisSteps[1].detail = "Versuch 2/6: Sende mit Bestätigung (ACK)…"
            self.tryHardwareSequence(attemptLabel: "2/6 (ACK)", useACK: true, cmds: ["\r", "ATZ", "ATE0", "ATRV"]) { [weak self] got2 in
                guard let self = self, self.isAutoDiagnosing else { return }
                if got2 { self.onHardwareSuccess(); return }

                // Versuch 3: TX/RX Kanäle vertauschen (kein ACK)
                if let rx = self.rxChar, let tx = self.txChar, rx.uuid != tx.uuid {
                    self.diagnosisSteps[1].detail = "Versuch 3/6: Vertausche TX↔RX Kanäle…"
                    self.rxChar = tx
                    self.txChar = rx
                    self.peripheral?.setNotifyValue(true, for: self.rxChar!)
                    self.logSystem("  → Swap: TX=\(self.txChar!.uuid) RX=\(self.rxChar!.uuid)")
                    self.tryHardwareSequence(attemptLabel: "3/6 (swap+no-ACK)", useACK: false, cmds: ["\r", "ATZ", "ATRV"]) { [weak self] got3 in
                        guard let self = self, self.isAutoDiagnosing else { return }
                        if got3 { self.onHardwareSuccess(); return }

                        // Versuch 4: TX/RX vertauscht + ACK
                        self.diagnosisSteps[1].detail = "Versuch 4/6: Vertauscht + ACK…"
                        self.tryHardwareSequence(attemptLabel: "4/6 (swap+ACK)", useACK: true, cmds: ["\r", "ATZ", "ATRV"]) { [weak self] got4 in
                            guard let self = self, self.isAutoDiagnosing else { return }
                            if got4 { self.onHardwareSuccess(); return }

                            // Swap zurücksetzen und Versuch 5/6
                            self.rxChar = rx
                            self.txChar = tx
                            self.peripheral?.setNotifyValue(true, for: self.rxChar!)
                            self.trySlowWakeup()
                        }
                    }
                } else {
                    // Keine 2 separaten Kanäle — direkt zu Slow Wakeup
                    self.trySlowWakeup()
                }
            }
        }
    }

    private func tryHardwareSequence(attemptLabel: String, useACK: Bool, cmds: [String], completion: @escaping (Bool) -> Void) {
        forceWriteWithResponse = useACK
        logSystem("  → Teste [\(attemptLabel)]…")
        sendSequence(cmds: cmds, timeout: 3.0) { [weak self] response, _ in
            guard let self = self else { return }
            let compact = response.replacingOccurrences(of: " ", with: "")
                                  .replacingOccurrences(of: "\r", with: "")
                                  .replacingOccurrences(of: "\n", with: "")
            let hasContent = compact.contains("ELM") || compact.contains("OK") ||
                             compact.contains("ATZ") || compact.contains("V") ||
                             compact.contains(">") || self.batteryVoltage != nil
            self.logSystem("    Antwort: '\(compact.prefix(40))' hasContent=\(hasContent)")
            completion(hasContent)
        }
    }

    private func trySlowWakeup() {
        guard isAutoDiagnosing else { return }
        diagnosisSteps[1].detail = "Versuch 5/6: Langsamer Wakeup-Reset (BK3231)…"
        logSystem("  → Slow-Wakeup: sende \\r + 1s Pause + ATZ")

        // Sehr langsame Init-Sequenz für schläfrige BK3231-Chips
        sendCommandRaw("\r")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, self.isAutoDiagnosing else { return }
            self.sendCommandRaw("ATZ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isAutoDiagnosing else { return }
                self.diagnosisSteps[1].detail = "Versuch 6/6: Bordspannung nach Wakeup…"
                self.tryHardwareSequence(attemptLabel: "6/6 (slow wakeup)", useACK: self.forceWriteWithResponse, cmds: ["ATE0", "ATRV"]) { [weak self] got6 in
                    guard let self = self, self.isAutoDiagnosing else { return }
                    if got6 { self.onHardwareSuccess(); return }
                    self.failDiagHardware()
                }
            }
        }
    }

    private func onHardwareSuccess() {
        let voltStr = batteryVoltage != nil ? String(format: "%.1f V", batteryVoltage!) : "OK (kein Volt-Wert)"
        let ignText: String
        if let v = batteryVoltage {
            ignText = v >= 13.0 ? "Motor läuft!" : (v >= 11.5 ? "Zündung Stufe 2 ✓" : "⚠ Spannung niedrig (\(String(format: "%.1f", v))V)")
        } else {
            ignText = "Adapter antwortet"
        }
        diagnosisSteps[1].status = .success
        diagnosisSteps[1].detail = "ELM327 aktiv • \(voltStr) • \(ignText) [\(forceWriteWithResponse ? "ACK" : "no-ACK")]"
        diagnosisBLEDebug = nil
        logSystem("✔ Diag Schritt 2 OK (\(voltStr), ACK=\(forceWriteWithResponse))")
        executeDiagStep3_ECU()
    }

    private func failDiagHardware() {
        let pName = peripheral?.name ?? "Unbekannt"
        let txUUID = txChar?.uuid.uuidString.suffix(4) ?? "?"
        let rxUUID = rxChar?.uuid.uuidString.suffix(4) ?? "?"

        diagnosisSteps[1].status = .failed
        diagnosisSteps[1].detail = "Alle 6 Versuche gescheitert (TX:\(txUUID) RX:\(rxUUID))"

        diagnosisSummary = """
        ❌ Adapter '\(pName)' verbunden, antwortet aber nicht auf AT-Kommandos.

        Was getestet wurde:
        • Write ohne ACK & mit ACK
        • TX/RX Kanäle getauscht (beide Richtungen)
        • Langsamer Wakeup-Reset (BK3231)

        Bitte versuche folgendes:
        1️⃣ Zündung kurz AUS, Dongle 10 Sek. abstecken, wieder einstecken, Zündung AN → Test erneut
        2️⃣ Stelle sicher, dass kein anderes Gerät (anderes Handy, Laptop, OBD-App) mit dem Adapter verbunden ist
        3️⃣ Öffne „Erweiterte Protokolle" unten → 7-Methoden Test ausführen
        """
        diagnosisRetryCount += 1
        isAutoDiagnosing = false
    }

    private func executeDiagStep3_ECU() {
        guard isAutoDiagnosing else { return }
        diagnosisSteps[2].status = .inProgress
        diagnosisSteps[2].detail = "Verbinde mit Bosch MED9.1 (Golf 5 CAN 11/500)…"
        logSystem("-> Diag Schritt 3: ECU-Anbindung…")

        // Merke alle Raw-Antworten für Diagnose
        var collectedResponses: [(String, String)] = [] // (beschriftung, raw-antwort)

        // 1. Standard CAN 11-Bit 500k
        sendSequence(cmds: ["ATSP6", "0100"], timeout: 4.5) { [weak self] resp1, succ1 in
            guard let self = self, self.isAutoDiagnosing else { return }
            let c1 = resp1.replacingOccurrences(of: " ", with: "")
            collectedResponses.append(("CAN11/500", resp1.trimmingCharacters(in: .whitespacesAndNewlines)))

            if c1.contains("4100") || c1.contains("410C") || c1.contains("4105") {
                self.selectedProtocol = .can11_500
                self.diagnosisSteps[2].status = .success
                self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet (CAN 11-Bit 500k)"
                self.logSystem("✔ Diag Schritt 3: Bosch MED9.1 über CAN 11/500 verbunden!")
                self.executeDiagStep4_Sensors()
                return
            }

            // 2. Direkt-Header 7E0
            self.diagnosisSteps[2].detail = "Teste Direkt-Adresse 7E0 (MED9.1 ECU)…"
            self.sendSequence(cmds: ["ATSP6", "ATSH7E0", "0100"], timeout: 4.5) { [weak self] resp2, succ2 in
                guard let self = self, self.isAutoDiagnosing else { return }
                let c2 = resp2.replacingOccurrences(of: " ", with: "")
                collectedResponses.append(("CAN11/500+7E0", resp2.trimmingCharacters(in: .whitespacesAndNewlines)))

                if c2.contains("4100") || c2.contains("410C") || c2.contains("4105") {
                    self.selectedProtocol = .can11_500_7e0
                    self.diagnosisSteps[2].status = .success
                    self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet (CAN 11-Bit 500k + Header 7E0)"
                    self.logSystem("✔ Diag Schritt 3: Bosch MED9.1 über CAN 11/500 + 7E0 verbunden!")
                    self.executeDiagStep4_Sensors()
                    return
                }

                // 3. K-Line Fallback
                self.diagnosisSteps[2].detail = "Teste K-Line (KWP2000 Fast)…"
                self.sendSequence(cmds: ["ATSH", "ATSP5", "0100"], timeout: 4.5) { [weak self] resp3, succ3 in
                    guard let self = self, self.isAutoDiagnosing else { return }
                    let c3 = resp3.replacingOccurrences(of: " ", with: "")
                    collectedResponses.append(("KWP2000", resp3.trimmingCharacters(in: .whitespacesAndNewlines)))

                    if c3.contains("4100") || c3.contains("410C") || c3.contains("4105") {
                        self.selectedProtocol = .kwpFast
                        self.diagnosisSteps[2].status = .success
                        self.diagnosisSteps[2].detail = "Bosch MED9.1 antwortet über K-Line (KWP2000)"
                        self.executeDiagStep4_Sensors()
                        return
                    }

                    // Analyse: Was hat der Adapter zurückgegeben?
                    let allRaw = collectedResponses.map { $0.1 }.joined()
                    let allCompact = allRaw.replacingOccurrences(of: " ", with: "")
                    let hadNODATA = allCompact.contains("NODATA")
                    let hadUNABLE = allCompact.contains("UNABLETOCONNECT")
                    let allTimeout = collectedResponses.allSatisfy { $0.1.isEmpty }

                    self.diagnosisSteps[2].status = .failed

                    if allTimeout {
                        // Adapter antwortet gar nicht → ist eigentlich ein Hardware-Problem
                        self.diagnosisSteps[2].detail = "Timeout bei allen 3 Protokollen (kein Echo)"
                        self.diagnosisSummary = """
                        ⚠️ Der OBD-Adapter sendet keine Antwort auf Protokollabfragen.

                        Mögliche Ursachen:
                        • Zündung ist nicht auf Stufe 2 (alle Kontrollleuchten müssen leuchten)
                        • OBD-Stecker sitzt nicht fest im Port (Golf 5: unter dem Lenkrad links)
                        • Ein anderes Gerät blockiert den CAN-Bus
                        
                        👉 Tipp: Versuche den „Erweiterte Protokolle → 7-Methoden Test" unten — dort siehst du ob irgendein Protokoll wenigstens NODATA zurückgibt.
                        """
                    } else if hadNODATA {
                        // ECU-Bus wird gefunden, aber 0100 kommt nicht durch
                        self.diagnosisSteps[2].detail = "CAN-Bus aktiv, aber 0100 → NO DATA"
                        self.diagnosisSummary = """
                        ⚠️ CAN-Bus Verbindung hergestellt, aber Steuergerät antwortet nicht auf OBD-Anfragen.

                        Bei deinem Golf 5 GTI (Bosch MED9.1) ist das oft ein Timing-Problem.

                        Bitte versuche:
                        1️⃣ Zündung auf Stufe 2 (NICHT starten!), 5 Sek. warten, dann Test erneut
                        2️⃣ Falls Fehlercode P0000 im Kombi: Wegfahrsperre aktiv → erst Motor kurz starten & wieder aus
                        3️⃣ Klicke auf „Erweiterte Protokolle" unten → „VAG CAN 11-Bit 500k" manuell aktivieren
                        """
                    } else if hadUNABLE {
                        self.diagnosisSteps[2].detail = "Falsches Protokoll oder Zündung zu früh"
                        self.diagnosisSummary = """
                        ⚠️ Der Adapter meldet „UNABLE TO CONNECT" — das Protokoll passt nicht oder die Zündung war beim Start noch nicht bereit.

                        Bitte:
                        1️⃣ Zündung auf Stufe 2 warten, bis alle Kontrollleuchten erloschen sind
                        2️⃣ Dann erst „Auto-Test" starten
                        3️⃣ Bei wiederholtem Fehler: „Erweiterte Protokolle" → „VAG CAN 11-Bit 500k (Direkt Header 7E0)" manuell testen
                        """
                    } else {
                        self.diagnosisSteps[2].detail = "Keine ECU-Antwort (Antwort war: \(allRaw.prefix(60)))"
                        self.diagnosisSummary = """
                        ⚠️ Das Motorsteuergerät antwortet nicht auf OBD-Abfragen.

                        Bitte Zündung auf Stufe 2 einschalten und Test erneut starten.
                        Rohantw.: \(allRaw.prefix(100))
                        """
                    }
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
