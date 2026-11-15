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

        let expected = EA113DynoCalculator.expectedWinDynValues(at: Double(rpm))

        // Volllast-Erkennung (WOT):
        // Hohe Drosselklappe (>75%), hohe Motorlast (>80%), Ladedruck > 0.8 bar oder starker MAF-Durchsatz (>100 g/s)
        let isWOT = (throttle != nil && throttle! >= 75) ||
                    (engineLoad != nil && engineLoad! >= 80) ||
                    (boostBar != nil && boostBar! >= 0.80) ||
                    (maf != nil && maf! >= 105.0)

        let calculatedPS: Double
        let calculatedNm: Double

        if let mafVal = maf, mafVal > 4.0 {
            // Soll-Luftmasse laut EA113 Stage 1 Prüfbericht für diese Drehzahl
            let expectedMAF = max(20.0, expected.ps / 1.25)
            // Tatsächlicher Durchsatz im Verhältnis zum Prüfstands-Soll
            let airflowRatio = min(1.15, max(0.15, mafVal / expectedMAF))

            if isWOT {
                // Bei Volllast: Luftmasse bestimmt, wie nah man an der 100% Stage-1 Kurve liegt
                let wotPerformanceRatio = min(1.08, max(0.85, airflowRatio))
                calculatedPS = expected.ps * wotPerformanceRatio
                calculatedNm = expected.nm * wotPerformanceRatio
            } else {
                // Teillast: Proportionale Skalierung
                let partLoadRatio = min(0.95, max(0.12, airflowRatio))
                calculatedPS = expected.ps * partLoadRatio
                calculatedNm = expected.nm * partLoadRatio
            }
        } else if isWOT {
            // Fallback wenn MAF kurz aussetzt: Volllast liefert die volle Stage-1 Kurve
            calculatedPS = expected.ps
            calculatedNm = expected.nm
        } else {
            // Cruising / Standgas
            let loadRatio = Double(engineLoad ?? throttle ?? 20) / 100.0
            calculatedPS = max(10.0, expected.ps * loadRatio * 0.45)
            calculatedNm = (calculatedPS * 7023.5) / max(Double(rpm), 800.0)
        }

        let clampedPS = min(310.0, max(0.0, calculatedPS))
        let clampedNm = min(440.0, max(0.0, calculatedNm))

        // Asymmetrischer Schnell-Filter:
        // Bei Beschleunigung (Leistungsanstieg): 85% neu, 15% alt -> Sofortiges Ansprechen ohne Latenz!
        // Bei Gaswegnahme: 30% neu, 70% alt -> Weiches, natürliches Ausfedern
        if clampedPS >= smoothedPS {
            smoothedPS = (smoothedPS * 0.15) + (clampedPS * 0.85)
            smoothedNm = (smoothedNm * 0.15) + (clampedNm * 0.85)
        } else {
            smoothedPS = (smoothedPS * 0.70) + (clampedPS * 0.30)
            smoothedNm = (smoothedNm * 0.70) + (clampedNm * 0.30)
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
