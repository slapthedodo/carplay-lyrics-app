// MARK: - OBDOilTempProber.swift
// Multi-Fallback Öltemperatur-Auslese für VW Golf 5 GTI (Bosch MED9.1 / EA113)
// ═══════════════════════════════════════════════════════════════════════════════
// STRATEGIE: Testet 15 verschiedene Methoden in Reihenfolge nach Wahrscheinlichkeit.
// Erste erfolgreiche Methode wird dauerhaft verwendet.
//
// METHODEN-ÜBERSICHT:
//  1.  OBD Standard PID 015C            (SAE J1979 Mode 01)
//  2.  VAG Mode 22 DID 115C             (MED9.1 extended, häufigste VAG Öltemp)
//  3.  VAG Mode 22 DID 1C1F             (Instrument Cluster Channel)
//  4.  VAG Mode 22 DID 1140             (MED9.x alternativ)
//  5.  VAG ECU 7E0 + Mode22 F43C        (MED9.1 direkt via ISO-TP)
//  6.  VAG ECU 7E0 + Mode22 F450        (Alternative F4xx Familie)
//  7.  VAG ECU 7E0 + Mode22 F435        (Weitere F4xx Variante)
//  8.  VAG ECU 7E0 + Mode22 0623        (Bosch Messgruppe 005 Äquivalent)
//  9.  VAG ECU 7E0 + Mode22 2101        (Manufacturer Specific Mode 21 equiv)
// 10.  Instrument Cluster 0x760 + 1C1F  (Standard VAG Cluster CAN-ISO-TP)
// 11.  Instrument Cluster 0x730 + 1C1F  (Alternative Cluster Adresse)
// 12.  Instrument Cluster 0x7C4 + 0C01  (Legacy Cluster Adresse)
// 13.  Broadcast 7DF + 015C             (Alle ECUs)
// 14.  KWP2000 Protocol + 015C          (Falls ECU auf ISO 14230 reagiert)
// 15.  CAN Monitor Capture              (Passives Belauschen von CAN Frames)
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation

extension OBDManager {

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Probe Methoden Definition (15 Methoden in Prioritätsreihenfolge)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Format: Einfacher String = direkter PID ohne Header-Wechsel
    ///         "CMD1||CMD2" = CMD1 senden (z.B. ATSH), dann CMD2 (Abfrage)
    ///         "PROTO:X||CMD" = Protokoll wechseln zu X, dann CMD senden
    internal static let oilTempProbeMethods: [OilTempProbeStatus] = [

        // ── Methode 1: SAE Standard PID 015C ────────────────────────────────
        // Einfachste Methode. MED9.1 gibt das oft per NODATA zurück,
        // aber es ist immer der erste Versuch wert.
        OilTempProbeStatus(
            methodName: "OBD Standard 015C (SAE J1979)",
            command: "015C"
        ),

        // ── Methode 2: VAG Mode 22 DID 115C mit ECU-Header 7E0 ─────────────
        // **WAHRSCHEINLICHSTE METHODE für MED9.1**
        // DID 0x115C ist der bekannteste VAG-spezifische Öltemp-PID.
        // Response: 62 11 5C XX → temp = val - 40
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+115C (MED9.1 primär)",
            command: "ATSH7E0||22115C"
        ),

