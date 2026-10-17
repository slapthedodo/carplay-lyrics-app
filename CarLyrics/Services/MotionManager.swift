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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private state
    // ─────────────────────────────────────────────────────────────────────────

    private let motion          = CMMotionManager()
    private var calibrationOffsetX: Double = 0
    private var calibrationOffsetY: Double = 0

    private var rawX: Double = 0
    private var rawY: Double = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public init() {}

    private var rawSampleCount: Int = 0

    public func start() {
        guard motion.isDeviceMotionAvailable, !isActive else { return }
        motion.deviceMotionUpdateInterval = 0.05   // 20 Hz – ultraschnelle Reaktion
        rawSampleCount = 0
        motion.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in 
                self.process(data)
                // Automatische Nullpunkt-Kalibrierung nach den ersten 15 Messpunkten (ca. 0.75 Sekunden)
                if self.rawSampleCount < 15 {
                    self.rawSampleCount += 1
                    if self.rawSampleCount == 15 {
                        self.calibrate()
                    }
                }
            }
        }
        isActive = true
    }

    public func stop() {
        motion.stopDeviceMotionUpdates()
        isActive = false
    }

    /// Zero out the current reading as the new "straight & level" baseline.
    /// Call this once the phone is mounted in the car holder.
    public func calibrate() {
        calibrationOffsetX = rawX
        calibrationOffsetY = rawY
        peakG = 0
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

        // Direkte G-Kräfte ohne Tiefpassfilter (Reagiert unverzögert auf jede Beschleunigung & Kurve)
        let calX = rawX - calibrationOffsetX
        let calY = rawY - calibrationOffsetY

        // Kombinierte G-Kraft im 2D-Fahrzeugvektor
        let combined = sqrt(calX * calX + calY * calY)

        gX = calX
        gY = calY
        currentG = combined

        // Peak tracking – unbegrenzt, erfasst alle tatsächlichen Kräfte
        if combined > peakG {
            peakG = combined
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

public extension MotionManager {

    var currentGFormatted: String { String(format: "%.1f G", currentG) }
    var peakGFormatted:    String { String(format: "%.1f G", peakG) }

    /// Normalized vectors clamped to −1 … +1 for UI crosshair
    var normalizedX: Double { max(-1, min(1, gX / 1.5)) }
    var normalizedY: Double { max(-1, min(1, gY / 1.5)) }
}
