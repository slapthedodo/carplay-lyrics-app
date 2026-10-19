// MARK: - HandyModusLandscapeView.swift
// Widescreen Racing Cockpit für den Querformat-Einsatz im Handy-Halter
// Native Widescreen-Layouts: Cockpit Split, Lyrics Focus & Race Cluster
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
        case race    = "Race"
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
            let leadPad = max(insets.leading, 12)
            let trailPad = max(insets.trailing, 12)
            let bottomPad = max(insets.bottom, 6)
            let topPad = max(insets.top, 4)

            let usableW = geo.size.width - leadPad - trailPad
            let usableH = geo.size.height - topPad - bottomPad

            let topBarH: CGFloat = 26
            let vSpacing: CGFloat = 6
            let hSpacing: CGFloat = 10
            let availableH = max(260, usableH - topBarH - vSpacing)

            VStack(spacing: vSpacing) {
                // ── Top Status Bar & Layout Switcher ──────────────────────────
                topBar(width: usableW, height: topBarH)

                // ── Active Layout Mode ────────────────────────────────────────
                Group {
                    switch layoutMode {
                    case .cockpit:
                        cockpitSplitLayout(width: usableW, height: availableH, spacing: hSpacing, vSpacing: vSpacing)
                    case .lyrics:
                        lyricsFocusLayout(width: usableW, height: availableH, vSpacing: vSpacing)
                    case .race:
                        raceClusterLayout(width: usableW, height: availableH, spacing: hSpacing, vSpacing: vSpacing)
                    }
                }
                .frame(width: usableW, height: availableH)
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
    // MARK: 1. Top Status Bar with Layout Switcher
    // ─────────────────────────────────────────────────────────────────────────

    private func topBar(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 8) {
            // OBD Status Pill
            connectionPill(label: obdLabel, color: obdPillColor, icon: "cable.connector")

            if !obd.isEnabled {
                connectionPill(label: "SIMULATION", color: .cyan, icon: "waveform")
            }

            Spacer()

            // Mode Picker Capsule
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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                layoutMode == mode ? Color.cyan.opacity(0.28) : Color.clear,
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

            Spacer()

            // Keep Screen Awake Pill
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.yellow)
                Text("Kein Standby").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.yellow.opacity(0.85))
            }
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
        .frame(width: width, height: height)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Layout 1: Cockpit Split Mode (Balanced Left/Right)
    // ─────────────────────────────────────────────────────────────────────────

    private func cockpitSplitLayout(width: CGFloat, height: CGFloat, spacing: CGFloat, vSpacing: CGFloat) -> some View {
        let leftW = (width - spacing) * 0.48
        let rightW = (width - spacing) * 0.52

        let gaugesCardH = height * 0.55
        let gForceCardH = height * 0.45 - vSpacing
        let lyricsCardH = height * 0.58
        let statsCardH  = height * 0.42 - vSpacing

        return HStack(alignment: .top, spacing: spacing) {
            // Linke Spalte: Widescreen Tacho Console + Widescreen G-Force Pod
            VStack(spacing: vSpacing) {
                WidescreenTachoConsole(obd: obd, width: leftW, height: gaugesCardH)
                WidescreenGForcePod(motion: motion, width: leftW, height: gForceCardH)
            }
            .frame(width: leftW, height: height)

            // Rechte Spalte: Widescreen Lyrics Stage + Widescreen Telemetry Ribbon
            VStack(spacing: vSpacing) {
                WidescreenLyricsConsole(observer: observer, width: rightW, height: lyricsCardH)
                WidescreenTelemetryRibbon(obd: obd, motion: motion, width: rightW, height: statsCardH)
            }
            .frame(width: rightW, height: height)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Layout 2: Lyrics Focus Mode (Kino-Songtext Bühne + Telemetrie)
    // ─────────────────────────────────────────────────────────────────────────

    private func lyricsFocusLayout(width: CGFloat, height: CGFloat, vSpacing: CGFloat) -> some View {
        let lyricsH = height * 0.68
        let statsH  = height * 0.32 - vSpacing

        return VStack(spacing: vSpacing) {
            // Große Widescreen Lyrics Bühne über die volle Breite
            WidescreenLyricsConsole(observer: observer, width: width, height: lyricsH)

            // Telemetrie Ribbon über die volle Breite darunter
            WidescreenTelemetryRibbon(obd: obd, motion: motion, width: width, height: statsH)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Layout 3: Race Cluster Mode (Motorsport Track Display)
    // ─────────────────────────────────────────────────────────────────────────

    private func raceClusterLayout(width: CGFloat, height: CGFloat, spacing: CGFloat, vSpacing: CGFloat) -> some View {
        let topTachoH = height * 0.56
        let bottomH   = height * 0.44 - vSpacing
        let bottomColW = (width - spacing) * 0.50

        return VStack(spacing: vSpacing) {
            // Volle Breite: Widescreen Tacho Console mit LED Shift-Lights & Hero Speed
            WidescreenTachoConsole(obd: obd, width: width, height: topTachoH)

            // Unten: G-Kräfte Scope links & Telemetrie Ribbon rechts
            HStack(spacing: spacing) {
                WidescreenGForcePod(motion: motion, width: bottomColW, height: bottomH)
                WidescreenTelemetryRibbon(obd: obd, motion: motion, width: bottomColW, height: bottomH)
            }
            .frame(width: width, height: bottomH)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Pill Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func connectionPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Image(systemName: icon).font(.system(size: 7.5, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 7.5, weight: .black, design: .rounded)).foregroundStyle(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
    }

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
