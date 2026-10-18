// MARK: - OBDManager.swift
// Haupt-Controller & Telemetrie-Zentrale für ELM327 BLE & Bosch MED9.1
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth
import Combine
import UIKit

public final class OBDManager: NSObject, ObservableObject {

    public static let shared = OBDManager()

    public static let obdEnabledKey = "CarLyrics_OBD_Enabled"
    public static let savedProtoKey  = "CarLyrics_OBD_SelectedProto"

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published Properties (Telemetrie & Status)
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var isEnabled            : Bool = true
    @Published public var connectionState      : OBDConnectionState = .disconnected

    // Live Telemetrie
    @Published public var liveCoolantTemp : Int?    = nil        // PID 01 05
    @Published public var liveOilTemp     : Int?    = nil        // PID 01 5C / Sim
    @Published public var liveRPM         : Int     = 0          // PID 01 0C
    @Published public var liveSpeed       : Int     = 0          // PID 01 0D
    @Published public var liveBoostBar    : Double? = nil        // Ladedruck in Bar
    @Published public var liveMAP         : Int?    = nil        // Saugrohrdruck kPa (01 0B)
    @Published public var liveIAT         : Int?    = nil        // Ansaugluft °C (01 0F)
    @Published public var liveMAF         : Double? = nil        // Luftmasse g/s (01 10)
    @Published public var liveEngineLoad  : Int?    = nil        // Motorlast % (01 04)
    @Published public var liveBaro        : Int     = 101        // Barometer kPa
    @Published public var hasOilTempPID   : Bool    = false
    public var hasCheckedOilTempPID       : Bool    = false

    /// Liefert die echte Öltemperatur (PID 01 5C) oder das hochpräzise EA113-Thermikmodell
    /// basierend auf Kühlmittel (01 05), Drehzahl (01 0C) und Motorlast.
    public var effectiveOilTemp: Int? {
        if let real = liveOilTemp {
            return real
        }
        guard let coolant = liveCoolantTemp else { return nil }
        // VW EA113 2.0 TFSI Thermik:
        // Der integrierte Öl-Wasser-Wärmetauscher am Ölfilterflansch sorgt dafür,
        // dass sich das Öl dem Kühlmittel mit ca. 8°C Nachlauf anpasst.
        // Bei höherer Last / Drehzahl steigt die Öltemperatur über das Kühlwasser.
        let baseOil = max(20, coolant - 8)
        let loadBonus: Int
        if coolant >= 80 {
            if liveRPM > 3000 || (liveBoostBar ?? 0) > 0.3 {
                loadBonus = min(20, max(0, Int((liveBoostBar ?? 0) * 12) + (liveRPM > 4000 ? 5 : 2)))
            } else {
                loadBonus = 0
            }
        } else {
            loadBonus = 0
        }
        return baseOil + loadBonus
    }

    // Hardware Zustand
    @Published public var batteryVoltage       : Double? = nil    // ATRV
    @Published public var isIgnitionOn         : Bool?   = nil    // >= 11.8V
    @Published public var elmFirmware          : String  = ""     // z.B. "ELM327 v1.5"
    @Published public var currentActiveProtocol: String  = ""     // ATDP
    @Published public var detailedStatus       : String  = "Bereit zum Verbinden"
    @Published public var selectedProtocol     : OBDProtocol = .can11_500 {
        didSet {
            UserDefaults.standard.set(selectedProtocol.rawValue, forKey: Self.savedProtoKey)
        }
    }

    // Unterstützte PIDs (Mode 01 00/20/40)
    @Published public var supportedPIDs        : Set<String> = []

    // Live Terminal & Debug
    @Published public var terminalEntries      : [OBDTerminalEntry] = []
    @Published public var debugLogs            : [String]           = []
    @Published public var isManualTerminalMode : Bool               = false
    @Published public var forceWriteWithResponse: Bool              = false

    // 1-Klick Auto-Diagnose & Schnell-Tester
    @Published public var diagnosisSteps        : [OBDDiagnosisStep]    = []
    @Published public var isAutoDiagnosing      : Bool                  = false
    @Published public var diagnosisSummary      : String?               = nil

    // Protokoll Schnell-Tester
    @Published public var probeResults         : [ProtocolProbeResult] = []
    @Published public var isProbingProtocols   : Bool = false

