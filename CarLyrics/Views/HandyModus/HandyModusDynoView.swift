// MARK: - HandyModusDynoView.swift
// SuperFlow WinDyn™ V3.2 1:1 Live Prüfstand für Golf 5 GTI EA113 Stage 1
// Kalibriert nach custom-chips GmbH Prüfbericht (268,9 PS / 392 Nm)
// Ultra-cleane Vollbild-Ansicht mit Leucht-Glow Füllung, schwebenden Live-Pills & Touch-Inspector
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusDynoView: View {
    @ObservedObject var obd: OBDManager
    @ObservedObject private var dyno = EA113DynoCalculator.shared
    @Binding var isPresented: Bool
    var showCloseButton: Bool = true

    // Interaktiver Touch-Inspector (Finger über Graph bewegen zum Erkunden der Kurve)
    @State private var inspectRPM: Double? = nil

    public init(obd: OBDManager, isPresented: Binding<Bool> = .constant(true), showCloseButton: Bool = true) {
        self.obd = obd
        self._isPresented = isPresented
        self.showCloseButton = showCloseButton
    }

    // Farben laut custom-chips SuperFlow WinDyn Original-Prüfbericht:
    // CEngTq (Drehmoment) = Rot
    // CEngHp (Leistung)   = Blau
    private let redTorque = Color(red: 1.0, green: 0.23, blue: 0.19)
    private let bluePower = Color(red: 0.12, green: 0.58, blue: 1.0)
    private let cyanGlow  = Color(red: 0.0, green: 0.94, blue: 1.0)

    public var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 8) {
                // ── 1. Authentischer SuperFlow WinDyn Motorsport Header ──
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("SUPERFLOW WINDYN™ V3.2")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)

                            Text("custom-chips")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(cyanGlow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(cyanGlow.opacity(0.12), in: Capsule())
                        }

                        Text("Golf 5 GTI 2.0 TFSI EA113 • Bosch MED9.1 Stage 1")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Top Badges
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Circle().fill(redTorque).frame(width: 5, height: 5)
                            Text("392 Nm")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(redTorque)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(redTorque.opacity(0.12), in: Capsule())

                        HStack(spacing: 4) {
                            Circle().fill(bluePower).frame(width: 5, height: 5)
                            Text("268,9 PS")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(bluePower)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(bluePower.opacity(0.12), in: Capsule())

                        if showCloseButton {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isPresented = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // ── 2. Vollbild WinDyn Prüfstand-Graph ──
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let left: CGFloat = 36
                    let right = w - 14
                    let top: CGFloat = 16
                    let bottom = h - 24
                    let plotW = right - left
                    let plotH = bottom - top

                    ZStack(alignment: .topLeading) {
                        // Raster & Achsenbeschriftung
                        DynoGridBackground(width: w, height: h)

                        // Serienkurven (Grau gestrichelt)
                        StockDynoCurves(width: w, height: h)

                        // ── LUMINÖSE GRADIENTEN-FÜLLUNG UNTER DEN KURVEN ──
                        Stage1TorqueFillPath(width: w, height: h)
                            .fill(LinearGradient(colors: [redTorque.opacity(0.22), redTorque.opacity(0.02), .clear], startPoint: .top, endPoint: .bottom))

                        Stage1PowerFillPath(width: w, height: h)
                            .fill(LinearGradient(colors: [bluePower.opacity(0.20), bluePower.opacity(0.01), .clear], startPoint: .top, endPoint: .bottom))

                        // Stage 1 Drehmoment-Kurve: ROT (392 Nm Peak @ 2800)
                        Stage1TorquePath(width: w, height: h)
                            .stroke(redTorque, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                            .shadow(color: redTorque.opacity(0.7), radius: 6)

                        // Stage 1 Leistungskurve: BLAU (268.9 PS Peak @ 6300)
                        Stage1PowerPath(width: w, height: h)
                            .stroke(bluePower, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                            .shadow(color: bluePower.opacity(0.7), radius: 6)

                        // ── LIVE-MESSUNG ODER TOUCH-INSPECTOR ──
                        let liveRPM = Double(obd.liveRPM)
                        let activeRPM = inspectRPM ?? liveRPM
                        let isInspecting = inspectRPM != nil
                        let isUnder1700 = !isInspecting && activeRPM < 1700

                        let targetValues = EA113DynoCalculator.expectedWinDynValues(at: activeRPM)
                        let displayNm = isInspecting ? Int(round(targetValues.nm)) : (isUnder1700 ? dyno.peakNm : (dyno.liveNm > 0 ? dyno.liveNm : Int(round(targetValues.nm))))
                        let displayPS = isInspecting ? Int(round(targetValues.ps)) : (isUnder1700 ? dyno.peakPS : (dyno.livePS > 0 ? dyno.livePS : Int(round(targetValues.ps))))

                        // X-Position für Sweep-Linie
                        let rpmForSweep = isUnder1700 ? 2800.0 : max(1500, min(7000, activeRPM))
                        let xRatio = (rpmForSweep - 1500.0) / 5500.0
                        let xSweep = left + (xRatio * plotW)

                        // Vertikale Sweep-Linie mit Leuchtschein
                        if !isUnder1700 || isInspecting {
                            Path { path in
                                path.move(to: CGPoint(x: xSweep, y: top))
                                path.addLine(to: CGPoint(x: xSweep, y: bottom))
                            }
                            .stroke(isInspecting ? cyanGlow : Color.white, style: StrokeStyle(lineWidth: isInspecting ? 2.0 : 1.5, dash: [4, 3]))
                            .shadow(color: (isInspecting ? cyanGlow : Color.white).opacity(0.6), radius: 4)
                        }

                        // ── DREHMOMENT PUNKT + SCHWEBENDER PILL (ROT) ──
                        let nmRPM = isUnder1700 ? 2800.0 : activeRPM
                        let nmX = left + (((max(1500, min(7000, nmRPM)) - 1500.0) / 5500.0) * plotW)
                        let nmY = bottom - (min(450.0, Double(displayNm)) / 450.0 * plotH)

                        Circle()
                            .fill(redTorque)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: redTorque, radius: 8)
                            .position(x: nmX, y: nmY)

                        HStack(spacing: 3) {
                            Text(isInspecting ? "SOLL" : (isUnder1700 ? "PEAK" : "LIVE"))
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Text("\(displayNm) Nm")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(redTorque.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        .shadow(color: redTorque.opacity(0.7), radius: 6)
                        .position(x: min(right - 45, max(left + 45, nmX)), y: max(top + 18, nmY - 20))

                        // ── LEISTUNG PUNKT + SCHWEBENDER PILL (BLAU) ──
                        let psRPM = isUnder1700 ? 6300.0 : activeRPM
                        let psX = left + (((max(1500, min(7000, psRPM)) - 1500.0) / 5500.0) * plotW)
                        let psY = bottom - (min(450.0, Double(displayPS)) / 450.0 * plotH)

                        Circle()
                            .fill(bluePower)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: bluePower, radius: 8)
                            .position(x: psX, y: psY)

                        HStack(spacing: 3) {
                            Text(isInspecting ? "SOLL" : (isUnder1700 ? "PEAK" : "LIVE"))
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Text("\(displayPS) PS")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(bluePower.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        .shadow(color: bluePower.opacity(0.7), radius: 6)
                        .position(x: min(right - 45, max(left + 45, psX)), y: max(top + 18, psY - 20))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let xClamped = max(left, min(right, val.location.x))
                                let ratio = (xClamped - left) / plotW
                                inspectRPM = 1500.0 + (ratio * 5500.0)
                            }
                            .onEnded { _ in
                                inspectRPM = nil
                            }
                    )
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)

                // ── 3. Footer Telemetrie-Bar & Peak Reset ──
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("PEAK:")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(dyno.peakNm) Nm")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(redTorque)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(dyno.peakPS) PS")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(bluePower)
                    }

                    Spacer()

                    if let boost = obd.liveBoostBar {
                        HStack(spacing: 3) {
                            Text("BOOST:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f bar", boost))
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(cyanGlow)
                        }
                    }

                    Button {
                        dyno.resetPeaks()
                    } label: {
                        Text("Reset Peaks")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(cyanGlow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Subviews für WinDyn Raster & Kurven
// ─────────────────────────────────────────────────────────────────────────────

private struct DynoGridBackground: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 36
            let right = size.width - 14
            let top: CGFloat = 16
            let bottom = size.height - 24
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
                context.draw(text, at: CGPoint(x: 18, y: y))
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
            let left: CGFloat = 36
            let plotW = width - 50
            let bottom = height - 24
            let plotH = bottom - 16

            func pt(_ rpm: Double, _ val: Double) -> CGPoint {
                let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
                let y = bottom - (val / 450.0 * plotH)
                return CGPoint(x: x, y: y)
            }

            // Serie Drehmoment (280 Nm ab 1800 bis 5000)
            path.move(to: pt(1500, 220))
            path.addLine(to: pt(1800, 280))
            path.addLine(to: pt(5000, 280))
            path.addLine(to: pt(6000, 220))
            path.addLine(to: pt(6700, 160))

            // Serie Leistung (200 PS @ 5100–6000)
            path.move(to: pt(1500, 45))
            path.addLine(to: pt(2800, 110))
            path.addLine(to: pt(4000, 160))
            path.addLine(to: pt(5100, 200))
            path.addLine(to: pt(6000, 200))
            path.addLine(to: pt(6700, 150))
        }
        .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
    }
}

