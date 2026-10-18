// MARK: - OBDDataParser.swift
// Hex-Dekodierung, PID-Auswertung & Sensorberechnung für Bosch MED9.1
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Parsing & Protocol Analysis
    // ─────────────────────────────────────────────────────────────────────────

    internal func handleRawMessageReceived(_ raw: String) {
        let clean = raw.replacingOccurrences(of: "\r", with: " ")
                       .replacingOccurrences(of: "\n", with: " ")
                       .replacingOccurrences(of: ">", with: "")
                       .trimmingCharacters(in: .whitespaces)

        if let handler = pendingSequenceHandler {
            pendingSequenceHandler = nil
            handler(clean)
            return
        }

        logRx(clean.isEmpty ? raw : clean)

        // 1. Bordspannung (ATRV: z.B. "12.4V" oder "14.1V")
        // Nur auswerten wenn: wir gerade ATRV gesendet haben ODER es aussieht wie "12.4V"
        let isVoltageResponse = lastCommandSent == "ATRV" ||
            (clean.count < 12 && (clean.contains("V") || clean.contains("v")))
        if isVoltageResponse {
            let numStr = clean.replacingOccurrences(of: "V", with: "")
                              .replacingOccurrences(of: "v", with: "")
                              .replacingOccurrences(of: " ", with: "")
            if let v = Double(numStr), v > 5.0 && v < 20.0 {
                batteryVoltage = v
                let ign = v >= 11.8
                isIgnitionOn = ign
                if !ign && connectionState == .connected {
                    detailedStatus = "Zündung AUS (Batterie \(String(format: "%.1f", v))V)"
                }
            }
        }

        let compact = clean.replacingOccurrences(of: " ", with: "")

        // 2. ELM Version (ATI: z.B. "ELM327 v1.5")
        if compact.contains("ELM327") {
            elmFirmware = clean
        }

        // 3. Fehler-Meldungen des ELM327
        if compact.contains("UNABLETOCONNECT") {
            detailedStatus = "Keine Verbindung zum Steuergerät (Zündung an?)"
            return
        }
        if compact.contains("BUSINIT:ERROR") || compact.contains("BUSINITERROR") {
            detailedStatus = "CAN-Bus Initialisierungsfehler"
            return
        }

        // 4. Bitmaske unterstützter PIDs (Mode 01 00)
        if let range = compact.range(of: "4100") {
            let after = String(compact[range.upperBound...])
            if after.count >= 8 {
                let hex8 = String(after.prefix(8))
                decodeSupportedPIDs(hex8, offset: 1)
                if connectionState == .searchingECU {
                    connectionState = .connected
                    detailedStatus = "Verbunden (\(selectedProtocol.rawValue))"
                    logSystem("✔ Bosch MED9.1 Steuergerät hat geantwortet!")
                    NotificationCenter.default.post(name: .obdDidConnectECU, object: nil)
                }
            }
        }

        // 5. Kühlmitteltemperatur (PID 01 05)
        if let range = compact.range(of: "4105") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let tempC = Int(val) - 40
                liveCoolantTemp = tempC
            }
        }

        // 6. Motordrehzahl (PID 01 0C)
        if let range = compact.range(of: "410C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4,
               let b1 = UInt8(after.prefix(2), radix: 16),
               let b2 = UInt8(after.dropFirst(2).prefix(2), radix: 16) {
                let rpm = ((Int(b1) * 256) + Int(b2)) / 4
                liveRPM = rpm
            }
        }

        // 7. Saugrohrdruck MAP & Ladedruck (PID 01 0B)
        if let range = compact.range(of: "410B") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let mapKpa = Int(val)
                liveMAP = mapKpa
                let relativeKpa = max(0, mapKpa - liveBaro)
                liveBoostBar = Double(relativeKpa) / 100.0
            }
        }

        // 8. Öltemperatur (PID 01 5C)
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let oil = Int(val) - 40
                if oil >= -20 && oil <= 160 {
                    liveOilTemp = oil
                    hasOilTempPID = true
                    hasCheckedOilTempPID = true
                }
            }
        } else if (compact.contains("NODATA") || clean.contains("NO DATA")) &&
                  (lastCommandSent == "015C" || lastCommandSent.hasSuffix("5C")) {
            hasOilTempPID = false
            hasCheckedOilTempPID = true
        }

        // 9. Ansauglufttemperatur (PID 01 0F)
        if let range = compact.range(of: "410F") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveIAT = Int(val) - 40
            }
        }

        // 10. Luftmasse MAF (PID 01 10)
        if let range = compact.range(of: "4110") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4,
               let b1 = UInt8(after.prefix(2), radix: 16),
               let b2 = UInt8(after.dropFirst(2).prefix(2), radix: 16) {
                liveMAF = Double((Int(b1) * 256) + Int(b2)) / 100.0
            }
        }

        // 11. Geschwindigkeit (PID 01 0D)
        if let range = compact.range(of: "410D") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveSpeed = Int(val)
            }
        }

        // 12. Motorlast (PID 01 04)
        if let range = compact.range(of: "4104") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveEngineLoad = Int(Double(val) * 100.0 / 255.0)
            }
        }
    }

    private func decodeSupportedPIDs(_ hex8: String, offset: Int) {
        guard let mask = UInt32(hex8, radix: 16) else { return }
        for i in 0..<32 {
            let isSupported = (mask & (1 << (31 - i))) != 0
            let pidNum = offset + i
            let pidHex = String(format: "%02X", pidNum)
            if isSupported {
                supportedPIDs.insert("01\(pidHex)")
            }
        }
        logSystem("ℹ PID Matrix aktualisiert: \(supportedPIDs.count) PIDs unterstützt.")
    }
}
