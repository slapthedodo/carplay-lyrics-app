// MARK: - OBDTypes.swift
// Datenmodelle, Enums & Protokoll-Definitionen für OBD-II (Bosch MED9.1 & ELM327)
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Connection State & Protocols
// ─────────────────────────────────────────────────────────────────────────────

public enum OBDConnectionState: String {
    case disconnected = "Getrennt"
    case scanning     = "Suche Adapter…"
    case connecting   = "Kopple BLE…"
    case initializing = "ELM327 Handshake…"
    case searchingECU = "Suche Steuergerät…"
    case connected    = "Verbunden"
    case error        = "Fehler"
}

public enum OBDProtocol: String, CaseIterable, Identifiable {
    case can11_500     = "VAG CAN 11-Bit 500k (Standard Golf 5)"
    case can11_500_7e0 = "VAG CAN 11-Bit 500k (Direkt Header 7E0)"
    case kwpFast       = "KWP2000 Fast Init (ISO 14230-4)"
    case kwp5Baud      = "KWP2000 5-Baud (ISO 14230-4)"
    case can29_500     = "CAN 29-Bit 500k (ISO 15765-4)"
    case iso9141       = "ISO 9141-2 (5-Baud Car)"
    case auto          = "Auto-Protokollsuche (ELM327 Standard)"

    public var id: String { rawValue }

    public var elmCommand: String {
        switch self {
        case .can11_500, .can11_500_7e0: return "ATSP6"
        case .kwpFast:                   return "ATSP5"
        case .kwp5Baud:                  return "ATSP4"
        case .can29_500:                 return "ATSP7"
        case .iso9141:                   return "ATSP3"
        case .auto:                      return "ATSP0"
        }
    }

    public var headerCommand: String? {
        switch self {
        case .can11_500_7e0: return "ATSH7E0"
        default:             return nil
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Diagnostics & Terminal Models
// ─────────────────────────────────────────────────────────────────────────────

public struct OBDDiagnosisStep: Identifiable {
    public let id = UUID()
    public let title: String
    public var detail: String
    public var status: StepStatus

    public init(title: String, detail: String, status: StepStatus = .waiting) {
        self.title = title
        self.detail = detail
        self.status = status
    }

    public enum StepStatus {
        case waiting
        case inProgress
        case success
        case failed
        case warning
    }
}

public struct ProtocolProbeResult: Identifiable {
    public let id = UUID()
    public let proto: OBDProtocol
    public var status: ProbeStatus
    public var rawResponse: String
    public var responseTimeMs: Int
    public var note: String

    public enum ProbeStatus {
        case pending
        case testing
        case success
        case failed
        case noData
    }
}

public struct OBDTerminalEntry: Identifiable {
    public let id = UUID()
    public let timestamp: String
    public let direction: Direction
    public let text: String
    public let style: EntryStyle

    public enum Direction {
        case tx
        case rx
        case system
    }

    public enum EntryStyle {
        case normal
        case success
        case error
        case warning
    }
}

public struct OBDDiscoveredDevice: Identifiable {
    public let id: String
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Notification Names
// ─────────────────────────────────────────────────────────────────────────────

public extension Notification.Name {
    static let obdDidConnectECU       = Notification.Name("obdDidConnectECU")
    static let obdDidUpdateTelemetry  = Notification.Name("obdDidUpdateTelemetry")
    static let obdDidDisconnect       = Notification.Name("obdDidDisconnect")
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Golf 5 GTI EA113 Gear Estimator
// ─────────────────────────────────────────────────────────────────────────────

public enum Golf5GTIGearEstimator {
    /// Berechnet den eingelegten Gang anhand der exakten VAG 02Q / DQ250 Übersetzungen
    /// für VW Golf 5 GTI (EA113 2.0 TFSI) mit 225/40 R18 / 225/45 R17 Serienbereifung.
    public static func estimate(speed: Int, rpm: Int) -> String {
        guard speed >= 5, rpm >= 500 else { return "N" }

        let ratio = Double(rpm) / Double(speed)

        // Auskuppeln / Leerlauf während der Fahrt (Standgas < 1100 RPM bei Geschwindigkeit)
        if ratio < 19.0 && rpm < 1100 {
            return "N"
        }

        // VW Golf 5 GTI Getriebeübersetzungen (RPM / km/h):
        // 1. Gang: ~131.5 (Schwelle: > 95.0)
        // 2. Gang: ~72.5  (Schwelle: > 58.0)
        // 3. Gang: ~47.2  (Schwelle: > 41.0)
        // 4. Gang: ~35.7  (Schwelle: > 31.0)
        // 5. Gang: ~26.7  (Schwelle: > 24.5)
        // 6. Gang: ~22.3  (Schwelle: >= 18.0)
        if ratio > 95.0 { return "1" }
        if ratio > 58.0 { return "2" }
        if ratio > 41.0 { return "3" }
        if ratio > 31.0 { return "4" }
        if ratio > 24.5 { return "5" }
        if ratio >= 18.0 { return "6" }

        return "N"
    }
}
