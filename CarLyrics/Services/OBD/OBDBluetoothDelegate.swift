// MARK: - OBDBluetoothDelegate.swift
// CoreBluetooth Delegaten & GATT-Charakteristik-Routing für ELM327 BLE
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth

// ─────────────────────────────────────────────────────────────────────────────
// MARK: CBCentralManagerDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension OBDManager: CBCentralManagerDelegate {

    public func startScan() {
        guard centralManager.state == .poweredOn else {
            logSystem("Bluetooth ist auf diesem Gerät nicht aktiv (\(centralManager.state.rawValue))")
            detailedStatus = "Bluetooth deaktiviert"
            return
        }
        discoveredDevices.removeAll()
        connectionState = .scanning
        detailedStatus = "Suche nach OBD2 Bluetooth Geräten…"
        logSystem("Starte BLE-Scan…")

        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScan() {
        centralManager.stopScan()
        initStepTimer?.invalidate()
        connectionWatchdogTimer?.invalidate()
    }

    public func connectToDevice(id: String) {
        guard let dev = discoveredDevices.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: "CarLyrics_Last_Connected_OBD_UUID")
        stopScan()
        self.peripheral = dev.peripheral
        connectionState = .connecting
        detailedStatus = "Verbinde mit \(dev.name)…"
        logSystem("Verbinde manuell mit \(dev.name) (\(dev.id))…")
        startConnectionWatchdog()
        centralManager.connect(dev.peripheral, options: nil)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isEnabled {
            resetTelemetryValues()
            startScan()
        } else if central.state != .poweredOn {
            connectionState = .disconnected
            resetTelemetryValues()
            detailedStatus = "Bluetooth nicht verfügbar"
            logSystem("Bluetooth deaktiviert oder Berechtigung fehlt.")
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unbekannt"
        let lower = name.lowercased()

        let dev = OBDDiscoveredDevice(id: peripheral.identifier.uuidString, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        if !discoveredDevices.contains(where: { $0.id == dev.id }) {
            discoveredDevices.append(dev)
        }

        let savedUUID = UserDefaults.standard.string(forKey: "CarLyrics_Last_Connected_OBD_UUID")
        let isSavedDevice = (savedUUID != nil && peripheral.identifier.uuidString == savedUUID)

        let isOBD = isSavedDevice ||
                    lower.contains("obd") ||
                    lower.contains("elm") ||
                    lower.contains("v-link") ||
                    lower.contains("vlink") ||
                    lower.contains("allstric") ||
                    lower.contains("ios-vlink") ||
                    lower.contains("vgate") ||
                    lower.contains("icar") ||
                    lower.contains("viecar") ||
                    lower.contains("konnwei") ||
                    lower.contains("ble") ||
                    lower.hasPrefix("bt-") ||
                    lower.contains("bt-g") ||
                    lower.contains("link") ||
                    lower.contains("car")

        if isOBD && connectionState == .scanning {
            logSystem("Gefunden: '\(name)' [RSSI: \(RSSI) dBm] – Verbinde automatisch…")
            self.peripheral = peripheral
            centralManager.stopScan()
            connectionState = .connecting
            detailedStatus = "Verbinde mit \(name)…"
            startConnectionWatchdog()
            centralManager.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "CarLyrics_Last_Connected_OBD_UUID")
        logSystem("✔ BLE-Verbindung hergestellt (\(peripheral.name ?? "Adapter")). Entdecke UART-Services…")
        connectionState = .initializing
        detailedStatus = "Entdecke UART-Dienste…"
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        logSystem("🔴 Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "Unbekannt")")
        connectionWatchdogTimer?.invalidate()
        connectionState = .error
        detailedStatus = "Verbindung fehlgeschlagen"
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        logSystem("⚠️ OBD-Adapter getrennt.")
        connectionWatchdogTimer?.invalidate()
        initStepTimer?.invalidate()
        connectionState = .disconnected
        detailedStatus = "Adapter getrennt"
        resetTelemetryValues()
        self.peripheral = nil
        txChar = nil
        rxChar = nil
        isInitializingUART = false
        stopPolling()
        if isEnabled && !isManualTerminalMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
            logSystem("Dienst entdeckt: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        if let error = error {
            logSystem("🔴 Char-Fehler für Dienst \(service.uuid): \(error.localizedDescription)")
            return
        }
        let serviceStr = service.uuid.uuidString.uppercased()
        if serviceStr.hasPrefix("1800") || serviceStr.hasPrefix("1801") || serviceStr.hasPrefix("180A") {
            return
        }

        guard let chars = service.characteristics else { return }
        for c in chars {
            logSystem("  -> Char: \(c.uuid) (Prop: \(c.properties.rawValue))")
        }

        // Spezifische Zuordnung nach bekannten BLE-UART Standards
        if serviceStr.contains("FFF0") {
            for c in chars {
                if c.properties.contains(.notify) || c.properties.contains(.indicate) { rxChar = c }
                if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) { txChar = c }
            }
        } else if serviceStr.contains("FFE0") {
            for c in chars {
                let u = c.uuid.uuidString.uppercased()
                if u.contains("FFE1") || c.properties.contains(.notify) || c.properties.contains(.write) {
                    if c.properties.contains(.notify) || c.properties.contains(.indicate) { rxChar = c }
                    if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) { txChar = c }
                }
            }
        } else if serviceStr.contains("6E400001") {
            for c in chars {
                let u = c.uuid.uuidString.uppercased()
                if u.contains("6E400002") { txChar = c }
                if u.contains("6E400003") { rxChar = c }
            }
        } else if serviceStr.contains("49535343") {
            for c in chars {
                let u = c.uuid.uuidString.uppercased()
                if u.contains("8841") { txChar = c }
                if u.contains("1E4D") { rxChar = c }
            }
        } else if serviceStr.contains("18F0") {
            for c in chars {
                let u = c.uuid.uuidString.uppercased()
                if u.contains("2AF0") { txChar = c }
                if u.contains("2AF1") { rxChar = c }
            }
        } else {
            // Generischer Fallback
            if rxChar == nil {
                rxChar = chars.first(where: { $0.properties.contains(.notify) })
                      ?? chars.first(where: { $0.properties.contains(.indicate) })
            }
            if txChar == nil {
                txChar = chars.first(where: { $0 != rxChar && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) })
                      ?? chars.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) })
            }
        }

        // Sobald TX und RX bereitstehen:
        if let tx = txChar, let rx = rxChar, connectionState == .initializing && !isInitializingUART {
            isInitializingUART = true
            connectionWatchdogTimer?.invalidate()
            logSystem("✔ UART Kanäle gefunden: TX=\(tx.uuid.uuidString) | RX=\(rx.uuid.uuidString)")

            logSystem("Aktiviere Benachrichtigungen auf RX…")
            peripheral.setNotifyValue(true, for: rx)

            // Falls didUpdateNotificationStateFor verzögert kommt oder ausbleibt:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                if self.connectionState == .initializing && self.initQueue.isEmpty && !self.isProbingProtocols {
                    self.logSystem("Starte Handshake per Timer-Fallback…")
                    self.startRobustInitSequence()
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logSystem("🔴 Notify Fehler auf \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        if characteristic.isNotifying {
            logSystem("✔ BLE Notify bestätigt für \(characteristic.uuid.uuidString)")
            if connectionState == .initializing && initQueue.isEmpty && !isProbingProtocols {
                startRobustInitSequence()
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logSystem("🔴 BLE Write Fehler auf \(characteristic.uuid): \(error.localizedDescription)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logSystem("🔴 Empfangsfehler auf \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let str = String(decoding: data, as: UTF8.self)
        guard !str.isEmpty else { return }

        receiveBuffer.append(str)
        if receiveBuffer.contains(">") {
            let fullMsg = receiveBuffer
            receiveBuffer = ""
            isWaitingForResponse = false

            if (connectionState == .initializing || connectionState == .searchingECU) && !isProbingProtocols {
                initStepTimer?.invalidate()
                handleRawMessageReceived(fullMsg)
                sendNextInitCommand()
            } else {
                handleRawMessageReceived(fullMsg)
            }
        }
    }
}
