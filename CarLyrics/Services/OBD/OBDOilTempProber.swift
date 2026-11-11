// MARK: - OBDOilTempProber.swift
// Multi-Fallback Öltemperatur-Auslese für VW Golf 5 GTI (Bosch MED9.1)
// Testet 6 verschiedene OBD-Methoden in Reihenfolge — erste erfolgreiche gewinnt.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Probe Methoden Definition
    // ─────────────────────────────────────────────────────────────────────────

    /// Alle Fallback-Methoden die wir für Öltemp probieren (Reihenfolge = Priorität)
    /// Format: Entweder einfacher PID-String, oder "HEADER_CMD||QUERY_CMD" für Header-Switch
    internal static let oilTempProbeMethods: [OilTempProbeStatus] = [
        OilTempProbeStatus(
            methodName: "OBD Standard PID 015C",
            command: "015C"
        ),
        OilTempProbeStatus(
            methodName: "VAG Mode 22 PID 1C1F",
            command: "221C1F"
        ),
        OilTempProbeStatus(
            methodName: "VAG Mode 22 PID 1140",
            command: "221140"
        ),
        OilTempProbeStatus(
            methodName: "VAG ECU (Header 7E0) + 22F43C",
            command: "ATSH7E0||22F43C"
        ),
        OilTempProbeStatus(
            methodName: "Kombiinstrument (Header 7C4)",
            command: "ATSH7C4||220C01"
        ),
        OilTempProbeStatus(
            methodName: "Broadcast 7DF + 015C",
            command: "ATSH7DF||015C"
        ),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Haupt-Probe Funktion
    // ─────────────────────────────────────────────────────────────────────────

    /// Startet den Multi-Fallback Öltemp-Test.
    /// Testet alle Methoden sequenziell. Hört bei erster Erfolg auf.
    @MainActor
    public func startTachoOilTempProbe() async {
        guard connectionState == .connected else {
            logSystem("⚠️ Tacho Öltemp: OBD nicht verbunden.")
            return
        }
        guard !isMeasuringTachoOilTemp else { return }

        isMeasuringTachoOilTemp = true
        tachoOilTempValue = nil
        tachoOilTempMethod = ""
        tachoOilTempProbeStatus = OBDManager.oilTempProbeMethods

        logSystem("🌡 Starte Öltemp-Probe: 6 Methoden werden getestet…")

        // Polling kurz pausieren während probe-Befehle gesendet werden
        let wasPolling = isPollingActive
        if wasPolling {
            stopPolling()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        for i in tachoOilTempProbeStatus.indices {
            tachoOilTempProbeStatus[i].status = .testing

            let method = tachoOilTempProbeStatus[i]
            let result = await probeOilTempMethod(method)

            tachoOilTempProbeStatus[i].rawResponse = result.rawResponse
            tachoOilTempProbeStatus[i].parsedValue = result.parsedValue
            tachoOilTempProbeStatus[i].status = result.success ? .success : (result.isNoData ? .noData : .failed)

            if result.success, let temp = result.parsedValue {
                tachoOilTempValue = temp
                tachoOilTempMethod = method.methodName
                liveOilTemp = temp
                hasOilTempPID = true
                hasCheckedOilTempPID = true
                logSystem("✅ Öltemp: \(temp)°C via '\(method.methodName)'")

                // Restliche auf pending lassen
                for j in (i + 1)..<tachoOilTempProbeStatus.count {
                    tachoOilTempProbeStatus[j].status = .pending
                }
                break
            }

            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms Pause zwischen Methoden
        }

        // ELM327 Header auf Standard zurücksetzen
        await resetELMHeader()

        if wasPolling {
            try? await Task.sleep(nanoseconds: 100_000_000)
            startPolling()
        }

        isMeasuringTachoOilTemp = false

        if tachoOilTempValue == nil {
            logSystem("❌ Öltemp: Alle 6 Methoden fehlgeschlagen. Motor läuft? Zündung an?")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Einzelne Methode testen
    // ─────────────────────────────────────────────────────────────────────────

    private struct OilTempProbeResult {
        let rawResponse: String
        let parsedValue: Int?
        let success: Bool
        let isNoData: Bool
    }

    @MainActor
    private func probeOilTempMethod(_ method: OilTempProbeStatus) async -> OilTempProbeResult {
        let cmd = method.command

        if cmd.contains("||") {
            let parts = cmd.components(separatedBy: "||")
            guard parts.count == 2 else {
                return OilTempProbeResult(rawResponse: "Ungültiger Befehl", parsedValue: nil, success: false, isNoData: false)
            }
            let headerCmd = parts[0]
            let queryCmd  = parts[1]

            let headerResponse = await sendSingleOBDCommand(headerCmd, timeout: 1.5)
            logSystem("   Header: \(headerCmd) → \(headerResponse)")

            let queryResponse = await sendSingleOBDCommand(queryCmd, timeout: 2.5)
            logSystem("   Query:  \(queryCmd) → \(queryResponse)")

            let parsed = parseOilTempFromResponse(queryResponse, pid: queryCmd)
            let compact = queryResponse.uppercased()
            return OilTempProbeResult(
                rawResponse: queryResponse,
                parsedValue: parsed,
                success: parsed != nil,
                isNoData: compact.contains("NODATA") || compact.contains("NO DATA")
            )
        } else {
            let response = await sendSingleOBDCommand(cmd, timeout: 2.5)
            logSystem("   \(cmd) → \(response)")

            let parsed = parseOilTempFromResponse(response, pid: cmd)
            let compact = response.uppercased()
            return OilTempProbeResult(
                rawResponse: response,
                parsedValue: parsed,
                success: parsed != nil,
                isNoData: compact.contains("NODATA") || compact.contains("NO DATA")
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ELM327 Single Command Wrapper (async)
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    internal func sendSingleOBDCommand(_ cmd: String, timeout: TimeInterval) async -> String {
        return await withCheckedContinuation { continuation in
            sendSequence(cmds: [cmd], timeout: timeout) { response, _ in
                continuation.resume(returning: response.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    @MainActor
    private func resetELMHeader() async {
        _ = await sendSingleOBDCommand("ATSH7DF", timeout: 1.0)
        logSystem("   Header auf 7DF (Standard) zurückgesetzt")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Oil Temp Parsing für alle Methoden
    // ─────────────────────────────────────────────────────────────────────────

    /// Versucht aus einer rohen OBD-Antwort eine Öltemperatur (°C) zu parsen.
    /// Unterstützt: Mode 01 PID 5C, Mode 22 (VAG), Cluster-spezifisch, generisch.
    internal func parseOilTempFromResponse(_ raw: String, pid: String) -> Int? {
        let compact = raw.replacingOccurrences(of: " ", with: "").uppercased()

        guard !compact.isEmpty,
              !compact.contains("NODATA"),
              !compact.contains("ERROR"),
              !compact.contains("STOPPED"),
              !compact.contains("UNABLETOCONNECT") else { return nil }

        // Mode 01 PID 5C → 41 5C XX  (SAE Standard, -40 Offset)
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // Mode 22 1C1F → 62 1C 1F XX  (VAG, -40 Offset)
        if let range = compact.range(of: "621C1F") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // Mode 22 1140 → 62 11 40 XX  (VAG alternative)
        if let range = compact.range(of: "621140") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // Mode 22 F43C → 62 F4 3C XX  (ECU 7E0 direkt)
        if let range = compact.range(of: "62F43C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // Kombiinstrument 220C01 → 62 0C 01 XX
        // Cluster kann direkt °C (kein -40) oder mit -40 senden — beide prüfen
        if let range = compact.range(of: "620C01") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let tempOffset = Int(val) - 40
                let tempDirect = Int(val)
                if tempOffset >= -20 && tempOffset <= 160 { return tempOffset }
                if tempDirect >= 0 && tempDirect <= 150 { return tempDirect }
            }
        }

        // Generische Mode-22-Antwort (62 XX XX DATA) — wenn kein spezifischer PID-Match
        // Nach "62" suchen und PID-Bytes überspringen → Datenbytes lesen
        if let range = compact.range(of: "62") {
            let after = String(compact[range.upperBound...])
            // Überspringe 4 Hex-Chars (2x PID-Byte) → Datenbytes
            if after.count >= 6 {
                let dataPart = String(after.dropFirst(4).prefix(2))
                if let val = UInt8(dataPart, radix: 16) {
                    let temp = Int(val) - 40
                    if temp >= -20 && temp <= 160 { return temp }
                }
            }
        }

        return nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Auto-Erkennung im normalen Polling (passiv, ohne Polling-Unterbrechung)
    // ─────────────────────────────────────────────────────────────────────────

    /// Wird aus handleRawMessageReceived aufgerufen. Prüft ob eine eingehende Antwort
    /// einer Öltemperatur entspricht (VAG Mode 22 oder 015C) — ohne Polling zu stören.
    @MainActor
    public func checkForAutoOilTempInResponse(_ raw: String, commandSent: String) {
        guard tachoOilTempEnabled, tachoOilTempValue == nil, !isMeasuringTachoOilTemp else { return }

        // 015C im Standard-Polling
        if commandSent == "015C" || commandSent.hasSuffix("5C") {
            if let temp = parseOilTempFromResponse(raw, pid: commandSent) {
                tachoOilTempValue = temp
                tachoOilTempMethod = "OBD Standard PID 015C (Auto)"
                liveOilTemp = temp
                hasOilTempPID = true
                logSystem("✅ Öltemp auto-erkannt: \(temp)°C via 015C")
            }
        }

        // VAG Mode 22 Antworten (falls irgendwann abgefragt)
        let compact = raw.replacingOccurrences(of: " ", with: "").uppercased()
        if compact.contains("621C1F") || compact.contains("621140") || compact.contains("62F43C") {
            if let temp = parseOilTempFromResponse(raw, pid: commandSent) {
                tachoOilTempValue = temp
                tachoOilTempMethod = "VAG Mode 22 (Auto)"
                liveOilTemp = temp
                hasOilTempPID = true
                logSystem("✅ Öltemp auto-erkannt: \(temp)°C via VAG Mode 22")
            }
        }
    }
}
