// MARK: - OBDManager.swift
// CarLyrics – CoreBluetooth BLE Client für ELM327 / OBD2 Bluetooth Adapter.
// Speziell optimiert für Low-Cost ELM327 Mini BLE Adapter (z.B. Allstric / V-Gate)
// mit automatischem Fallback für VW 2.0 TFSI Motoren.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
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

    private var pollTimer       : Timer?
    private var receiveBuffer   : String = ""
    private var currentPIDIndex : Int = 0
    private let queryCycle      : [String] = ["010B", "015C", "0105", "010C", "010D", "010F", "0104", "0133"]

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
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionState = .disconnected
        resetTelemetryValues()
    }

    public func resetTelemetryValues() {
        liveOilTemp = nil
        liveCoolantTemp = nil
        liveBoostBar = nil
        liveMAP = nil
        liveIAT = nil
        liveEngineLoad = nil
        liveRPM = 0
        liveSpeed = 0
        hasOilTempPID = false
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
        // Scan nach bekannten UUIDs oder generell nach Geräten mit Namen
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScan() {
        centralManager.stopScan()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ELM327 Befehle senden
    // ─────────────────────────────────────────────────────────────────────────

    private func sendCommand(_ cmd: String) {
        guard let p = peripheral, let tx = txChar else { return }
        let fullCmd = cmd + "\r"
        if let data = fullCmd.data(using: .ascii) {
            let writeType: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: tx, type: writeType)
        }
    }

    private func log(_ msg: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugLogs.insert("[\(timestamp)] \(msg)", at: 0)
        if debugLogs.count > 50 { debugLogs.removeLast() }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Polling Loop
    // ─────────────────────────────────────────────────────────────────────────

    private func startPolling() {
        pollTimer?.invalidate()
        // Fragt alle 500ms abwechselnd Öltemperatur, Kühlmittel und Drehzahl ab
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollNextPID()
            }
        }
    }

    private func pollNextPID() {
        guard connectionState == .connected else { return }
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
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveOilTemp = Int(val) - 40
                    hasOilTempPID = true
                }
            }
        }
        // 3. Kühlmitteltemperatur (PID 01 05 -> Antwort 4105 XX)
        if let range = compact.range(of: "4105") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2 {
                let hexByte = String(after.prefix(2))
                if let val = UInt8(hexByte, radix: 16) {
                    liveCoolantTemp = Int(val) - 40
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
        // 9. VW 2.0 TFSI Besonderheit Check
        if compact.contains("NODATA") && compact.contains("5C") {
            hasOilTempPID = false
            log("⚠ VW meldet 'NO DATA' für Öltemperatur (PID 01 5C). Fallback auf Kühlmittel aktiv!")
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

        // Filtert nach gängigen OBD2 / ELM327 BLE Namen
        let isOBD = lower.contains("obd") ||
                    lower.contains("elm") ||
                    lower.contains("v-link") ||
                    lower.contains("allstric") ||
                    lower.contains("ios-vlink") ||
                    lower.contains("ble")

        if isOBD || !name.isEmpty {
            log("Gefunden: '\(name)' [RSSI: \(RSSI)]")
        }

        if isOBD {
            log("Verbinde mit passendem OBD-Adapter: \(name)…")
            self.peripheral = peripheral
            centralManager.stopScan()
            connectionState = .connecting
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
        connectionState = .error
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        log("OBD-Adapter getrennt.")
        connectionState = .disconnected
        resetTelemetryValues()
        self.peripheral = nil
        txChar = nil
        rxChar = nil
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
        guard let chars = service.characteristics else { return }
        for c in chars {
            log("  -> Char: \(c.uuid) (Prop: \(c.properties.rawValue))")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                rxChar = c
                peripheral.setNotifyValue(true, for: c)
            }
            if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                txChar = c
            }
        }

        // Sobald TX und RX gefunden wurden, initialisieren
        if txChar != nil && rxChar != nil && connectionState == .initializing {
            log("GATT UART bereit. Sende ELM327 Init-Sequenz…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendCommand("ATZ")   // Reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.sendCommand("ATE0")  // Echo off
                    self?.sendCommand("ATL0")  // Linefeeds off
                    self?.sendCommand("ATSP0") // Auto Protocol
                    self?.connectionState = .connected
                    self?.log("ELM327 initialisiert. Starte PID-Abfragen.")
                    self?.startPolling()
                }
            }
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
            parseResponse(fullMsg)
        }
    }
}
