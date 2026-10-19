// MARK: - HandyModusGForcePanel.swift
// G-Kräfte Scope-Panel: GBall + Gauge + Live-Vektoren für den Handy-Modus
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusGForcePanel: View {
    @ObservedObject public var motion: MotionManager

    public init(motion: MotionManager) {
        self.motion = motion
    }

    // Purple accent matching rest of design system
    private let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public var body: some View {
        VStack(spacing: 8) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(purple)
                Text("G-KRÄFTE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(purple.opacity(0.8))

                Spacer()

                // Kalibrieren (1s Mittelwert)
                Button {
                    motion.calibrate()
                } label: {
                    if motion.isCalibrating {
                        HStack(spacing: 3) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(purple)
                            Text("1s…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(purple)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(purple.opacity(0.18), in: Capsule())
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "scope")
                            Text("Nullpunkt")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(purple.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(purple.opacity(0.12), in: Capsule())
                    }
                }
                .disabled(motion.isCalibrating)

                // Peak Reset
                Button {
                    motion.resetPeak()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Peak")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 14) {
                // GBall scope
                GBallView(
                    x: motion.normalizedX,
                    y: motion.normalizedY,
                    currentG: motion.currentG,
                    maxG: motion.maxG
                )
                .frame(width: 110, height: 110)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.4))
                )

                // Numeric readouts
                VStack(alignment: .leading, spacing: 10) {
                    gReadout(label: "AKTUELL", value: motion.currentGFormatted, color: gColor(motion.currentG, maxG: motion.maxG))
                    gReadout(label: "PEAK",    value: motion.peakGFormatted,    color: .orange)
                    gReadout(label: "LATERAL", value: String(format: "%.2f G", abs(motion.gX)), color: purple.opacity(0.8))
                    gReadout(label: "LÄNGS",   value: String(format: "%.2f G", abs(motion.gY)), color: purple.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Badge gauge
                GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: 95)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func gReadout(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widescreen Powertrain & Dynamics Wing (Landscape-Native Left Wing)
// ─────────────────────────────────────────────────────────────────────────────

public struct WidescreenPowertrainPod: View {
    @ObservedObject public var obd: OBDManager
    @ObservedObject public var motion: MotionManager
    public var width: CGFloat
    public var height: CGFloat

    private let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public init(obd: OBDManager, motion: MotionManager, width: CGFloat, height: CGFloat) {
        self.obd = obd
        self.motion = motion
        self.width = width
        self.height = height
    }

    private var boostRatio: Double {
        guard let b = obd.liveBoostBar else { return 0.0 }
        return min(1.0, max(0.0, (b - (-0.5)) / 2.0))
    }

    private var boostColor: Color {
        guard let b = obd.liveBoostBar else { return .secondary }
        if b < 0.0 { return .cyan }
        if b < 0.6 { return Color(red: 0.3, green: 0.95, blue: 0.4) }
        if b < 1.1 { return .orange }
        return .red
    }

    private var oilRatio: Double {
        guard let t = obd.effectiveOilTemp else { return 0.0 }
        return min(1.0, max(0.0, Double(t - 40) / 90.0))
    }

    private var oilColor: Color {
        guard let t = obd.effectiveOilTemp else { return .secondary }
        if t < 70  { return .cyan }
        if t < 105 { return Color(red: 0.3, green: 0.95, blue: 0.4) }
        if t < 118 { return .orange }
        return .red
    }

    public var body: some View {
        let pillarH = max(60, height * 0.45)
        let radarSize = min(80, height * 0.42)

        return VStack(spacing: 4) {
            // ── Section 1: Twin Precision Pillars (Boost & Oil) ───────────────
            HStack(spacing: 8) {
                // Boost Pillar
                telemetryPillar(
                    title: "LADEDRUCK",
                    valueStr: obd.isEnabled && obd.connectionState == .connected && obd.liveBoostBar != nil
                        ? String(format: "%+.2f", obd.liveBoostBar!)
                        : "--",
                    unit: "BAR",
                    ratio: boostRatio,
                    color: boostColor,
                    barHeight: pillarH
                )

                // Oil Temp Pillar
                telemetryPillar(
                    title: "ÖLTEMPERATUR",
                    valueStr: obd.effectiveOilTemp != nil ? "\(obd.effectiveOilTemp!)°" : "--°",
                    unit: "°C",
                    ratio: oilRatio,
                    color: oilColor,
                    barHeight: pillarH
                )
            }
            .frame(maxWidth: .infinity)

            // ── Section 2: Seamless 2D G-Force Friction Radar ────────────────
            HStack(spacing: 8) {
                GBallView(
                    x: motion.normalizedX,
                    y: motion.normalizedY,
                    currentG: motion.currentG,
                    maxG: motion.maxG
                )
                .frame(width: radarSize, height: radarSize)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("G-KRAFT")
                            .font(.system(size: 7.5, weight: .black, design: .rounded))
                            .foregroundStyle(purple)
                        Spacer()
                        // Nullpunkt Quick Touch
                        Button { motion.calibrate() } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(purple)
                                .padding(3)
                                .background(purple.opacity(0.18), in: Circle())
                        }
                    }

                    Text(motion.currentGFormatted)
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))

                    HStack(spacing: 4) {
                        Text("PEAK: \(motion.peakGFormatted)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                        Button { motion.resetPeak() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.orange.opacity(0.8))
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: width, height: height)
    }

    private func telemetryPillar(title: String, valueStr: String, unit: String, ratio: Double, color: Color, barHeight: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)

            ZStack(alignment: .bottom) {
                // Background Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 14, height: barHeight)

                // Fill Level with Gradient
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.65), color],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .frame(width: 14, height: max(4, barHeight * CGFloat(ratio)))
                    .shadow(color: color.opacity(0.85), radius: 6)
                    .animation(.interactiveSpring(response: 0.16), value: ratio)
            }

            Text(valueStr)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(color)

            Text(unit)
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widescreen G-Force Cockpit Pod (Dedicated Motorsport G-Scope)
// ─────────────────────────────────────────────────────────────────────────────

public struct WidescreenGForcePod: View {
    @ObservedObject public var motion: MotionManager
    public var width: CGFloat
    public var height: CGFloat

    private let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public init(motion: MotionManager, width: CGFloat, height: CGFloat) {
        self.motion = motion
        self.width = width
        self.height = height
    }

    public var body: some View {
        let radarSize = min(96, height * 0.72)

        return HStack(spacing: 10) {
            GBallView(
                x: motion.normalizedX,
                y: motion.normalizedY,
                currentG: motion.currentG,
                maxG: motion.maxG
            )
            .frame(width: radarSize, height: radarSize)
            .background(Circle().fill(Color.black.opacity(0.45)))
            .overlay(Circle().stroke(purple.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("G-KRÄFTE")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .foregroundStyle(purple)
                    Spacer()
                    Button { motion.calibrate() } label: {
                        Text(motion.isCalibrating ? "1s…" : "Nullpunkt")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(purple)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(purple.opacity(0.18), in: Capsule())
                    }
                }

                Text(motion.currentGFormatted)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))

                HStack(spacing: 8) {
                    Text("PEAK: \(motion.peakGFormatted)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("LAT: \(String(format: "%.2f", abs(motion.gX)))G")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(purple.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: height)
    }
}

