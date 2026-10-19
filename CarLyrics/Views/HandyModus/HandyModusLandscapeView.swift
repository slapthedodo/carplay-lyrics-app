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

    private var safeHardwareInsets: UIEdgeInsets {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window.safeAreaInsets
        }
        return UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
    }

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.interfaceOrientation
        }
        return .landscapeLeft
    }

    public var body: some View {
        GeometryReader { geo in
            let hwInsets = safeHardwareInsets
            let orientation = currentInterfaceOrientation

            // Dynamic Island Erkennung:
            // Bei landscapeLeft (Oberseite/Island links): Island ist leading
            // Bei landscapeRight (Oberseite/Island rechts): Island ist trailing
            let isIslandLeading: Bool = {
                if orientation == .landscapeLeft { return true }
                if orientation == .landscapeRight { return false }
                return hwInsets.left > 20
            }()

            let isIslandTrailing: Bool = {
                if orientation == .landscapeRight { return true }
                if orientation == .landscapeLeft { return false }
                return hwInsets.right > 20
            }()

            // iPhone 14 Pro Max / 15 Pro / 16 Pro Dynamic Island Hardware Clearance:
            // Die Dynamic Island ragt 59pt von der Kante hinein. Mit 4pt Puffer = 63pt.
            // Die Gegenseite ohne Island geht bis auf 14pt bündig an den Rand (kein toter Bereich!).
            let islandPad: CGFloat = max(hwInsets.left > 20 ? hwInsets.left : 0, hwInsets.right > 20 ? hwInsets.right : 0, 59) + 4
            let edgePad: CGFloat = 14

            let leadPad: CGFloat = isIslandLeading ? islandPad : edgePad
            let trailPad: CGFloat = isIslandTrailing ? islandPad : edgePad
            let bottomPad: CGFloat = max(hwInsets.bottom, 16)
            let topPad: CGFloat = max(hwInsets.top, 4)

            let usableW = geo.size.width - leadPad - trailPad
            let usableH = geo.size.height - topPad - bottomPad

            let topBarH: CGFloat = 24
            let flightBarH: CGFloat = 36
            let vSpacing: CGFloat = 5
            let mainStageH = max(200, usableH - topBarH - flightBarH - (vSpacing * 2))

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
                // Tri-Zone: Left Powertrain & G-Radar (33.5%) | Center Speed/RPM (34%) | Right Lyrics (32.5%)
                HStack(spacing: 0) {
                    WidescreenPowertrainPod(obd: obd, motion: motion, width: width * 0.335, height: height)

                    divider(height: height)

                    WidescreenTachoConsole(obd: obd, width: width * 0.340, height: height)

                    divider(height: height)

                    WidescreenLyricsConsole(observer: observer, width: width * 0.325, height: height)
                }

            case .lyrics:
                // Music-First: Left Expansive Cinema Lyrics (62%) | Right Speed & RPM Console (38%)
                HStack(spacing: 0) {
                    WidescreenLyricsConsole(observer: observer, width: width * 0.620, height: height)

                    divider(height: height)

                    WidescreenTachoConsole(obd: obd, width: width * 0.380, height: height)
                }
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

