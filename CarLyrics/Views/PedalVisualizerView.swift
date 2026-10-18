// MARK: - PedalVisualizerView.swift
// 'Pedale' Tab – Live-Pedalanzeige + Drehzahlmesser + Ganganzeige
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Main View

public struct PedalVisualizerView: View {

    @ObservedObject var obd: OBDManager
    @ObservedObject var motion: MotionManager

    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(obd: OBDManager, motion: MotionManager) {
        self.obd = obd
        self.motion = motion
    }

    // ── Derived values ────────────────────────────────────────────────────────

    private var gasValue: Int {
        obd.liveEngineLoad ?? 0
    }

    private var brakeValue: Int {
        let g = motion.gY   // negative = braking
        guard g < -0.15 else { return 0 }
        return min(100, Int(abs(g) * 200))
    }

    private var rpmValue: Int { obd.liveRPM }
    private var speedValue: Int { obd.liveSpeed }

    private var estimatedGear: String {
        estimateGear(speed: speedValue, rpm: rpmValue)
    }

    // ── Layout ────────────────────────────────────────────────────────────────

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                if isLandscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout(geo: geo)
                }
            }
        }
        .navigationTitle("Pedale")
        .preferredColorScheme(.dark)
    }

    // MARK: Portrait

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            pedalsRow(height: geo.size.height * 0.38)
            rpmGauge(size: min(geo.size.width * 0.72, 240))
            gearIndicator()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: Landscape

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 20) {
            pedalsRow(height: geo.size.height * 0.72)
                .frame(width: geo.size.width * 0.50)
            VStack(spacing: 20) {
                rpmGauge(size: min(geo.size.width * 0.35, 220))
                gearIndicator()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
    }

    // MARK: Pedals

    private func pedalsRow(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            PedalView(
                label: "GAS",
                emoji: "🚀",
                value: gasValue,
                color: .cyan,
                available: true,
                height: height
            )
            PedalView(
                label: "BREMSE",
                emoji: "🛑",
                value: brakeValue,
                color: .red,
                available: true,
                height: height
            )
            PedalView(
                label: "KUPPLUNG",
                emoji: "⚙️",
                value: 0,
                color: .orange,
                available: false,
                height: height
            )
        }
    }

    // MARK: RPM Gauge

    private func rpmGauge(size: CGFloat) -> some View {
        RPMArcGauge(rpm: rpmValue, size: size)
    }

    // MARK: Gear Indicator

    private func gearIndicator() -> some View {
        VStack(spacing: 2) {
            Text(estimatedGear)
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(estimatedGear == "N" ? Color.yellow : Color.white)
                .shadow(color: .cyan.opacity(0.5), radius: 12)
            Text("GANG")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(4)
        }
    }
}

// MARK: - Gear Estimation

private func estimateGear(speed: Int, rpm: Int) -> String {
    guard speed >= 5 else { return "N" }
    let safeRPM = max(rpm, 1)
    let ratio = Double(speed) / Double(safeRPM) * 1000.0
    switch ratio {
    case ..<5:  return "1"
    case ..<9:  return "2"
    case ..<13: return "3"
    case ..<18: return "4"
    case ..<24: return "5"
    default:    return "6"
    }
}

// MARK: - Single Pedal View

private struct PedalView: View {

    let label: String
    let emoji: String
    let value: Int          // 0–100
    let color: Color
    let available: Bool
    let height: CGFloat

    private var fraction: CGFloat {
        available ? CGFloat(value) / 100.0 : 0
    }

    var body: some View {
        VStack(spacing: 6) {
            // Label
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 18))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(available ? color : .gray)
            }

            // Bar
            pedalBar

            // Value text
            if available {
                Text("\(value)%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(value > 0 ? color : .white.opacity(0.4))
            } else {
                Text("N/A")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pedalBar: some View {
        GeometryReader { geo in
            let barH = geo.size.height
            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(available ? color.opacity(0.25) : Color.gray.opacity(0.2), lineWidth: 1)
                    )

                // Fill
                if available && fraction > 0 {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.4), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: barH * fraction)
                        .shadow(color: color.opacity(0.8), radius: fraction > 0.1 ? 10 : 0)
                        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: fraction)
                }

                // Tick marks
                ForEach([25, 50, 75], id: \.self) { tick in
                    let yPos = barH * (1.0 - CGFloat(tick) / 100.0)
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 8, height: 1)
                            .padding(.trailing, 4)
                    }
                    .offset(y: yPos - barH / 2)
                }
            }
        }
        .frame(height: max(height - 70, 60))
    }
}

// MARK: - RPM Arc Gauge

private struct RPMArcGauge: View {

    let rpm: Int
    let size: CGFloat

    private let maxRPM: Double = 7000
    private let startAngle: Double = 145
    private let endAngle: Double   = 395   // 250° sweep

    private var fraction: Double {
        min(1.0, Double(rpm) / maxRPM)
    }

    private var sweepAngle: Double {
        (endAngle - startAngle) * fraction
    }

    private var needleColor: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: CGFloat((endAngle - startAngle) / 360.0))
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(startAngle))

            // Fill arc
            Circle()
                .trim(from: 0, to: CGFloat(sweepAngle / 360.0))
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .orange, .red],
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(endAngle)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(startAngle))
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: fraction)

            // RPM label
            VStack(spacing: 2) {
                Text("\(rpm)")
                    .font(.system(size: size * 0.17, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("RPM")
                    .font(.system(size: size * 0.08, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(3)
            }

            // Tick marks (every 1000 RPM)
            ForEach(0...7, id: \.self) { i in
                rpmTick(index: i, total: 7, outerR: size / 2 - 4, innerR: size / 2 - 14)
            }
        }
        .frame(width: size, height: size)
    }

    private func rpmTick(index: Int, total: Int, outerR: CGFloat, innerR: CGFloat) -> some View {
        let angleDeg = startAngle + (endAngle - startAngle) * Double(index) / Double(total)
        let rad = angleDeg * .pi / 180.0
        let ox = cos(rad) * outerR + size / 2
        let oy = sin(rad) * outerR + size / 2
        let ix = cos(rad) * innerR + size / 2
        let iy = sin(rad) * innerR + size / 2
        return Path { p in
            p.move(to: CGPoint(x: ox, y: oy))
            p.addLine(to: CGPoint(x: ix, y: iy))
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    PedalVisualizerView(obd: OBDManager.shared, motion: MotionManager.shared)
}
