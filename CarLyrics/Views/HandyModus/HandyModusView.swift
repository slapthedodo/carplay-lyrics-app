// MARK: - HandyModusView.swift
// Vollbild-Dashboard als Handy-Ersatz für CarPlay: Racing-Design mit
// Lyrics, RPM, Ladedruck, Öltemp, G-Kräfte, IAT, MAF, Batterie, Auspuff (est.)
// ─────────────────────────────────────────────────────────────────────────────
// STRICT: max 499 Zeilen. Gauge-Details → HandyModusGaugesView.swift,
//         Lyrics       → HandyModusLyricsPanel.swift,
//         G-Force      → HandyModusGForcePanel.swift,
//         Stats        → HandyModusStatsBar.swift,
//         Background   → HandyModusBackground.swift
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusView: View {

    @ObservedObject public var observer : MusicObserver
    @ObservedObject public var obd      : OBDManager
    @ObservedObject public var motion   : MotionManager
    @ObservedObject public var warmup   : WarmupManager

    // Keep screen awake while this tab is visible
    @State private var idleTimerDisabled = false
    // Show calibration hint once
    @State private var showCalibHint = true
    // Live Prüfstand Dyno Sheet
    @State private var showDynoSheet = false

    // Auto-hiding Tab Bar: Leiste geht nach Inaktivität langsam weg und ploppt bei Berührung wieder auf
    @State private var isTabBarVisible: Bool = true
    @State private var hideTabBarTask: Task<Void, Never>? = nil

    private func showTabBarTemporarily() {
        if !isTabBarVisible {
            withAnimation(.easeInOut(duration: 0.25)) {
                isTabBarVisible = true
            }
        }
        hideTabBarTask?.cancel()
        hideTabBarTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5s sichtbar bleiben
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.8)) { // Langsam & weich ausblenden
                        isTabBarVisible = false
                    }
                }
            }
        }
    }

    public init(observer: MusicObserver,
                obd:      OBDManager,
                motion:   MotionManager,
                warmup:   WarmupManager) {
        self.observer = observer
        self.obd      = obd
        self.motion   = motion
        self.warmup   = warmup
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Body
    // ─────────────────────────────────────────────────────────────────────────

    private var safeHardwareInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap({ $0.windows }).first {
            return window.safeAreaInsets
        }
        return UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    public var body: some View {
        ZStack {
            HandyModusBackground()

            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                if isLandscape {
                    HandyModusLandscapeView(
                        observer: observer,
                        obd: obd,
                        motion: motion,
                        warmup: warmup
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            // ── 1. Status-Streifen ──────────────────────────────────
                            statusStrip
                                .padding(.top, max(safeHardwareInsets.top, geo.safeAreaInsets.top, 56))

                            // ── 2. Lyrics Panel ─────────────────────────────────────
                            HandyModusLyricsPanel(observer: observer)

                            // ── 3. Haupt-Gauges: RPM + Ladedruck + Öltemp ──────────
                            mainGaugesRow

                            // ── 4. G-Kräfte Panel ────────────────────────────────
                            HandyModusGForcePanel(motion: motion)

                            // ── 5. Stats-Grid (8 Kacheln) ───────────────────────────
                            HandyModusStatsBar(obd: obd, motion: motion)

                            // ── 6. Widget-Erklärung (einmalig) ──────────────────────
                            widgetExplanationBanner

                            // ── 7. Kalibrierung & Warmup-Footer ─────────────────────
                            footerControls
                                .padding(.bottom, max(safeHardwareInsets.bottom, geo.safeAreaInsets.bottom, 34))
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .toolbar(isTabBarVisible ? .visible : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.4), value: isTabBarVisible)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    showTabBarTemporarily()
                }
        )
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDynoSheet) {
            HandyModusDynoView(obd: obd, isPresented: $showDynoSheet)
        }
        .overlay(
            Group {
                if obd.isColdOverloaded {
                    ColdEngineOverloadFlashOverlay(title: obd.coldOverloadMessage, detail: obd.coldOverloadDetail)
                }
            }
        )
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            idleTimerDisabled = true
            showTabBarTemporarily()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTimerDisabled = false
            hideTabBarTask?.cancel()
            isTabBarVisible = true
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Status Strip
    // ─────────────────────────────────────────────────────────────────────────

    private var statusStrip: some View {
        HStack(spacing: 8) {
            // OBD Verbindung
            connectionPill(
                label:  obdLabel,
                color:  obdPillColor,
                icon:   "cable.connector"
            )

            // Simulation / OBD Modus
            if !obd.isEnabled {
                connectionPill(label: "SIMULATION", color: .cyan, icon: "waveform")
            }

            Spacer()

            // 📈 SuperFlow Dyno Prüfstand Button (Oben Rechts)
            Button {
                showDynoSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 9, weight: .bold))
                    Text("Dyno")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Color.cyan.opacity(0.3), lineWidth: 1))
            }

            // Bildschirm aktiv
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                Text("Kein Standby")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
    }

    private func connectionPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
    }

    private var obdLabel: String {
        guard obd.isEnabled else { return "OBD AUS" }
        switch obd.connectionState {
        case .connected:   return "OBD LIVE"
        case .scanning:    return "SUCHE…"
        case .connecting:  return "VERBINDET…"
        default:           return "OBD GETRENNT"
        }
    }

    private var obdPillColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected:   return .green
        case .scanning, .connecting, .initializing: return .orange
        default:           return .red
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Main Gauges Row  (RPM + Ladedruck + Öltemp)
    // ─────────────────────────────────────────────────────────────────────────

    private var mainGaugesRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // Öltemp Ring (links)
            VStack(spacing: 4) {
                OilTempRingView(tempC: obd.effectiveOilTemp, size: 110)
                Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL (EST)")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)

            // RPM Tacho (Mitte, größer)
            VStack(spacing: 4) {
                RPMTachometerView(rpm: obd.liveRPM, size: 155)
                Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)

            // Ladedruck Arc (rechts)
            VStack(spacing: 4) {
                BoostArcView(
                    boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                    size: 110
                )
                Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Widget-Erklärung (Info-Banner)
    // ─────────────────────────────────────────────────────────────────────────

    @AppStorage("handymodus_widget_hint_dismissed") private var widgetHintDismissed = false

    @ViewBuilder
    private var widgetExplanationBanner: some View {
        if !widgetHintDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.cyan)
                    Text("Widget & Dynamic Island — Wie es wirklich funktioniert")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Button {
                        widgetHintDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("""
• **Dynamic Island / Sperrbildschirm** — Live-Lyrics in Echtzeit ✅ (startet automatisch im Auto)
• **iPhone Home-Screen Widget** — iOS erlaubt nur ~40–70 Updates/Tag, echte Lyrics-Synchronisation ist Apple-technisch unmöglich ❌
• Das Widget zeigt den letzten bekannten Songtitel + Öl-Warmup-Kurve, die immer frisch ist.
• **Fazit:** Für Live-Lyrics immer die Dynamic Island nutzen — genau dafür ist dieser Modus hier!
""")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.cyan.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Footer Controls
    // ─────────────────────────────────────────────────────────────────────────

    private var footerControls: some View {
        Group {
            if obd.isEnabled && obd.connectionState != .connected {
                HStack {
                    Spacer()
                    Button {
                        obd.reconnect()
                    } label: {
                        Label("OBD Connect", systemImage: "cable.connector")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(CockpitButtonStyle(color: .green))
                    Spacer()
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Kaltstart-Überlastung Warn-Overlay (Rot blinkend)
// ─────────────────────────────────────────────────────────────────────────────

public struct ColdEngineOverloadFlashOverlay: View {
    public let title: String
    public let detail: String
    @State private var isBlinking = false

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Rot blinkende Rand-Vignette
            Rectangle()
                .strokeBorder(Color.red.opacity(isBlinking ? 0.95 : 0.25), lineWidth: 10)
                .background(Color.red.opacity(isBlinking ? 0.20 : 0.04))
                .ignoresSafeArea()

            // Alarm-Banner oben
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isBlinking)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.red.opacity(0.95))
                    .shadow(color: .red.opacity(0.8), radius: 20)
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }
}
