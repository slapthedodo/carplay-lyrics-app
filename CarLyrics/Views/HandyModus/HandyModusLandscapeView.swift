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

    public var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            // Dynamic Island Erkennung (Leading oder Trailing je nach Halterungsausrichtung)
            let isIslandLeading = insets.leading > 20
            let isIslandTrailing = insets.trailing > 20

            // Nutzt 100% des Bildschirms aus: Nur an der Kamera-Insel wird geschützt, die andere Seite geht bis 10pt an den Rand
            let leadPad: CGFloat = isIslandLeading ? max(insets.leading, 46) : 10
            let trailPad: CGFloat = isIslandTrailing ? max(insets.trailing, 46) : 10
            let bottomPad: CGFloat = max(insets.bottom, 6)
            let topPad: CGFloat = max(insets.top, 2)

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
                // Tri-Zone: Left Powertrain & G-Radar (32%) | Center Speed/RPM (35.5%) | Right Lyrics (32.5%)
                HStack(spacing: 0) {
                    WidescreenPowertrainPod(obd: obd, motion: motion, width: width * 0.320, height: height)

                    divider(height: height)

                    WidescreenTachoConsole(obd: obd, width: width * 0.355, height: height)

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

