// MARK: - OBDOilTempProber.swift
// Multi-Fallback Öltemperatur-Auslese für VW Golf 5 GTI (Bosch MED9.1 / EA113)
// ═══════════════════════════════════════════════════════════════════════════════
// STRATEGIE: Testet 18 verschiedene Methoden in Reihenfolge nach Wahrscheinlichkeit.
// Erste erfolgreiche Methode wird dauerhaft verwendet.
//
// UNTERSTÜTZTE FORMELN / DEKODIERUNG:
//  • 16-Bit Kelvin (0.1K Auflösung): (((A * 256) + B) - 2731) / 10
//  • 16-Bit 0.1°C mit -40 Offset:    (((A * 256) + B) / 10) - 40
//  • 16-Bit 0.1°C direkt:            ((A * 256) + B) / 10
//  • 8-Bit Standard mit -40 Offset:  A - 40
//  • 8-Bit Kombiinstrument direkt:   A (wenn im Bereich 45...150°C)
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation

extension OBDManager {

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Probe Methoden Definition (18 Methoden in Prioritätsreihenfolge)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Format: Einfacher String = direkter PID ohne Header-Wechsel
    ///         "CMD1||CMD2" = CMD1 senden (z.B. ATSH), dann CMD2 (Abfrage)
    ///         "PROTO:X||CMD" = Protokoll wechseln zu X, dann CMD senden
    internal static let oilTempProbeMethods: [OilTempProbeStatus] = [

        // ── 1. VW TP 2.0 Tacho (Adresse 0x17 + MWB 050) ★★★ ─────────────────
        // Öffnet VW TP 2.0 Kanal via CAN-ID 0x200 zum Kombiinstrument (0x17),
        // liest Messwertblock 50 (Ölsensor G266) direkt aus dem Tacho!
        OilTempProbeStatus(
            methodName: "VW TP 2.0 Tacho (0x17 + MWB 50 ★★★)",
            command: "TP20:17:32"
        ),

        // ── 2. VW TP 2.0 Motor (Adresse 0x01 + MWB 134) ★★★ ─────────────────
        // Öffnet VW TP 2.0 Kanal via CAN-ID 0x200 zum Motorsteuergerät (0x01),
        // liest Messwertblock 134 (Feld 1 = Öltemperatur G266)!
        OilTempProbeStatus(
            methodName: "VW TP 2.0 Motor (0x01 + MWB 134 ★★★)",
            command: "TP20:01:86"
        ),

        // ── 3. Cluster UDS Tacho (Adresse 0x714 + DID 0x202F ★★★) ───────────
        // Für weiße MFAs / Tachos mit UDS: Tx=0x714, Rx=0x77E, DID=0x202F (Öltemperatur)
        OilTempProbeStatus(
            methodName: "Cluster UDS (0x714 + DID 202F ★★★)",
            command: "ATSH714||ATCRA77E||22202F"
        ),

        // ── 4. SAE Standard PID 015C ────────────────────────────────────────
        OilTempProbeStatus(
            methodName: "OBD Standard 015C (SAE J1979)",
            command: "015C"
        ),

        // ── 2. VAG KWP2000 MWB 134 + Session 1089 (OBDeleven / VCDS Favorit ★★★) ──
        // Liest Block 134 (0x86) via KWP2000: Feld 1 = G266 Öltemperatur!
        OilTempProbeStatus(
            methodName: "KWP2000 MWB 134 + 1089 (OBDeleven/VCDS Block 134 ★★★)",
            command: "ATSH7E0||1089||2186"
        ),

        // ── 3. VAG KWP2000 MWB 134 direkt ──────────────────────────────────
        OilTempProbeStatus(
            methodName: "KWP2000 MWB 134 direkt (Block 134 ohne 1089)",
            command: "ATSH7E0||2186"
        ),

        // ── 4. VAG KWP2000 MWB 005 + Session 1089 ──────────────────────────
        OilTempProbeStatus(
            methodName: "KWP2000 MWB 005 + 1089 (Block 005 Motor/Öl)",
            command: "ATSH7E0||1089||2105"
        ),

        // ── 5. VAG KWP2000 MWB 005 direkt ──────────────────────────────────
        OilTempProbeStatus(
            methodName: "KWP2000 MWB 005 direkt",
            command: "ATSH7E0||2105"
        ),

        // ── 6. Kombiinstrument 0x760 + MWB 050 (Tacho-Ölsensor) ────────────
        OilTempProbeStatus(
            methodName: "Cluster 0x760 + MWB 050 (Tacho KWP2000 Geber)",
            command: "ATSH760||1089||2132"
        ),

        // ── 7. VAG Mode 22 DID 1106 mit ECU-Header 7E0 ─────────────────────
        // ★ HÄUFIGSTER MED9.1 Custom-PID in Torque Pro / VAG-Foren!
        // Liefert oft 2-Byte Kelvin oder 0.1°C
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1106 (Torque Pro MED9.1 Favorit ★)",
            command: "ATSH7E0||221106"
        ),