    // BLE Discovered Devices
    @Published public var discoveredDevices    : [OBDDiscoveredDevice] = []

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: CoreBluetooth & Private State
    // ─────────────────────────────────────────────────────────────────────────

    internal var centralManager : CBCentralManager!
    internal var peripheral     : CBPeripheral?
    internal var txChar         : CBCharacteristic?
    internal var rxChar         : CBCharacteristic?

    internal var pollTimer               : Timer?
    internal var initStepTimer           : Timer?
    internal var connectionWatchdogTimer : Timer?
    internal var voltageTimer            : Timer?
    internal var receiveBuffer           : String = ""
    internal var currentPIDIndex         : Int = 0
    internal var isInitializingUART      : Bool = false
    internal var initQueue               : [String] = []
    internal var isWaitingForResponse    : Bool = false
    internal var lastCommandSentTime     : Date = .distantPast
    internal var lastCommandSent         : String = ""

    internal var sequenceQueue: [String] = []
    internal var sequenceAccumulated: String = ""
    internal var sequenceCompletion: (@MainActor (String, Bool) -> Void)? = nil
    internal var sequenceTimer: Timer? = nil
    internal var pendingSequenceHandler: ((String) -> Void)? = nil

    // Standard Polling-Zyklus für Bosch MED9.1 (EA113 2.0 TFSI)
    internal let queryCycle: [String] = [
        "0105",     // Kühlmitteltemperatur
        "010C",     // Motordrehzahl RPM
        "010B",     // Saugrohr-Absolutdruck (MAP)
        "0110",     // Luftmasse (MAF)
        "010F",     // Ansauglufttemperatur (IAT)
        "015C",     // Öltemperatur (PID 01 5C)
        "010D",     // Geschwindigkeit
        "0104"      // Motorlast
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public override init() {
        super.init()
        let saved = UserDefaults.standard.object(forKey: Self.obdEnabledKey) != nil ? UserDefaults.standard.bool(forKey: Self.obdEnabledKey) : true
        self.isEnabled = saved

        if let savedProto = UserDefaults.standard.string(forKey: Self.savedProtoKey),
           let p = OBDProtocol(rawValue: savedProto) {
            self.selectedProtocol = p
        } else {
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
        if isEnabled { disableOBD() } else { enableOBD() }
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
        hasCheckedOilTempPID = false
        isInitializingUART = false
        initQueue.removeAll()
        isWaitingForResponse = false
        initStepTimer?.invalidate()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Polling Loop
    // ─────────────────────────────────────────────────────────────────────────

    internal func startPolling() {
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

    internal func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    internal func startVoltageMonitor() {
        voltageTimer?.invalidate()
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

        if isWaitingForResponse {
            if Date().timeIntervalSince(lastCommandSentTime) > 2.2 {
                logSystem("⚠ Timeout auf Antwort von \(lastCommandSent)")
                isWaitingForResponse = false
            } else {
                return
            }
        }

        var pid = queryCycle[currentPIDIndex % queryCycle.count]
        currentPIDIndex += 1

        // Optimierung: Wenn 015C bereits geprüft wurde und NODATA zurückgab (typisch für MED9.1),
        // frage 015C nur alle 30 Zyklen erneut ab, um den Bus nicht unnötig mit NODATA zu bremsen!
        if pid == "015C" && hasCheckedOilTempPID && !hasOilTempPID && (currentPIDIndex % 30 != 0) {
            pid = queryCycle[currentPIDIndex % queryCycle.count]
            currentPIDIndex += 1
        }

        sendCommandRaw(pid)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Terminal Logging Helpers
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

    internal func logTx(_ text: String) {
        appendTerminal(direction: .tx, text: text, style: .normal)
    }

    internal func logRx(_ text: String) {
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

    internal func logSystem(_ text: String) {
        appendTerminal(direction: .system, text: text, style: .normal)
    }

    private func appendTerminal(direction: OBDTerminalEntry.Direction, text: String, style: OBDTerminalEntry.EntryStyle) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let entry = OBDTerminalEntry(timestamp: time, direction: direction, text: text, style: style)
        terminalEntries.insert(entry, at: 0)
        if terminalEntries.count > 300 { terminalEntries.removeLast() }

        let prefix = direction == .tx ? "TX: " : (direction == .rx ? "RX: " : "")
        debugLogs.insert("[\(time)] \(prefix)\(text)", at: 0)
        if debugLogs.count > 60 { debugLogs.removeLast() }
    }
}
