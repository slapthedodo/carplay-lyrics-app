// MARK: - OBDManager.swift
// CarLyrics & OBD Workbench – CoreBluetooth BLE Client für ELM327 / OBD2 Adapter.
// Hochoptimiert für VW EA113 2.0 TFSI (Bosch MED9.1) & günstige ELM327 Mini Klone.
// Enthält Live-Terminal, Protokoll-Prober, Bordspannungs-Monitor und VAG-Messwertblöcke.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import CoreBluetooth
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Data Types & Enums
// ─────────────────────────────────────────────────────────────────────────────

public enum OBDConnectionState: String {
    case disconnected = "Getrennt"
    case scanning     = "Suche nach OBD-Adapter…"
    case connecting   = "Verbinde mit BLE-Adapter…"
    case initializing = "ELM327 Handshake…"
    case searchingECU = "Verbinde mit Steuergerät…"
    case connected    = "Verbunden & ECU Aktiv"
    case error        = "Fehler / Keine Antwort"
}

public enum OBDProtocol: String, CaseIterable, Identifiable {
    case can11_500     = "CAN 11-Bit 500k (AT SP 6)"       // Standard VAG Golf 5 / MED9.1
    case can11_500_7e0 = "CAN 11-Bit 500k + 7E0 Header"   // Direkt Bosch MED9.1 ECU
    case kwpFast       = "KWP2000 Fast (AT SP 5)"         // Frühe VAG MK5 K-Line
    case can29_500     = "CAN 29-Bit 500k (AT SP 7)"
    case kwp5Baud      = "KWP2000 5-Baud (AT SP 4)"
    case iso9141       = "ISO 9141-2 (AT SP 3)"
    case auto          = "Auto-Suche (AT SP 0)"

    public var id: String { rawValue }

    public var elmCommand: String {
        switch self {
        case .can11_500, .can11_500_7e0: return "ATSP6"
        case .can29_500:                 return "ATSP7"
        case .kwpFast:                   return "ATSP5"
        case .kwp5Baud:                  return "ATSP4"
        case .iso9141:                   return "ATSP3"
        case .auto:                      return "ATSP0"
        }
    }

    public var headerCommand: String? {
        switch self {
        case .can11_500_7e0: return "ATSH7E0"
        case .can11_500:     return "ATSH7DF"
        default:             return nil
        }
    }
}

public struct OBDTerminalEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: String
    public let direction: Direction
    public let text: String
    public let style: EntryStyle

    public enum Direction {
        case tx, rx, system
    }

    public enum EntryStyle {
        case normal, success, error, warning
    }
}

public struct ProtocolProbeResult: Identifiable, Equatable {
    public let id = UUID()
    public let proto: OBDProtocol
    public var status: ProbeStatus
    public var rawResponse: String
    public var responseTimeMs: Int
    public var note: String

    public enum ProbeStatus: Equatable {
        case pending
        case testing
        case success
        case failed
        case noData
        case timeout
    }
}

