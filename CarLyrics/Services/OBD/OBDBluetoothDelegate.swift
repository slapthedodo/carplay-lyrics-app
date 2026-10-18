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
                    lower.contains("obdii") ||
                    lower.contains("odb") ||
                    lower.hasPrefix("bt-g") ||
                    lower.hasPrefix("bt-obd") ||
                    lower.hasPrefix("elm327") ||
                    lower.hasPrefix("carlyric")

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

        // Spezifische Zuordnung nach BLE-GATT UART Standards:
        // RX (iPhone empfängt Daten): MUSS .notify oder .indicate haben.
        // TX (iPhone sendet Daten):   MUSS .write oder .writeWithoutResponse haben.
        var discoveredRx: CBCharacteristic? = nil
        var discoveredTx: CBCharacteristic? = nil

        // Spezifische Erkennung bekannter UART-Services
        let isKnownUART = serviceStr.contains("FFF0") ||
                          serviceStr.contains("FFE0") ||
                          serviceStr.contains("6E400001") ||
                          serviceStr.contains("49535343") ||
                          serviceStr.contains("18F0")

        for c in chars {
            let hasNotify = c.properties.contains(.notify) || c.properties.contains(.indicate)
            let hasWrite = c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse)

            // Benachrichtigungen auf allen empfangsbereiten Charakteristiken scharf schalten
            if hasNotify {
                peripheral.setNotifyValue(true, for: c)
                logSystem("  ✔ Benachrichtigungen aktiviert auf \(c.uuid)")
                if discoveredRx == nil {
                    discoveredRx = c
                }
            }

            if hasWrite {
                // Bevorzuge reine Schreib-Charakteristik als TX falls vorhanden
                if discoveredTx == nil || (discoveredTx == discoveredRx && !hasNotify) {
                    discoveredTx = c
                }
            }
        }

        // Falls getrennter Write-Kanal existiert, bevorzuge ihn gegenüber kombiniertem RX/TX
        if let separateWrite = chars.first(where: { ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) && $0 != discoveredRx }) {
            discoveredTx = separateWrite
        } else if discoveredTx == nil {
            discoveredTx = chars.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) })
        }

        if let rx = discoveredRx, let tx = discoveredTx {
            rxChar = rx
            txChar = tx

            if connectionState == .initializing && !isInitializingUART {
                isInitializingUART = true
                connectionWatchdogTimer?.invalidate()
                logSystem("✔ UART bereit: TX=\(tx.uuid.uuidString) | RX=\(rx.uuid.uuidString)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self = self else { return }
                    if self.connectionState == .initializing && self.initQueue.isEmpty && !self.isProbingProtocols && !self.isAutoDiagnosing {
                        self.logSystem("Starte Handshake per Timer-Fallback…")
                        self.startRobustInitSequence()
                    }
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
            if connectionState == .initializing && initQueue.isEmpty && !isProbingProtocols && !isAutoDiagnosing {
                startRobustInitSequence()
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error = error {
            logSystem("🔴 BLE Write Fehler auf \(characteristic.uuid): \(error.localizedDescription)")
            if !forceWriteWithResponse {
                forceWriteWithResponse = true
            }
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

            if (connectionState == .initializing || connectionState == .searchingECU) && !isProbingProtocols && !isAutoDiagnosing {
                initStepTimer?.invalidate()
                handleRawMessageReceived(fullMsg)
                sendNextInitCommand()
            } else {
                handleRawMessageReceived(fullMsg)
            }
        }
    }
}
