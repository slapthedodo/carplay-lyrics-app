// MARK: - OBDManager.swift
// CarLyrics – CoreBluetooth BLE Client für ELM327 / OBD2 Bluetooth Adapter.
// Speziell optimiert für Low-Cost ELM327 Mini BLE Adapter (z.B. Allstric / V-Gate)
// mit automatischem Fallback für VW 2.0 TFSI Motoren.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import CoreBluetooth
import Combine

public enum OBDConnectionState: String {
    case disconnected = "Getrennt"
    case scanning     = "Suche nach OBD-Adapter…"
    case connecting   = "Verbinde mit Adapter…"
    case initializing = "Initialisiere ELM327…"
    case connected    = "Verbunden & Aktiv"
    case error        = "Fehler"
}

@MainActor
public final class OBDManager: NSObject, ObservableObject {

    public static let shared = OBDManager()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published State
    // ─────────────────────────────────────────────────────────────────────────

    private static let obdEnabledKey = "carlyrics_obd_enabled"

    @Published public var connectionState : OBDConnectionState = .disconnected
    @Published public var isEnabled       : Bool = UserDefaults.standard.bool(forKey: "carlyrics_obd_enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.obdEnabledKey)
        }
    }
    @Published public var liveOilTemp     : Int? = nil           // PID 01 5C (wenn unterstützt)
    @Published public var liveCoolantTemp : Int? = nil           // PID 01 05 (immer bei VW)
    @Published public var liveRPM         : Int  = 0             // PID 01 0C
    @Published public var liveSpeed       : Int  = 0             // PID 01 0D
    @Published public var liveBoostBar    : Double? = nil        // Berechneter Ladedruck in Bar (PID 01 0B - Baro)
    @Published public var liveMAP         : Int? = nil           // Saugrohr-Absolutdruck in kPa (PID 01 0B)
    @Published public var liveIAT         : Int? = nil           // Ansauglufttemperatur in °C (PID 01 0F)
    @Published public var liveMAF         : Double? = nil        // Luftmasse in g/s (PID 01 10)
    @Published public var liveEngineLoad  : Int? = nil           // Motorlast in % (PID 01 04)
    @Published public var liveBaro        : Int  = 101           // Atmosphärendruck in kPa (PID 01 33 oder 101.3 kPa)
    @Published public var hasOilTempPID   : Bool = false         // Wurde PID 01 5C quittiert?
    @Published public var debugLogs       : [String] = []

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: CoreBluetooth & State
    // ─────────────────────────────────────────────────────────────────────────

    private var centralManager : CBCentralManager!
    private var peripheral     : CBPeripheral?
    private var txChar         : CBCharacteristic?
    private var rxChar         : CBCharacteristic?

    // Bekannte BLE-UART Services für billige ELM327/Allstric Klone
    private let serviceUUIDs: [CBUUID] = [
        CBUUID(string: "FFF0"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "18F0"),
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART
        CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
    ]

    private var pollTimer               : Timer?
    private var initStepTimer           : Timer?
    private var connectionWatchdogTimer : Timer?
    private var receiveBuffer           : String = ""
    private var currentPIDIndex         : Int = 0
    private var isInitializingUART      : Bool = false
    private var initQueue               : [String] = []
    private var isWaitingForResponse    : Bool = false
    private var lastCommandSentTime     : Date = .distantPast
    // VAG EA113 Bosch MED 9.1 Zyklus (KWP2000 / ISO 9141):
    // Alle Standard OBD-II Mode 01 PIDs — die auf diesem Steuergerät wirklich antworten.
    // PID 01 5C (Öltemperatur) ist auf KWP2000-Steuergeräten oft NICHT implementiert.
    // Wenn er keine Antwort gibt, springt das thermische EA113-Modell automatisch ein.
    private let queryCycle: [String] = [
        "0105",     // Kühlmitteltemperatur in °C
        "010C",     // Motordrehzahl RPM
        "010F",     // Ansauglufttemperatur (IAT) in °C
        "0110",     // Luftmasse (MAF) in g/s
        "010B",     // Saugrohr-Absolutdruck (MAP) in kPa -> Ladedruck
        "015C",     // Öltemperatur (PID 01 5C) — auf EA113 oft NO DATA, aber versuchen
        "010D",     // Geschwindigkeit in km/h
        "0104"      // Motorlast in %
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public override init() {
        super.init()
        let saved = UserDefaults.standard.bool(forKey: Self.obdEnabledKey)
        self.isEnabled = saved
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func enableOBD() {
        isEnabled = true
        resetTelemetryValues()
        startScan()
    }

    public func disableOBD() {
        isEnabled = false
        stopScan()
        initStepTimer?.invalidate()
        connectionWatchdogTimer?.invalidate()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionState = .disconnected
        resetTelemetryValues()
    }

    public func reconnect() {
        log("🔄 Manueller Reconnect angefordert…")
        initStepTimer?.invalidate()
        connectionWatchdogTimer?.invalidate()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        self.peripheral = nil
        txChar = nil
        rxChar = nil
        resetTelemetryValues()
        if isEnabled {
            startScan()
        }
    }

    public func resetTelemetryValues() {
        liveOilTemp = nil
        liveCoolantTemp = nil
        liveBoostBar = nil
        liveMAP = nil
        liveIAT = nil
        liveMAF = nil
        liveEngineLoad = nil
        liveRPM = 0
        liveSpeed = 0
        hasOilTempPID = false
        isInitializingUART = false
        initQueue.removeAll()
        isWaitingForResponse = false
        initStepTimer?.invalidate()
    }

    public func toggleOBD() {
        if isEnabled {
            disableOBD()
        } else {
            enableOBD()
        }
    }

    public func startScan() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth nicht aktiv (\(centralManager.state.rawValue))")
            return
        }
        connectionState = .scanning
        log("Starte BLE-Scan nach ELM327 / OBDII…")
        // Im Vordergrund scannen wir ohne Service-Filter (findet 100% aller Adapter, auch Klone ohne Advertised Services)
        let isBackground = UIApplication.shared.applicationState == .background
        let targetServices: [CBUUID]? = isBackground ? serviceUUIDs : nil
        centralManager.scanForPeripherals(withServices: targetServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScan() {
        centralManager.stopScan()
        pollTimer?.invalidate()
        pollTimer = nil
        initStepTimer?.invalidate()
        connectionWatchdogTimer?.invalidate()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ELM327 Befehle senden
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ELM327 Befehle senden
    // ─────────────────────────────────────────────────────────────────────────

    private func sendCommand(_ cmd: String) {
        guard let p = peripheral, let tx = txChar else { return }
        log("TX: \(cmd)")
        let fullCmd = cmd + "\r"
        if let data = fullCmd.data(using: .ascii) {
            let writeType: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: tx, type: writeType)
            isWaitingForResponse = true
            lastCommandSentTime = Date()
        }
    }

    private func log(_ msg: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugLogs.insert("[\(timestamp)] \(msg)", at: 0)
        if debugLogs.count > 50 { debugLogs.removeLast() }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Initialisierungs-Sequenz (Schritt für Schritt mit > Bestätigung & Timeout)
    // ─────────────────────────────────────────────────────────────────────────

    private func startInitSequence() {
        // ATE0 (Echo aus), ATL0 (Linefeeds aus), ATH0 (Header aus), ATSP0 (Protokoll Auto)
        // Kein ATZ: ATZ bootet den Chip neu und führt bei billigen BLE-Klonen oft zu Bluetooth-Abbrüchen!
        initQueue = ["ATE0", "ATL0", "ATH0", "ATSP0"]
        log("Starte saubere ELM327-Initialisierung…")
        sendNextInitCommand()
    }

    private func sendNextInitCommand() {
        initStepTimer?.invalidate()
        initStepTimer = nil

        guard !initQueue.isEmpty else {
            connectionState = .connected
            isInitializingUART = false
            connectionWatchdogTimer?.invalidate()
            log("✔ ELM327 initialisiert & bereit. Starte Live-Sensorabfragen.")
            startPolling()
            return
        }

        let nextCmd = initQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.sendCommand(nextCmd)
            // Timeout-Absicherung: Nach 1.0s ohne Antwort trotzdem fortfahren
            self.initStepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.connectionState == .initializing {
                        self.log("ℹ Timeout für \(nextCmd) – fahre fort.")
                        self.isWaitingForResponse = false
                        self.sendNextInitCommand()
                    }
                }
            }
        }
    }

    private func startConnectionWatchdog() {
        connectionWatchdogTimer?.invalidate()
        connectionWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.connectionState == .connecting || self.connectionState == .initializing {
                    if self.txChar != nil && self.rxChar != nil {
                        self.log("⚡ Watchdog: UART verbunden, starte Sensor-Abfragen!")
                        self.connectionState = .connected
                        self.isInitializingUART = false
                        self.startPolling()
                    } else {
                        self.log("⚠ Watchdog: Verbindung hängt – starte Scan neu…")
                        if let p = self.peripheral {
                            self.centralManager.cancelPeripheralConnection(p)
                        }
                        self.connectionState = .scanning
                        self.startScan()
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Polling Loop (Antwort-gesteuert, keine Kollisionen)
    // ─────────────────────────────────────────────────────────────────────────

    private func startPolling() {
        pollTimer?.invalidate()
        // Fragt regelmäßig ab, sobald der Adapter die vorherige PID beantwortet hat
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndPollNextPID()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkAndPollNextPID() {
        guard connectionState == .connected else { return }

        // Wenn wir noch auf eine Antwort warten: Timeout nach 2.5 Sekunden prüfen
        if isWaitingForResponse {
            if Date().timeIntervalSince(lastCommandSentTime) > 2.5 {
                log("⚠ Timeout für PID – sende nächsten Messwertbefehl")
                isWaitingForResponse = false
            } else {
                return // Adapter verarbeitet noch die vorherige Abfrage
            }
        }

        let pid = queryCycle[currentPIDIndex % queryCycle.count]
        currentPIDIndex += 1
        sendCommand(pid)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Parsing der OBD-Antworten
    // ─────────────────────────────────────────────────────────────────────────

    private func parseResponse(_ raw: String) {
        let clean = raw.replacingOccurrences(of: "\r", with: " ")
                       .replacingOccurrences(of: "\n", with: " ")
                       .replacingOccurrences(of: ">", with: "")
                       .trimmingCharacters(in: .whitespaces)

        log("RX: \(clean)")
        let compact = clean.replacingOccurrences(of: " ", with: "").uppercased()

        // 1. Saugrohrdruck & Ladedruck (PID 01 0B -> Antwort 410B XX)
        if let range = compact.range(of: "410B") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    let mapKpa = Int(val)
                    liveMAP = mapKpa
                    // Relative boost = (MAP - Baro) / 100 in bar
                    let rawBoost = (Double(mapKpa) - Double(liveBaro)) / 100.0
                    liveBoostBar = max(-1.0, min(3.5, rawBoost))
                }
            }
        }
        // 2. Öltemperatur (PID 01 5C -> Antwort 415C XX)
        // Auf dem EA113 / KWP2000 oft NO DATA — wenn ja, arbeitet das Kühlmittel-Modell als Fallback.
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    let oil = Int(val) - 40
                    if oil >= -20 && oil <= 160 {
                        liveOilTemp = oil
                        hasOilTempPID = true
                        WarmupManager.shared.triggerWarmNotificationIfNeeded(temp: oil)
                    }
                }
            }
        }
        // 3. Kühlmitteltemperatur (PID 01 05 -> Antwort 4105 XX)
        if let range = compact.range(of: "4105") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    let coolant = Int(val) - 40
                    liveCoolantTemp = coolant
                    if liveOilTemp == nil {
                        let estimatedOil = max(20, coolant - 8)
                        WarmupManager.shared.triggerWarmNotificationIfNeeded(temp: estimatedOil)
                    }
                }
            }
        }
        // 4. Motordrehzahl RPM (PID 01 0C -> Antwort 410C AA BB)
        if let range = compact.range(of: "410C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4 {
                let b1Str = String(after.prefix(2))
                let b2Str = String(after.dropFirst(2).prefix(2))
                if let b1 = UInt8(b1Str, radix: 16), let b2 = UInt8(b2Str, radix: 16) {
                    liveRPM = ((Int(b1) * 256) + Int(b2)) / 4
                }
            }
        }
        // 5. Geschwindigkeit Speed (PID 01 0D -> Antwort 410D XX)
        if let range = compact.range(of: "410D") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveSpeed = Int(val)
                }
            }
        }
        // 6. Ansauglufttemperatur (PID 01 0F -> Antwort 410F XX)
        if let range = compact.range(of: "410F") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveIAT = Int(val) - 40
                }
            }
        }
        // 7. Berechnete Motorlast (PID 01 04 -> Antwort 4104 XX)
        if let range = compact.range(of: "4104") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveEngineLoad = Int(Double(val) * 100.0 / 255.0)
                }
            }
        }
        // 8. Barometrischer Umgebungsdruck (PID 01 33 -> Antwort 4133 XX)
        if let range = compact.range(of: "4133") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveBaro = Int(val)
                }
            }
        }
        // 9. Luftmasse MAF (PID 01 10 -> Antwort 4110 AA BB)
        if let range = compact.range(of: "4110") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4 {
                let b1Str = String(after.prefix(2))
                let b2Str = String(after.dropFirst(2).prefix(2))
                if let b1 = UInt8(b1Str, radix: 16), let b2 = UInt8(b2Str, radix: 16) {
                    let maf = Double((Int(b1) * 256) + Int(b2)) / 100.0
                    liveMAF = maf
                    // VW 2.0 TFSI Fallback: Wenn MAP (010B) fehlt, Ladedruck aus MAF und RPM berechnen!
                    if liveMAP == nil && liveRPM > 650 {
                        let theoreticalNA = (Double(liveRPM) / 60.0) * 1.006
                        if theoreticalNA > 4.0 {
                            let boost = (maf / theoreticalNA) - 1.0
                            liveBoostBar = max(-0.8, min(2.5, boost))
                        }
                    }
                }
            }
        }
        // 10. VW 2.0 TFSI Besonderheit Check
        if compact.contains("NODATA") && compact.contains("5C") {
            if liveOilTemp == nil {
                hasOilTempPID = false
                log("ℹ VW meldet 'NO DATA' für PID 01 5C. Nutze VAG Mode 22 oder Kühlmittel-Modell.")
            }
        }
        if compact.contains("SEARCHING") {
            log("ELM327 sucht CAN-Bus Protokoll…")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: CBCentralManagerDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension OBDManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isEnabled {
            resetTelemetryValues()
            startScan()
        } else if central.state != .poweredOn {
            connectionState = .disconnected
            resetTelemetryValues()
            log("Bluetooth deaktiviert oder nicht verfügbar.")
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let lower = name.lowercased()

        // Filtert nach allen gängigen OBD2 / ELM327 BLE Adapter-Namen
        let isOBD = lower.contains("obd") ||
                    lower.contains("elm") ||
                    lower.contains("v-link") ||
                    lower.contains("vlink") ||
                    lower.contains("allstric") ||
                    lower.contains("ios-vlink") ||
                    lower.contains("vgate") ||
                    lower.contains("icar") ||
                    lower.contains("viecar") ||
                    lower.contains("konnwei") ||
                    lower.contains("ble-obd") ||
                    lower.contains("ble")

        if isOBD || !name.isEmpty {
            log("Gefunden: '\(name)' [RSSI: \(RSSI)]")
        }

        if isOBD {
            log("Verbinde mit passendem OBD-Adapter: \(name)…")
            self.peripheral = peripheral
            centralManager.stopScan()
            connectionState = .connecting
            startConnectionWatchdog()
            centralManager.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("BLE-Verbindung hergestellt. Entdecke GATT-Services…")
        connectionState = .initializing
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        log("Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "Unbekannt")")
        connectionWatchdogTimer?.invalidate()
        connectionState = .error
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        log("OBD-Adapter getrennt.")
        connectionWatchdogTimer?.invalidate()
        initStepTimer?.invalidate()
        connectionState = .disconnected
        resetTelemetryValues()
        self.peripheral = nil
        txChar = nil
        rxChar = nil
        isInitializingUART = false
        pollTimer?.invalidate()
        if isEnabled {
            // Reconnect-Versuch nach 2 Sekunden
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startScan()
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: CBPeripheralDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension OBDManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            log("Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        let serviceStr = service.uuid.uuidString.uppercased()
        // Standard Bluetooth SIG Dienste ignorieren (Generic Access 1800, Device Info 180A etc.)
        if serviceStr.hasPrefix("1800") || serviceStr.hasPrefix("1801") || serviceStr.hasPrefix("180A") {
            return
        }

        guard let chars = service.characteristics else { return }
        for c in chars {
            log("  -> Char: \(c.uuid) (Prop: \(c.properties.rawValue))")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                rxChar = c
                peripheral.setNotifyValue(true, for: c)
            }
            if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                if txChar == nil || txChar?.service?.uuid == service.uuid {
                    txChar = c
                }
            }
        }

        // Sobald TX und RX gefunden wurden, genau 1x Initialisierung starten
        if txChar != nil && rxChar != nil && connectionState == .initializing && !isInitializingUART {
            isInitializingUART = true
            log("GATT UART bereit. Starte ELM327 Initialisierungs-Warteschlange…")
            startInitSequence()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let data = characteristic.value,
              let str = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) else {
            return
        }

        receiveBuffer.append(str)
        if receiveBuffer.contains(">") {
            let fullMsg = receiveBuffer
            receiveBuffer = ""
            isWaitingForResponse = false

            if connectionState == .initializing {
                initStepTimer?.invalidate()
                sendNextInitCommand()
            } else {
                parseResponse(fullMsg)
            }
        }
    }
}
