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
            } else if fullResponse.contains("NO DATA") || compactResp.contains("NODATA") {
                self.probeResults[index].status = .noData
                self.probeResults[index].note = "NO DATA (Bus erkannt, aber keine Antwort auf 0100)"
            } else {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = fullResponse.isEmpty ? "Timeout" : fullResponse
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextProbeStep(index: index + 1)
            }
        }
    }
}
