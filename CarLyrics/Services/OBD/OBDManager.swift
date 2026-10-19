// MARK: - OBDManager.swift
// Haupt-Controller & Telemetrie-Zentrale für ELM327 BLE & Bosch MED9.1
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth
import Combine
import UIKit
import AVFoundation

public final class OBDManager: NSObject, ObservableObject {

    public static let shared = OBDManager()

    public static let obdEnabledKey = "CarLyrics_OBD_Enabled"
    public static let savedProtoKey  = "CarLyrics_OBD_SelectedProto"

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published Properties (Telemetrie & Status)
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var isEnabled            : Bool = true
    /// CarPlay-Gating: Wenn true (Standard), verbindet OBD NUR wenn echtes CarPlay aktiv ist.
    /// Im Diagnose-Workbench (manuelle Scan-Taste) wird das Gate explizit deaktiviert.
    @Published public var carPlayGatingEnabled : Bool = true
    @Published public var connectionState      : OBDConnectionState = .disconnected

    // Fokus-Modus für gezielte Sensorabfrage ohne Ruckeln
    public enum OBDFocusMode: Equatable {
        case standard      // Alle Cockpit-Sensoren
        case pedalOnly     // Nur Gaspedal/Last, RPM & Speed (ultraschnell für Pedale)
        case minimal       // Relaxed, nur Basiswerte für Fahrschul-Tutorial
    }
    @Published public var focusMode: OBDFocusMode = .standard

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
    @Published public var throttlePosition: Int?    = nil        // Gaspedal / Drosselklappe % (PID 01 11)
    @Published public var liveBaro        : Int     = 101        // Barometer kPa
    @Published public var liveEGT         : Int?    = nil        // Geschätzte Abgastemperatur °C (thermische Trägheit)
    @Published public var isColdOverloaded: Bool    = false      // Kaltstart-Überlastung erkannt
    @Published public var coldOverloadMessage: String = ""      // Kurztitel der Warnung
    @Published public var coldOverloadDetail: String = ""       // Detailhinweis für Fahrer
    internal var smoothedEGT              : Double? = nil
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
        // Bei kaltem Motor starten beide bei ähnlicher Temperatur (z.B. 10°C).
        let baseOil: Int
        if coolant < 25 {
            baseOil = coolant
        } else if coolant < 60 {
            baseOil = coolant - 6
        } else {
            baseOil = coolant - 8
        }

