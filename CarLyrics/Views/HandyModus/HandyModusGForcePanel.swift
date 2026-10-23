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

                // Kalibrieren (1s Mittelwert) direkt rechts neben dem Text
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

                Spacer()

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
        let cardH = max(112, min(136, height * 0.39))
        let barH = cardH - 46
        let radarSize = min(126, height * 0.43)

        return VStack(spacing: 6) {
            // ── Section 1: Twin Precision Instrument Cards (Boost & Oil) ─────
            HStack(spacing: 8) {
                // Boost Card
                telemetryCard(
                    title: "LADEDRUCK",
                    icon: "gauge.with.needle.fill",
                    valueStr: obd.isEnabled && obd.connectionState == .connected && obd.liveBoostBar != nil
                        ? String(format: "%+.2f", obd.liveBoostBar!)
                        : "--",
                    unit: "BAR RELATIV",
                    ratio: boostRatio,
                    color: boostColor,
                    barHeight: barH
                )

                // Oil Temp Card
                telemetryCard(
                    title: obd.hasOilTempPID ? "ÖLTEMPERATUR" : "ÖLTEMP (EST)",
                    icon: "drop.fill",
                    valueStr: obd.effectiveOilTemp != nil
                        ? (obd.hasOilTempPID ? "\(obd.effectiveOilTemp!)°" : "~\(obd.effectiveOilTemp!)°")
                        : "--°",
                    unit: "CELSIUS",
                    ratio: oilRatio,
                    color: oilColor,
                    barHeight: barH
                )
            }
            .frame(maxWidth: .infinity)

            // Feine horizontale Trennlinie
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 4)

            // ── Section 2: G-Force Friction Radar & Values ───────────────────
            HStack(spacing: 10) {
                GBallView(
                    x: motion.normalizedX,
                    y: motion.normalizedY,
                    currentG: motion.currentG,
                    maxG: motion.maxG
                )
                .frame(width: radarSize, height: radarSize)
                .background(Circle().fill(Color.black.opacity(0.50)))
                .overlay(Circle().stroke(purple.opacity(0.35), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    // Header: Text + Nullpunkt-Button direkt rechts daneben
                    HStack(spacing: 5) {
                        Text("G-KRAFT")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(purple)

                        Button {
                            motion.calibrate()
                        } label: {
                            HStack(spacing: 2) {
                                if motion.isCalibrating {
                                    ProgressView().scaleEffect(0.5).tint(purple)
                                    Text("1s…").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(purple)
                                } else {
                                    Image(systemName: "scope").font(.system(size: 7.5, weight: .bold)).foregroundStyle(purple)
                                    Text("Nullpunkt").font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundStyle(purple)
                                }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(purple.opacity(0.18), in: Capsule())
                        }
                        .disabled(motion.isCalibrating)

                        Spacer(minLength: 0)
                    }

                    Text(motion.currentGFormatted)
                        .font(.system(size: min(22, height * 0.11), weight: .black, design: .monospaced))
                        .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))

                    HStack(spacing: 4) {
                        Text("PEAK: \(motion.peakGFormatted)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                        Button { motion.resetPeak() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.orange.opacity(0.85))
                        }
                    }

                    HStack(spacing: 6) {
                        Text("LAT: \(String(format: "%.2fG", abs(motion.gX)))")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(purple.opacity(0.80))

                        Text("MAX \(String(format: "%.1f", motion.maxG))G")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: width, height: height)
    }

    private func telemetryCard(title: String, icon: String, valueStr: String, unit: String, ratio: Double, color: Color, barHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            // Header
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            // Body: Bar + Digital Display
            HStack(spacing: 8) {
                // Precision Bar with scale ticks
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 18, height: barHeight)
                        .overlay(
                            VStack(spacing: 0) {
                                ForEach(0..<4) { _ in
                                    Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 3)
                        )

                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.60), color],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 18, height: max(5, barHeight * CGFloat(ratio)))
                        .shadow(color: color.opacity(0.80), radius: 6)
                        .animation(.interactiveSpring(response: 0.16), value: ratio)
                }

                // Digital Readout
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)
                    Text(valueStr)
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    Text(unit)
                        .font(.system(size: 6.5, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
                HStack(spacing: 6) {
                    Text("G-KRÄFTE")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .foregroundStyle(purple)
                    Button { motion.calibrate() } label: {
                        Text(motion.isCalibrating ? "1s…" : "Nullpunkt")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(purple)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(purple.opacity(0.18), in: Capsule())
                    }
                    Spacer()
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

