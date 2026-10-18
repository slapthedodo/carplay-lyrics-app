// MARK: - PedalVisualizerView.swift
// 'Pedale' Tab – Live-Pedalanzeige (Kupplung, Bremse, Gas) + Drehzahl + Gang
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Main View

public struct PedalVisualizerView: View {

    @ObservedObject var obd: OBDManager
    @ObservedObject var motion: MotionManager

    // Interaktive Demo-Werte für Kupplung und Bremse (zum Erklären)
    @State private var manualClutch: Double = 0
    @State private var manualBrake: Double  = 0

    public init(obd: OBDManager, motion: MotionManager) {
        self.obd = obd
        self.motion = motion
    }

    // ── Derived values ────────────────────────────────────────────────────────

    // 1. KUPPLUNG (Links): Manuell interaktiv per Touch (Golf 5 hat keinen analogen Kupplungssensor in OBD2)
    private var clutchValue: Int {
        Int(manualClutch)
    }

    // 2. BREMSE (Mitte): Echte Längsverzögerung NUR bei Fahrt (speed > 3 km/h), sonst interaktiv per Touch
    private var brakeValue: Int {
        if manualBrake > 0 { return Int(manualBrake) }
        guard obd.liveSpeed > 3 else { return 0 } // Im Stand kein Schüttel-Fehlauslöser!
        let g = motion.gY   // negative = Bremsverzögerung im Fahrzeug
        guard g < -0.12 else { return 0 }
        return min(100, Int(abs(g) * 200))
    }

    // 3. GAS (Rechts): 100% Live aus der Motorsteuerung (PID 01 11 / Drosselklappe & Last)
    private var gasValue: Int {
        obd.throttlePosition ?? obd.liveEngineLoad ?? 0
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
        .onAppear {
            obd.focusMode = .pedalOnly
        }
        .onDisappear {
            obd.focusMode = .standard
        }
    }

    // MARK: Portrait

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                pedalsRow(height: min(geo.size.height * 0.38, 260))

                rpmGauge(size: min(geo.size.width * 0.65, 210))

                gearIndicator()

                pedalInfoNotice()
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
    }

    // MARK: Landscape

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 16) {
            pedalsRow(height: geo.size.height * 0.76)
                .frame(width: geo.size.width * 0.52)

            VStack(spacing: 10) {
                rpmGauge(size: min(geo.size.width * 0.32, 190))
                gearIndicator()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
    }

    // MARK: Pedale (Kupplung - Bremse - Gas)

    private func pedalsRow(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            // 1. KUPPLUNG (Links)
            PedalView(
                label: "KUPPLUNG",
                emoji: "⚙️",
                value: clutchValue,
                color: .orange,
                badge: "TOUCH / DEMO",
                height: height,
                interactiveValue: $manualClutch
            )

            // 2. BREMSE (Mitte)
            PedalView(
                label: "BREMSE",
                emoji: "🛑",
                value: brakeValue,
                color: .red,
                badge: obd.liveSpeed > 3 ? "G-VERZÖGERUNG" : "TOUCH / DEMO",
                height: height,
                interactiveValue: $manualBrake
            )

            // 3. GAS (Rechts)
            PedalView(
                label: "GAS",
                emoji: "🚀",
                value: gasValue,
                color: .cyan,
                badge: "OBD LIVE (01 11)",
                height: height,
                interactiveValue: nil
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
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(estimatedGear == "N" ? Color.yellow : Color.white)
                .shadow(color: .cyan.opacity(0.4), radius: 10)

            Text("GANG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2.5)
        }
    }

    // MARK: Info Notice

    private func pedalInfoNotice() -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.cyan)

            Text("Reihenfolge: Kupplung (L) – Bremse (M) – Gas (R). Gas kommt 1:1 live aus dem Golf 5 GTI. Bremse & Kupplung kannst du auf dem Bildschirm direkt mit dem Finger drücken, um Fahranfängern das Anfahren zu zeigen.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineSpacing(2)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Gear Estimator

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
    let badge: String
    let height: CGFloat
    var interactiveValue: Binding<Double>? = nil

    private var fraction: CGFloat {
        CGFloat(min(100, max(0, value))) / 100.0
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 16))
                Text(label)
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(color)
            }

            // Pedal Bar (Interaktiv per Drag / Tap falls Binding vorhanden)
            pedalBar

            // Value text + Badge
            VStack(spacing: 2) {
                Text("\(value)%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(value > 0 ? color : .white.opacity(0.35))

                Text(badge)
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pedalBar: some View {
        GeometryReader { geo in
            let barH = geo.size.height
            ZStack(alignment: .bottom) {
                // Background Track
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(color.opacity(0.25), lineWidth: 1)
                    )

                // Fill Bar
                if fraction > 0 {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.45), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: barH * fraction)
                        .shadow(color: color.opacity(0.7), radius: fraction > 0.1 ? 8 : 0)
                        .animation(.spring(response: 0.15, dampingFraction: 0.75), value: fraction)
                }

                // Rillen / Ticks wie bei echten Sportpedalen
                ForEach([25, 50, 75], id: \.self) { tick in
                    let yPos = barH * (1.0 - CGFloat(tick) / 100.0)
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .offset(y: yPos - barH / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard let binding = interactiveValue else { return }
                        let percent = 1.0 - (g.location.y / barH)
                        binding.wrappedValue = min(100.0, max(0.0, Double(percent * 100.0)))
                    }
                    .onEnded { _ in
                        guard let binding = interactiveValue else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            binding.wrappedValue = 0
                        }
                    }
            )
        }
        .frame(height: max(height - 75, 70))
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

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: CGFloat((endAngle - startAngle) / 360.0))
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 12, lineCap: .round))
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
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
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
        }
        .frame(width: size, height: size)
    }
}
