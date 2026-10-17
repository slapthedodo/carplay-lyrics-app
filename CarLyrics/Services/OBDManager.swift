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

    @Published public var connectionState : OBDConnectionState = .disconnected
    @Published public var isEnabled       : Bool = false         // Toggle: OBD vs Simulation
    @Published public var liveOilTemp     : Int? = nil           // PID 01 5C (wenn unterstützt)
    @Published public var liveCoolantTemp : Int? = nil           // PID 01 05 (immer bei VW)
    @Published public var liveRPM         : Int  = 0             // PID 01 0C
    @Published public var liveSpeed       : Int  = 0             // PID 01 0D
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
    private let queryCycle      : [String] = ["015C", "0105", "010C", "010D"]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func enableOBD() {
        isEnabled = true
        startScan()
    }

    public func disableOBD() {
        isEnabled = false
        stopScan()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionState = .disconnected
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

        // Check auf Standard-Antworten
        if clean.contains("41 5C") {
            // Öltemperatur: 41 5C XX -> Wert = XX (hex) - 40
            if let temp = parseSingleBytePID(clean, prefix: "41 5C") {
                liveOilTemp = temp - 40
                hasOilTempPID = true
            }
        } else if clean.contains("41 05") {
            // Kühlmitteltemperatur: 41 05 XX -> Wert = XX - 40
            if let temp = parseSingleBytePID(clean, prefix: "41 05") {
                liveCoolantTemp = temp - 40
            }
        } else if clean.contains("41 0C") {
            // RPM: 41 0C AA BB -> ((AA*256)+BB)/4
            if let rpm = parseTwoBytePID(clean, prefix: "41 0C") {
                liveRPM = rpm / 4
            }
        } else if clean.contains("41 0D") {
            // Speed: 41 0D XX -> XX km/h
            if let speed = parseSingleBytePID(clean, prefix: "41 0D") {
                liveSpeed = speed
            }
        } else if clean.contains("NO DATA") && clean.contains("5C") {
            // VW 2.0 TFSI Besonderheit: Generisches OBD-II unterstützt oft kein 01 5C
            hasOilTempPID = false
            log("⚠ VW meldet 'NO DATA' für Öltemperatur (PID 01 5C). Fallback aktiv!")
        }
    }

    private func parseSingleBytePID(_ text: String, prefix: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let parts = after.components(separatedBy: " ")
        guard let first = parts.first, let val = UInt8(first, radix: 16) else { return nil }
        return Int(val)
    }

    private func parseTwoBytePID(_ text: String, prefix: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let parts = after.components(separatedBy: " ")
        guard parts.count >= 2,
              let b1 = UInt8(parts[0], radix: 16),
              let b2 = UInt8(parts[1], radix: 16) else { return nil }
        return (Int(b1) * 256) + Int(b2)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: CBCentralManagerDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension OBDManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isEnabled {
            startScan()
        } else if central.state != .poweredOn {
            connectionState = .disconnected
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
        if receiveBuffer.contains(">") || receiveBuffer.contains("\r") {
            parseResponse(receiveBuffer)
            receiveBuffer = ""
        }
    }
}