        // ── 3. VAG Mode 22 DID 115C mit ECU-Header 7E0 ─────────────────────
        // ★ WAHRSCHEINLICHSTE Standard-VAG Öltemp-Adresse
        // Response: 62 11 5C XX → temp = val - 40
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+115C (MED9.1 primär ★)",
            command: "ATSH7E0||22115C"
        ),

        // ── 4. VAG Mode 22 DID 11BE mit ECU-Header 7E0 ─────────────────────
        // Standard VAG UDS Öltemp (ReadDataByIdentifier)
        // 2-Byte Kelvin Formel: (((A*256)+B)-2731)/10
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+11BE (VAG UDS Standard)",
            command: "ATSH7E0||2211BE"
        ),

        // ── 5. VAG Mode 22 DID 1152 mit ECU-Header 7E0 ─────────────────────
        // Car Scanner VAG-Profil Standard für Öltemp
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1152 (Car Scanner VAG Profil)",
            command: "ATSH7E0||221152"
        ),

        // ── 6. VAG Mode 22 DID F43C mit ECU-Header 7E0 ─────────────────────
        // F43C ist auf vielen MED9.x und Bosch Steuergeräten aktiv
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F43C (MED9.1 F4-Familie)",
            command: "ATSH7E0||22F43C"
        ),

        // ── 7. VAG Mode 22 DID 1C1F ohne Header-Override ───────────────────
        // 1C1F ist PQ35 Instrument-Cluster Kanal
        OilTempProbeStatus(
            methodName: "VAG Mode22 1C1F (PQ35 Cluster-Kanal)",
            command: "221C1F"
        ),

        // ── 8. VAG ECU 7E0 + DID 1C1F ──────────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1C1F (mit ECU-Header)",
            command: "ATSH7E0||221C1F"
        ),

        // ── 9. VAG Mode 22 DID 1140 ────────────────────────────────────────
        // Alternativer VAG-Öltemp-DID (MED9.5 / MED9.1)
        OilTempProbeStatus(
            methodName: "VAG Mode22 1140 (alternativ)",
            command: "221140"
        ),

        // ── 10. VAG ECU 7E0 + DID 1140 ─────────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+1140 (mit ECU-Header)",
            command: "ATSH7E0||221140"
        ),

        // ── 11. VAG ECU 7E0 + DID 2002 ─────────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+2002 (Car Scanner Alt)",
            command: "ATSH7E0||222002"
        ),

        // ── 12. VAG Mode 22 DID F450 ───────────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F450 (F4xx alternativ)",
            command: "ATSH7E0||22F450"
        ),

        // ── 13. VAG Mode 22 DID F435 ───────────────────────────────────────
        OilTempProbeStatus(
            methodName: "VAG Mode22 7E0+F435 (F4xx Variante)",
            command: "ATSH7E0||22F435"
        ),

        // ── 14. Instrument Cluster über ISO-TP Adresse 0x760 ───────────────
        // ★ Offizielle VAG MK5 Kombiinstrument-Adresse (Kombi = 17)
        OilTempProbeStatus(
            methodName: "Cluster 0x760 + 221C1F (VAG MK5 Tacho ★)",
            command: "ATSH760||221C1F"
        ),

        // ── 15. Instrument Cluster über ISO-TP Adresse 0x730 ───────────────
        OilTempProbeStatus(
            methodName: "Cluster 0x730 + 221C1F (Tacho alternativ)",
            command: "ATSH730||221C1F"
        ),

        // ── 16. Instrument Cluster 0x7C4 ───────────────────────────────────
        OilTempProbeStatus(
            methodName: "Cluster 0x7C4 + 220C01 (Tacho Legacy)",
            command: "ATSH7C4||220C01"
        ),

        // ── 17. Broadcast 7DF + 015C (alle Steuergeräte antworten) ─────────
        OilTempProbeStatus(
            methodName: "Broadcast 7DF + 015C (alle ECUs)",
            command: "ATSH7DF||015C"
        ),

        // ── 18. Protocol 5 (KWP2000 Fast Init) + 015C ──────────────────────
        OilTempProbeStatus(
            methodName: "KWP2000 (ATSP5) + 015C (ISO 14230 Fallback)",
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

        // Spezialfall: VW TP 2.0 Handshake (z.B. "TP20:17:32" oder "TP20:01:86")
        if cmd.hasPrefix("TP20:") {
            return await probeWithVWTP20(method)
        }

        // Spezialfall: Protokoll-Wechsel (z.B. "PROTO:5||015C")
        if cmd.hasPrefix("PROTO:") {
            return await probeWithProtocolSwitch(method)
        }

        // Normalfall: Header-Switch oder verkettete Befehle (z.B. "ATSH7E0||1089||2186")
        if cmd.contains("||") {
            let parts = cmd.components(separatedBy: "||")
            guard !parts.isEmpty else {
                return OilTempProbeResult(rawResponse: "Ungültiger Befehl", parsedValue: nil, success: false, isNoData: false)
            }

            var lastResp = ""
            var lastCmd = ""
            for (idx, part) in parts.enumerated() {
                let isLast = (idx == parts.count - 1)
                let timeout: TimeInterval = isLast ? 2.5 : 1.5
                let resp = await sendSingleOBDCommand(part, timeout: timeout)
                logSystem("     → \(part): \(resp.prefix(35))")
                lastResp = resp
                lastCmd = part
                if !isLast {
                    try? await Task.sleep(nanoseconds: 60_000_000) // 60ms Pause in der Kette
                }
            }

            let parsed = parseOilTempFromResponse(lastResp, pid: lastCmd)
            let compact = lastResp.uppercased()
            return OilTempProbeResult(
                rawResponse: String(lastResp.prefix(80)),
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
    // MARK: VW TP 2.0 Handshake (Kombiinstrument 0x17 / Motor 0x01)
    // ═══════════════════════════════════════════════════════════════════════════

    @MainActor
    private func probeWithVWTP20(_ method: OilTempProbeStatus) async -> OilTempProbeResult {
        let parts = method.command.components(separatedBy: ":")
        guard parts.count == 3 else {
            return OilTempProbeResult(rawResponse: "Formatfehler", parsedValue: nil, success: false, isNoData: false)
        }
        let dest = parts[1].uppercased()   // "17" (Tacho) oder "01" (Motor)
        let block = parts[2].uppercased()  // "32" (MWB 50) oder "86" (MWB 134)

        logSystem("   [TP2.0] Starte VW TP 2.0 Handshake für Modul 0x\(dest)…")

        // 1. ELM327 für Raw CAN vorbereiten (Auto Formatting AUS, Active Mode)
        _ = await sendSingleOBDCommand("ATSP6", timeout: 1.5)
        _ = await sendSingleOBDCommand("ATCAF0", timeout: 1.5)
        _ = await sendSingleOBDCommand("ATAL", timeout: 1.5)
        _ = await sendSingleOBDCommand("ATCSM0", timeout: 1.5) // Silent Monitor AUS (aktives Senden + ACKs)

        // 2. Header auf VW Gateway (0x200) setzen
        _ = await sendSingleOBDCommand("ATSH200", timeout: 1.5)

        // 3. Empfangsfilter für Modul-Antwort (200 + Dest)
        let rxFilter = "2" + dest // z.B. 217 für Tacho 17, 201 für Motor 01
        _ = await sendSingleOBDCommand("ATCRA\(rxFilter)", timeout: 1.5)

        // 4. Kanalaufbau-Befehl senden: [Dest] C0 00 10 00 03 01
        let setupCmd = "\(dest) C0 00 10 00 03 01"
        let setupResp = await sendSingleOBDCommand(setupCmd, timeout: 2.5)
        logSystem("   [TP2.0] Gateway Setup: \(setupCmd) → \(setupResp)")

        let cleanSetup = setupResp.replacingOccurrences(of: " ", with: "")
                                  .replacingOccurrences(of: "\r", with: "")
                                  .replacingOccurrences(of: "\n", with: "")
                                  .uppercased()

        // Prüfung: Antwort muss D0 enthalten (Kanalbestätigung)
        guard cleanSetup.contains("D0") else {
            // Restore defaults
            _ = await sendSingleOBDCommand("ATCAF1", timeout: 1.0)
            _ = await sendSingleOBDCommand("ATAR", timeout: 1.0)
            _ = await sendSingleOBDCommand("ATSH7DF", timeout: 1.0)
            let isNoData = cleanSetup.contains("NODATA") || cleanSetup.contains("NO DATA") || cleanSetup.contains("?")
            return OilTempProbeResult(rawResponse: setupResp, parsedValue: nil, success: false, isNoData: isNoData)
        }

        logSystem("   [TP2.0] ✅ Kanal offen! Antwort: \(cleanSetup)")

        // 5. Dynamische Tx / Rx CAN-IDs ermitteln
        var txID = "740"
        var rxID = "300"

        if let d0Range = cleanSetup.range(of: "D0") {
            let afterD0 = String(cleanSetup[d0Range.upperBound...])
            if afterD0.count >= 8 {
                let rxL = String(afterD0.prefix(2))
                let rxH = String(afterD0.dropFirst(2).prefix(2))
                let txL = String(afterD0.dropFirst(4).prefix(2))
                let txH = String(afterD0.dropFirst(6).prefix(2))

                if let rxVal = UInt16(rxH + rxL, radix: 16), rxVal > 0 {
                    rxID = String(format: "%X", rxVal)
                }
                if let txVal = UInt16(txH + txL, radix: 16), txVal > 0 {
                    txID = String(format: "%X", txVal)
                }
            }
        }
        logSystem("   [TP2.0] Dynamische CAN-IDs: Tx=0x\(txID), Rx=0x\(rxID)")

        // 6. Header auf dynamische Tx-ID und Empfangsfilter auf Rx-ID
        _ = await sendSingleOBDCommand("ATSH\(txID)", timeout: 1.5)
        _ = await sendSingleOBDCommand("ATCRA\(rxID)", timeout: 1.5)

        // 7. TP 2.0 Parameter-Aushandlung (Opcode A0)
        let paramResp = await sendSingleOBDCommand("A0 0F 8A FF 32 FF 00", timeout: 2.0)
        logSystem("   [TP2.0] Parameter Setup: A0 → \(paramResp)")

        // 8. KWP2000 MWB Anfrage senden: 10 02 21 [Block]
        // Opcode 10 = Single Frame / First Frame in TP 2.0, 02 = 2 Bytes Länge, 21 = ReadLocalId
        var kwpResp = await sendSingleOBDCommand("10 02 21 \(block)", timeout: 2.5)
        logSystem("   [TP2.0] KWP2000 MWB \(block): 10 02 21 \(block) → \(kwpResp)")

        let cleanKwp = kwpResp.replacingOccurrences(of: " ", with: "").uppercased()
        if cleanKwp.contains("7F21") || cleanKwp.contains("NODATA") || cleanKwp.contains("NO DATA") {
            // Falls Modul vor MWB-Auslese eine Session benötigt (StartDiagnosticSession 10 89)
            logSystem("   [TP2.0] Teste Diagnose-Session (10 89)…")
            _ = await sendSingleOBDCommand("10 02 10 89", timeout: 2.0)
            try? await Task.sleep(nanoseconds: 80_000_000)
            kwpResp = await sendSingleOBDCommand("10 02 21 \(block)", timeout: 2.5)
            logSystem("   [TP2.0] KWP2000 MWB \(block) nach Session: → \(kwpResp)")
        }

        // 9. Restore defaults
        _ = await sendSingleOBDCommand("ATCAF1", timeout: 1.0)
        _ = await sendSingleOBDCommand("ATAR", timeout: 1.0)
        _ = await sendSingleOBDCommand("ATSH7DF", timeout: 1.0)

        // 10. Auswerten
        let parsed = parseOilTempFromResponse(kwpResp, pid: "21" + block)
                  ?? decodeVAGMeasuringBlock(kwpResp.replacingOccurrences(of: " ", with: ""))
        let compactKwp = kwpResp.uppercased()

        return OilTempProbeResult(
            rawResponse: kwpResp,
            parsedValue: parsed,
            success: parsed != nil,
            isNoData: compactKwp.contains("NODATA") || compactKwp.contains("NO DATA") || compactKwp.contains("?")
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
    // MARK: Universal Multi-Byte & Multi-Formel Temperatur-Dekodierer
    // ═══════════════════════════════════════════════════════════════════════════

    /// Nimmt die hexadezimalen Datenbytes einer ECU-Antwort entgegen und testet alle
    /// bekannten VAG / Bosch Dekodier-Formeln (16-Bit Kelvin, 16-Bit 0.1°C, 8-Bit -40, 8-Bit direkt).
    internal func decodeTemperatureBytes(_ hex: String) -> Int? {
        // ── 1. 16-Bit (2 Bytes = 4 Hex Chars) zuerst prüfen ─────────────────
        if hex.count >= 4, let word = UInt16(hex.prefix(4), radix: 16) {
            // Formel A: Kelvin mit 0.1K Auflösung: (((A*256)+B)-2731)/10
            // Bei 20°C: 2931 -> (2931-2731)/10 = 20
            // Bei 90°C: 3631 -> (3631-2731)/10 = 90
            // Gültiger Kelvin-Bereich: 2531 (-20°C) bis 4331 (+160°C)
            if word >= 2431 && word <= 4431 {
                let tempK = (Int(word) - 2731) / 10
                if tempK >= -20 && tempK <= 160 { return tempK }
            }

            // Formel B: 0.1°C Auflösung mit -40 Offset: ((word)/10) - 40
            // Bei 90°C: 1300 -> 130 - 40 = 90
            if word >= 200 && word <= 2000 {
                let tempOffset = (Int(word) / 10) - 40
                if tempOffset >= -20 && tempOffset <= 160 { return tempOffset }
            }

            // Formel C: 0.1°C Auflösung direkt: word / 10
            // Bei 90°C: 900 -> 90°C
            if word >= 300 && word <= 1600 {
                let tempDirect = Int(word) / 10
                if tempDirect >= 20 && tempDirect <= 160 { return tempDirect }
            }
        }

        // ── 2. 8-Bit (1 Byte = 2 Hex Chars) prüfen ───────────────────────────
        if hex.count >= 2, let byte = UInt8(hex.prefix(2), radix: 16) {
            // Standard OBD / VAG mit -40 Offset
            let tempOffset = Int(byte) - 40
            if tempOffset >= -20 && tempOffset <= 160 { return tempOffset }

            // Kombiinstrument direkt °C (ohne Offset, z.B. 45°C ... 150°C)
            if byte >= 45 && byte <= 150 {
                return Int(byte)
            }
        }

        return nil
    }

    /// Dekodiert VAG KWP2000 Messwertblöcke (Triple-Byte: [Type, ValA, ValB])
    /// Verwendet von OBDeleven & VCDS für Block 134, 005 und Kombiinstrument.
    internal func decodeVAGMeasuringBlock(_ hex: String) -> Int? {
        guard hex.count >= 4 else { return nil }

        // VAG Standard Triplett: Type (2 chars), ValA (2 chars), ValB (2 chars)
        if hex.count >= 6,
           let typeByte = UInt8(hex.prefix(2), radix: 16),
           let valA = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
           let valB = UInt8(hex.dropFirst(4).prefix(2), radix: 16) {

            // Type 0x05: Temperatur °C -> A * (B - 100) * 0.1
            if typeByte == 0x05 {
                let temp = Int(Double(valA) * (Double(valB) - 100.0) * 0.1)
                if temp >= -20 && temp <= 160 { return temp }
            }
            // Type 0x37: Temperatur direkt °C (A - 50 oder A)
            if typeByte == 0x37 || typeByte == 0x25 {
                let temp = Int(valA) - 50
                if temp >= -20 && temp <= 160 { return temp }
            }
        }

        // Direkte Bytes (ohne Type-Header)
        if let firstByte = UInt8(hex.prefix(2), radix: 16) {
            let tempOffset = Int(firstByte) - 40
            if tempOffset >= -20 && tempOffset <= 160 { return tempOffset }
            let tempOffset50 = Int(firstByte) - 50
            if tempOffset50 >= -20 && tempOffset50 <= 160 { return tempOffset50 }
            if firstByte >= 45 && firstByte <= 150 { return Int(firstByte) }
        }
        return nil
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: Oil Temp Parsing (unterstützt alle Antwortformate & DIDs)
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
            if let val = decodeTemperatureBytes(after) {
                return val
            }
        }

        // ── KWP2000 Mode 21 Messwertblöcke (61 86 = MWB 134, 61 05 = MWB 005, 61 32 = MWB 50) ──
        // OBDeleven & VCDS Protokoll für Geber G266 auf Golf 5 GTI EA113 Bosch MED9.1
        if let range = compact.range(of: "6186") {
            let dataPart = String(compact[range.upperBound...])
            if let temp = decodeVAGMeasuringBlock(dataPart) ?? decodeTemperatureBytes(dataPart) {
                return temp
            }
        }
        if let range = compact.range(of: "6105") {
            let dataPart = String(compact[range.upperBound...])
            if let temp = decodeVAGMeasuringBlock(dataPart) ?? decodeTemperatureBytes(dataPart) {
                return temp
            }
        }
        if let range = compact.range(of: "6132") {
            let dataPart = String(compact[range.upperBound...])
            if let temp = decodeVAGMeasuringBlock(dataPart) ?? decodeTemperatureBytes(dataPart) {
                return temp
            }
        }
        // Generisches Mode 21: "61" + 2 Hex Block-ID + Daten
        if let range = compact.range(of: "61") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4 {
                let dataPart = String(after.dropFirst(2))
                if let temp = decodeVAGMeasuringBlock(dataPart) ?? decodeTemperatureBytes(dataPart) {
                    return temp
                }
            }
        }

        // ── Mode 22 DIDs: Gezieltes Pattern-Matching ────────────────────────
        let knownDIDs = [
            "62202F",   // VAG UDS Tacho (Cluster 0x714, DID 0x202F)
            "621106",   // Torque Pro Favorit für MED9.1
            "62115C",   // VAG primär
            "6211BE",   // VAG UDS
            "621152",   // Car Scanner VAG
            "621C1F",   // Cluster Channel
            "621140",   // Alternativ
            "622002",   // Car Scanner Alt
            "62F43C",   // F4 Familie
            "62F450",
            "62F435",
            "620C01"    // Tacho Legacy
        ]

        for prefix in knownDIDs {
            if let range = compact.range(of: prefix) {
                let dataPart = String(compact[range.upperBound...])
                if let temp = decodeTemperatureBytes(dataPart) {
                    return temp
                }
            }
        }

        // ── Generisches Mode-22 Parsing: "62" + 4 Hex PID-Bytes + Daten ────
        // Falls eine andere Mode-22 DID geantwortet hat
        if let range = compact.range(of: "62") {
            let after = String(compact[range.upperBound...])
            // 4 Hex-Chars = 2 PID-Bytes überspringen → Datenbytes dekodieren
            if after.count >= 6 {
                let dataPart = String(after.dropFirst(4))
                if let temp = decodeTemperatureBytes(dataPart) {
                    return temp
                }
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
        let mode22Patterns = [
            "62202F", "621106", "62115C", "6211BE", "621152", "621C1F",
            "621140", "622002", "62F43C", "62F450", "62F435"
        ]
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
