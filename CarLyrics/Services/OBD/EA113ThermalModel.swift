// MARK: - EA113ThermalModel.swift
// Physikalisch kalibriertes Thermik-Modell für VW Golf 5 GTI (2.0 TFSI EA113 / Bosch MED9.1)
// 4.6 Liter Motoröl (5W-30/5W-40), Grauguss-Block, Öl-Wasser-Wärmetauscher am Ölfilterblock.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public final class EA113ThermalModel {
    public static let shared = EA113ThermalModel()

    private let userDefaults = UserDefaults.standard
    private let keyLastStopTime = "EA113_LastStopTime"
    private let keyLastStopTemp = "EA113_LastStopTemp"

    // Interner Simulationszustand
    private var simulatedOilTemp: Double = 10.0
    private var lastUpdateTime: Date? = nil
    private var isInitialized: Bool = false

    /// Liefert die aktuell modellierte Öltemperatur in °C
    public var currentOilTemp: Int {
        Int(simulatedOilTemp.rounded())
    }

    public init() {
        simulatedOilTemp = calculateInitialStartTemp()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Standzeit-Berechnung (Newton-Abkühlung)
    // ─────────────────────────────────────────────────────────────────────────

    /// Berechnet die Starttemperatur nach dem Abstellen anhand der realen Standzeit.
    /// Nach 5 Stunden Standzeit ist der 2.0 TFSI Block vollständig kalt (= Umgebungstemperatur).
    public func calculateInitialStartTemp() -> Double {
        let ambient = WarmupCalculator.profileForCurrentDate().ambientTemp
        let lastStopTime = userDefaults.double(forKey: keyLastStopTime)
        let lastStopTemp = userDefaults.double(forKey: keyLastStopTemp)
        let now = Date().timeIntervalSince1970

        // Falls noch nie gespeichert oder fehlerhaft: Außentemperatur nehmen
        guard lastStopTime > 0, lastStopTemp > ambient, (now - lastStopTime) > 0 else {
            return ambient
        }

        let standzeitSekunden = now - lastStopTime

        // Halbwertszeit der Abkühlung für massiven 2.0 TFSI Grauguss-Block: ca. 75 Minuten (4500 s).
        // kCool = 0.00015 s⁻¹
        // Nach 30 Min: ~75% Restwärme
        // Nach 2 Std:  ~34% Restwärme
        // Nach 5 Std:  < 6% Restwärme -> Motorblock ist praktisch vollständig kalt!
        let kCool = 0.00015
        let remainingTempDelta = (lastStopTemp - ambient) * exp(-kCool * standzeitSekunden)

        let calculatedStart = ambient + remainingTempDelta
        return max(ambient, min(lastStopTemp, calculatedStart))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Zeitbasiertes Ramping während der Fahrt
    // ─────────────────────────────────────────────────────────────────────────

    /// Wird aufgerufen, wenn neue OBD-Telemetriedaten (Kühlmittel, RPM, Ladedruck) eintreffen.
    /// WICHTIG: Streng zeitbasiert über `dt = now - lastUpdateTime`, NIEMALS framebasiert!
    public func update(coolantTemp: Int?, rpm: Int, boostBar: Double?, now: Date = Date()) {
        guard let coolant = coolantTemp else { return }

        if !isInitialized {
            let standTemp = calculateInitialStartTemp()
            // Falls das Kühlwasser noch kälter ist als die geschätzte Stand-Temp, nimm das kältere
            if Double(coolant) < standTemp {
                simulatedOilTemp = Double(coolant)
            } else {
                simulatedOilTemp = standTemp
            }
            lastUpdateTime = now
            isInitialized = true
            return
        }

        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = now
            return
        }

        let dt = min(now.timeIntervalSince(lastTime), 5.0) // Obergrenze 5s gegen Zeitsprünge
        guard dt >= 0.05 else { return } // Max. alle 50ms aktualisieren
        lastUpdateTime = now

        let coolantD = Double(coolant)

        // ── Physikalische Zieltemperatur (Betriebstemperatur) ──
        // Im Leerlauf/Normalfahrt stabilisiert sich EA113 Motoröl bei ca. 88-92°C.
        var targetOil: Double = 90.0

        // Ladedruck & Drehzahl-Zuschlag:
        // Bei sportlicher Fahrt (Ladedruck > 0.5 bar, RPM > 3500) steigt das Öl auf 96-105°C
        let boostBonus = max(0.0, (boostBar ?? 0.0)) * 7.0
        let rpmBonus = rpm > 3500 ? Double(min(10, (rpm - 3500) / 280)) : 0.0
        targetOil += (boostBonus + rpmBonus)

        // ── Physikalische Aufheizrate für 4.6L Öl ──
        // Basis-Rate: Erwärmt das Öl bei normaler Fahrt in ca. 12-15 Minuten von kalt auf 80°C.
        var heatingRate: Double = 0.0018 // s⁻¹

        if coolantD > simulatedOilTemp {
            // Sobald Kühlwasser wärmer als Öl ist, überträgt der Öl-Wasser-Wärmetauscher
            // zusätzliche Wärme ins Öl (proportional zum Temperaturunterschied)
            let deltaWater = min(coolantD - simulatedOilTemp, 60.0)
            heatingRate += (deltaWater / 60.0) * 0.0012
        }

        if rpm > 2600 {
            // Mehr Öldurchfluss durch Kolbenbodenkühlung & Kurbelwelle
            heatingRate *= 1.25
        }

        let tempDelta = heatingRate * (targetOil - simulatedOilTemp) * dt

        // Physikalische Obergrenze: Max. 0.075°C pro Sekunde (~4.5°C pro Minute)
        // Verhindert unrealistisches Hochschießen selbst bei glühend heißem Kühlwasser!
        let maxDeltaAllowed = 0.075 * dt
        let clampedDelta = min(tempDelta, maxDeltaAllowed)

        simulatedOilTemp += clampedDelta

        // Zustand persistieren für den nächsten Kaltstart-Vergleich
        userDefaults.set(now.timeIntervalSince1970, forKey: keyLastStopTime)
        userDefaults.set(simulatedOilTemp, forKey: keyLastStopTemp)
    }

    public func reset() {
        lastUpdateTime = nil
        isInitialized = false
    }
}
