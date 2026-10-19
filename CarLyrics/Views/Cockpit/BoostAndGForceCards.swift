// MARK: - BoostAndGForceCards.swift
// Ladedruck, G-Kraft Badge, G-Meter & GBall Ansichten
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Boost Card (Ladedruck & Ansaugung)
// ─────────────────────────────────────────────────────────────────────────────

public struct BoostCard: View {
    @ObservedObject var obd: OBDManager

    public init(obd: OBDManager) {
        self.obd = obd
    }

    public var boostVal: Double? {
        obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Ladedruck & Ansaugung", systemImage: "gauge.with.needle.fill")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if obd.isEnabled {
                        if obd.connectionState == .connected && obd.liveBoostBar != nil {
                            Text(obd.liveMAP != nil ? "LIVE (MAP)" : "LIVE (MAF)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        } else if obd.connectionState == .connected {
                            Text("OBD BEREIT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        } else if obd.connectionState == .scanning {
                            Text("SUCHE ADAPTER…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text("OBD GETRENNT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("SIMULATION (KEIN OBD)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let val = boostVal {
                            Text(String(format: "%.2f", val))
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .foregroundStyle(val > 0.8 ? .orange : (val > 0.1 ? .green : .cyan))
                        } else {
                            Text("--")
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text("BAR RELATIV (LADEDRUCK)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        if let iat = obd.liveIAT {
                            Text("Ansaugluft: \(iat) °C").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                        }
                        if let maf = obd.liveMAF {
                            Text(String(format: "Luftmasse: %.1f g/s", maf)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        }
                        if let load = obd.liveEngineLoad {
                            Text("Last: \(load) %").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
                        }
                        if !obd.isEnabled || obd.connectionState != .connected {
                            Text(obd.isEnabled ? "Warte auf OBD-Daten" : "Schalte OBD ein für Ladedruck")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Force Badge & Card
// ─────────────────────────────────────────────────────────────────────────────

public struct GForceGaugeBadge: View {
    public let currentG : Double
    public var maxG     : Double = 1.2
    public var size     : CGFloat = 130

    public init(currentG: Double, maxG: Double = 1.2, size: CGFloat = 130) {
        self.currentG = currentG
        self.maxG = maxG
        self.size = size
    }

    public var body: some View {
        let ratio = min(max(currentG / max(0.4, maxG), 0.0), 1.0)
        let purpleColor = Color(red: 0.68, green: 0.35, blue: 0.98)

        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: size > 60 ? 3 : 2)

            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: size > 60 ? 1.5 : 1, height: size > 60 ? 6 : 3.5)
                    .offset(y: -(size / 2 - (size > 60 ? 3 : 2)))
                    .rotationEffect(.degrees(Double(deg)))
            }

            Circle()
                .trim(from: 0.0, to: CGFloat(max(0.04, ratio * 0.75)))
                .stroke(
                    LinearGradient(
                        colors: [purpleColor.opacity(0.4), purpleColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size > 60 ? 4.5 : 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.interactiveSpring(response: 0.2), value: ratio)

            VStack(spacing: size > 60 ? 3 : -1) {
                Image(systemName: "scope")
                    .font(.system(size: size > 60 ? 18 : 8, weight: .bold))
                    .foregroundStyle(.white)

                Text("G-KRAFT")
                    .font(.system(size: size > 60 ? 10 : 5, weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text(String(format: "%.1f", currentG))
                    .font(.system(size: size > 60 ? 24 : 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text("G")
                    .font(.system(size: size > 60 ? 8 : 4.5, weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}

public struct GForceCard: View {
    @ObservedObject var motion: MotionManager

    public init(motion: MotionManager) {
        self.motion = motion
    }

    public var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Text("G-Kräfte Telemetrie")
                    .font(.headline).foregroundStyle(.cyan)

                HStack(spacing: 20) {
                    GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: 125)

                    GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG, maxG: motion.maxG)
                        .frame(width: 125, height: 125)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 20) {
                    VStack {
                        Text("AKTUELL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.currentGFormatted)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))
                    }
                    VStack {
                        Text("PEAK").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.peakGFormatted)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    VStack {
                        Text("MAX LIMIT").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(String(format: "%.2f G", motion.maxG))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Maximale G-Kraft (Skala & Limit):")
                            .font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f G", motion.maxG))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }

                    Slider(value: $motion.maxG, in: 0.5...3.0, step: 0.05)
                        .tint(.cyan)

                    HStack {
                        Text("0.5G (Komfort)").font(.system(size: 8)).foregroundStyle(.secondary)
                        Spacer()
                        Text("1.2G (TFSI Serie)").font(.system(size: 8).bold()).foregroundStyle(.cyan)
                        Spacer()
                        Text("3.0G (Track)").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        motion.resetPeak()
                    } label: {
                        Label("Peak Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .secondary))

                    Button {
                        motion.calibrate()
                    } label: {
                        if motion.isCalibrating {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7).tint(.cyan)
                                Text("1s Mittelwert…").font(.caption.bold())
                            }
                        } else {
                            Label("Nullpunkt setzen", systemImage: "scope")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(CockpitButtonStyle(color: .cyan))
                    .disabled(motion.isCalibrating)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

public struct GBallView: View {
    public let x        : Double
    public let y        : Double
    public let currentG : Double
    public var maxG     : Double = 1.2

    public init(x: Double, y: Double, currentG: Double, maxG: Double = 1.2) {
        self.x = x
        self.y = y
        self.currentG = currentG
        self.maxG = maxG
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r  = min(w, h) / 2 - 8

            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { frac in
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: r * 2 * frac, height: r * 2 * frac)
                }

                Rectangle().fill(Color.white.opacity(0.08)).frame(width: r * 2, height: 1)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: r * 2)

                Text("ACC").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(y: -(r - 6))
                Text("BRK").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(y: r - 6)
                Text("L").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(x: -(r - 6))
                Text("R").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(x: r - 6)

                Text(String(format: "%.1fG", maxG))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.6))
                    .offset(x: r - 16, y: -(r - 16))

                Circle()
                    .fill(gColor(currentG, maxG: maxG))
                    .frame(width: 18, height: 18)
                    .shadow(color: gColor(currentG, maxG: maxG).opacity(0.8), radius: 8)
                    .offset(x: CGFloat(x) * r, y: -CGFloat(y) * r)
                    .animation(.interactiveSpring(response: 0.15), value: x)
                    .animation(.interactiveSpring(response: 0.15), value: y)
            }
            .frame(width: w, height: h)
        }
    }
}