private func Stage1TorquePath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 36
        let plotW = width - 50
        let bottom = height - 24
        let plotH = bottom - 16

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1750, 260))
        path.addCurve(to: pt(2800, 392), control1: pt(2100, 310), control2: pt(2450, 385))
        path.addLine(to: pt(3500, 370))
        path.addLine(to: pt(4500, 352))
        path.addCurve(to: pt(5500, 300), control1: pt(4900, 335), control2: pt(5200, 315))
        path.addLine(to: pt(6300, 245))
        path.addLine(to: pt(6700, 220))
        path.addLine(to: pt(6800, 100))
    }
}

private func Stage1TorqueFillPath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 36
        let plotW = width - 50
        let bottom = height - 24
        let plotH = bottom - 16

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1750, 0))
        path.addLine(to: pt(1750, 260))
        path.addCurve(to: pt(2800, 392), control1: pt(2100, 310), control2: pt(2450, 385))
        path.addLine(to: pt(3500, 370))
        path.addLine(to: pt(4500, 352))
        path.addCurve(to: pt(5500, 300), control1: pt(4900, 335), control2: pt(5200, 315))
        path.addLine(to: pt(6300, 245))
        path.addLine(to: pt(6700, 220))
        path.addLine(to: pt(6800, 100))
        path.addLine(to: pt(6800, 0))
        path.closeSubpath()
    }
}