        // ── Methode 3: VAG Mode 22 DID F43C mit ECU-Header 7E0 ─────────────
        // F43C ist der zweit-häufigste VAG Öltemp-DID auf MED9.x ECUs.
        // Response: 62 F4 3C XX → temp = val - 40
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F43C (MED9.1 F4-Familie)",
            command: "ATSH7E0||22F43C"
        ),

        // ── Methode 4: VAG Mode 22 DID 1C1F ohne Header-Override ───────────
        // 1C1F ist ein VAG-Instrument-Cluster-Kanal der oft vom ECU
        // beantwortet wird. Gut dokumentiert für PQ35-Plattform.
        // Response: 62 1C 1F XX → temp = val - 40
        OilTempProbeStatus(
            methodName: "VAG Mode22 1C1F (PQ35 Cluster-Kanal)",
            command: "221C1F"
        ),

        // ── Methode 5: VAG Mode 22 DID 1140 ────────────────────────────────
        // Alternativer VAG-Öltemp-DID, bekannt von MED9.5 aber auch MED9.1.
        // Response: 62 11 40 XX → temp = val - 40
        OilTempProbeStatus(
            methodName: "VAG Mode22 1140 (alternativ)",
            command: "221140"
        ),

        // ── Methode 6: VAG ECU 7E0 + DID 1C1F ──────────────────────────────
        // Gleiche DID wie Methode 4, aber explizit mit ECU-Header 7E0.
        // Manche ELM327-Adapter brauchen den expliziten Header.
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1C1F (mit Header)",
            command: "ATSH7E0||221C1F"
        ),

        // ── Methode 7: VAG ECU 7E0 + DID 1140 ──────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1140 (mit Header)",
            command: "ATSH7E0||221140"
        ),

        // ── Methode 8: VAG Mode 22 DID F450 ────────────────────────────────
        // Weitere F4xx-Familie. Bosch MED9 verwendet F4xx-Range für
        // viele Sensordaten. F450 ist auf einigen EA113 Varianten.
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F450 (F4xx alternativ)",
            command: "ATSH7E0||22F450"
        ),

        // ── Methode 9: VAG Mode 22 DID F435 ────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F435 (F4xx Variante)",
            command: "ATSH7E0||22F435"
        ),

        // ── Methode 10: Instrument Cluster über ISO-TP Adresse 0x760 ────────
        // Standard VAG Kombiinstrument ISO-TP Diagnose-Adresse für PQ35.
        // 0x760 = Request, 0x768 = Response (typisch VAG MK5).
        // DID 0x1C1F ist der Cluster-Kanal für Öltemp.
        OilTempProbeStatus(
            methodName: "Cluster 0x760 + 221C1F (VAG MK5 Standard)",
            command: "ATSH760||221C1F"
        ),

        // ── Methode 11: Instrument Cluster über ISO-TP Adresse 0x730 ────────
        // Alternative Cluster-Adresse für einige VAG MK5 Varianten.
        OilTempProbeStatus(
            methodName: "Cluster 0x730 + 221C1F (VAG alternativ)",
            command: "ATSH730||221C1F"
        ),

        // ── Methode 12: Instrument Cluster 0x7C4 (Legacy) ───────────────────
        // Einige ältere ELM327-Guides nennen 0x7C4 für den Cluster.
        // Das könnte eine CAN-Broadcast-ID sein, kein Diagnose-Request.
        OilTempProbeStatus(
            methodName: "Cluster 0x7C4 + 220C01 (legacy)",
            command: "ATSH7C4||220C01"
        ),

        // ── Methode 13: Broadcast 7DF + 015C (alle ECUs antworten) ──────────
        // 7DF ist der OBD-Funktional-Header — alle ECUs im Netz antworten.
        // Falls irgendeiner der ECUs 015C kennt, gibt er hier Antwort.
        OilTempProbeStatus(
            methodName: "Broadcast 7DF + 015C (alle ECUs)",
            command: "ATSH7DF||015C"
        ),

        // ── Methode 14: Bosch Messgruppe 0623 ───────────────────────────────
        // In VCDS ist Öltemp in Steuergerät 01 (Motor), Messgruppe 005.
        // Die nächste Annäherung via Mode 22 könnte DID 0x0623 sein
        // (Messgruppe 06, Byte 23 — Bosch-interne Nomenklatur).
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+0623 (Messgruppe 005 equiv)",
            command: "ATSH7E0||220623"
        ),

        // ── Methode 15: Protocol 5 (KWP2000 Fast Init) + 015C ───────────────
        // Falls das ELM327 auf CAN nicht reagiert, KWP2000 versuchen.
        // ATSP5 = ISO 14230-4 KWP (5 baud init), ATSP5 = fast init.
        // Nach dem Test: Protokoll wieder zurück auf SP6 (CAN).
        // Format: "PROTO:5||015C" = speziell verarbeiteter Befehl
        OilTempProbeStatus(
            methodName: "KWP2000 (ATSP5) + 015C (ISO 14230)",
            command: "PROTO:5||015C"
        ),
    ]

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Haupt-Probe Funktion
    // ═══════════════════════════════════════════════════════════════════════════

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

        logSystem("🌡 Starte Öltemp-Probe: \(OBDManager.oilTempProbeMethods.count) Methoden werden getestet…")

        // Polling pausieren während Probe-Befehle gesendet werden
        let wasPolling = isPollingActive
        if wasPolling {
            stopPolling()
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms Stabilisierung
        }

        // Originales Protokoll sichern (SP6 = CAN)
        let originalProtocol = currentElmProtocol ?? "ATSP6"

        for i in tachoOilTempProbeStatus.indices {
            tachoOilTempProbeStatus[i].status = .testing
            let method = tachoOilTempProbeStatus[i]

            logSystem("  [\(i+1)/\(tachoOilTempProbeStatus.count)] Teste: \(method.methodName)")

            let result = await probeOilTempMethod(method)

            tachoOilTempProbeStatus[i].rawResponse = result.rawResponse
            tachoOilTempProbeStatus[i].parsedValue = result.parsedValue
            tachoOilTempProbeStatus[i].status = result.success ? .success :
                                                (result.isNoData ? .noData : .failed)

            if result.success, let temp = result.parsedValue {
                // ✅ Erfolg! Echten Wert speichern und aufhören.
                tachoOilTempValue = temp
                tachoOilTempMethod = method.methodName
                liveOilTemp = temp
                hasOilTempPID = true
                hasCheckedOilTempPID = true
                logSystem("✅ Öltemp: \(temp)°C via '\(method.methodName)'")

                // Restliche auf .pending lassen
                for j in (i + 1)..<tachoOilTempProbeStatus.count {
                    tachoOilTempProbeStatus[j].status = .pending
                }
                break
            }

            // Kurze Pause zwischen Methoden (ELM327 braucht Zeit)
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        // ── Aufräumen: Header + Protokoll zurücksetzen ───────────────────────
        await restoreELMDefaults(protocol: originalProtocol)

        if wasPolling {
            try? await Task.sleep(nanoseconds: 150_000_000)
            startPolling()
        }

        isMeasuringTachoOilTemp = false

        if tachoOilTempValue == nil {
            logSystem("❌ Öltemp: Alle \(OBDManager.oilTempProbeMethods.count) Methoden fehlgeschlagen.")
            logSystem("   Motor läuft? Zündung an? ELM327 richtig verbunden?")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Einzelne Methode testen
    // ═══════════════════════════════════════════════════════════════════════════

    private struct OilTempProbeResult {
        let rawResponse: String
        let parsedValue: Int?
        let success: Bool
        let isNoData: Bool
    }

    @MainActor
    private func probeOilTempMethod(_ method: OilTempProbeStatus) async -> OilTempProbeResult {
        let cmd = method.command

        // Spezialfall: Protokoll-Wechsel (z.B. "PROTO:5||015C")
        if cmd.hasPrefix("PROTO:") {
            return await probeWithProtocolSwitch(method)
        }

        // Normalfall: Header-Switch oder direkter PID
        if cmd.contains("||") {
            let parts = cmd.components(separatedBy: "||")
            guard parts.count == 2 else {
                return OilTempProbeResult(rawResponse: "Ungültiger Befehl", parsedValue: nil, success: false, isNoData: false)
            }
            let headerCmd = parts[0]
            let queryCmd  = parts[1]

            let headerResp = await sendSingleOBDCommand(headerCmd, timeout: 1.5)
            logSystem("     → \(headerCmd): \(headerResp.prefix(20))")

            let queryResp = await sendSingleOBDCommand(queryCmd, timeout: 2.5)
            logSystem("     → \(queryCmd): \(queryResp.prefix(40))")

            let parsed = parseOilTempFromResponse(queryResp, pid: queryCmd)
            let compact = queryResp.uppercased()
            return OilTempProbeResult(
                rawResponse: String(queryResp.prefix(80)),
                parsedValue: parsed,
                success: parsed != nil,
                isNoData: compact.contains("NODATA") || compact.contains("NO DATA")
            )
        } else {
            // Direkter PID ohne Header-Änderung
            let resp = await sendSingleOBDCommand(cmd, timeout: 2.5)
            logSystem("     → \(cmd): \(resp.prefix(40))")

            let parsed = parseOilTempFromResponse(resp, pid: cmd)
            let compact = resp.uppercased()
            return OilTempProbeResult(
                rawResponse: String(resp.prefix(80)),
                parsedValue: parsed,
                success: parsed != nil,
                isNoData: compact.contains("NODATA") || compact.contains("NO DATA")
            )
        }
    }

    /// Protokoll-Wechsel Probe: Schaltet auf KWP2000, fragt PID, stellt CAN wieder her
    @MainActor
    private func probeWithProtocolSwitch(_ method: OilTempProbeStatus) async -> OilTempProbeResult {
        let parts = method.command.components(separatedBy: "||")
        guard parts.count == 2 else {
            return OilTempProbeResult(rawResponse: "Ungültig", parsedValue: nil, success: false, isNoData: false)
        }
        let protoStr = parts[0] // z.B. "PROTO:5"
        let queryCmd = parts[1] // z.B. "015C"

        let protoNum = protoStr.replacingOccurrences(of: "PROTO:", with: "")
        let atspCmd  = "ATSP\(protoNum)"

        // Protokoll wechseln
        let protoResp = await sendSingleOBDCommand(atspCmd, timeout: 2.0)
        logSystem("     Protokoll \(atspCmd): \(protoResp.prefix(20))")
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms warten nach Protokollwechsel

        // PID abfragen
        let queryResp = await sendSingleOBDCommand(queryCmd, timeout: 3.0)
        logSystem("     → \(queryCmd): \(queryResp.prefix(40))")

        // Zurück auf CAN (SP6)
        _ = await sendSingleOBDCommand("ATSP6", timeout: 2.0)
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms warten nach Rückkehr zu CAN

        let parsed = parseOilTempFromResponse(queryResp, pid: queryCmd)
        let compact = queryResp.uppercased()
        return OilTempProbeResult(
            rawResponse: String(queryResp.prefix(80)),
            parsedValue: parsed,
            success: parsed != nil,
            isNoData: compact.contains("NODATA") || compact.contains("NO DATA")
        )
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: ELM327 Helpers (async)
    // ═══════════════════════════════════════════════════════════════════════════

    @MainActor
    internal func sendSingleOBDCommand(_ cmd: String, timeout: TimeInterval) async -> String {
        return await withCheckedContinuation { continuation in
            sendSequence(cmds: [cmd], timeout: timeout) { response, _ in
                continuation.resume(returning: response.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Setzt ELM327 auf sichere Defaults zurück (Header 7DF, Protokoll SP6)
    @MainActor
    private func restoreELMDefaults(protocol originalProto: String) async {
        _ = await sendSingleOBDCommand("ATSH7DF", timeout: 1.0)
        _ = await sendSingleOBDCommand(originalProto, timeout: 1.5)
        logSystem("   ELM327 zurückgesetzt: Header=7DF, Proto=\(originalProto)")
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Oil Temp Parsing (unterstützt alle Antwortformate)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Versucht aus einer rohen OBD-Antwort eine plausible Öltemperatur (°C) zu parsen.
    /// Unterstützt: Mode 01 PID 5C, alle bekannten Mode 22 DIDs (VAG), generisch.
    internal func parseOilTempFromResponse(_ raw: String, pid: String) -> Int? {
        let compact = raw.replacingOccurrences(of: " ", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\n", with: "")
                         .uppercased()

        // Frühe Ausschlüsse: Fehlermeldungen
        guard !compact.isEmpty else { return nil }
        let errorWords = ["NODATA", "ERROR", "STOPPED", "UNABLETOCONNECT",
                          "CANERROR", "BUSBUSY", "BUSERROR", "LVRESET", "?"]
        for word in errorWords {
            if compact.contains(word) { return nil }
        }

        // ── Mode 01 PID 5C → Antwort: 41 5C XX (-40 Offset) ────────────────
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID 115C → Antwort: 62 11 5C XX (-40 Offset) ───────────
        if let range = compact.range(of: "62115C") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID 1C1F → Antwort: 62 1C 1F XX (-40 Offset) ───────────
        if let range = compact.range(of: "621C1F") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID 1140 → Antwort: 62 11 40 XX (-40 Offset) ───────────
        if let range = compact.range(of: "621140") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID F43C → Antwort: 62 F4 3C XX (-40 Offset) ───────────
        if let range = compact.range(of: "62F43C") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID F450 → Antwort: 62 F4 50 XX ────────────────────────
        if let range = compact.range(of: "62F450") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID F435 → Antwort: 62 F4 35 XX ────────────────────────
        if let range = compact.range(of: "62F435") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Mode 22 DID 0623 → Antwort: 62 06 23 XX ────────────────────────
        if let range = compact.range(of: "620623") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let temp = Int(val) - 40
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // ── Generisches Mode-22 Parsing: "62" + 4 Hex PID-Bytes + Datenbytes ─
        // Fällt hier hin wenn kein spezifischer PID-Match oben greift.
        // Versuche alle "62 XX XX" Präfixe die wir gesendet haben zu matchen.
        if let range = compact.range(of: "62") {
            let after = String(compact[range.upperBound...])
            // 4 Hex-Chars = 2 PID-Bytes überspringen → Datenbyte lesen
            if after.count >= 6 {
                let dataByte = String(after.dropFirst(4).prefix(2))
                if let val = UInt8(dataByte, radix: 16) {
                    let tempWithOffset = Int(val) - 40
                    if tempWithOffset >= -20 && tempWithOffset <= 160 { return tempWithOffset }
                    // Manche Cluster senden ohne -40 Offset (direktes °C)
                    if val >= 50 && val <= 150 { return Int(val) }
                }
            }
        }

        // ── Kombiinstrument spezifisch: 220C01 → 62 0C 01 XX ───────────────
        if let range = compact.range(of: "620C01") {
            let after = String(compact[range.upperBound...])
            if let val = UInt8(after.prefix(2), radix: 16) {
                let tempOffset = Int(val) - 40
                let tempDirect = Int(val)
                if tempOffset >= -20 && tempOffset <= 160 { return tempOffset }
                if tempDirect >= 0 && tempDirect <= 150 { return tempDirect }
            }
        }

        return nil
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Auto-Erkennung im normalen Polling (passiv, ohne Polling-Unterbrechung)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Passives Erkennen der Öltemp aus dem normalen Polling-Datenstrom.
    /// Wird aufgerufen wenn handleRawMessageReceived eine Antwort auf bekannte
    /// Öltemp-PIDs erhält — ohne dass startTachoOilTempProbe() laufen muss.
    @MainActor
    public func checkForAutoOilTempInResponse(_ raw: String, commandSent: String) {
        guard tachoOilTempEnabled, tachoOilTempValue == nil, !isMeasuringTachoOilTemp else { return }

        let compact = raw.replacingOccurrences(of: " ", with: "").uppercased()

        // 015C im normalen Polling (wenn ECU es doch unterstützt)
        if commandSent == "015C" || commandSent.hasSuffix("5C") {
            if let temp = parseOilTempFromResponse(raw, pid: commandSent) {
                tachoOilTempValue = temp
                tachoOilTempMethod = "OBD Standard 015C (auto im Polling)"
                liveOilTemp = temp
                hasOilTempPID = true
                logSystem("✅ Öltemp auto-erkannt: \(temp)°C via 015C")
            }
        }

        // VAG Mode 22 Antworten (falls durch anderen Code ausgelöst)
        let mode22Patterns = ["62115C", "621C1F", "621140", "62F43C", "62F450", "62F435"]
        for pattern in mode22Patterns {
            if compact.contains(pattern) {
                if let temp = parseOilTempFromResponse(raw, pid: commandSent) {
                    tachoOilTempValue = temp
                    tachoOilTempMethod = "VAG Mode22 \(pattern) (auto)"
                    liveOilTemp = temp
                    hasOilTempPID = true
                    logSystem("✅ Öltemp auto-erkannt: \(temp)°C via \(pattern)")
                    return
                }
            }
        }
    }
}
