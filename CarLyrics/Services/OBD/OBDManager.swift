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
    /// CarPlay-Gating: verbindet OBD nur bei aktivem CarPlay (Batterieschutz).
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
    internal var smoothedOilTemp          : Double? = nil
    @Published public var hasOilTempPID   : Bool    = false
    public var hasCheckedOilTempPID       : Bool    = false
    // Tacho Öltemp: Multi-Fallback OBD-Auslese (echte Sensor-Temp statt Schätzung)
    @Published public var tachoOilTempEnabled    : Bool   = true
    @Published public var tachoOilTempValue      : Int?   = nil      // Bestätigter echter Wert in °C
    @Published public var tachoOilTempMethod     : String = ""       // Welche Methode hat funktioniert
    @Published public var tachoOilTempProbeStatus: [OilTempProbeStatus] = []
    @Published public var isMeasuringTachoOilTemp: Bool   = false
    /// Zuletzt gesetztes ELM327-Protokoll (z.B. "ATSP6" für CAN). Wird für Prober-Cleanup genutzt.
    internal var currentElmProtocol       : String? = "ATSP6"
    internal var sessionConnectedAt       : Date?   = nil
    internal var initialCoolantTemp       : Int?    = nil

    /// Liefert echte Öltemperatur (PID 01 5C) oder das thermisch träge EA113-Modell (PT1-geglättet).
    public var effectiveOilTemp: Int? {
        if let real = liveOilTemp { return real }
        guard let coolant = liveCoolantTemp else { return nil }

        let baseOil = coolant < 25 ? coolant : (coolant < 60 ? coolant - 8 : (coolant < 85 ? coolant - 10 : coolant - 8))
        var target = baseOil

        if let initCoolant = initialCoolantTemp, initCoolant < 60, let connAt = sessionConnectedAt {
            let elapsed = Date().timeIntervalSince(connAt)
            let limit = Int(WarmupCalculator.calculateOilTemp(at: elapsed, from: Double(initCoolant)).rounded())
            if limit < 80 { target = min(baseOil, limit) }
        }

        if coolant >= 85 && target >= 78 {
            let boostX = Int((liveBoostBar ?? 0) * 10)
            let rpmX = liveRPM > 4200 ? 4 : 0
            target += min(16, max(0, boostX + rpmX))
        }

        // PT1-Glättung: 4.6L Öl reagieren thermisch träge – kein schlagartiges Springen bei Last!
        let targetD = Double(target)
        if let prev = smoothedOilTemp {
            let alpha = targetD > prev ? 0.006 : 0.0025
            let next = prev + alpha * (targetD - prev)
            smoothedOilTemp = next
            return Int(next.rounded())
        } else {
            smoothedOilTemp = targetD
            return target
        }
    }

    // PID-Unterstützungs-Flags (Bosch MED9.1 Filter: 010B standardmäßig false)
    @Published public var hasMAPPID            : Bool    = false
    @Published public var hasCheckedMAPPID     : Bool    = false   // false = 010B beim ersten Connect immer probieren
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
        liveBoostBar = nil
        liveMAP = nil
        liveIAT = nil
        liveMAF = nil
        liveEngineLoad = nil
        liveRPM = 0
        liveSpeed = 0
        liveEGT = nil
        smoothedEGT = nil
        smoothedOilTemp = nil
        isColdOverloaded = false
        coldOverloadMessage = ""
        coldOverloadDetail = ""
        batteryVoltage = nil
        isIgnitionOn = nil
        hasOilTempPID = false
        hasCheckedOilTempPID = false
        hasMAPPID = false
        hasCheckedMAPPID = false   // Immer 010B neu probieren bei Reconnect
        sessionConnectedAt = nil
        initialCoolantTemp = nil
        isInitializingUART = false
        initQueue.removeAll()
        isWaitingForResponse = false
        initStepTimer?.invalidate()
        tachoOilTempValue = nil
        tachoOilTempMethod = ""
        isMeasuringTachoOilTemp = false
        // Note: tachoOilTempEnabled und tachoOilTempProbeStatus bleiben erhalten (UI-Anzeige)
    }
}
