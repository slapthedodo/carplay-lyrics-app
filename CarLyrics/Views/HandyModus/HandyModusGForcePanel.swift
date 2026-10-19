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
