// MARK: - KupplungTutorialView.swift
// 'Fahren' Tab – 3D-Kupplungsvisualisierung mit Wellen & Kupplungsschnalz-Schutz
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Main View

public struct KupplungTutorialView: View {

    @ObservedObject public var obd: OBDManager
    @Environment(\.dismiss) private var dismiss

    // ── Interaktive Schieberegler ──────────────────────────────────────────────
    @State private var gasPercent: Double      = 25     // 0–100 % (Start im Standgas)
    @State private var kupplungPercent: Double = 0      // 0 = Getreten (getrennt), 100 = Losgelassen (Kraftschluss)

    // ── Dynamik-Überwachung (Kupplung fallen lassen) ─────────────────────────
    @State private var lastKupplungPercent: Double = 0
    @State private var lastKupplungTime: Date      = Date()
    @State private var isStalled: Bool            = false
    @State private var stallReason: String         = ""

    // ── 3D Rotationswinkel ───────────────────────────────────────────────────
    @State private var motorAngle: Double = 0           // Radiant
    @State private var autoAngle: Double  = 0           // Radiant

    @State private var animTimer: Timer?
    @State private var lastTick: Date = Date()

    public init(obd: OBDManager = OBDManager.shared) {
        self.obd = obd
    }

    // ── Physik & Ableitungen ─────────────────────────────────────────────────

    private var effectiveGas: Double {
        if obd.isEnabled && obd.connectionState == .connected {
            if let thr = obd.throttlePosition, thr > 0 { return Double(thr) }
            if let load = obd.liveEngineLoad, load > 5 { return Double(load) }
        }
        return gasPercent
    }

    private var motorDPS: Double {
        if isStalled { return 0 }
        return 2.8 + (effectiveGas / 100.0) * 11.0
    }

    private var clutchEngagement: Double {
        if kupplungPercent < 20 { return 0.0 }
        return min(1.0, (kupplungPercent - 20.0) / 75.0)
    }

    private var autoDPS: Double {
        isStalled ? 0 : (motorDPS * clutchEngagement)
    }

    private var statusText: String {
        if isStalled { return "ABGEWÜRGT! 😬 – \(stallReason) Kupplung ganz treten!" }
        if kupplungPercent < 15 { return "1. Kupplung getreten – Scheiben sind getrennt (Freilauf)" }
        if kupplungPercent >= 85 && effectiveGas >= 20 { return "5. Angefahren! 🎉 Beide Scheiben drehen synchron." }
        if kupplungPercent >= 65 { return "4. Kraftschluss fast da – Auto beschleunigt zügig!" }
        if kupplungPercent >= 35 { return "3. Schleifpunkt! Rechte Scheibe dreht langsam an ⚙️" }
        if effectiveGas < 20 { return "2. Etwas Gas geben (~1.500 U/min Standgas erhöhen)..." }
        return "Kupplung langsam kommen lassen..."
    }

    private var statusColor: Color {
        if isStalled { return .red }
        if kupplungPercent >= 85 && effectiveGas >= 20 { return .green }
        if kupplungPercent >= 35 { return Color(red: 0.95, green: 0.86, blue: 0.48) }
        return Color(red: 0.64, green: 0.94, blue: 0.97)
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    public var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.13).ignoresSafeArea()

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

    // MARK: Portrait Layout

    @ViewBuilder
    private func portraitLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            topBar()
            headerTitles()

            clutch3DCanvas()
                .frame(height: min(geo.size.height * 0.38, 230))
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

