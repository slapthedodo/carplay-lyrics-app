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

    // Low-pass filter factor (0 = no filtering, 1 = fully damped)
    private let alpha: Double = 0.8

    private var filteredX: Double = 0
    private var filteredY: Double = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public init() {}

    public func start() {
        guard motion.isDeviceMotionAvailable, !isActive else { return }
        motion.deviceMotionUpdateInterval = 0.1   // 10 Hz
        motion.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in self.process(data) }
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
        calibrationOffsetX = filteredX
        calibrationOffsetY = filteredY
        peakG = 0
    }

    public func resetPeak() {
        peakG = 0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private processing
    // ─────────────────────────────────────────────────────────────────────────

    private func process(_ data: CMDeviceMotion) {
        let rawX = data.userAcceleration.x
        let rawY = data.userAcceleration.y

        // Low-pass filter to smooth sensor noise
        filteredX = alpha * filteredX + (1 - alpha) * rawX
        filteredY = alpha * filteredY + (1 - alpha) * rawY

        // Apply calibration offset
        let calX = filteredX - calibrationOffsetX
        let calY = filteredY - calibrationOffsetY

        // Combined 2-D G-force in the horizontal plane
        let combined = sqrt(calX * calX + calY * calY)

        gX = calX
        gY = calY
        currentG = combined

        if combined > peakG { peakG = combined }
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