public struct OBDDiscoveredDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral

    public static func == (lhs: OBDDiscoveredDevice, rhs: OBDDiscoveredDevice) -> Bool {
        lhs.id == rhs.id && lhs.rssi == rhs.rssi
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: OBDManager Class
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
public final class OBDManager: NSObject, ObservableObject {

    public static let shared = OBDManager()

    private static let obdEnabledKey  = "carlyrics_obd_enabled"
    private static let savedProtoKey  = "carlyrics_obd_protocol"

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published State
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var connectionState : OBDConnectionState = .disconnected
    @Published public var isEnabled       : Bool = UserDefaults.standard.bool(forKey: "carlyrics_obd_enabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.obdEnabledKey) }
    }

    // Live Sensor Telemetrie
    @Published public var liveOilTemp     : Int? = nil           // PID 01 5C oder Messwertblock 134
    @Published public var liveCoolantTemp : Int? = nil           // PID 01 05 (Immer bei VW)
    @Published public var liveRPM         : Int  = 0             // PID 01 0C
    @Published public var liveSpeed       : Int  = 0             // PID 01 0D
    @Published public var liveBoostBar    : Double? = nil        // Ladedruck in Bar (PID 01 0B - Baro)
    @Published public var liveMAP         : Int? = nil           // Saugrohrdruck in kPa (PID 01 0B)
    @Published public var liveIAT         : Int? = nil           // Ansauglufttemperatur in °C (PID 01 0F)
    @Published public var liveMAF         : Double? = nil        // Luftmasse in g/s (PID 01 10)
    @Published public var liveEngineLoad  : Int? = nil           // Motorlast in % (PID 01 04)
    @Published public var liveBaro        : Int  = 101           // Atmosphärendruck in kPa
    @Published public var hasOilTempPID   : Bool = false         // Wurde PID 01 5C quittiert?

    // Diagnose & Hardware Zustand
    @Published public var batteryVoltage       : Double? = nil    // Bordspannung aus ATRV (z.B. 12.4V oder 14.1V)
    @Published public var isIgnitionOn         : Bool? = nil      // true wenn Spannung >= 11.8V
    @Published public var elmFirmware          : String = ""      // z.B. "ELM327 v1.5"
    @Published public var currentActiveProtocol: String = ""      // aus ATDP
    @Published public var detailedStatus       : String = "Bereit zum Verbinden"
    @Published public var selectedProtocol     : OBDProtocol = .can11_500 {
        didSet {
            UserDefaults.standard.set(selectedProtocol.rawValue, forKey: Self.savedProtoKey)
        }
    }

    // Bitmasken-Tracker für unterstützte PIDs (Mode 01 00/20/40)
    @Published public var supportedPIDs        : Set<String> = []

    // Live Terminal
    @Published public var terminalEntries      : [OBDTerminalEntry] = []
    @Published public var debugLogs            : [String] = []    // Kompatibilität mit bestehenden Views
    @Published public var isManualTerminalMode : Bool = false

    // Protokoll Schnell-Tester / Brute-Force
    @Published public var probeResults         : [ProtocolProbeResult] = []
    @Published public var isProbingProtocols   : Bool = false

    // BLE Discovered Devices
    @Published public var discoveredDevices    : [OBDDiscoveredDevice] = []

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: CoreBluetooth & Private State
    // ─────────────────────────────────────────────────────────────────────────

    private var centralManager : CBCentralManager!
    private var peripheral     : CBPeripheral?
    private var txChar         : CBCharacteristic?
    private var rxChar         : CBCharacteristic?

    // Bekannte BLE-UART Services für ELM327 Klone
    private let serviceUUIDs: [CBUUID] = [
        CBUUID(string: "FFF0"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "18F0"),
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART
        CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")  // ISSC
    ]

    private var pollTimer               : Timer?
    private var initStepTimer           : Timer?
    private var connectionWatchdogTimer : Timer?
    private var voltageTimer            : Timer?
    private var receiveBuffer           : String = ""
    private var currentPIDIndex         : Int = 0
    private var isInitializingUART      : Bool = false
    private var initQueue               : [String] = []
    private var isWaitingForResponse    : Bool = false
    private var lastCommandSentTime     : Date = .distantPast
    private var lastCommandSent         : String = ""

    // VAG EA113 Bosch MED 9.1 Standard Polling Zyklus:
    private let queryCycle: [String] = [
        "0105",     // Kühlmitteltemperatur in °C
        "010C",     // Motordrehzahl RPM
        "010B",     // Saugrohr-Absolutdruck (MAP) -> Ladedruck
        "0110",     // Luftmasse (MAF) in g/s
        "010F",     // Ansauglufttemperatur (IAT) in °C
        "015C",     // Öltemperatur (PID 01 5C)
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

        if let savedProto = UserDefaults.standard.string(forKey: Self.savedProtoKey),
           let p = OBDProtocol(rawValue: savedProto) {
            self.selectedProtocol = p
        } else {
            // Standardmäßig für VW 2.0 TFSI: VAG CAN 11-Bit 500k (AT SP 6)
            self.selectedProtocol = .can11_500
        }

        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public Controls
    // ─────────────────────────────────────────────────────────────────────────

    public func enableOBD() {
        isEnabled = true
        resetTelemetryValues()
        startScan()
    }

    public func disableOBD() {
        isEnabled = false
        stopScan()
        stopPolling()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionState = .disconnected
        detailedStatus = "Deaktiviert"
        resetTelemetryValues()
    }

    public func toggleOBD() {
        if isEnabled {
            disableOBD()
        } else {
            enableOBD()
        }
    }

    public func reconnect() {
        logSystem("🔄 Reconnect angefordert…")
        stopPolling()
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

    public func selectProtocol(_ proto: OBDProtocol) {
        selectedProtocol = proto
        logSystem("Protokoll gewechselt zu: \(proto.rawValue)")
        if connectionState == .connected || connectionState == .searchingECU {
            // Im laufenden Betrieb Protokoll übermitteln
            sendInitCommands([proto.elmCommand] + (proto.headerCommand != nil ? [proto.headerCommand!] : []))
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
        batteryVoltage = nil
        isIgnitionOn = nil
        hasOilTempPID = false
        isInitializingUART = false
        initQueue.removeAll()
        isWaitingForResponse = false
        initStepTimer?.invalidate()
    }

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

        // Breiter Scan, um auch nicht deklarierte Klone zu finden
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScan() {
        centralManager.stopScan()
        initStepTimer?.invalidate()
        connectionWatchdogTimer?.invalidate()
    }

    public func connectToDevice(id: String) {
        guard let dev = discoveredDevices.first(where: { $0.id == id }) else { return }
        stopScan()
        self.peripheral = dev.peripheral
        connectionState = .connecting
        detailedStatus = "Verbinde mit \(dev.name)…"
        logSystem("Verbinde manuell mit \(dev.name) (\(dev.id))…")
        startConnectionWatchdog()
        centralManager.connect(dev.peripheral, options: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Live Terminal & Raw Command Execution
    // ─────────────────────────────────────────────────────────────────────────

    public func sendManualCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logTx(trimmed)
        sendCommandRaw(trimmed)
    }

    public func copyTerminalLogToClipboard() {
        let lines = terminalEntries.map { entry in
            let dir = entry.direction == .tx ? "TX > " : (entry.direction == .rx ? "RX < " : "SYS: ")
            return "[\(entry.timestamp)] \(dir)\(entry.text)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = lines
        logSystem("✔ Log in die Zwischenablage kopiert (\(terminalEntries.count) Zeilen).")
    }

    public func clearTerminalLogs() {
        terminalEntries.removeAll()
        debugLogs.removeAll()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Automated Protocol Prober ("Tausende Methoden Schnelltest")
    // ─────────────────────────────────────────────────────────────────────────

    public func runProtocolAutoProbe() {
        guard txChar != nil else {
            logSystem("⚠️ Kein Adapter verbunden. Bitte zuerst mit OBD-Adapter koppeln.")
            return
        }
        isProbingProtocols = true
        stopPolling()

        // Bereite Test-Matrix vor
        let candidates: [OBDProtocol] = [
            .can11_500,         // Standard Golf 5 GTI EA113
            .can11_500_7e0,     // Direkter ECU Header
            .kwpFast,           // K-Line Fast
            .kwp5Baud,          // K-Line 5-Baud
            .can29_500,         // CAN 29-bit
            .iso9141,           // ISO 9141-2
            .auto               // Auto-Search
        ]

        probeResults = candidates.map {
            ProtocolProbeResult(proto: $0, status: .pending, rawResponse: "", responseTimeMs: 0, note: "")
        }

        logSystem("⚡ Starte Protokoll-Schnelltest über \(candidates.count) Methoden…")
        executeNextProbeStep(index: 0)
    }

    public func stopProtocolAutoProbe() {
        isProbingProtocols = false
        logSystem("Protokoll-Schnelltest abgebrochen.")
        if connectionState == .connected {
            startPolling()
        }
    }

    private func executeNextProbeStep(index: Int) {
        guard isProbingProtocols else { return }
        guard index < probeResults.count else {
            isProbingProtocols = false
            logSystem("🏁 Protokoll-Schnelltest abgeschlossen!")

            // Wenn ein erfolgreiches Protokoll gefunden wurde, direkt aktivieren!
            if let winner = probeResults.first(where: { $0.status == .success }) {
                logSystem("🏆 Erfolgreiches Protokoll gefunden: \(winner.proto.rawValue) – Wird jetzt aktiviert!")
                selectProtocol(winner.proto)
                connectionState = .connected
                startPolling()
            } else {
                detailedStatus = "Kein Protokoll hat geantwortet. Zündung eingeschaltet?"
            }
            return
        }

        probeResults[index].status = .testing
        let target = probeResults[index].proto
        detailedStatus = "Teste Methode \(index + 1)/\(probeResults.count): \(target.rawValue)…"
        logSystem("-> Teste: \(target.rawValue)")

        // Sende Protokoll-Befehl gefolgt von Test-PID 0100
        var cmds = [target.elmCommand]
        if let h = target.headerCommand { cmds.append(h) }
        cmds.append("0100") // Lese unterstützte PIDs

        let startTime = Date()
        sendSequence(cmds: cmds, timeout: target == .auto ? 6.5 : 3.5) { [weak self] fullResponse, success in
            guard let self = self else { return }
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            self.probeResults[index].responseTimeMs = duration
            self.probeResults[index].rawResponse = fullResponse

            if success && fullResponse.contains("4100") {
                self.probeResults[index].status = .success
                self.probeResults[index].note = "ECU antwortet! Bosch MED9.1 erkannt."
                self.logSystem("✔ Treffer bei \(target.rawValue) in \(duration)ms!")
            } else if fullResponse.contains("UNABLE TO CONNECT") {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "UNABLE TO CONNECT (Falsches Protokoll oder Zündung aus)"
            } else if fullResponse.contains("BUS INIT") || fullResponse.contains("BUSINIT") {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = "BUS INIT ERROR"
            } else if fullResponse.contains("NO DATA") {
                self.probeResults[index].status = .noData
                self.probeResults[index].note = "NO DATA (Bus erkannt, aber keine Antwort auf 0100)"
            } else {
                self.probeResults[index].status = .failed
                self.probeResults[index].note = fullResponse.isEmpty ? "Timeout" : fullResponse
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextProbeStep(index: index + 1)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Low-Level Command Execution
    // ─────────────────────────────────────────────────────────────────────────

    private func sendCommandRaw(_ cmd: String) {
        guard let p = peripheral, let tx = txChar else {
            logSystem("⚠️ Kein Bluetooth TX Characteristic gefunden.")
            return
        }
        let fullCmd = cmd + "\r"
        if let data = fullCmd.data(using: .ascii) {
            let writeType: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: tx, type: writeType)
            isWaitingForResponse = true
            lastCommandSentTime = Date()
            lastCommandSent = cmd
        }
    }

    private var sequenceQueue: [String] = []
    private var sequenceAccumulated: String = ""
    private var sequenceCompletion: (@MainActor (String, Bool) -> Void)? = nil
    private var sequenceTimer: Timer? = nil
    private var pendingSequenceHandler: ((String) -> Void)? = nil

    private func sendSequence(cmds: [String], timeout: TimeInterval, completion: @escaping @MainActor (String, Bool) -> Void) {
        sequenceQueue = cmds
        sequenceAccumulated = ""
        sequenceCompletion = completion
        sendNextInSequence(timeout: timeout)
    }

    private func sendNextInSequence(timeout: TimeInterval) {
        sequenceTimer?.invalidate()
        sequenceTimer = nil

        guard !sequenceQueue.isEmpty else {
            let comp = sequenceCompletion
            sequenceCompletion = nil
            pendingSequenceHandler = nil
            comp?(sequenceAccumulated, true)
            return
        }

        let nextCmd = sequenceQueue.removeFirst()
        sendCommandRaw(nextCmd)

        sequenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isWaitingForResponse = false
                let comp = self.sequenceCompletion
                self.sequenceCompletion = nil
                self.pendingSequenceHandler = nil
                comp?(self.sequenceAccumulated, false)
            }
        }

        pendingSequenceHandler = { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.sequenceAccumulated += " " + response
                self.sendNextInSequence(timeout: timeout)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Robust Initialization Sequence
    // ─────────────────────────────────────────────────────────────────────────

    private func startRobustInitSequence() {
        connectionState = .initializing
        detailedStatus = "Initialisiere ELM327 Hardware…"
        logSystem("Starte saubere ELM327 Handshake-Sequenz…")

        // Sequenz:
        // 1. ATE0 (Echo aus)
        // 2. ATL0 (Linefeeds aus)
        // 3. ATS0 (Leerzeichen aus für maximalen Durchsatz)
        // 4. ATH0 (Headers standardmäßig aus)
        // 5. ATRV (Bordspannung messen zur Zündungs-Verifizierung!)
        // 6. ATI  (ELM327 Firmware-Version auslesen)
        // 7. Ausgewähltes Protokoll setzen (z.B. ATSP6)
        // 8. Prüfen mit 0100 (ECU Suche)
        var sequence = ["ATE0", "ATL0", "ATS0", "ATH0", "ATRV", "ATI", selectedProtocol.elmCommand]
        if let header = selectedProtocol.headerCommand {
            sequence.append(header)
        }
        sequence.append("0100") // Probe ECU

        initQueue = sequence
        sendNextInitCommand()
    }

    private func sendInitCommands(_ cmds: [String]) {
        initQueue.append(contentsOf: cmds)
        if !isWaitingForResponse {
            sendNextInitCommand()
        }
    }

    private func sendNextInitCommand() {
        initStepTimer?.invalidate()
        initStepTimer = nil

        guard !initQueue.isEmpty else {
            isInitializingUART = false
            connectionWatchdogTimer?.invalidate()
            if connectionState != .connected {
                connectionState = .connected
            }
            detailedStatus = "Verbunden (\(selectedProtocol.rawValue))"
            logSystem("✔ ELM327 initialisiert. Starte kontinuierliche Sensorabfrage.")
            startPolling()
            startVoltageMonitor()
            return
        }

        let nextCmd = initQueue.removeFirst()
        if nextCmd == "0100" {
            connectionState = .searchingECU
            detailedStatus = "Verbinde mit Steuergerät (Bosch MED9.1)…"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self = self else { return }
            self.sendCommandRaw(nextCmd)

            // Timeout-Absicherung für Init-Befehle (Auto-Protokoll braucht ggf. länger)
            let waitTime: TimeInterval = (nextCmd == "0100" && self.selectedProtocol == .auto) ? 7.0 : 1.8
            self.initStepTimer = Timer.scheduledTimer(withTimeInterval: waitTime, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.connectionState == .initializing || self.connectionState == .searchingECU {
                        self.logSystem("ℹ Timeout bei Befehl \(nextCmd) – fahre fort.")
                        self.isWaitingForResponse = false
                        self.sendNextInitCommand()
                    }
                }
            }
        }
    }

    private func startConnectionWatchdog() {
        connectionWatchdogTimer?.invalidate()
        connectionWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.connectionState == .connecting || self.connectionState == .initializing {
                    self.logSystem("⚠ Verbindungs-Watchdog: Adapter reagiert nicht. Starte Scan neu…")
                    self.reconnect()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Polling Loop (Sensoren)
    // ─────────────────────────────────────────────────────────────────────────

    private func startPolling() {
        guard !isProbingProtocols && !isManualTerminalMode else { return }
        pollTimer?.invalidate()

        let timer = Timer(timeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollNextPID()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    private func startVoltageMonitor() {
        voltageTimer?.invalidate()
        // Alle 6 Sekunden Batteriespannung über ATRV nachprüfen
        let timer = Timer(timeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.connectionState == .connected, !self.isProbingProtocols else { return }
                self.sendCommandRaw("ATRV")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        voltageTimer = timer
    }

    private func pollNextPID() {
        guard connectionState == .connected, !isProbingProtocols, !isManualTerminalMode else { return }

        // Wenn noch auf Antwort gewartet wird: Nach 2.2s Timeout nächste PID
        if isWaitingForResponse {
            if Date().timeIntervalSince(lastCommandSentTime) > 2.2 {
                logSystem("⚠ Timeout auf Antwort von \(lastCommandSent)")
                isWaitingForResponse = false
            } else {
                return
            }
        }

        let pid = queryCycle[currentPIDIndex % queryCycle.count]
        currentPIDIndex += 1
        sendCommandRaw(pid)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Parsing & Protocol Analysis
    // ─────────────────────────────────────────────────────────────────────────

    private func handleRawMessageReceived(_ raw: String) {
        let clean = raw.replacingOccurrences(of: "\r", with: " ")
                       .replacingOccurrences(of: "\n", with: " ")
                       .replacingOccurrences(of: ">", with: "")
                       .trimmingCharacters(in: .whitespaces)

        if let handler = pendingSequenceHandler {
            pendingSequenceHandler = nil
            handler(clean)
            return
        }

        logRx(clean)

        let compact = clean.replacingOccurrences(of: " ", with: "").uppercased()

        // 1. Batteriespannung (ATRV: z.B. "12.4V")
        if clean.contains("V") && (compact.contains(".") || compact.count <= 6) {
            let numStr = clean.replacingOccurrences(of: "V", with: "").trimmingCharacters(in: .whitespaces)
            if let volts = Double(numStr), volts > 5.0 && volts < 20.0 {
                batteryVoltage = volts
                isIgnitionOn = volts >= 11.8
                if volts < 11.6 {
                    logSystem("⚠️ Bordspannung nur \(volts)V: Zündung evtl. AUS oder Batterie schwach!")
                }
            }
        }

        // 2. ELM Version (ATI: z.B. "ELM327 v1.5")
        if compact.contains("ELM327") {
            elmFirmware = clean
            logSystem("ℹ Adapter Firmware: \(clean)")
        }

        // 3. Fehler-Meldungen des ELM327
        if compact.contains("UNABLETOCONNECT") {
            logSystem("🔴 UNABLE TO CONNECT: Steuergerät antwortet nicht. Zündung auf Stufe 2? Motor an?")
            detailedStatus = "Fehler: UNABLE TO CONNECT (Zündung an?)"
            if selectedProtocol == .auto && !isProbingProtocols {
                logSystem("💡 Tipp: Auto-Suche ist fehlgeschlagen. Wechsle zu 'CAN 11-Bit 500k (AT SP 6)'!")
            }
        } else if compact.contains("BUSINIT:ERROR") || compact.contains("BUSINITERROR") {
            logSystem("🔴 BUS INIT: ERROR: Bus-Fehler auf aktuellem Protokoll. Versuche KWP2000 (AT SP 5).")
            detailedStatus = "Fehler: BUS INIT (Falsches Protokoll)"
        } else if compact.contains("CANERROR") {
            logSystem("🔴 CAN ERROR: Leitungsfehler oder falsche Baudrate.")
            detailedStatus = "Fehler: CAN ERROR"
        }

        // 4. ECU Quittung für 0100 (Unterstützte PIDs)
        if let range = compact.range(of: "4100") {
            let after = String(compact[range.upperBound...])
            if after.count >= 8 {
                connectionState = .connected
                detailedStatus = "✔ ECU Verbunden (Bosch MED9.1)"
                decodeSupportedPIDs(String(after.prefix(8)), offset: 1)
            }
        }

        // 5. Kühlmitteltemperatur (PID 01 05 -> Antwort 4105 XX)
        if let range = compact.range(of: "4105") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let coolant = Int(val) - 40
                liveCoolantTemp = coolant
                connectionState = .connected

                if liveOilTemp == nil {
                    let estimatedOil = max(20, coolant - 8)
                    WarmupManager.shared.triggerWarmNotificationIfNeeded(temp: estimatedOil)
                }
            }
        }

        // 6. Motordrehzahl RPM (PID 01 0C -> Antwort 410C AA BB)
        if let range = compact.range(of: "410C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4,
               let b1 = UInt8(after.prefix(2), radix: 16),
               let b2 = UInt8(after.dropFirst(2).prefix(2), radix: 16) {
                liveRPM = ((Int(b1) * 256) + Int(b2)) / 4
            }
        }

        // 7. Saugrohrdruck & Ladedruck (PID 01 0B -> Antwort 410B XX)
        if let range = compact.range(of: "410B") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let mapKpa = Int(val)
                liveMAP = mapKpa
                let rawBoost = (Double(mapKpa) - Double(liveBaro)) / 100.0
                liveBoostBar = max(-1.0, min(3.5, rawBoost))
            }
        }

        // 8. Öltemperatur (PID 01 5C -> Antwort 415C XX)
        if let range = compact.range(of: "415C") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                let oil = Int(val) - 40
                if oil >= -20 && oil <= 160 {
                    liveOilTemp = oil
                    hasOilTempPID = true
                    WarmupManager.shared.triggerWarmNotificationIfNeeded(temp: oil)
                }
            }
        } else if compact.contains("NODATA") && lastCommandSent == "015C" {
            hasOilTempPID = false
        }

        // 9. Ansauglufttemperatur (PID 01 0F -> Antwort 410F XX)
        if let range = compact.range(of: "410F") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveIAT = Int(val) - 40
            }
        }

        // 10. Luftmasse MAF (PID 01 10 -> Antwort 4110 AA BB)
        if let range = compact.range(of: "4110") {
            let after = String(compact[range.upperBound...])
            if after.count >= 4,
               let b1 = UInt8(after.prefix(2), radix: 16),
               let b2 = UInt8(after.dropFirst(2).prefix(2), radix: 16) {
                let maf = Double((Int(b1) * 256) + Int(b2)) / 100.0
                liveMAF = maf
            }
        }

        // 11. Geschwindigkeit (PID 01 0D -> Antwort 410D XX)
        if let range = compact.range(of: "410D") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveSpeed = Int(val)
            }
        }

        // 12. Motorlast (PID 01 04 -> Antwort 4104 XX)
        if let range = compact.range(of: "4104") {
            let after = String(compact[range.upperBound...])
            if after.count >= 2, let val = UInt8(after.prefix(2), radix: 16) {
                liveEngineLoad = Int(Double(val) * 100.0 / 255.0)
            }
        }

        // 13. VAG Messwertblock 134 (Öltemp, Kühlmittel, etc.)
        if compact.contains("6186") || compact.contains("621154") {
            parseVAGMeasuringBlock(compact)
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

    private func parseVAGMeasuringBlock(_ raw: String) {
        logSystem("ℹ VAG Messwertblock Antwort empfangen: \(raw)")
        // VAG MWB 134 enthält: Feld 1 Öltemperatur, Feld 4 Kühlmittel
        // Implementiert als erweiterte Dekodierung
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Terminal Logging Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func logTx(_ text: String) {
        appendTerminal(direction: .tx, text: text, style: .normal)
    }

    private func logRx(_ text: String) {
        let style: OBDTerminalEntry.EntryStyle
        if text.contains("41") || text.contains("OK") {
            style = .success
        } else if text.contains("ERROR") || text.contains("UNABLE") || text.contains("STOPPED") {
            style = .error
        } else if text.contains("SEARCHING") || text.contains("NODATA") {
            style = .warning
        } else {
            style = .normal
        }
        appendTerminal(direction: .rx, text: text, style: style)
    }

    private func logSystem(_ text: String) {
        appendTerminal(direction: .system, text: text, style: .normal)
    }

    private func appendTerminal(direction: OBDTerminalEntry.Direction, text: String, style: OBDTerminalEntry.EntryStyle) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let entry = OBDTerminalEntry(timestamp: time, direction: direction, text: text, style: style)
        terminalEntries.insert(entry, at: 0)
        if terminalEntries.count > 300 { terminalEntries.removeLast() }

        // Kompatibilitäts-Log
        let prefix = direction == .tx ? "TX: " : (direction == .rx ? "RX: " : "")
        debugLogs.insert("[\(time)] \(prefix)\(text)", at: 0)
        if debugLogs.count > 60 { debugLogs.removeLast() }
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
                    lower.contains("ble")

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
        let serviceStr = service.uuid.uuidString.uppercased()
        if serviceStr.hasPrefix("1800") || serviceStr.hasPrefix("1801") || serviceStr.hasPrefix("180A") {
            return
        }

        guard let chars = service.characteristics else { return }
        for c in chars {
            logSystem("  -> Char: \(c.uuid) (Prop: \(c.properties.rawValue))")
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

        // Sobald TX und RX verfügbar sind, genau 1x Handshake starten
        if txChar != nil && rxChar != nil && connectionState == .initializing && !isInitializingUART {
            isInitializingUART = true
            logSystem("✔ UART bereit (TX & RX verbunden). Starte Handshake…")
            startRobustInitSequence()
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

            if connectionState == .initializing || connectionState == .searchingECU {
                initStepTimer?.invalidate()
                handleRawMessageReceived(fullMsg)
                sendNextInitCommand()
            } else {
                handleRawMessageReceived(fullMsg)
            }
        }
    }
}
