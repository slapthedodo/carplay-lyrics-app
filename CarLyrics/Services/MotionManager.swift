// MARK: - MotionManager.swift
// CarLyrics – real-time G-force telemetry via CoreMotion.
// ─────────────────────────────────────────────────────────────────────────────
//
// Uses CMMotionManager.deviceMotion (fused accelerometer + gyro).
// userAcceleration removes gravity — gives only vehicle-induced forces.
//
// Vectors (device frame, calibrated by user):
//   y  → longitudinal (braking −, acceleration +)
//   x  → lateral      (left-turn +, right-turn −)
//
// Combined G = √(x² + y²)   (2-D horizontal plane)
// ─────────────────────────────────────────────────────────────────────────────

import CoreMotion
import Foundation
import Combine
import UIKit

@MainActor
public final class MotionManager: ObservableObject {

    public static let shared = MotionManager()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published state
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var currentG  : Double = 0    // G   combined
    @Published public var gX        : Double = 0    // lateral vector
    @Published public var gY        : Double = 0    // longitudinal vector
    @Published public var peakG     : Double = 0    // session maximum
    @Published public var isActive  : Bool   = false

    /// Konfigurierbare maximale G-Kraft (Skalierung und Plausibilitäts-Grenze)
    @Published public var maxG: Double = {
        let saved = UserDefaults.standard.double(forKey: "carlyrics_max_g_scale")
        return saved > 0.1 ? saved : 1.2
    }() {
        didSet {
            UserDefaults.standard.set(maxG, forKey: "carlyrics_max_g_scale")
            if peakG > maxG {
                peakG = maxG
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private state
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var isCalibrating: Bool = false

    private let motion          = CMMotionManager()
    private var calibrationOffsetX: Double = 0
    private var calibrationOffsetY: Double = 0
    private var calibrationSamplesX: [Double] = []
    private var calibrationSamplesY: [Double] = []
    private var calibrationTimer: Timer? = nil

    private var rawX: Double = 0
    private var rawY: Double = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public init() {}

    private var rawSampleCount: Int = 0

    public var onGChange: ((_ currentG: Double, _ peakG: Double) -> Void)?
    private var lastNotifiedG: Double = 0

    public func start() {
        guard motion.isDeviceMotionAvailable, !isActive else { return }
        motion.deviceMotionUpdateInterval = 0.04   // 25 Hz – ultraschnelle Reaktion
        rawSampleCount = 0
        motion.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in 
                self.process(data)
                // Automatische Nullpunkt-Kalibrierung nach den ersten 25 Messpunkten (ca. 1.0 Sekunden)
                if self.rawSampleCount < 25 {
                    self.rawSampleCount += 1
                    if self.rawSampleCount == 25 {
                        self.calibrate()
                    }
                }
            }
        }
        isActive = true
    }

    public func stop() {
        motion.stopDeviceMotionUpdates()
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        isCalibrating = false
        isActive = false
    }

    /// Nullpunkt über 1.0 Sekunde abtasten und arithmetischen Mittelwert bilden
    /// Filtert Vibrationen, Erschütterungen und Motorklopfen im Stand perfekt heraus.
    public func calibrate(duration: TimeInterval = 1.0) {
        guard !isCalibrating else { return }
        isCalibrating = true
        calibrationSamplesX.removeAll()
        calibrationSamplesY.removeAll()

        calibrationTimer?.invalidate()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.calibrationSamplesX.isEmpty {
                    let avgX = self.calibrationSamplesX.reduce(0.0, +) / Double(self.calibrationSamplesX.count)
                    let avgY = self.calibrationSamplesY.reduce(0.0, +) / Double(self.calibrationSamplesY.count)
                    self.calibrationOffsetX = avgX
                    self.calibrationOffsetY = avgY
                } else {
                    self.calibrationOffsetX = self.rawX
                    self.calibrationOffsetY = self.rawY
                }
                self.peakG = 0
                self.isCalibrating = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    public func resetPeak() {
        peakG = 0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private processing (Direkte, ungefilterte G-Kräfte)
    // ─────────────────────────────────────────────────────────────────────────

    private func process(_ data: CMDeviceMotion) {
        rawX = data.userAcceleration.x
        rawY = data.userAcceleration.y

        if isCalibrating {
            calibrationSamplesX.append(rawX)
            calibrationSamplesY.append(rawY)
        }

        // Direkte G-Kräfte ohne Tiefpassfilter (Reagiert unverzögert auf jede Beschleunigung & Kurve)
        let calX = rawX - calibrationOffsetX
        let calY = rawY - calibrationOffsetY

        // Kombinierte G-Kraft im 2D-Fahrzeugvektor
        let combined = sqrt(calX * calX + calY * calY)

        let limit = max(0.3, maxG)
        // Begrenzung auf das konfigurierte Maximum (fängt unrealistische Stoß- und Schlaglochspitzen ab)
        let clampedCombined = min(limit, combined)

        gX = min(limit, max(-limit, calX))
        gY = min(limit, max(-limit, calY))
        currentG = clampedCombined

        let prevPeak = peakG
        // Peak tracking – bis zum konfigurierten Limit
        if clampedCombined > peakG {
            peakG = clampedCombined
        }

        // Schnelle Benachrichtigung bei G-Kraft-Änderungen >= 0.03 G oder neuem Peak
        let delta = abs(clampedCombined - lastNotifiedG)
        let peakChanged = peakG > prevPeak
        if delta >= 0.03 || peakChanged {
            lastNotifiedG = clampedCombined
            onGChange?(clampedCombined, peakG)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

public extension MotionManager {

    var currentGFormatted: String { String(format: "%.2f G", currentG) }
    var peakGFormatted:    String { String(format: "%.2f G", peakG) }

    /// Normalized vectors clamped to −1 … +1 for UI crosshair based on maxG
    var normalizedX: Double { max(-1, min(1, gX / max(0.3, maxG))) }
    var normalizedY: Double { max(-1, min(1, gY / max(0.3, maxG))) }
}