            statusBanner()
            Spacer(minLength: 4)
            slidersSection()
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: Landscape Layout

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 6) {
            topBar()
            HStack(spacing: 14) {
                VStack(spacing: 8) {
                    headerTitles()
                    clutch3DCanvas()
                        .frame(maxHeight: .infinity)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                    statusBanner()
                }
                .frame(maxWidth: .infinity)

                slidersSection()
                    .frame(width: geo.size.width * 0.36)
            }
        }
        .padding(12)
    }

    // MARK: Top Bar mit Schließen-Button

    private func topBar() -> some View {
        HStack {
            Label("Schaltgetriebe-Tutorial", systemImage: "steeringwheel")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Header Titles

    private func headerTitles() -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("1. MOTOR (DREHT SICH)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.64, green: 0.94, blue: 0.97))
                Text("(Läuft frei im Standgas)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("2. AUTO / RÄDER (STEHT)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.86, blue: 0.48))
                Text("(Steht still = 1.500 kg Trägheit)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 3D Canvas Visualisierung

    private func clutch3DCanvas() -> some View {
        Canvas { context, size in
            let midY = size.height / 2
            let midX = size.width / 2

            let maxGap: CGFloat = min(size.width * 0.26, 95)
            let gap: CGFloat = maxGap * (1.0 - CGFloat(clutchEngagement))

            let radius: CGFloat = min(size.height * 0.38, 72)
            let thickness: CGFloat = radius * 0.30
            let shaftL: CGFloat = min(size.width * 0.20, 75)
            let shaftR: CGFloat = radius * 0.25

            let leftCenterX = midX - (thickness / 2 + gap / 2)
            let rightCenterX = midX + (thickness / 2 + gap / 2)

            // 1. Linke Baugruppe: MOTOR (Welle nach links)
            draw3DAssembly(
                context: context, centerX: leftCenterX, centerY: midY,
                radius: radius, thickness: thickness, shaftLength: shaftL, shaftRadius: shaftR,
                angle: motorAngle, isLeft: true,
                primaryColor: Color(red: 0.64, green: 0.94, blue: 0.97),
                darkColor: Color(red: 0.18, green: 0.23, blue: 0.28)
            )

            // 2. Rechte Baugruppe: AUTO (Welle nach rechts)
            // KORREKTUR: -autoAngle für physikalisch synchrone Rotationsrichtung
            draw3DAssembly(
                context: context, centerX: rightCenterX, centerY: midY,
                radius: radius, thickness: thickness, shaftLength: shaftL, shaftRadius: shaftR,
                angle: -autoAngle, isLeft: false,
                primaryColor: Color(red: 0.95, green: 0.86, blue: 0.48),
                darkColor: Color(red: 0.18, green: 0.23, blue: 0.28)
            )

            // 3. Reibungs-Effekt bei Berührung
            if gap < 8 && motorDPS > 0 && autoDPS < motorDPS * 0.95 {
                var glowPath = Path()
                glowPath.addRoundedRect(in: CGRect(x: midX - 2.5, y: midY - radius * 0.8, width: 5, height: radius * 1.6), cornerSize: CGSize(width: 2.5, height: 2.5))
                context.fill(glowPath, with: .color(.orange.opacity(0.85)))
            }
        }
    }

    // MARK: 3D Zeichnung einer Scheibe mit Welle & Rillen

    private func draw3DAssembly(
        context: GraphicsContext, centerX: CGFloat, centerY: CGFloat,
        radius: CGFloat, thickness: CGFloat, shaftLength: CGFloat, shaftRadius: CGFloat,
        angle: Double, isLeft: Bool, primaryColor: Color, darkColor: Color
    ) {
        let yawScale: CGFloat = 0.40
        let xFront = isLeft ? (centerX + thickness / 2) : (centerX - thickness / 2)
        let xBack  = isLeft ? (centerX - thickness / 2) : (centerX + thickness / 2)

        // 1. Chrome-Welle
        let shaftStartX = isLeft ? (xBack - shaftLength) : xBack
        let shaftRect = CGRect(x: shaftStartX, y: centerY - shaftRadius, width: shaftLength, height: shaftRadius * 2)
        var shaftPath = Path()
        shaftPath.addRoundedRect(in: shaftRect, cornerSize: CGSize(width: shaftRadius * 0.45, height: shaftRadius * 0.45))

        let chromeGradient = Gradient(colors: [
            Color(white: 0.32), Color(white: 0.90), Color(white: 0.45), Color(white: 0.20)
        ])
        context.fill(shaftPath, with: .linearGradient(chromeGradient, startPoint: CGPoint(x: shaftStartX, y: centerY - shaftRadius), endPoint: CGPoint(x: shaftStartX, y: centerY + shaftRadius)))

        // 2. Randstreifen (Cylindrical Rim)
        let sectorCount = 8
        let sectorAngle = (2.0 * .pi) / Double(sectorCount)

        for i in 0..<sectorCount {
            let a1 = angle + Double(i) * sectorAngle
            let a2 = a1 + sectorAngle
            let segColor = (i % 2 == 0) ? primaryColor : darkColor

            let cosMid = cos(a1 + sectorAngle / 2)
            let isRimVisible = isLeft ? (cosMid < 0.15) : (cosMid > -0.15)
            if isRimVisible {
                var rimPath = Path()
                let y1 = centerY + radius * sin(a1)
                let y2 = centerY + radius * sin(a2)
                let xf1 = xFront + radius * cos(a1) * yawScale
                let xf2 = xFront + radius * cos(a2) * yawScale
                let xb1 = xBack + radius * cos(a1) * yawScale
                let xb2 = xBack + radius * cos(a2) * yawScale

                rimPath.move(to: CGPoint(x: xb1, y: y1))
                rimPath.addLine(to: CGPoint(x: xf1, y: y1))
                rimPath.addLine(to: CGPoint(x: xf2, y: y2))
                rimPath.addLine(to: CGPoint(x: xb2, y: y2))
                rimPath.closeSubpath()
                context.fill(rimPath, with: .color(segColor))
            }
        }

        // 3. Frontfläche (8 Keile)
        for i in 0..<sectorCount {
            let a1 = angle + Double(i) * sectorAngle
            let a2 = a1 + sectorAngle
            let segColor = (i % 2 == 0) ? primaryColor : darkColor

            var facePath = Path()
            facePath.move(to: CGPoint(x: xFront, y: centerY))

            for s in 0...6 {
                let currA = a1 + (a2 - a1) * (Double(s) / 6.0)
                facePath.addLine(to: CGPoint(x: xFront + radius * cos(currA) * yawScale, y: centerY + radius * sin(currA)))
            }
            facePath.closeSubpath()
            context.fill(facePath, with: .color(segColor))
        }

        // 4. Zentrierte Nabe
        var hubPath = Path()
        let hubR = radius * 0.25
        hubPath.addEllipse(in: CGRect(x: xFront - hubR * yawScale, y: centerY - hubR, width: hubR * 2 * yawScale, height: hubR * 2))
        context.fill(hubPath, with: .color(darkColor.opacity(0.85)))
        context.stroke(hubPath, with: .color(primaryColor.opacity(0.7)), lineWidth: 1.5)
    }

    // MARK: Status Banner

    private func statusBanner() -> some View {
        Text(statusText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.35), lineWidth: 1))
            .animation(.easeInOut(duration: 0.25), value: statusText)
    }

    // MARK: Sliders Section

    private func slidersSection() -> some View {
        VStack(spacing: 12) {
            sliderBlock(
                title: "🚀 Gaspedal",
                valueStr: String(format: "%.0f %%", effectiveGas),
                subtext: obd.connectionState == .connected ? "Live OBD Gas" : "Manuell",
                color: Color(red: 0.64, green: 0.94, blue: 0.97),
                binding: $gasPercent, range: 0...100, onChange: { _ in }
            )

            sliderBlock(
                title: "⚙️ Kupplung (Pedal)",
                valueStr: String(format: "%.0f %%", kupplungPercent),
                subtext: kupplungPercent < 20 ? "Getreten" : (kupplungPercent > 80 ? "Losgelassen" : "Schleifpunkt"),
                color: Color(red: 0.95, green: 0.86, blue: 0.48),
                binding: $kupplungPercent, range: 0...100,
                onChange: { newVal in checkClutchReleaseSpeed(newVal: newVal) }
            )
        }
        .padding(.horizontal, 4)
    }

    private func sliderBlock(
        title: String, valueStr: String, subtext: String, color: Color,
        binding: Binding<Double>, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                Spacer()
                Text(subtext).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Text(valueStr).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }
            Slider(value: binding, in: range)
                .tint(color)
                .onChange(of: binding.wrappedValue) { val in onChange(val) }
        }
    }

    // MARK: Kupplungsschnalz- & Abwürg-Erkennung

    private func checkClutchReleaseSpeed(newVal: Double) {
        let now = Date()
        let dt = max(0.016, now.timeIntervalSince(lastKupplungTime))
        let delta = newVal - lastKupplungPercent
        lastKupplungPercent = newVal
        lastKupplungTime = now

        let releaseRate = delta / dt // % pro Sekunde

        if releaseRate > 95.0 && newVal > 35.0 && effectiveGas < 40.0 {
            isStalled = true
            stallReason = "Kupplung zu schnell schnalzen lassen!"
        } else if newVal > 45.0 && effectiveGas < 15.0 {
            isStalled = true
            stallReason = "Zu wenig Gas für 1.500 kg Trägheit!"
        }

        if newVal < 10.0 && isStalled {
            withAnimation(.easeOut(duration: 0.25)) {
                isStalled = false
                stallReason = ""
            }
        }
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [self] _ in
            let now = Date()
            let dt = min(0.1, now.timeIntervalSince(self.lastTick))
            self.lastTick = now

            if !self.isStalled {
                self.motorAngle = (self.motorAngle + self.motorDPS * dt).truncatingRemainder(dividingBy: 2.0 * .pi)
                self.autoAngle  = (self.autoAngle + self.autoDPS * dt).truncatingRemainder(dividingBy: 2.0 * .pi)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
