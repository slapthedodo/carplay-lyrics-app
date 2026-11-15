// MARK: - HandyModusLandscapeView.swift
// Widescreen Racing Cockpit: Unibody Panoramic Glass Cockpit für den Querformat-Einsatz
// Edge-to-Edge Skalierung für iPhone 14 Pro Max + Tri-Zone Cockpit + MoTeC Flight-Bar + 18-LED Shift Runway
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLandscapeView: View {
    @ObservedObject public var observer : MusicObserver
    @ObservedObject public var obd      : OBDManager
    @ObservedObject public var motion   : MotionManager
    @ObservedObject public var warmup   : WarmupManager

    public enum LandscapeLayoutMode: String, CaseIterable {
        case cockpit = "Cockpit"
        case lyrics  = "Lyrics"
        case dyno    = "Dyno"
    }

    @AppStorage("carlyrics_landscape_layout_mode")
    private var layoutMode: LandscapeLayoutMode = .cockpit

    public init(observer: MusicObserver,
                obd:      OBDManager,
                motion:   MotionManager,
                warmup:   WarmupManager) {
        self.observer = observer
        self.obd      = obd
        self.motion   = motion
        self.warmup   = warmup
    }

    @State private var orientationID: UUID = UUID()

    private var windowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap({ $0.windows }).first {
            return window.safeAreaInsets
        }
        return UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
    }

    private var islandOnLeft: Bool {
        let insets = windowSafeAreaInsets
        if insets.left > 20 && insets.right < 20 { return true }
        if insets.right > 20 && insets.left < 20 { return false }

        let dev = UIDevice.current.orientation
        if dev == .landscapeLeft { return true }
        if dev == .landscapeRight { return false }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            if scene.interfaceOrientation == .landscapeRight { return true }
            if scene.interfaceOrientation == .landscapeLeft { return false }
        }
        return true
    }

    public var body: some View {
        GeometryReader { geo in
            let isLeft = islandOnLeft
            // Dynamic Island Seite: 60pt (exakt 1pt Abstand zur 59pt Dynamic Island)
            let islandPad: CGFloat = 60
            // Abgerundete Gehäuse-Ecke: 22pt (exakt an der Kante der 55pt Display-Rundung)
            let edgePad: CGFloat = 22

            let leadPad: CGFloat = isLeft ? islandPad : edgePad
            let trailPad: CGFloat = isLeft ? edgePad : islandPad
            let topPad: CGFloat = 4
            let bottomPad: CGFloat = 18

            let usableW = geo.size.width - leadPad - trailPad
            let usableH = geo.size.height - topPad - bottomPad

            let topBarH: CGFloat = 22
            let flightBarH: CGFloat = 34
            let vSpacing: CGFloat = 4
            let mainStageH = max(240, usableH - topBarH - flightBarH - (vSpacing * 2))

            VStack(spacing: vSpacing) {
                // ── 1. Top F1/GT3 Shift-Light Runway & Horizon Bar ────────────
                topShiftLightRunway(width: usableW, height: topBarH)

                // ── 2. Unified Unibody Glass Cockpit Main Stage ───────────────
                mainCockpitStage(width: usableW, height: mainStageH)

                // ── 3. Bottom MoTeC Telemetry Flight-Bar ──────────────────────
                WidescreenTelemetryRibbon(obd: obd, motion: motion, width: usableW, height: flightBarH)
            }
            .padding(.leading, leadPad)
            .padding(.trailing, trailPad)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .id(orientationID)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                orientationID = UUID()
            }
        }
        .overlay(
            Group {
                if obd.isColdOverloaded {
                    ColdEngineOverloadFlashOverlay(title: obd.coldOverloadMessage, detail: obd.coldOverloadDetail)
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 1. Top Shift-Light Runway (18 LEDs + OBD Status + Mode Switcher)
    // ─────────────────────────────────────────────────────────────────────────

    private func topShiftLightRunway(width: CGFloat, height: CGFloat) -> some View {
        let rpmRatio = min(1.0, max(0.0, Double(obd.liveRPM) / 7000.0))

        return HStack(spacing: 8) {
            // Left: OBD Status Pill
            HStack(spacing: 3) {
                Circle().fill(obdPillColor).frame(width: 5, height: 5)
                Text(obdLabel)
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .foregroundStyle(obdPillColor)
            }
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(obdPillColor.opacity(0.12), in: Capsule())

            // Center: 18-Segment GT3 / F1 Shift-Lights
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { idx in
                    let threshold = Double(idx + 1) / 18.0
                    let isLit = rpmRatio >= threshold
                    let color: Color = idx < 6 ? .green : (idx < 12 ? .yellow : (idx < 16 ? .orange : .red))

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isLit ? color : Color.white.opacity(0.08))
                        .frame(height: 5.5)
                        .shadow(color: isLit ? color.opacity(0.85) : .clear, radius: 4)
                }
            }
            .frame(maxWidth: .infinity)

            // Mode Picker Capsule (Cockpit | Lyrics)
            HStack(spacing: 2) {
                ForEach(LandscapeLayoutMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layoutMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 8.5, weight: layoutMode == mode ? .black : .bold))
                            .foregroundStyle(layoutMode == mode ? .white : .white.opacity(0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(
                                layoutMode == mode ? Color.cyan.opacity(0.30) : Color.clear,
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

            // Right: Keep Screen Awake
            HStack(spacing: 3) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 7.5)).foregroundStyle(.yellow)
                Text("AWAKE").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.yellow.opacity(0.85))
            }
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
        .frame(width: width, height: height)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 2. Main Cockpit Stage (Unified Unibody Glass Housing)
    // ─────────────────────────────────────────────────────────────────────────

    private func mainCockpitStage(width: CGFloat, height: CGFloat) -> some View {
        Group {
            switch layoutMode {
            case .cockpit:
                // Tri-Zone: Left Powertrain & G-Radar (30%) | Center Speed/RPM (36%) | Right Lyrics + Dyno (34%)
                let leftW = width * 0.30
                let centerW = width * 0.36
                let rightW = width * 0.34
                let vGap: CGFloat = 6
                let lyricsH = max(90, (height - vGap) * 0.44)
                let dynoH = max(110, height - lyricsH - vGap)

                HStack(spacing: 0) {
                    WidescreenPowertrainPod(obd: obd, motion: motion, width: leftW, height: height)

                    divider(height: height)

                    WidescreenTachoConsole(obd: obd, width: centerW, height: height)

                    divider(height: height)

                    // Right Column: Top Lyrics + Bottom Dyno Widget (im blauen Bereich)
                    VStack(spacing: vGap) {
                        WidescreenLyricsConsole(observer: observer, width: rightW, height: lyricsH)

                        WidescreenDynoPod(obd: obd, width: rightW, height: dynoH) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                layoutMode = .dyno
                            }
                        }
                    }
                    .frame(width: rightW, height: height)
                }

            case .lyrics:
                // Music-First: Left Expansive Cinema Lyrics (62%) | Right Speed & RPM Console (38%)
                HStack(spacing: 0) {
                    WidescreenLyricsConsole(observer: observer, width: width * 0.620, height: height)

                    divider(height: height)

                    WidescreenTachoConsole(obd: obd, width: width * 0.380, height: height)
                }

            case .dyno:
                // SuperFlow WinDyn Live Dyno Graph
                HandyModusDynoView(obd: obd, isPresented: .constant(true), showCloseButton: false)
            }
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func divider(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: height * 0.82)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Pill Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private var obdLabel: String {
        guard obd.isEnabled else { return "OBD AUS" }
        switch obd.connectionState {
        case .connected: return "OBD LIVE"
        case .scanning, .connecting, .initializing: return "VERBINDET…"
        default: return "OBD GETRENNT"
        }
    }

    private var obdPillColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .initializing: return .orange
        default: return .red
        }
    }
}

