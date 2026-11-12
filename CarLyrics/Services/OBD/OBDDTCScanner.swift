// MARK: - OBDDTCScanner.swift
// Fehlerspeicher Diagnose (Mode 03, Mode 07) & Löschen (Mode 04) für CarLyrics
// Mit spezieller VW EA113 / Bosch MED9.1 Fehlerdatenbank & deutscher Erklärung
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public struct DiagnosticTroubleCode: Identifiable, Hashable {
    public let id = UUID()
    public let code: String          // z.B. "P0299"
    public let title: String         // z.B. "Ladedruckregelung: Regelgrenze unterschritten"
    public let detail: String        // z.B. "Typischer EA113 Fehler: Schubumluftventil SUV defekt..."
    public let severity: DTCSeverity
    public let isPending: Bool       // Mode 07 (Pending) vs Mode 03 (Confirmed)
}

public enum DTCSeverity: String {
    case critical = "Kritisch"
    case warning  = "Warnung"
    case info     = "Hinweis"

    public var colorHex: String {
        switch self {
        case .critical: return "red"
        case .warning:  return "orange"
        case .info:     return "yellow"
        }
    }
}

public final class OBDDTCScanner: ObservableObject {
    public static let shared = OBDDTCScanner()

    @Published public var storedCodes: [DiagnosticTroubleCode] = []
    @Published public var isScanning: Bool = false
    @Published public var isClearing: Bool = false
    @Published public var lastScanDate: Date? = nil
    @Published public var statusMessage: String = "Noch kein Scan durchgeführt"

    // ── VAG EA113 / Golf 5 GTI Fehlerdatenbank ──
    private static let vagDatabase: [String: (title: String, detail: String, severity: DTCSeverity)] = [
        "P0299": (
            "Ladedruckregelung: Regelgrenze unterschritten",
            "Der Turbolader erreicht den Solldruck nicht. Häufigste Ursachen beim EA113: Schubumluftventil (SUV) Membran gerissen (auf neues Kolbenventil 'D' umbauen!) oder Wastegate-Gestänge ausgeschlagen.",
            .critical
        ),
        "P0300": (
            "Verbrennungsaussetzer erkannt (mehrere Zylinder)",
            "Unregelmäßige Zündungen. Zündkerzen, Zündspulen (z.B. Audi R8 Spulen) oder Kraftstoffdruck prüfen.",
            .critical
        ),
        "P0301": ("Verbrennungsaussetzer Zylinder 1", "Zündkerze oder Zündspule an Zylinder 1 prüfen/tauschen.", .warning),
        "P0302": ("Verbrennungsaussetzer Zylinder 2", "Zündkerze oder Zündspule an Zylinder 2 prüfen/tauschen.", .warning),
        "P0303": ("Verbrennungsaussetzer Zylinder 3", "Zündkerze oder Zündspule an Zylinder 3 prüfen/tauschen.", .warning),
        "P0304": ("Verbrennungsaussetzer Zylinder 4", "Zündkerze oder Zündspule an Zylinder 4 prüfen/tauschen.", .warning),
        "P0171": (
            "Kraftstoffbemessungssystem: Gemisch zu mager (Bank 1)",
            "Motor zieht Falschluft oder Kurbelgehäuseentlüftung (PCV-Ventil) ist undicht. Kann bei Volllast zu Überhitzung führen!",
            .critical
        ),
        "P2187": (
            "System zu mager bei Leerlaufdrehzahl (Bank 1)",
            "Klassischer EA113 Fehler! Fast immer ist die Membran im Kurbelgehäuseentlüftungsventil (PCV) gerissen.",
            .warning
        ),
        "P0087": (
            "Kraftstoffverteilerrohr-Druck zu niedrig",
            "WICHTIG BEIM EA113: Sofort den Becherstößel der Hochdruckpumpe (HD-Pumpe) prüfen! Wenn dieser durchgeschliffen ist, droht Nockenwellenschaden.",
            .critical
        ),
        "P2293": (
            "Kraftstoffdruckregler-Ventil (N276): Mechanischer Fehler",
            "Hochdruckpumpen-Regelventil. Ebenfalls Becherstößel und Nockenwelle kontrollieren.",
            .critical
        ),
        "P0420": (
            "Katalysatorsystem Wirkungsgrad unter Schwellenwert",
            "Katalysator oder Nachkat-Lambdasonde. Bei Downpipe ohne Software-Anpassung häufig.",
            .info
        ),
        "P0101": (
            "Luftmassenmesser (G70): unplausibles Signal",
            "Luftmassenmesser reinigen oder prüfen, Ansaugschlauch auf Risse prüfen.",
            .warning
        ),
        "P0102": ("Luftmassenmesser (G70): Signal zu klein", "Kabelbruch oder LMM defekt.", .warning),
        "P0106": ("Saugrohrdrucksensor (G71): unplausibles Signal", "MAP-Sensor im Saugrohr prüfen/reinigen.", .warning),
        "P0118": ("Kühlmitteltemperatursensor (G62): Signal zu groß", "Doppeltemperaturgeber tauschen.", .warning),
        "P0507": ("Leerlaufregelung: Drehzahl über Sollwert", "Falschluft im Ansaugtrakt oder Drosselklappe verschmutzt.", .warning),
        "P2015": (
            "Saugrohrklappen-Positionssensor: unplausibles Signal",
            "Saugrohrklappen im Ansaugkrümmer ausgeschlagen oder Sensorhebel lose (P2015-Begrenzer nachrüsten).",
            .warning
        ),
        "P0441": (
            "Tankentlüftungssystem: fehlerhafter Durchfluss",
            "N80-Magnetventil der Tankentlüftung klemmt (sitzt oben am Ventildeckel).",
            .info
        )
    ]