        let loadBonus: Int
        if coolant >= 80 {
            if liveRPM > 3000 || (liveBoostBar ?? 0) > 0.3 {
                loadBonus = min(25, max(0, Int((liveBoostBar ?? 0) * 12) + (liveRPM > 4000 ? 6 : 2)))
            } else {
                loadBonus = 0
            }
        } else {
            loadBonus = 0
        }
        return baseOil + loadBonus
    }

    // PID-Unterstützungs-Flags (Bosch MED9.1 Filter: 010B standardmäßig false)
    @Published public var hasMAPPID            : Bool    = false
    @Published public var hasCheckedMAPPID     : Bool    = true
    @Published public var isPollingActive      : Bool    = false
    internal var pollWatchdogTimer             : Timer?  = nil

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
    @Published public var diagnosisBLEDebug     : String?               = nil   // Technische Infos bei Fehler
    @Published public var diagnosisRetryCount   : Int                   = 0

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
        carPlayGatedScan()
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
            carPlayGatedScan()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: CarPlay Battery-Guard: Gated Scan & Safe Disconnect
    // ─────────────────────────────────────────────────────────────────────────

    /// Startet Bluetooth-Scan NUR wenn CarPlay aktiv ist – oder Gating explizit deaktiviert (Diagnose).
    /// Verhindert, dass die App das Auto-Steuergerät zuhause im Hintergrund aufweckt.
    public func carPlayGatedScan() {
        guard carPlayGatingEnabled else {
            // Diagnose-Workbench: immer erlaubt (manueller Modus)
            startScan()
            return
        }
        let hasCarPlay = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay } ||
                         AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
        guard hasCarPlay else {
            logSystem("🔒 OBD-Scan blockiert: Kein CarPlay aktiv (Batterieschutz)")
            detailedStatus = "Wartet auf CarPlay…"
            return
        }
        startScan()
    }

    /// Wird aufgerufen wenn CarPlay getrennt wird oder Zündung aus ist.
    /// Sendet ATLP (ELM327 Low-Power Standby) und kappt die BLE-Verbindung sofort.
    @MainActor public func carPlayDidDisconnect() {
        guard isEnabled, connectionState != .disconnected else { return }
        logSystem("⚡ CarPlay/Zündung aus – ATLP + BT-Trennung (Batterieschutz aktiv)")
        // ELM327 schläft: < 2mA statt 45mA an Klemme 30
        sendCommandRaw("ATLP")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.stopPolling()
            self.initStepTimer?.invalidate()
            self.connectionWatchdogTimer?.invalidate()
            if let p = self.peripheral {
                self.centralManager.cancelPeripheralConnection(p)
            }
            self.peripheral = nil
            self.txChar = nil
            self.rxChar = nil
            self.isInitializingUART = false
            self.connectionState = .disconnected
            self.detailedStatus = "Getrennt – Batterieschutz aktiv"
            self.resetTelemetryValues()
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
        liveBoostBar = 0.0
        liveMAP = 101
        liveIAT = 20
        liveMAF = 3.5
        liveEngineLoad = nil
        liveRPM = 0
        liveSpeed = 0
        liveEGT = nil
        smoothedEGT = nil
        isColdOverloaded = false
        coldOverloadMessage = ""
        coldOverloadDetail = ""
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
        guard !isProbingProtocols && !isManualTerminalMode && !isAutoDiagnosing else { return }
        isPollingActive = true
        pollTimer?.invalidate()
        pollTimer = nil
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil

        // Ersten Befehl mit kleiner 60ms Pause absetzen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
            self.pollNextPID()
        }
    }

    internal func stopPolling() {
        isPollingActive = false
        pollTimer?.invalidate()
        pollTimer = nil
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    internal func startVoltageMonitor() {
        // ATRV wird nun kollisionsfrei direkt im Polling-Zyklus alle 25 Zyklen abgefragt
        voltageTimer?.invalidate()
        voltageTimer = nil
    }

    // Antwort wurde empfangen (">"): Adaptive Pause basierend auf Fokus-Modus
    internal func onResponseCompleted() {
        guard isPollingActive, connectionState == .connected, !isProbingProtocols, !isManualTerminalMode, !isAutoDiagnosing else { return }
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = nil

        let delay: Double
        switch focusMode {
        case .pedalOnly:
            delay = 0.020 // 20ms ultraschnell für 20-30Hz flüssige Pedal- & Ganganzeige
        case .minimal:
            delay = 0.100 // 100ms entspannt für Kupplungs-Tutorial, schont CPU & BLE
        case .standard:
            delay = 0.045 // 45ms Standard Cockpit-Takt
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
            self.pollNextPID()
        }
    }

    private func pollNextPID() {
        guard connectionState == .connected, !isProbingProtocols, !isManualTerminalMode, !isAutoDiagnosing else { return }

        let activePIDs: [String]
        switch focusMode {
        case .pedalOnly:
            // Exklusiv nur Werte für den Pedal- und Ganganzeige-Tab (Null Overhead)
            activePIDs = [
                "010C",     // Motordrehzahl RPM
                "0111",     // Gaspedal / Drosselklappe %
                "0104",     // Motorlast % (Fallback)
                "010D"      // Geschwindigkeit km/h (für Gang)
            ]
        case .minimal:
            // Für Kupplungs-Tutorial: Nur RPM & Gas, keine schweren Cockpit-Sensoren
            activePIDs = [
                "010C",     // RPM
                "0111",     // Gaspedal %
                "0104"      // Motorlast %
            ]
        case .standard:
            // PIDs für Bosch MED9.1 zusammenstellen (Cockpit / HandyModus)
            var pids: [String] = [
                "010C",     // Motordrehzahl RPM (Prio 1)
                "0110",     // Luftmasse MAF (Prio 1)
                "0104",     // Motorlast (Prio 2)
                "0105",     // Kühlmittel (Prio 2)
                "010D",     // Geschwindigkeit
                "010F"      // Ansaugluft IAT
            ]

            // 010B nur abfragen wenn unterstützt (MED9.1 liefert typischerweise NODATA)
            if !hasCheckedMAPPID || hasMAPPID {
                pids.append("010B")
            }

            // 015C nur alle 35 Zyklen kurz anfragen
            if !hasCheckedOilTempPID || hasOilTempPID || (currentPIDIndex % 35 == 0) {
                pids.append("015C")
            }

            // ATRV alle 25 Zyklen kollisionsfrei in den Stream einstreuen
            if currentPIDIndex % 25 == 0 {
                pids.append("ATRV")
            }
            activePIDs = pids
        }

        guard !activePIDs.isEmpty else { return }
        let pid = activePIDs[currentPIDIndex % activePIDs.count]
        currentPIDIndex += 1

        sendCommandRaw(pid)

        // Sicherheits-Watchdog: Falls BLE ein Paket verschluckt, nach 850ms weitermachen
        pollWatchdogTimer?.invalidate()
        pollWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPollingActive, self.connectionState == .connected else { return }
                self.isWaitingForResponse = false
                self.pollNextPID()
            }
        }
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
