// MARK: - HandyModusDynoMiniCard.swift
// Kompaktes Live-Dyno Dashboard-Widget für das Cockpit
// Zeigt SuperFlow WinDyn V3.2 Kurven, Live Sweep & Peak-Locking in einer cleanen Kachel
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusDynoMiniCard: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var dyno = EA113DynoCalculator.shared
    var onOpenFullscreen: (() -> Void)? = nil

    public init(obd: OBDManager, onOpenFullscreen: (() -> Void)? = nil) {
        self.obd = obd
        self.onOpenFullscreen = onOpenFullscreen
    }

    private let redTorque = Color(red: 1.0, green: 0.23, blue: 0.19)
    private let bluePower = Color(red: 0.12, green: 0.58, blue: 1.0)
    private let cyanGlow  = Color(red: 0.0, green: 0.94, blue: 1.0)

    public var body: some View {
        VStack(spacing: 8) {
            // ── Header: Titel + Vollbild Button ──
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(cyanGlow)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SUPERFLOW WINDYN™ V3.2")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)

                        Text("custom-chips • EA113 Stage 1")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(cyanGlow.opacity(0.8))
                    }
                }

                Spacer()

                if let open = onOpenFullscreen {
                    Button(action: open) {
                        HStack(spacing: 3) {
                            Text("Vollbild")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .black))
                        }
                        .foregroundStyle(cyanGlow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(cyanGlow.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(cyanGlow.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .studioText(id: "w_dyno")

            // ── Twin Live Badges (Rot Nm / Blau PS) ──
            let currentRPM = Double(obd.liveRPM)
            let isUnder1700 = currentRPM < 1700
            let displayNm = isUnder1700 ? dyno.peakNm : (dyno.liveNm > 0 ? dyno.liveNm : Int(round(EA113DynoCalculator.expectedWinDynValues(at: currentRPM).nm)))
            let displayPS = isUnder1700 ? dyno.peakPS : (dyno.livePS > 0 ? dyno.livePS : Int(round(EA113DynoCalculator.expectedWinDynValues(at: currentRPM).ps)))

            HStack(spacing: 8) {
                // Drehmoment Badge (Rot)
                HStack(spacing: 5) {
                    Circle().fill(redTorque).frame(width: 6, height: 6)
                    Text(isUnder1700 ? "PEAK" : "LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(redTorque.opacity(0.8))
                    Spacer()
                    Text("\(displayNm) Nm")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(redTorque.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(redTorque.opacity(0.35), lineWidth: 1))

                // Leistung Badge (Blau)
                HStack(spacing: 5) {
                    Circle().fill(bluePower).frame(width: 6, height: 6)
                    Text(isUnder1700 ? "PEAK" : "LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(bluePower.opacity(0.8))
                    Spacer()
                    Text("\(displayPS) PS")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bluePower.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(bluePower.opacity(0.35), lineWidth: 1))
            }
            .studioText(id: "w_dyno")

            // ── Mini Prüfstand SVG Graph ──
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let left: CGFloat = 24
                let right = w - 10
                let top: CGFloat = 8
                let bottom = h - 14
                let plotW = right - left
                let plotH = bottom - top

                ZStack(alignment: .topLeading) {
                    // Raster
                    Canvas { context, _ in
                        for i in 0...3 {
                            let y = bottom - (CGFloat(i) / 3.0 * plotH)
                            var p = Path()
                            p.move(to: CGPoint(x: left, y: y))
                            p.addLine(to: CGPoint(x: right, y: y))
                            context.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.6)
                        }
                    }

                    // Füllung unter Drehmoment-Kurve (Rot Gradient)
                    Stage1MiniTorqueFill(left: left, right: right, top: top, bottom: bottom, plotW: plotW, plotH: plotH)
                        .fill(LinearGradient(colors: [redTorque.opacity(0.25), redTorque.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                    // Füllung unter Leistungskurve (Blau Gradient)
                    Stage1MiniPowerFill(left: left, right: right, top: top, bottom: bottom, plotW: plotW, plotH: plotH)
                        .fill(LinearGradient(colors: [bluePower.opacity(0.22), bluePower.opacity(0.01)], startPoint: .top, endPoint: .bottom))

                    // Drehmoment Kurve (Rot)
                    Stage1MiniTorqueStroke(left: left, right: right, top: top, bottom: bottom, plotW: plotW, plotH: plotH)
                        .stroke(redTorque, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: redTorque.opacity(0.5), radius: 4)

                    // Leistungskurve (Blau)
                    Stage1MiniPowerStroke(left: left, right: right, top: top, bottom: bottom, plotW: plotW, plotH: plotH)
                        .stroke(bluePower, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: bluePower.opacity(0.5), radius: 4)

                    // Live Sweep & Punkte
                    let nmRPM = isUnder1700 ? 2800.0 : currentRPM
                    let psRPM = isUnder1700 ? 6300.0 : currentRPM

                    let nmX = left + (((max(1500, min(7000, nmRPM)) - 1500.0) / 5500.0) * plotW)
                    let nmY = bottom - (min(450.0, Double(displayNm)) / 450.0 * plotH)

                    let psX = left + (((max(1500, min(7000, psRPM)) - 1500.0) / 5500.0) * plotW)
                    let psY = bottom - (min(450.0, Double(displayPS)) / 450.0 * plotH)

                    if !isUnder1700 {
                        let sweepX = left + (((max(1500, min(7000, currentRPM)) - 1500.0) / 5500.0) * plotW)
                        Path { p in
                            p.move(to: CGPoint(x: sweepX, y: top))
                            p.addLine(to: CGPoint(x: sweepX, y: bottom))
                        }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    }

                    // Roter Punkt
                    Circle()
                        .fill(redTorque)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(color: redTorque, radius: 5)
                        .position(x: nmX, y: nmY)

                    // Blauer Punkt
                    Circle()
                        .fill(bluePower)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(color: bluePower, radius: 5)
                        .position(x: psX, y: psY)
                }
            }
            .frame(height: 90)
            .studioBar(id: "w_dyno")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Kurven Geometrie für Mini-Card
// ─────────────────────────────────────────────────────────────────────────────

private func Stage1MiniTorqueStroke(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, plotH: CGFloat) -> Path {
    Path { path in
        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            CGPoint(x: left + ((rpm - 1500.0) / 5500.0 * plotW), y: bottom - (val / 450.0 * plotH))
        }
        path.move(to: pt(1750, 260))
        path.addCurve(to: pt(2800, 392), control1: pt(2100, 310), control2: pt(2450, 385))
        path.addLine(to: pt(3500, 370))
        path.addLine(to: pt(4500, 352))
        path.addCurve(to: pt(5500, 300), control1: pt(4900, 335), control2: pt(5200, 315))
        path.addLine(to: pt(6300, 245))
        path.addLine(to: pt(6700, 220))
    }
}

private func Stage1MiniTorqueFill(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, plotH: CGFloat) -> Path {
    Path { path in
        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            CGPoint(x: left + ((rpm - 1500.0) / 5500.0 * plotW), y: bottom - (val / 450.0 * plotH))
        }
        path.move(to: pt(1750, 0))
        path.addLine(to: pt(1750, 260))
        path.addCurve(to: pt(2800, 392), control1: pt(2100, 310), control2: pt(2450, 385))
        path.addLine(to: pt(3500, 370))
        path.addLine(to: pt(4500, 352))
        path.addCurve(to: pt(5500, 300), control1: pt(4900, 335), control2: pt(5200, 315))
        path.addLine(to: pt(6300, 245))
        path.addLine(to: pt(6700, 220))
        path.addLine(to: pt(6700, 0))
        path.closeSubpath()
    }
}

private func Stage1MiniPowerStroke(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, plotH: CGFloat) -> Path {
    Path { path in
        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            CGPoint(x: left + ((rpm - 1500.0) / 5500.0 * plotW), y: bottom - (val / 450.0 * plotH))
        }
        path.move(to: pt(1750, 65))
        path.addCurve(to: pt(2800, 156), control1: pt(2100, 95), control2: pt(2450, 130))
        path.addLine(to: pt(4500, 225))
        path.addLine(to: pt(5500, 248))
        path.addCurve(to: pt(6300, 268.9), control1: pt(5800, 258), control2: pt(6100, 266))
        path.addLine(to: pt(6700, 255))
    }
}

private func Stage1MiniPowerFill(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, plotH: CGFloat) -> Path {
    Path { path in
        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            CGPoint(x: left + ((rpm - 1500.0) / 5500.0 * plotW), y: bottom - (val / 450.0 * plotH))
        }
        path.move(to: pt(1750, 0))
        path.addLine(to: pt(1750, 65))
        path.addCurve(to: pt(2800, 156), control1: pt(2100, 95), control2: pt(2450, 130))
        path.addLine(to: pt(4500, 225))
        path.addLine(to: pt(5500, 248))
        path.addCurve(to: pt(6300, 268.9), control1: pt(5800, 258), control2: pt(6100, 266))
        path.addLine(to: pt(6700, 255))
        path.addLine(to: pt(6700, 0))
        path.closeSubpath()
    }
}
