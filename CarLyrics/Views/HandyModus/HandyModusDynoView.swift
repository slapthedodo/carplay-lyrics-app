// MARK: - HandyModusDynoView.swift
// SuperFlow WinDyn 1:1 Live Prüfstand-Ansicht für Golf 5 GTI EA113 Stage 1
// Inspiriert von custom-chips DIN corrected Engine power (hp) Vs. EngSpd
// Mit Live-RPM-Linie und dynamischen Live-Messpunkten auf den Leistungskurven
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusDynoView: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var dyno = EA113DynoCalculator.shared
    @Binding var isPresented: Bool

    public init(obd: OBDManager, isPresented: Binding<Bool>) {
        self.obd = obd
        self._isPresented = isPresented
    }

    private let cyanGlow = Color(red: 0.0, green: 0.94, blue: 1.0)
    private let orangeGlow = Color(red: 1.0, green: 0.6, blue: 0.1)

    public var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 12) {
                // ── 1. Header Banner (SuperFlow WinDyn Style) ──
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DIN corrected Engine power (hp) Vs. EngSpd")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)

                        Text("VW_Golf5_GTI_2.0TFSI_EA113_[customized_Stage1]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(cyanGlow)

                        HStack(spacing: 10) {
                            Text("● Blau/Cyan: Ausgang 268,9 PS / 395 Nm")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(cyanGlow)
                            Text("● Grau: Serie 200 PS / 280 Nm")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // ── 2. Live Telemetrie Badges ──
                HStack(spacing: 10) {
                    // Live Leistung
                    VStack(spacing: 2) {
                        Text("LIVE LEISTUNG")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(dyno.livePS)")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(orangeGlow)
                            Text("PS")
                                .font(.caption.bold())
                                .foregroundStyle(orangeGlow)
                        }
                        Text("Peak: \(dyno.peakPS) / Ziel: 268,9")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    // Live Drehmoment
                    VStack(spacing: 2) {
                        Text("LIVE DREHMOMENT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(dyno.liveNm)")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundStyle(cyanGlow)
                            Text("Nm")
                                .font(.caption.bold())
                                .foregroundStyle(cyanGlow)
                        }
                        Text("Peak: \(dyno.peakNm) / Ziel: 395")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .padding(.horizontal, 16)

                // ── 3. Authentischer Prüfstand-Graph mit Live-Linie ──
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack {
                        // Raster & Achsen
                        DynoGridBackground(width: w, height: h)

                        // Serienkurven (Grau gestrichelt)
                        StockDynoCurves(width: w, height: h)

                        // Stage 1 Drehmoment-Kurve (Cyan / Blau)
                        Stage1TorquePath(width: w, height: h)
                            .stroke(cyanGlow, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                            .shadow(color: cyanGlow.opacity(0.6), radius: 5)

                        // Stage 1 Leistungskurve (Orange / Gelb)
                        Stage1PowerPath(width: w, height: h)
                            .stroke(orangeGlow, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                            .shadow(color: orangeGlow.opacity(0.6), radius: 5)

                        // ── DYNAMISCHE LIVE-LINIE AN DER AKTUELLEN DREHZAHL ──
                        let rpmClamped = max(1500, min(7000, Double(obd.liveRPM)))
                        let xRatio = (rpmClamped - 1500.0) / 5500.0
                        let xPos = 42.0 + (xRatio * (w - 62.0))

                        // Vertikale Sweep-Linie
                        Path { path in
                            path.move(to: CGPoint(x: xPos, y: 15))
                            path.addLine(to: CGPoint(x: xPos, y: h - 25))
                        }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .shadow(color: cyanGlow, radius: 4)

                        // Live-Punkt auf Drehmoment
                        let nmY = (h - 25.0) - (min(450.0, Double(dyno.liveNm)) / 450.0) * (h - 40.0)
                        Circle()
                            .fill(cyanGlow)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .shadow(color: cyanGlow, radius: 6)
                            .position(x: xPos, y: nmY)

                        // Live-Punkt auf Leistung
                        let psY = (h - 25.0) - (min(450.0, Double(dyno.livePS)) / 450.0) * (h - 40.0)
                        Circle()
                            .fill(orangeGlow)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .shadow(color: orangeGlow, radius: 6)
                            .position(x: xPos, y: psY)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: 330)

                // ── 4. Footer & Peak Reset ──
                HStack {
                    Text("custom-chips GmbH • SuperFlow WinDyn™ • Bosch MED9.1")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Peaks Reset") {
                        dyno.resetPeaks()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(cyanGlow)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Subviews für Prüfstand Raster & Kurven
// ─────────────────────────────────────────────────────────────────────────────

private struct DynoGridBackground: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 42
            let right = size.width - 20
            let top: CGFloat = 15
            let bottom = size.height - 25
            let plotW = right - left
            let plotH = bottom - top

            // Raster horizontal (0 bis 450)
            for i in 0...9 {
                let y = bottom - (CGFloat(i) / 9.0 * plotH)
                var p = Path()
                p.move(to: CGPoint(x: left, y: y))
                p.addLine(to: CGPoint(x: right, y: y))
                context.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)

                let val = i * 50
                let text = Text("\(val)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color.gray)
                context.draw(text, at: CGPoint(x: 22, y: y))
            }

            // Raster vertikal (1500 bis 7000 RPM)
            let rpmSteps = [1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500, 7000]
            for (idx, rpm) in rpmSteps.enumerated() {
                let x = left + (CGFloat(idx) / CGFloat(rpmSteps.count - 1) * plotW)
                var p = Path()
                p.move(to: CGPoint(x: x, y: top))
                p.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)

                let text = Text("\(rpm)")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(Color.gray)
                context.draw(text, at: CGPoint(x: x, y: bottom + 12))
            }

            // Rahmen
            var border = Path()
            border.addRect(CGRect(x: left, y: top, width: plotW, height: plotH))
            context.stroke(border, with: .color(Color.cyan.opacity(0.2)), lineWidth: 1)
        }
    }
}

private struct StockDynoCurves: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Path { path in
            let left: CGFloat = 42
            let plotW = width - 62
            let bottom = height - 25
            let plotH = bottom - 15

            // Serie Drehmoment (~280 Nm)
            path.move(to: CGPoint(x: left, y: bottom - (220.0 / 450.0 * plotH)))
            path.addQuadCurve(to: CGPoint(x: left + (1000.0 / 5500.0 * plotW), y: bottom - (280.0 / 450.0 * plotH)),
                              control: CGPoint(x: left + 30, y: bottom - (270.0 / 450.0 * plotH)))
            path.addLine(to: CGPoint(x: left + (2700.0 / 5500.0 * plotW), y: bottom - (280.0 / 450.0 * plotH)))
            path.addLine(to: CGPoint(x: left + (4500.0 / 5500.0 * plotW), y: bottom - (220.0 / 450.0 * plotH)))
        }
        .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
    }
}

private func Stage1TorquePath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 42
        let plotW = width - 62
        let bottom = height - 25
        let plotH = bottom - 15

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1500, 240))
        path.addCurve(to: pt(2800, 395), control1: pt(1900, 310), control2: pt(2400, 385))
        path.addLine(to: pt(3500, 395))
        path.addLine(to: pt(4200, 390))
        path.addCurve(to: pt(6000, 315), control1: pt(4800, 375), control2: pt(5500, 340))
        path.addLine(to: pt(6500, 275))
        path.addLine(to: pt(6700, 90))
    }
}

private func Stage1PowerPath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 42
        let plotW = width - 62
        let bottom = height - 25
        let plotH = bottom - 15

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1500, 52))
        path.addCurve(to: pt(3500, 195), control1: pt(2000, 88), control2: pt(2800, 155))
        path.addCurve(to: pt(5900, 268.9), control1: pt(4400, 242), control2: pt(5200, 262))
        path.addLine(to: pt(6400, 258))
        path.addLine(to: pt(6700, 85))
    }
}
