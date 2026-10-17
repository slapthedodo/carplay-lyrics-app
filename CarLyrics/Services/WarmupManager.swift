// MARK: - WarmupManager.swift
// CarLyrics – engine warm-up assistant for a 2.0L TFSI Turbo petrol (200 hp).
// ─────────────────────────────────────────────────────────────────────────────
//
// Physics model:
//   The warm-up curve is a Newton-cooling-inspired asymptotic ramp:
//     T(t) = T_target - (T_target - T_start) * exp(-λ * t)
//
//   Tuned constants for a 2.0 TFSI at moderate driving:
//     T_start  = startTemp (20 °C default)
//     T_target = 90 °C
//     λ        = 0.006 s⁻¹  → reaches ~85 °C after ~12 min (720 s)
//
// Phase thresholds:
//     < 60 °C  → COLD    (blue)
//     60–79 °C → WARMING (orange)
//     ≥ 80 °C  → READY   (green) + haptic + flag
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import Combine
import UserNotifications

@MainActor
public final class WarmupManager: ObservableObject {

    public static let shared = WarmupManager()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published state
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var oilTemp        : Double      = 20
    @Published public var phase          : WarmupPhase = .cold
    @Published public var warmupProgress : Double      = 0        // 0 … 1
    @Published public var isEngineWarm   : Bool        = false
    @Published public var elapsedSeconds : TimeInterval = 0
    @Published public var isRunning      : Bool        = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Seasonal & Monthly Safety Profile (EA113 BWA 2.0 TFSI)
    // ─────────────────────────────────────────────────────────────────────────

    public struct SeasonalProfile {
        public let ambientTemp          : Double   // Konservative Starttemperatur
        public let lambda               : Double   // Konservativer Aufheizkoeffizient
        public let estimatedMinutesTo80 : Int      // Warmfahrzeit in Minuten
        public let seasonName           : String   // z.B. "Tiefwinter (Frost)"
    }

