// MARK: - PorscheGT3TorqueWidget.swift
// Porsche 911 GT3 RS Style Performance Torque Mini-Widget
// Shaded Silhouette-Kurve mit vertikalen 1000er Segmenten & leuchtendem Live-RPM-Punkt
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct PorscheGT3TorqueWidget: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var dyno = EA113DynoCalculator.shared

    public init(obd: OBDManager) {
        self.obd = obd
    }

    private let curveFillColor = Color(red: 0.52, green: 0.56, blue: 0.75).opacity(0.45)
    private let curveStrokeColor = Color(red: 0.65, green: 0.70, blue: 0.90)
    private let amberDotColor = Color(red: 1.0, green: 0.78, blue: 0.15)

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                // Header (Porsche OEM Performance Style)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 14, height: 2)
                            Text("Performance")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text("Torque")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Live digitaler Wert
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(dyno.liveNm) Nm")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundStyle(curveStrokeColor)
                        Text("Peak: \(dyno.peakNm) Nm")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // Porsche GT3 RS Silhouette Graph
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack {
                        // 1. Ausgefüllte Silhouette-Fläche
                        GT3TorqueClosedShape(width: w, height: h)
                            .fill(
                                LinearGradient(
                                    colors: [curveFillColor, curveFillColor.opacity(0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // 2. Vertikale Segment-Linien (0 bis 7 x 1000 RPM)
                        Canvas { context, size in
                            for i in 1...6 {
                                let x = CGFloat(i) / 7.0 * size.width
                                let yTop = torqueNormalizedY(rpm: Double(i * 1000)) * (size.height - 18)
                                var p = Path()
                                p.move(to: CGPoint(x: x, y: size.height - 18 - yTop))
                                p.addLine(to: CGPoint(x: x, y: size.height - 18))
                                context.stroke(p, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                            }

                            // Horizontale Basislinie
                            var base = Path()
                            base.move(to: CGPoint(x: 0, y: size.height - 18))
                            base.addLine(to: CGPoint(x: size.width, y: size.height - 18))
                            context.stroke(base, with: .color(Color.white.opacity(0.35)), lineWidth: 1.2)
                        }

                        // 3. Oberer Kurvenverlauf (Stroke)
                        GT3TorqueContourPath(width: w, height: h)
                            .stroke(curveStrokeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // 4. X-Achsen Beschriftung: 0 1 2 3 4 5 6 7  1/min x 1000
                        HStack(spacing: 0) {
                            ForEach(0...7, id: \.self) { rpm in
                                Text("\(rpm)")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .position(x: w / 2, y: h - 8)

                        Text("1/min × 1000")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .position(x: w - 30, y: h - 26)

                        // 5. 🌟 LEUCHTENDER LIVE-PUNKT (wie im GT3 RS Instrument!)
                        let clampedRPM = max(0, min(7000, Double(obd.liveRPM)))
                        let dotX = (clampedRPM / 7000.0) * w
                        let normY = torqueNormalizedY(rpm: clampedRPM)
                        let dotY = (h - 18) - (normY * (h - 18))

                        Circle()
                            .fill(amberDotColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                            .shadow(color: amberDotColor.opacity(0.9), radius: 6)
                            .position(x: max(5, min(w - 5, dotX)), y: max(5, dotY))
                    }
                }
                .frame(height: 80)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: GT3 Torque Kurven-Mathematik
// ─────────────────────────────────────────────────────────────────────────────

private func torqueNormalizedY(rpm: Double) -> CGFloat {
    if rpm < 800 {
        return CGFloat(rpm / 800.0 * 0.2)
    } else if rpm < 1800 {
        return CGFloat(0.2 + (rpm - 800) / 1000.0 * 0.35) // 0.55
    } else if rpm < 2800 {
        return CGFloat(0.55 + (rpm - 1800) / 1000.0 * 0.40) // 0.95 (Overboost Peak)
    } else if rpm < 4200 {
        return CGFloat(0.95 - (rpm - 2800) / 1400.0 * 0.05) // 0.90 Plateau (395 Nm)
    } else if rpm < 6000 {
        return CGFloat(0.90 - (rpm - 4200) / 1800.0 * 0.25) // 0.65 (315 Nm)
    } else if rpm < 6700 {
        return CGFloat(0.65 - (rpm - 6000) / 700.0 * 0.45) // 0.20
    } else {
        return 0.05
    }
}

private func GT3TorqueContourPath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let plotH = height - 18
        path.move(to: CGPoint(x: 0, y: plotH))

        let steps = 40
        for i in 1...steps {
            let r = Double(i) / Double(steps) * 7000.0
            let x = CGFloat(i) / CGFloat(steps) * width
            let y = plotH - (torqueNormalizedY(rpm: r) * plotH)
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
}

private func GT3TorqueClosedShape(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let plotH = height - 18
        path.move(to: CGPoint(x: 0, y: plotH))

        let steps = 40
        for i in 1...steps {
            let r = Double(i) / Double(steps) * 7000.0
            let x = CGFloat(i) / CGFloat(steps) * width
            let y = plotH - (torqueNormalizedY(rpm: r) * plotH)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: width, y: plotH))
        path.closeSubpath()
    }
}
