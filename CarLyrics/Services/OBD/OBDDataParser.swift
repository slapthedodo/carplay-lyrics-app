// MARK: - OBDDataParser.swift
// Hex-Dekodierung, PID-Auswertung & Sensorberechnung für Bosch MED9.1
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import AVFoundation

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
                    if carPlayGatingEnabled && v < 11.6 {
                        Task { @MainActor in
                            self.carPlayDidDisconnect()
                        }
                    }
                }
            }
        }

        let compact = clean.replacingOccurrences(of: " ", with: "").uppercased()

        // 2. ELM Version (ATI: z.B. "ELM327 v1.5")
        if compact.contains("ELM327") {
            elmFirmware = clean
        }

        // 3. Fehler-Meldungen des ELM327
        if compact.contains("UNABLETOCONNECT") {
            detailedStatus = "Keine Verbindung zum Steuergerät (Zündung an?)"
            if carPlayGatingEnabled {
                let hasCarPlayScreen = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }
                let hasCarAudio = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
                if !hasCarPlayScreen && !hasCarAudio {
                    Task { @MainActor in
                        self.carPlayDidDisconnect()
                    }
                }
            }
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
                if let eff = effectiveOilTemp {
                    Task { @MainActor in
                        WarmupManager.shared.updateLiveOilTemp(eff)
                    }
                }
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
                hasMAPPID = true
                hasCheckedMAPPID = true
            }
        } else if (compact.contains("NODATA") || clean.contains("NO DATA")) &&
                  (lastCommandSent == "010B" || lastCommandSent.hasSuffix("0B")) {
            hasMAPPID = false
            hasCheckedMAPPID = true
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
                    Task { @MainActor in
                        WarmupManager.shared.updateLiveOilTemp(oil)
                    }
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
                let maf = Double((Int(b1) * 256) + Int(b2)) / 100.0
                liveMAF = maf

                // EA113 2.0 TFSI MAF-basierte Ladedruck-Schätzung
                // NUR wenn 010B kein gültiges Ergebnis liefert (hasMAPPID == false)
                if !hasMAPPID && liveRPM > 600 {
                    let iatK = Double((liveIAT ?? 20) + 273)
                    // Natürliche Ansaugluftmenge bei Atmosphärendruck (1 bar):
                    // Rho_Luft = 101.325/(0.287058 * iatK) kg/m3
                    // V_Zylinder = 1.984 L = 0.001984 m3
                    // Jeder Zylinder saugt bei 4-Takter alle 2 Umdrehungen -> RPM/120 Ansaugtakte/s
                    // vol.Eff. EA113 NA = 0.80 (konservativ)
                    let rhoAir = 101.325 / (0.287058 * iatK)
                    let baseAirflowNA = (Double(liveRPM) / 120.0) * 0.001984 * rhoAir * 0.80 * 1000.0 // g/s
                    if baseAirflowNA > 1.0 {
                        let ratio = maf / baseAirflowNA
                        // ratio > 1.0 bedeutet Aufladung, ratio - 1.0 = Ladedruck in bar (grob)
                        let boostEst = max(0.0, ratio - 1.0)
                        liveBoostBar = Double(round(boostEst * 100) / 100)
                        liveMAP = Int(101.3 * max(0.2, ratio))
                    } else {
                        liveBoostBar = 0.0
                        liveMAP = 101
                    }
                }
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
                let load = Int(Double(val) * 100.0 / 255.0)
                liveEngineLoad = load
                if liveBoostBar == nil || liveBoostBar == 0.0 {
                    if liveRPM > 2000 && load > 75 {
                        let est = Double(load - 75) / 25.0 * 0.9
                        liveBoostBar = Double(round(est * 50) / 50)
                    }
                }
            }
        }

        // 13. Drosselklappe / Gaspedal (PID 01 11)
        if let range = compact.range(of: "4111") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                throttlePosition = Int(Double(val) * 100.0 / 255.0)
            }
        }

        // Thermische EGT-Glättung und Kaltstart-Überlastungsprüfung
        updateThermalEGT()
        checkColdEngineOverload()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: EGT Modell mit thermischer Trägheit (PT1-Glied)
    // ─────────────────────────────────────────────────────────────────────────

    public func updateThermalEGT() {
        guard isEnabled, connectionState == .connected else {
            liveEGT = nil
            smoothedEGT = nil
            return
        }

        let iat = Double(liveIAT ?? 20)
        let rpmFactor = Double(liveRPM) / 80.0
        let loadFactor = Double(liveEngineLoad ?? 20) * 5.2
        let boostFactor = (liveBoostBar ?? 0.0) * 120.0
        let targetEGT = min(920.0, max(220.0, iat + 180.0 + rpmFactor + loadFactor + boostFactor))

        if let prev = smoothedEGT {
            // Thermische Trägheit: Gusseisenkrümmer & K03 Gehäuse erwärmen sich schnell, kühlen langsam ab
            let alpha = targetEGT > prev ? 0.08 : 0.035
            let next = prev + alpha * (targetEGT - prev)
            smoothedEGT = next
            liveEGT = Int(next.rounded())
        } else {
            smoothedEGT = targetEGT
            liveEGT = Int(targetEGT.rounded())
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Kaltstart-Überlastungsschutz (Visual / Haptic Alert)
    // ─────────────────────────────────────────────────────────────────────────

    public func checkColdEngineOverload() {
        guard isEnabled, connectionState == .connected else {
            if isColdOverloaded {
                isColdOverloaded = false
                coldOverloadMessage = ""
                coldOverloadDetail = ""
            }
            return
        }

        let temp = effectiveOilTemp ?? liveCoolantTemp ?? 20
        let rpm = liveRPM
        let load = liveEngineLoad ?? 0
        let boost = liveBoostBar ?? 0.0

        // Stufe 1: MOTOR KALT (Öl < 60°C)
        if temp < 60 {
            if rpm > 2800 {
                setColdOverload(
                    title: "DREHZAHL ZU HOCH!",
                    detail: "\(rpm) U/min bei kaltem Öl (\(temp)°C) • Bitte unter 2.500 U/min bleiben!"
                )
                return
            }
            if load > 55 {
                setColdOverload(
                    title: "ZU VIEL MOTORLAST!",
                    detail: "\(load)% Last bei kaltem Öl (\(temp)°C) • Bitte sanfter beschleunigen!"
                )
                return
            }
            if boost > 0.15 {
                setColdOverload(
                    title: "KEIN LADEDRUCK BEI KALTSTART!",
                    detail: String(format: "%.2f bar bei %d°C Öl • Turbolader schonen!", boost, temp)
                )
                return
            }
        }
        // Stufe 2: WARMFAHREN (Öl 60°C – 79°C)
        else if temp < 80 {
            if rpm > 3800 {
                setColdOverload(
                    title: "MOTOR NOCH NICHT BETRIEBSWARM",
                    detail: "\(rpm) U/min bei \(temp)°C Öl • Max. 3.500 U/min bis 80°C!"
                )
                return
            }
            if load > 75 {
                setColdOverload(
                    title: "HOHE MOTORLAST VOR 80°C",
                    detail: "\(load)% Last bei \(temp)°C Öl • Noch etwas Geduld!"
                )
                return
            }
            if boost > 0.65 {
                setColdOverload(
                    title: "LADEDRUCK ÜBER 0.6 BAR",
                    detail: String(format: "%.2f bar bei %d°C Öl • Vollen Ladedruck erst ab 80°C!", boost, temp)
                )
                return
            }
        }

        // Entwarnung wenn Last und Drehzahl wieder im schonenden Bereich
        if isColdOverloaded {
            isColdOverloaded = false
            coldOverloadMessage = ""
            coldOverloadDetail = ""
        }
    }

    private func setColdOverload(title: String, detail: String) {
        if !isColdOverloaded {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        isColdOverloaded = true
        coldOverloadMessage = title
        coldOverloadDetail = detail
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