private func Stage1PowerPath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 36
        let plotW = width - 50
        let bottom = height - 24
        let plotH = bottom - 16

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1750, 65))
        path.addCurve(to: pt(2800, 156), control1: pt(2100, 95), control2: pt(2450, 130))
        path.addLine(to: pt(4500, 225))
        path.addLine(to: pt(5500, 248))
        path.addCurve(to: pt(6300, 268.9), control1: pt(5800, 258), control2: pt(6100, 266))
        path.addLine(to: pt(6600, 265))
        path.addLine(to: pt(6700, 255))
        path.addLine(to: pt(6800, 95))
    }
}

private func Stage1PowerFillPath(width: CGFloat, height: CGFloat) -> Path {
    Path { path in
        let left: CGFloat = 36
        let plotW = width - 50
        let bottom = height - 24
        let plotH = bottom - 16

        func pt(_ rpm: Double, _ val: Double) -> CGPoint {
            let x = left + ((rpm - 1500.0) / 5500.0 * plotW)
            let y = bottom - (val / 450.0 * plotH)
            return CGPoint(x: x, y: y)
        }

        path.move(to: pt(1750, 0))
        path.addLine(to: pt(1750, 65))
        path.addCurve(to: pt(2800, 156), control1: pt(2100, 95), control2: pt(2450, 130))
        path.addLine(to: pt(4500, 225))
        path.addLine(to: pt(5500, 248))
        path.addCurve(to: pt(6300, 268.9), control1: pt(5800, 258), control2: pt(6100, 266))
        path.addLine(to: pt(6600, 265))
        path.addLine(to: pt(6700, 255))
        path.addLine(to: pt(6800, 95))
        path.addLine(to: pt(6800, 0))
        path.closeSubpath()
    }
}
