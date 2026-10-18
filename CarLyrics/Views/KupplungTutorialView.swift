// MARK: - KupplungTutorialView.swift
// 'Fahren' Tab – Interaktive Kupplung-Anfahren-Visualisierung
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Main View

public struct KupplungTutorialView: View {

    @ObservedObject public var obd: OBDManager

    // ── State ─────────────────────────────────────────────────────────────────
    @State private var gasPercent: Double      = 0      // 0–100 (Slider)
    @State private var kupplungPercent: Double = 0      // 0–100 (Slider)

    @State private var motorRotation: Double   = 0      // current angle (°)
    @State private var autoRotation: Double    = 0

    // Timer driving the motor disc animation
    @State private var animTimer: Timer?
    @State private var lastTick: Date = Date()

    public init(obd: OBDManager = OBDManager.shared) {
        self.obd = obd
    }

    // ── Derived ───────────────────────────────────────────────────────────────

    /// Echter Gaspedalwert aus dem Auto wenn OBD verbunden ist, sonst der Schieberegler
    private var effectiveGas: Double {
        if obd.isEnabled && obd.connectionState == .connected {
            if let thr = obd.throttlePosition, thr > 0 { return Double(thr) }
            if let load = obd.liveEngineLoad, load > 5 { return Double(load) }
        }
        return gasPercent
    }

    /// Motor speed in °/s
    private var motorDPS: Double {
        effectiveGas * 3.6   // 0 → 0 °/s, 100 → 360 °/s
    }

    /// Engagement factor 0–1 (ramps up 50–100% clutch)
    private var engagement: Double {
        let k = kupplungPercent
        if k < 50 { return 0 }
        return min(1.0, (k - 50.0) / 50.0)
    }

    /// AUTO disc lags behind MOTOR proportionally to engagement
    private var autoDPS: Double {
        motorDPS * engagement
    }

    private var isStalled: Bool {
        kupplungPercent > 50 && effectiveGas < 15
    }

    private var statusText: String {
        if isStalled                                      { return "ABGEWÜRGT! 😬" }
        if kupplungPercent < 1                            { return "Kupplung komplett treten!" }
        if kupplungPercent >= 90 && effectiveGas > 30     { return "Angefahren! 🎉" }
        if kupplungPercent >= 70                         { return "Fast da!" }
        if kupplungPercent >= 30                         { return "Kupplung langsam loslassen..." }
        if effectiveGas < 20                             { return "Gas geben..." }
        return "Kupplung langsam loslassen..."
    }

    private var statusColor: Color {
        switch statusText {
        case let s where s.contains("ABGEWÜRGT"): return .red
        case let s where s.contains("Angefahren"): return .green
        case let s where s.contains("Fast"):       return .yellow
        default:                                   return .cyan
        }
    }

