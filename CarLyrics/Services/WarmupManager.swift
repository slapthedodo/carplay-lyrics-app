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
    // MARK: Configuration
    // ─────────────────────────────────────────────────────────────────────────

    public var startTemp    : Double = 20    // °C — can be set before start()
    public let targetTemp   : Double = 90    // °C operating temperature
    public let lambda       : Double = 0.0028 // Realistischer 2.0 TFSI Wert: ~15-18 Min. bis 80°C

    private let coldThreshold    : Double = 60
    private let warmingThreshold : Double = 80

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private state
    // ─────────────────────────────────────────────────────────────────────────

    private var timer              : Timer?
    private var startedAt          : Date?
    private var didFireWarmHaptic  : Bool = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Begin the warm-up curve from `startTemp`.
    /// Call with `cold: true` to reset to ambient, `false` to use a warm start.
    public func start(cold: Bool = true) {
        if cold {
            // Winter/Kaltzeit-Erkennung (Okt - April): 8°C statt 20°C
            let month = Calendar.current.component(.month, from: Date())
            let isWinter = (month >= 10 || month <= 4)
            startTemp = isWinter ? 8.0 : 20.0
        } else {
            startTemp = 45.0 // z.B. 10 Min. geparkt
        }
        oilTemp           = startTemp
        elapsedSeconds    = 0
        didFireWarmHaptic = false
        isEngineWarm      = false
        warmupProgress    = 0
        phase             = phaseFor(temp: startTemp)
        startedAt         = Date()
        isRunning         = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    public func reset() {
        timer?.invalidate()
        timer          = nil
        isRunning      = false
        oilTemp        = startTemp
        elapsedSeconds = 0
        warmupProgress = 0
        isEngineWarm   = false
        phase          = phaseFor(temp: startTemp)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Tick
    // ─────────────────────────────────────────────────────────────────────────

    private func tick() {
        guard let startedAt else { return }
        let t = Date().timeIntervalSince(startedAt)
        elapsedSeconds = t

        // Newton-cooling asymptotic ramp
        let newTemp = targetTemp - (targetTemp - startTemp) * exp(-lambda * t)
        oilTemp = min(newTemp, targetTemp)

        // Progress: 0 → 1 when going from startTemp to 85 °C
        let span = 85.0 - startTemp
        warmupProgress = max(0, min((oilTemp - startTemp) / span, 1.0))

        // Phase transition
        let newPhase = phaseFor(temp: oilTemp)
        if newPhase != phase { phase = newPhase }

        // One-shot haptic + engine-warm flag
        if oilTemp >= 80 && !isEngineWarm {
            isEngineWarm = true
            fireHaptic()
        }

        // Auto-stop once stable at target
        if oilTemp >= targetTemp {
            timer?.invalidate()
            timer     = nil
            isRunning = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

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

    public var oilTempInt: Int { Int(oilTemp.rounded()) }

    public var elapsedFormatted: String {
        let mins = Int(elapsedSeconds) / 60
        let secs = Int(elapsedSeconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
