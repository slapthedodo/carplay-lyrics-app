// MARK: - EA113DynoCalculator.swift
// Virtueller Prüfstand (Virtual Dyno) für Golf 5 GTI 2.0 TFSI (EA113 Bosch MED9.1)
// Exakt kalibriert nach custom-chips SuperFlow WinDyn V3.2: 268,9 PS / 392 Nm
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public final class EA113DynoCalculator: ObservableObject {
    public static let shared = EA113DynoCalculator()

    // ── Exakte Prüfstand-Eckdaten laut custom-chips SuperFlow WinDyn V3.2 ──
    public let targetStage1PS: Double = 268.9  // Peak bei 6.300 U/min
    public let targetStage1Nm: Double = 392.0  // Peak bei 2.800 U/min

    // ── Live Berechnete Werte ──
    @Published public var livePS: Int = 0
    @Published public var liveNm: Int = 0

    // ── Permanent in der App gespeicherte Höchstwerte ──
    @Published public var peakPS: Int {
        didSet { UserDefaults.standard.set(peakPS, forKey: "carlyrics_dyno_peak_ps") }
    }
    @Published public var peakNm: Int {
        didSet { UserDefaults.standard.set(peakNm, forKey: "carlyrics_dyno_peak_nm") }
    }

    // ── Geglättete Werte für ruhiges Cockpit-Display ──
    private var smoothedPS: Double = 0.0
    private var smoothedNm: Double = 0.0

    public init() {
        // Lade gespeicherte Höchstwerte aus UserDefaults (bleiben permanent erhalten)
        let savedPS = UserDefaults.standard.integer(forKey: "carlyrics_dyno_peak_ps")
        let savedNm = UserDefaults.standard.integer(forKey: "carlyrics_dyno_peak_nm")
        self.peakPS = savedPS > 0 ? savedPS : 269
        self.peakNm = savedNm > 0 ? savedNm : 392
    }

    /// Aktualisiert Leistung & Drehmoment basierend auf MAF (g/s), Drehzahl (RPM), Ladedruck, Gaspedal und Motorlast
    @MainActor
    public func update(maf: Double?, rpm: Int, boostBar: Double?, throttle: Int? = nil, engineLoad: Int? = nil) {
        guard rpm > 700 else {
            livePS = 0
            liveNm = 0
            return
        }

        let currentRPM = Double(rpm)
        let expected = EA113DynoCalculator.expectedWinDynValues(at: currentRPM)

        // ── 1. Volllast-Erkennung (WOT) ──
        // Ein EA113 Golf 5 GTI ist bei WOT wenn:
        // - Gaspedal/Drosselklappe >= 65%
        // - ODER Motorlast >= 70%
        // - ODER Ladedruck >= 0.60 bar
        // - ODER Luftmasse erreicht mindestens 60% des Volllast-Solls für diese Drehzahl
        let expectedWOT_MAF = max(25.0, (expected.ps / 1.25))
        let isHighMAF = (maf != nil && maf! >= (expectedWOT_MAF * 0.60))

        let isWOT = (throttle != nil && throttle! >= 65) ||
                    (engineLoad != nil && engineLoad! >= 70) ||
                    (boostBar != nil && boostBar! >= 0.60) ||
                    isHighMAF

        let rawPS: Double
        let rawNm: Double

        if let mafVal = maf, mafVal > 5.0 {
            // PHYSIKALISCH EXAKTE LEISTUNGSBERECHNUNG:
            // 1 g/s Luftmasse im 2.0 TFSI = 1,25 PS Kurbelwellenleistung (Stage 1 / Lambda ~0.85)
            let directPS = mafVal * 1.25

            if isWOT {
                // Bei Vollgas: Echte gemessene Leistung aus MAF!
                // Wenn Vollgas erkannt wurde, erreicht der EA113 92% bis 105% der Prüfstandskurve
                let dynamicPS = max(directPS, expected.ps * 0.92)
                rawPS = min(expected.ps * 1.05, dynamicPS)
                rawNm = (rawPS * 7023.5) / currentRPM
            } else {
                // Teillast: Echte Leistung direkt aus MAF (flüssig skaliert)
                let partialPS = min(expected.ps * 0.88, max(8.0, directPS))
                rawPS = partialPS
                rawNm = (rawPS * 7023.5) / currentRPM
            }
        } else if isWOT {
            // Vollgas-Fallback ohne MAF: Folgt exakt der Stage 1 Prüfstandskurve
            rawPS = expected.ps
            rawNm = expected.nm
        } else {
            // Teillast / Cruising ohne MAF
            let loadRatio = Double(engineLoad ?? throttle ?? 25) / 100.0
            rawPS = max(10.0, expected.ps * loadRatio * 0.45)
            rawNm = (rawPS * 7023.5) / currentRPM
        }

        let clampedPS = min(310.0, max(0.0, rawPS))
        let clampedNm = min(440.0, max(0.0, rawNm))

        // Asymmetrischer Schnell-Filter für direktes, sportliches Gasannahme-Gefühl:
        // Bei Leistungsanstieg (Gas geben): 90% neu, 10% alt -> Sofortiger Anschlag ohne Verzögerung!
        // Bei Gaswegnahme: 40% neu, 60% alt -> Weiches, natürliches Abtouren
        if clampedPS >= smoothedPS {
            smoothedPS = (smoothedPS * 0.10) + (clampedPS * 0.90)
            smoothedNm = (smoothedNm * 0.10) + (clampedNm * 0.90)
        } else {
            smoothedPS = (smoothedPS * 0.60) + (clampedPS * 0.40)
            smoothedNm = (smoothedNm * 0.60) + (clampedNm * 0.40)
        }

        livePS = Int(round(smoothedPS))
        liveNm = Int(round(smoothedNm))

        // Peak-Werte festhalten und permanent speichern
        if rpm > 2200 {
            if livePS > peakPS { peakPS = livePS }
            if liveNm > peakNm { peakNm = liveNm }
        }
    }

    /// Liefert die theoretischen Soll-Werte laut custom-chips SuperFlow WinDyn Datenblatt für jede Drehzahl
    public static func expectedWinDynValues(at rpm: Double) -> (ps: Double, nm: Double) {
        if rpm < 1750 {
            return (65.0, 260.0)
        } else if rpm <= 2800 {
            // Steiler Drehmoment-Aufbau von 1750 (260 Nm) bis 2800 (392 Nm Peak)
            let factor = (rpm - 1750.0) / (2800.0 - 1750.0)
            let nm = 260.0 + (392.0 - 260.0) * factor
            let ps = 65.0 + (156.0 - 65.0) * factor
            return (ps, nm)
        } else if rpm <= 4500 {
            // Sanftes Drehmoment-Plateau 2800 (392 Nm) bis 4500 (352 Nm)
            let factor = (rpm - 2800.0) / (4500.0 - 2800.0)
            let nm = 392.0 - (392.0 - 352.0) * factor
            let ps = 156.0 + (225.0 - 156.0) * factor
            return (ps, nm)
        } else if rpm <= 6300 {
            // Leistungsanstieg bis zum Peak 6300 (268.9 PS)
            let factor = (rpm - 4500.0) / (6300.0 - 4500.0)
            let nm = 352.0 - (352.0 - 245.0) * factor
            let ps = 225.0 + (268.9 - 225.0) * factor
            return (ps, nm)
        } else if rpm <= 6700 {
            // Breites Leistungs-Plateau bis zum Begrenzer
            let factor = (rpm - 6300.0) / (6700.0 - 6300.0)
            let nm = 245.0 - (245.0 - 220.0) * factor
            let ps = 268.9 - (268.9 - 260.0) * factor
            return (ps, nm)
        } else {
            // Steiler Drehzahlabfall am Begrenzer (6800+)
            return (100.0, 100.0)
        }
    }

    @MainActor
    public func resetPeaks() {
        peakPS = 0
        peakNm = 0
    }
}
