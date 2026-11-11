// MARK: - OBDPollingLoop.swift
// Kontinuierliche Sensor-Abfrageschleife & Taktung für ELM327 BLE (Bosch MED9.1)
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Polling Steuerung
    // ─────────────────────────────────────────────────────────────────────────

    internal func startPolling() {
        guard !isProbingProtocols && !isManualTerminalMode && !isAutoDiagnosing else { return }
        isPollingActive = true
        pollTimer?.invalidate()
        pollTimer = nil
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil

        // Ersten Befehl mit kleiner 60ms Pause absetzen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
            self.pollNextPID()
        }
    }

    internal func stopPolling() {
        isPollingActive = false
        pollTimer?.invalidate()
        pollTimer = nil
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    internal func startVoltageMonitor() {
        // ATRV wird nun kollisionsfrei direkt im Polling-Zyklus alle 25 Zyklen abgefragt
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Antwort-Verarbeitung & Taktung
    // ─────────────────────────────────────────────────────────────────────────

    /// Antwort wurde empfangen (">"): Adaptive Pause basierend auf Fokus-Modus
    internal func onResponseCompleted() {
        guard isPollingActive, connectionState == .connected, !isProbingProtocols, !isManualTerminalMode, !isAutoDiagnosing else { return }
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil

        let delay: Double
        switch focusMode {
        case .pedalOnly:
            delay = 0.015 // 15ms ultraschnell für flüssige Pedal- & Ganganzeige
        case .minimal:
            delay = 0.080 // 80ms für Kupplungs-Tutorial
        case .standard:
            delay = 0.015 // 15ms blitzschneller Takt für CAN-Bus (spart 30ms pro Abfrage!)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
            self.pollNextPID()
        }
    }

    internal func pollNextPID() {
        guard connectionState == .connected, !isProbingProtocols, !isManualTerminalMode, !isAutoDiagnosing else { return }

        let activePIDs: [String]
        switch focusMode {
        case .pedalOnly:
            // Exklusiv nur Werte für den Pedal- und Ganganzeige-Tab (Null Overhead)
            activePIDs = [
                "010C",     // Motordrehzahl RPM
                "0111",     // Gaspedal / Drosselklappe %
                "0104",     // Motorlast % (Fallback)
                "010D"      // Geschwindigkeit km/h (für Gang)
            ]
        case .minimal:
            // Für Kupplungs-Tutorial: Nur RPM & Gas, keine schweren Cockpit-Sensoren
            activePIDs = [
                "010C",     // RPM
                "0111",     // Gaspedal %
                "0104"      // Motorlast %
            ]
        case .standard:
            // High-Speed Priority Interleaving für EA113 2.0 TFSI (Bosch MED9.1):
            // Schnelle Werte (Ladedruck via MAP/MAF & Drehzahl) bekommen 75% der Bandbreite!
            let fastPIDs: [String]
            if hasCheckedMAPPID && !hasMAPPID {
                // MED9.1 nutzt MAF (0110) für Ladedruck + 010C (RPM)
                fastPIDs = ["0110", "010C"]
            } else if hasCheckedMAPPID && hasMAPPID {
                // Echtes MAP (010B) vorhanden
                fastPIDs = ["010B", "010C"]
            } else {
                // Noch nicht geprüft: MAP, MAF und RPM abfragen
                fastPIDs = ["010B", "0110", "010C"]
            }

            var slowPIDs: [String] = [
                "010D", // Geschwindigkeit km/h
                "0105", // Kühlmittel °C (steigt nur sehr langsam)
                "0104", // Motorlast %
                "010F"  // Ansaugluft IAT °C
            ]

            // 015C (Öltemperatur) alle paar Zyklen einstreuen
            if !hasCheckedOilTempPID || hasOilTempPID || (currentPIDIndex % 20 == 0) {
                slowPIDs.append("015C")
            }

            // ATRV (Bordspannung) alle 30 Zyklen
            if currentPIDIndex % 30 == 0 {
                slowPIDs.append("ATRV")
            }

            // 3:1 Taktung: 3x Fast PID (Ladedruck/Drehzahl), dann 1x Slow PID (Wasser/IAT/Last/Temp)
            // Ladedruck wird dadurch alle ~150-250ms aktualisiert (5-8 Hz statt vorher 0.8 Hz!)
            let step = currentPIDIndex % 4
            let selectedPID: String
            if step < 3 {
                let fastIdx = (currentPIDIndex / 4 * 3 + step) % fastPIDs.count
                selectedPID = fastPIDs[fastIdx]
            } else {
                let slowIdx = (currentPIDIndex / 4) % slowPIDs.count
                selectedPID = slowPIDs[slowIdx]
            }
            activePIDs = [selectedPID]
        }

        guard !activePIDs.isEmpty else { return }
        let pid = activePIDs[currentPIDIndex % activePIDs.count]
        currentPIDIndex += 1

        sendCommandRaw(pid)

        // Sicherheits-Watchdog: Falls BLE ein Paket verschluckt, nach 850ms weitermachen
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
                self.isWaitingForResponse = false
                self.pollNextPID()
            }
        }
    }
}
