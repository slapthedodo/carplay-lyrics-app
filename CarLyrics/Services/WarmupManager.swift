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

    public typealias SeasonalProfile = WarmupCalculator.SeasonalProfile

    /// Liefert das exakte Monats- und Sicherheits-Profil für mitteleuropäisches Klima
    /// Kalibriert nach der Devise: Eher etwas zu lange warmfahren als zu kurz (Turbo- & Motorschutz).
    public static func profileForCurrentDate(date: Date = Date()) -> SeasonalProfile {
        WarmupCalculator.profileForCurrentDate(date: date)
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
        UserDefaults(suiteName: "group.com.carlyrics")?.set(startedAt!.timeIntervalSince1970, forKey: "carlyrics_warmup_started_at")
        UserDefaults(suiteName: "group.com.carlyrics")?.set(startTemp, forKey: "carlyrics_warmup_start_temp")

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
        UserDefaults(suiteName: "group.com.carlyrics")?.removeObject(forKey: "carlyrics_warmup_started_at")
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
        WarmupCalculator.calculateOilTemp(at: t, from: sTemp, targetTemp: targetTemp, lambda: lambda)
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