    public init() {}

    /// Startet einen vollständigen Fehlerspeicher-Scan (Mode 03 + Mode 07)
    @MainActor
    public func startScan(obd: OBDManager) async {
        guard obd.connectionState == .connected else {
            statusMessage = "⚠️ OBD nicht verbunden."
            return
        }
        guard !isScanning else { return }

        isScanning = true
        statusMessage = "Lese Fehlerspeicher aus (Mode 03 & 07)…"

        let wasPolling = obd.isPollingActive
        if wasPolling {
            obd.stopPolling()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        var found: [DiagnosticTroubleCode] = []

        // 1. Mode 03: Gespeicherte Fehler (Confirmed DTCs)
        let resp03 = await obd.sendSingleOBDCommand("03", timeout: 3.0)
        let parsed03 = parseDTCResponse(resp03, isPending: false)
        found.append(contentsOf: parsed03)

        try? await Task.sleep(nanoseconds: 150_000_000)

        // 2. Mode 07: Vorläufige Fehler (Pending DTCs)
        let resp07 = await obd.sendSingleOBDCommand("07", timeout: 3.0)
        let parsed07 = parseDTCResponse(resp07, isPending: true)
        for code in parsed07 {
            if !found.contains(where: { $0.code == code.code }) {
                found.append(code)
            }
        }

        storedCodes = found
        lastScanDate = Date()
        isScanning = false

        if wasPolling {
            try? await Task.sleep(nanoseconds: 100_000_000)
            obd.startPolling()
        }

        if found.isEmpty {
            statusMessage = "✅ Keine Fehler hinterlegt! Fehlerspeicher ist sauber."
        } else {
            statusMessage = "⚠️ \(found.count) Fehlercode(s) gefunden!"
        }
    }

    /// Löscht den Fehlerspeicher und setzt die Motorkontrollleuchte (MIL) zurück (Mode 04)
    @MainActor
    public func clearDTCs(obd: OBDManager) async {
        guard obd.connectionState == .connected else {
            statusMessage = "⚠️ OBD nicht verbunden."
            return
        }
        guard !isClearing else { return }

        isClearing = true
        statusMessage = "Lösche Fehlerspeicher (Mode 04)…"

        let wasPolling = obd.isPollingActive
        if wasPolling {
            obd.stopPolling()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let resp04 = await obd.sendSingleOBDCommand("04", timeout: 3.5)
        let compact = resp04.replacingOccurrences(of: " ", with: "").uppercased()

        if compact.contains("44") || compact.contains("OK") {
            storedCodes.removeAll()
            statusMessage = "✅ Fehlerspeicher erfolgreich gelöscht!"
        } else {
            statusMessage = "Antwort auf Mode 04: \(resp04)"
        }

        isClearing = false

        if wasPolling {
            try? await Task.sleep(nanoseconds: 100_000_000)
            obd.startPolling()
        }
    }

    /// Dekodiert eine rohe OBD Mode 03/07 Antwort in DTC-Objekte
    internal func parseDTCResponse(_ raw: String, isPending: Bool) -> [DiagnosticTroubleCode] {
        let compact = raw.replacingOccurrences(of: " ", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\n", with: "")
                         .uppercased()

        guard !compact.isEmpty,
              !compact.contains("NODATA"),
              !compact.contains("ERROR"),
              !compact.contains("STOPPED") else { return [] }

        // Mode 03 Prefix = 43, Mode 07 Prefix = 47
        let prefix = isPending ? "47" : "43"
        guard let range = compact.range(of: prefix) else { return [] }

        let after = String(compact[range.upperBound...])
        // Überspringe ggf. DTC-Count Byte (erste 2 Hex-Zeichen)
        var hexStream = after
        if hexStream.count % 4 != 0 && hexStream.count >= 2 {
            hexStream = String(hexStream.dropFirst(2))
        }

        var results: [DiagnosticTroubleCode] = []
        var index = hexStream.startIndex

        while hexStream.distance(from: index, to: hexStream.endIndex) >= 4 {
            let nextIndex = hexStream.index(index, offsetBy: 4)
            let dtcHex = String(hexStream[index..<nextIndex])
            index = nextIndex

            if dtcHex == "0000" { continue }

            if let formatted = decodeDTCBytes(dtcHex) {
                let dbEntry = Self.vagDatabase[formatted]
                let codeItem = DiagnosticTroubleCode(
                    code: formatted,
                    title: dbEntry?.title ?? "Standard OBD-II Diagnosecode",
                    detail: dbEntry?.detail ?? "Hersteller-spezifischer oder generischer Fehlercode. Siehe VCDS/Reparaturleitfaden.",
                    severity: dbEntry?.severity ?? .warning,
                    isPending: isPending
                )
                if !results.contains(where: { $0.code == formatted }) {
                    results.append(codeItem)
                }
            }
        }

        return results
    }

    /// Wandelt 4 Hex-Zeichen (2 Bytes) in einen DTC-String um (z.B. "0299" -> "P0299")
    internal func decodeDTCBytes(_ hex4: String) -> String? {
        guard hex4.count == 4, let byte1 = UInt8(hex4.prefix(2), radix: 16) else { return nil }
        let typeBits = (byte1 >> 6) & 0x03
        let firstLetter: String
        switch typeBits {
        case 0: firstLetter = "P"
        case 1: firstLetter = "C"
        case 2: firstLetter = "B"
        case 3: firstLetter = "U"
        default: firstLetter = "P"
        }

        let secondDigit = (byte1 >> 4) & 0x03
        let thirdDigit = String(format: "%X", byte1 & 0x0F)
        let lastTwoDigits = String(hex4.suffix(2))

        return "\(firstLetter)\(secondDigit)\(thirdDigit)\(lastTwoDigits)"
    }
}
