// MARK: - EA113DynoCalculator.swift
// Virtueller Prüfstand (Virtual Dyno) für Golf 5 GTI 2.0 TFSI (EA113 Bosch MED9.1)
// Kalibriert für Stage 1 Software: 268,9 PS / 395 Nm Peak
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public final class EA113DynoCalculator: ObservableObject {
    public static let shared = EA113DynoCalculator()

    // ── Kalibrierte Parameter für Stage 1 EA113 ──
    public let targetStage1PS: Double = 268.9
    public let targetStage1Nm: Double = 395.0

    // ── Live Berechnete Werte ──
    @Published public var livePS: Int = 0
    @Published public var liveNm: Int = 0
    @Published public var peakPS: Int = 0
    @Published public var peakNm: Int = 0

    // ── Geglättete Werte für ruhiges Cockpit-Display ──
    private var smoothedPS: Double = 0.0
    private var smoothedNm: Double = 0.0

    public init() {}

    /// Aktualisiert Leistung & Drehmoment basierend auf echter MAF-Luftmasse (g/s) und Drehzahl (RPM)
    @MainActor
    public func update(maf: Double?, rpm: Int, boostBar: Double?) {
        guard rpm > 700 else {
            livePS = 0
            liveNm = 0
            return
        }

        let calculatedPS: Double

        if let mafVal = maf, mafVal > 3.0 {
            // Physikalische EA113 Turbo-Formel:
            // Bei WOT (Volllast) & optimiertem Stage-1 Zündwinkel: PS ≈ MAF * 1.25
            // 215 g/s MAF ≈ 268.9 PS
            let basePS = mafVal * 1.25

            // Ladedruck-Plausibilisierung (falls MAP aktiv):
            if let boost = boostBar, boost > 0.1 {
                // Bei 1.35 bar Haltedruck (typisch Stage 1)
                let boostFactor = min(1.15, max(0.9, 1.0 + (boost - 1.2) * 0.15))
                calculatedPS = basePS * boostFactor
            } else {
                calculatedPS = basePS
            }
        } else if let boost = boostBar, boost > 0.05 {
            // Fallback über Ladedruck & Drehzahl falls MAF kurz aussetzt
            // Saugmotor-Grundleistung (ca. 115 PS bei 6000) * (1 + Ladedruck)
            let pressureRatio = 1.0 + boost
            let rpmRatio = Double(rpm) / 6000.0
            calculatedPS = 115.0 * pressureRatio * min(1.0, rpmRatio * 1.1)
        } else {
            // Leerlauf / Schiebebetrieb
            calculatedPS = Double(rpm) / 350.0
        }

        // Drehmoment über physikalische Formel: M (Nm) = (kW * 9548.8) / RPM = (PS * 7023.5) / RPM
        let calculatedNm = (calculatedPS * 7023.5) / max(Double(rpm), 800.0)

        // Begrenzung auf plausible Stage-1 Obergrenzen (+10% Puffer gegen Messspitzen)
        let clampedPS = min(310.0, max(0.0, calculatedPS))
        let clampedNm = min(440.0, max(0.0, calculatedNm))

        // Glättung (PT1 Filter)
        smoothedPS = (smoothedPS * 0.65) + (clampedPS * 0.35)
        smoothedNm = (smoothedNm * 0.65) + (clampedNm * 0.35)

        livePS = Int(round(smoothedPS))
        liveNm = Int(round(smoothedNm))

        // Peak-Werte festhalten (nur bei Vollgas / Drehzahl > 2500)
        if rpm > 2500 {
            if livePS > peakPS { peakPS = livePS }
            if liveNm > peakNm { peakNm = liveNm }
        }
    }

    @MainActor
    public func resetPeaks() {
        peakPS = 0
        peakNm = 0
    }
}