    /// Liefert das exakte Monats- und Sicherheits-Profil für mitteleuropäisches Klima
    /// Kalibriert nach der Devise: Eher etwas zu lange warmfahren als zu kurz (Turbo- & Motorschutz).
    public static func profileForCurrentDate(date: Date = Date()) -> SeasonalProfile {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let hour = calendar.component(.hour, from: date)
        let isNightOrEarlyMorning = (hour < 8 || hour >= 22)
        let nightOffset: Double = isNightOrEarlyMorning ? -2.0 : 0.0

        switch month {
        case 1:  // Januar: Tiefwinter, harter Frost (ca. 19-20 Min bis 80°C)
            let base = 2.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(-5.0, base), lambda: 0.0019, estimatedMinutesTo80: 20, seasonName: "Tiefwinter (Frostschutz)")
        case 2:  // Februar: Spätwinter, oft noch Schnee & Salz (ca. 18-19 Min)
            let base = 3.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(-4.0, base), lambda: 0.0020, estimatedMinutesTo80: 19, seasonName: "Spätwinter")
        case 3:  // März: Vorfrühling, kalte Nächte & Morgen (ca. 17 Min)
            let base = 6.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(0.0, base), lambda: 0.00215, estimatedMinutesTo80: 17, seasonName: "Vorfrühling (Kaltphase)")
        case 4:  // April: Typischer wechselhafter Frühling (ca. 15-16 Min)
            let base = 9.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(3.0, base), lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Frühling")
        case 5:  // Mai: Milder Frühling (ca. 14-15 Min)
            let base = 14.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(8.0, base), lambda: 0.00245, estimatedMinutesTo80: 14, seasonName: "Milder Frühling")
        case 6:  // Juni: Frühsommer (ca. 13-14 Min)
            let base = 18.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(12.0, base), lambda: 0.0026, estimatedMinutesTo80: 13, seasonName: "Frühsommer")
        case 7:  // Juli: Hochsommer (ca. 12-13 Min)
            let base = 21.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(15.0, base), lambda: 0.0027, estimatedMinutesTo80: 12, seasonName: "Hochsommer")
        case 8:  // August: Hochsommer (ca. 12-13 Min)
            let base = 20.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(14.0, base), lambda: 0.0027, estimatedMinutesTo80: 12, seasonName: "Hochsommer")
        case 9:  // September: Spätsommer / Frühherbst (ca. 14 Min)
            let base = 15.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(9.0, base), lambda: 0.0025, estimatedMinutesTo80: 14, seasonName: "Spätsommer")
        case 10: // Oktober: Herbst, deutlich kühlere Tage (ca. 15-16 Min)
            let base = 9.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(3.0, base), lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Herbst")
        case 11: // November: Spätherbst, nasskalt (ca. 17-18 Min)
            let base = 5.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(0.0, base), lambda: 0.0021, estimatedMinutesTo80: 18, seasonName: "Spätherbst (Nasskalt)")
        case 12: // Dezember: Winterbeginn & Frost (ca. 19-20 Min)
            let base = 2.0 + nightOffset
            return SeasonalProfile(ambientTemp: max(-5.0, base), lambda: 0.0019, estimatedMinutesTo80: 20, seasonName: "Winterbeginn")
        default:
            return SeasonalProfile(ambientTemp: 10.0, lambda: 0.0023, estimatedMinutesTo80: 16, seasonName: "Standard")
        }
    }

    public var currentProfile: SeasonalProfile {
        Self.profileForCurrentDate()
    }

    public var lambda: Double {
        currentProfile.lambda
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Configuration
    // ─────────────────────────────────────────────────────────────────────────

    public var startTemp    : Double = 10    // °C — wird saisonal dynamisch ermittelt
    public let targetTemp   : Double = 90    // °C operating temperature

    private let coldThreshold    : Double = 60
    private let warmingThreshold : Double = 80

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private state
    // ─────────────────────────────────────────────────────────────────────────

    private var timer              : Timer?
    private var startedAt          : Date?
    private var didFireWarmHaptic  : Bool = false
    private var didSendWarmNotification : Bool = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        let savedTime = UserDefaults.standard.double(forKey: "carlyrics_warmup_started_at")
        let savedTemp = UserDefaults.standard.double(forKey: "carlyrics_warmup_start_temp")
        let now = Date().timeIntervalSince1970
        // Falls die letzte Fahrt vor weniger als 45 Minuten gestartet wurde: Session nahtlos fortsetzen!
        if savedTime > 0 && (now - savedTime) < 2700 {
            self.startedAt = Date(timeIntervalSince1970: savedTime)
            self.startTemp = savedTemp > -20 ? savedTemp : Self.profileForCurrentDate().ambientTemp
            self.isRunning = true
            resumeTimer()
        } else {
            // Frischer Kaltstart mit aktuellem Monats-Sicherheitsprofil
            start(cold: true)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Begin the warm-up curve from `startTemp`.
    /// Call with `cold: true` to reset to ambient, `false` to use a warm start.
    public func start(cold: Bool = true) {
        let profile = Self.profileForCurrentDate()
        if cold {
            startTemp = profile.ambientTemp
        } else {
            startTemp = max(40.0, profile.ambientTemp + 30.0) // z.B. 10 Min. geparkt
        }
        oilTemp                 = startTemp
        elapsedSeconds          = 0
        didFireWarmHaptic       = false
        didSendWarmNotification = false
        isEngineWarm            = false
        warmupProgress          = 0
        phase                   = phaseFor(temp: startTemp)
        startedAt               = Date()
        isRunning               = true

        // Dauerhaft sichern, damit die Temperatur auch bei minimierter oder beendeter App exakt weiterläuft
        UserDefaults.standard.set(startedAt!.timeIntervalSince1970, forKey: "carlyrics_warmup_started_at")
        UserDefaults.standard.set(startTemp, forKey: "carlyrics_warmup_start_temp")

        resumeTimer()
    }

    private func resumeTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func reset() {
        timer?.invalidate()
        timer                   = nil
        isRunning               = false
        oilTemp                 = startTemp
        elapsedSeconds          = 0
        warmupProgress          = 0
        isEngineWarm            = false
        didFireWarmHaptic       = false
        didSendWarmNotification = false
        phase                   = phaseFor(temp: startTemp)
        UserDefaults.standard.removeObject(forKey: "carlyrics_warmup_started_at")
    }

    public func stop() {
        reset()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Tick
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Physics Calculation with Thermal Inertia & Safety Factor
    // ─────────────────────────────────────────────────────────────────────────

    public func calculateOilTemp(at t: TimeInterval, from sTemp: Double) -> Double {
        guard t > 0 else { return sTemp }
        let baseLambda = lambda
        // Thermische Trägheit des 85kg Grauguss-Blocks (EA113 BWA):
        // In den ersten 120 Sekunden absorbiert der schwere Block die Verbrennungswärme,
        // das Öl in der Wanne hinkt hinterher. Wir dämpfen das Lambda für die ersten 2 Minuten sanft ab.
        let effectiveLambda: Double
        if t < 120 {
            effectiveLambda = baseLambda * (0.6 + 0.4 * (t / 120.0))
        } else {
            effectiveLambda = baseLambda
        }
        let newTemp = targetTemp - (targetTemp - sTemp) * exp(-effectiveLambda * t)
        return min(max(newTemp, sTemp), targetTemp)
    }

    private func tick() {
        guard let startedAt else { return }
        let t = Date().timeIntervalSince(startedAt)
        elapsedSeconds = t

        // Newton-cooling asymptotic ramp mit thermischer Trägheit
        let newTemp = calculateOilTemp(at: t, from: startTemp)
        oilTemp = min(newTemp, targetTemp)

        // Progress: 0 → 1 when going from startTemp to 85 °C
        let span = max(10.0, 85.0 - startTemp)
        warmupProgress = max(0, min((oilTemp - startTemp) / span, 1.0))

        // Phase transition
        let newPhase = phaseFor(temp: oilTemp)
        if newPhase != phase { phase = newPhase }

        // One-shot haptic + engine-warm flag + iOS Push Notification
        if oilTemp >= 80 {
            triggerWarmNotificationIfNeeded(temp: Int(oilTemp))
        }

        // Auto-stop once stable at target
        if oilTemp >= targetTemp {
            timer?.invalidate()
            timer     = nil
            isRunning = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers & Benachrichtigungen
    // ─────────────────────────────────────────────────────────────────────────

    public func triggerWarmNotificationIfNeeded(temp: Int) {
        guard !didSendWarmNotification else { return }
        if temp >= 80 {
            didSendWarmNotification = true
            isEngineWarm = true
            fireHaptic()
            sendWarmNotification(temp: temp)
        }
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error {
                print("[WarmupManager] Notification permission error: \(error)")
            }
        }
    }

    private func sendWarmNotification(temp: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Motor ist warm"
        content.body = "Öltemperatur: \(temp)°C"
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "carlyrics_warm_engine", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[WarmupManager] Send notification error: \(error)")
            }
        }
    }

    private func phaseFor(temp: Double) -> WarmupPhase {
        if temp < coldThreshold    { return .cold }
        if temp < warmingThreshold { return .warming }
        return .ready
    }

    private func fireHaptic() {
        guard !didFireWarmHaptic else { return }
        didFireWarmHaptic = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Formatted helpers for UI
    // ─────────────────────────────────────────────────────────────────────────

    public var currentOilTemp: Double {
        guard isRunning, let startedAt else { return startTemp }
        let t = Date().timeIntervalSince(startedAt)
        return calculateOilTemp(at: t, from: startTemp)
    }

    public var oilTempInt: Int { Int(currentOilTemp.rounded()) }

    public var elapsedFormatted: String {
        let mins = Int(elapsedSeconds) / 60
        let secs = Int(elapsedSeconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