    // ── Body ──────────────────────────────────────────────────────────────────

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
        .preferredColorScheme(.dark)
        .onAppear {
            obd.focusMode = .minimal
            startTimer()
        }
        .onDisappear {
            obd.focusMode = .standard
            stopTimer()
        }
    }

    // MARK: Layouts

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            statusBanner()
            discRow(discSize: min(geo.size.width * 0.37, 160))
            engagementZone()
            Spacer(minLength: 8)
            slidersSection()
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                statusBanner()
                discRow(discSize: min(geo.size.height * 0.36, 140))
                engagementZone()
            }
            .frame(maxWidth: .infinity)
            slidersSection()
                .frame(width: geo.size.width * 0.3)
        }
        .padding(16)
    }

    // MARK: Status Banner

    private func statusBanner() -> some View {
        Text(statusText)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.4), lineWidth: 1))
            .animation(.easeInOut(duration: 0.3), value: statusText)
            .id(statusText)
    }

    // MARK: Disc Row

    private func discRow(discSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            ClutchDiscView(
                label: "MOTOR",
                accentColor: .cyan,
                rotation: motorRotation,
                isSpinning: motorDPS > 0,
                speedFraction: gasPercent / 100.0
            )
            .frame(width: discSize, height: discSize)

            engagementBridge(discSize: discSize)

            ClutchDiscView(
                label: "AUTO",
                accentColor: Color(red: 1.0, green: 0.75, blue: 0.0),
                rotation: autoRotation,
                isSpinning: autoDPS > 0,
                speedFraction: autoDPS / max(motorDPS, 1) * gasPercent / 100.0
            )
            .frame(width: discSize, height: discSize)
        }
    }

    // MARK: Engagement Bridge

    private func engagementBridge(discSize: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 50, height: discSize * 0.25)

            // fill bar based on engagement
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.orange, .yellow, .green],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 50 * engagement, height: discSize * 0.25)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .animation(.easeInOut(duration: 0.1), value: engagement)

            Text(String(format: "%.0f%%", kupplungPercent))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .offset(y: discSize * 0.18)
        }
        .frame(width: 50, height: discSize * 0.40)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Engagement Zone Label

    private func engagementZone() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Einrückpunkt")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.5)
                Text(String(format: "Einrückung: %.0f%%", engagement * 100))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(engagementColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Motor")
                    .font(.system(size: 10)).foregroundStyle(.cyan.opacity(0.7))
                Text(String(format: "%.0f °/s", motorDPS))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(.horizontal, 4)
    }

    private var engagementColor: Color {
        switch engagement {
        case ..<0.3:  return .red
        case ..<0.7:  return .orange
        case ..<0.95: return .yellow
        default:      return .green
        }
    }

    // MARK: Sliders

    private func slidersSection() -> some View {
        VStack(spacing: 20) {
            sliderRow(
                label: "🚀 Gaspedal",
                value: $gasPercent,
                color: .cyan,
                min: 0, max: 100
            )
            sliderRow(
                label: "⚙️ Kupplung",
                value: $kupplungPercent,
                color: .orange,
                min: 0, max: 100
            )
        }
        .padding(.horizontal, 4)
    }

    private func sliderRow(label: String, value: Binding<Double>,
                           color: Color, min: Double, max: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: value, in: min...max)
                .tint(color)
        }
    }

    // MARK: Timer (Ruckelfrei ohne Task-Allocation)

    private func startTimer() {
        stopTimer()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [self] _ in
            let now = Date()
            let dt = min(0.1, now.timeIntervalSince(self.lastTick))
            self.lastTick = now

            let mDPS = self.motorDPS
            let aDPS = self.autoDPS

            // Wenn der Motor steht, keine State-Invalidierung auslösen (0% CPU)
            guard mDPS > 0 || aDPS > 0 else { return }

            self.motorRotation = (self.motorRotation + mDPS * dt).truncatingRemainder(dividingBy: 360)
            self.autoRotation  = (self.autoRotation + aDPS * dt).truncatingRemainder(dividingBy: 360)
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Clutch Disc View

private struct ClutchDiscView: View {

    let label: String
    let accentColor: Color
    let rotation: Double
    let isSpinning: Bool
    let speedFraction: Double   // 0–1 for glow intensity

    private let lineCount = 12

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(accentColor, lineWidth: 8)
                .shadow(color: isSpinning ? accentColor.opacity(speedFraction * 0.8) : .clear,
                        radius: speedFraction * 18)

            // Radial lines (rotate with disc)
            radialLines
                .rotationEffect(.degrees(rotation))

            // Inner hub
            Circle()
                .fill(accentColor.opacity(0.25))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle().stroke(accentColor, lineWidth: 2)
                )

            // Center label
            Text(label)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: accentColor.opacity(0.9), radius: 4)
        }
    }

    private var radialLines: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outerR = min(geo.size.width, geo.size.height) / 2 - 10
            let innerR: CGFloat = 20
            Path { path in
                for i in 0..<lineCount {
                    let angle = Double(i) / Double(lineCount) * 2.0 * .pi
                    let ox = center.x + cos(angle) * outerR
                    let oy = center.y + sin(angle) * outerR
                    let ix = center.x + cos(angle) * innerR
                    let iy = center.y + sin(angle) * innerR
                    path.move(to: CGPoint(x: ix, y: iy))
                    path.addLine(to: CGPoint(x: ox, y: oy))
                }
            }
            .stroke(accentColor.opacity(0.45), lineWidth: 1.5)
        }
    }
}

// MARK: - Preview

#Preview {
    KupplungTutorialView()
}
