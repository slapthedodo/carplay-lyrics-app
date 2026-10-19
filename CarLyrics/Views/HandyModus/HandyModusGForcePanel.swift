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
// MARK: Widescreen G-Force Cockpit Pod (Landscape-Native)
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

    private func gSeverityColor(_ g: Double) -> Color {
        let r = motion.maxG > 0 ? g / motion.maxG : 0
        if r < 0.45 { return .green }
        if r < 0.75 { return .yellow }
        return .red
    }

    public var body: some View {
        let gBallSize = min(74, height * 0.58)
        let badgeSize = min(68, height * 0.54)

        return VStack(spacing: 4) {
            // ── Header Bar ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(purple)
                Text("G-KRÄFTE TELEMETRIE")
                    .font(.system(size: 8.5, weight: .black, design: .rounded))
                    .foregroundStyle(purple.opacity(0.9))

                Spacer()

                // Kalibrieren 1s
                Button { motion.calibrate() } label: {
                    if motion.isCalibrating {
                        HStack(spacing: 2.5) {
                            ProgressView().scaleEffect(0.5).tint(purple)
                            Text("1s…").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundStyle(purple)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2).background(purple.opacity(0.2), in: Capsule())
                    } else {
                        HStack(spacing: 2.5) { Image(systemName: "scope"); Text("Nullpunkt") }
                            .font(.system(size: 7.5, weight: .bold)).foregroundStyle(purple.opacity(0.95))
                            .padding(.horizontal, 5).padding(.vertical, 2).background(purple.opacity(0.14), in: Capsule())
                    }
                }.disabled(motion.isCalibrating)

                // Peak Reset
                Button { motion.resetPeak() } label: {
                    HStack(spacing: 2.5) { Image(systemName: "arrow.counterclockwise"); Text("Peak") }
                        .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.orange.opacity(0.9))
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange.opacity(0.14), in: Capsule())
                }
            }

            // ── Main Content: Radar Scope + Dual G-Meter Bars + Badge ────────
            HStack(alignment: .center, spacing: 8) {
                // 1. GBall Radar Scope
                GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG, maxG: motion.maxG)
                    .frame(width: gBallSize, height: gBallSize)
                    .background(Circle().fill(Color.black.opacity(0.5)))

                // 2. Dual Horizontal/Vertical Vector Readouts
                VStack(spacing: 3.5) {
                    // Aktuell & Peak Digits
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("AKTUELL")
                                .font(.system(size: 6, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(motion.currentGFormatted)
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundStyle(gSeverityColor(motion.currentG))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PEAK")
                                .font(.system(size: 6, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(motion.peakGFormatted)
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Lateral Bar Indicator
                    HStack(spacing: 3) {
                        Text("LAT")
                            .font(.system(size: 6, weight: .bold, design: .rounded))
                            .foregroundStyle(purple.opacity(0.7))
                        GeometryReader { barGeo in
                            let center = barGeo.size.width / 2
                            let maxOffset = center - 2
                            let currentOffset = CGFloat(max(-1.0, min(1.0, motion.gX / max(0.4, motion.maxG)))) * maxOffset
                            ZStack(alignment: .center) {
                                Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 6)
                                Capsule()
                                    .fill(purple)
                                    .frame(width: max(4, abs(currentOffset)), height: 3.5)
                                    .offset(x: currentOffset / 2)
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.2fG", abs(motion.gX)))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(purple)
                    }
                }
                .frame(maxWidth: .infinity)

                // 3. Circular G-Force Badge Gauge
                GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: badgeSize)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(purple.opacity(0.22), lineWidth: 1)
                )
        )
    }
}
