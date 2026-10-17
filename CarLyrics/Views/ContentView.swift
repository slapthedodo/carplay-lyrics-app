// MARK: - ContentView.swift  (v3 — Spotify + OBD-II Cockpit Edition)
// CarLyrics – Dark Cockpit UI mit Spotify-Verbindung, CarPlay-Audioverzögerung,
// OBD-II Live-Daten vs. TFSI-Simulation und G-Ball.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import MediaPlayer

public struct ContentView: View {

    @ObservedObject private var observer = MusicObserver.shared
    @ObservedObject private var warmup   = WarmupManager.shared
    @ObservedObject private var motion   = MotionManager.shared
    @ObservedObject private var spotify  = SpotifyManager.shared
    @ObservedObject private var obd      = OBDManager.shared

    @State private var showMockSheet    = false
    @State private var showSpotifySheet = false
    @State private var showOBDSheet     = false
    @State private var selectedTab      = 0

    public var body: some View {
        ZStack {
            CockpitBackground()

            TabView(selection: $selectedTab) {
                CockpitTab(observer: observer, warmup: warmup, motion: motion, obd: obd, onOpenDiagnostics: { selectedTab = 1 })
                    .tabItem { Label("Cockpit", systemImage: "gauge.with.needle") }
                    .tag(0)

                OBDDiagnosticWorkbenchView(obd: obd, isPresentedAsSheet: false)
                    .tabItem { Label("OBD Labor", systemImage: "wrench.and.screwdriver.fill") }
                    .tag(1)

                SettingsTab(spotify: spotify, obd: obd, observer: observer)
                    .tabItem { Label("Setup", systemImage: "gearshape.fill") }
                    .tag(2)
            }
            .tint(.cyan)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMockSheet) {
            MockInjectorView(observer: observer)
        }
        .sheet(isPresented: $showSpotifySheet) {
            SpotifySetupSheet(spotify: spotify)
        }
        .sheet(isPresented: $showOBDSheet) {
            OBDDiagnosticWorkbenchView(obd: obd, isPresentedAsSheet: true)
        }
        .onAppear {
            observer.warmupManager = warmup
            observer.motionManager = motion

            // Automatisch Kaltstart-Tracking & Sensoren starten
            if !warmup.isRunning {
                warmup.start(cold: true)
            }
            motion.start()
            BackgroundKeepAliveManager.shared.start()

            // Dynamic Island Live Activity re-attachen oder starten
            Task {
                await observer.reattachOrCreateLiveActivity()
            }
            observer.startTelemetryHeartbeat()

            if spotify.isAuthenticated {
                spotify.startPolling()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // OBD Status Pill
                Button { showOBDSheet = true } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(obdColor)
                            .frame(width: 8, height: 8)
                        Text(obd.isEnabled ? "OBD: \(obd.connectionState.rawValue)" : "OBD: Sim")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                // Spotify Button
                Button { showSpotifySheet = true } label: {
                    Image(systemName: spotify.isAuthenticated ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(spotify.isAuthenticated ? .green : .secondary)
                }
            }
        }
    }

    private var obdColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected:    return .green
        case .connecting, .initializing, .scanning: return .orange
        default:            return .red
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Cockpit Tab (Lyrics + Telemetrie kombiniert)
// ─────────────────────────────────────────────────────────────────────────────

struct CockpitTab: View {
    @ObservedObject var observer : MusicObserver
    @ObservedObject var warmup   : WarmupManager
    @ObservedObject var motion   : MotionManager
    @ObservedObject var obd      : OBDManager
    var onOpenDiagnostics        : () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                NowPlayingCard(observer: observer)
                LyricsCard(observer: observer)

                // OBD Toggle Card & Labor Schnellzugriff
                GlassCard {
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Datenquelle")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(obd.isEnabled ? "OBD Live (\(obd.detailedStatus))" : "TFSI Simulation")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(obd.isEnabled ? .green : .cyan)
                            }
                            Spacer()
                            Toggle("", isOn: $obd.isEnabled)
                                .labelsHidden()
                                .tint(.green)
                                .onChange(of: obd.isEnabled) { _, enabled in
                                    if enabled { obd.enableOBD() } else { obd.disableOBD() }
                                }
                        }
                        if obd.isEnabled {
                            Button {
                                onOpenDiagnostics()
                            } label: {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                    Text("OBD-Labor & Diagnose-Werkbank")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                WarmupCard(warmup: warmup, obd: obd)
                BoostCard(obd: obd)
                GForceCard(motion: motion)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Settings / Setup Tab
// ─────────────────────────────────────────────────────────────────────────────

struct SettingsTab: View {
    @ObservedObject var spotify : SpotifyManager
    @ObservedObject var obd     : OBDManager
    @ObservedObject var observer: MusicObserver
    @State private var tokenInput: String = ""
    @State private var resetSuccess: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Dynamic Island & Live Activity Steuerung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Dynamic Island & Sperrbildschirm", systemImage: "capsule.fill")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Die Dynamic Island aktualisiert Öltemperatur, Ladedruck, G-Kraft und Songtexte live. Beim Beenden der App wird sie nach 8 Sekunden automatisch entfernt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                Task {
                                    await observer.resetLiveActivities()
                                }
                                resetSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    resetSuccess = false
                                }
                            } label: {
                                Label(resetSuccess ? "Zurückgesetzt ✓" : "Dynamic Island zurücksetzen",
                                      systemImage: resetSuccess ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(resetSuccess ? .green : .white)
                            }
                            .buttonStyle(CockpitButtonStyle(color: resetSuccess ? .green : .cyan))

                            Spacer()

                            Button {
                                Task {
                                    await observer.reattachOrCreateLiveActivity()
                                }
                            } label: {
                                Label("Neu starten", systemImage: "play.circle.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .secondary))
                        }
                    }
                }

                // Apple Kurzbefehle & Automation
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Apple Kurzbefehle (Shortcuts) & Automation", systemImage: "bolt.badge.automatic.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)

                        Text("Du kannst die Dynamic Island jetzt direkt über Apple Kurzbefehle, Siri oder automatisierte Auslöser steuern:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.purple).font(.caption)
                                Text("Aktionen: 'Dynamic Island beenden' & 'Dynamic Island starten'")
                                    .font(.caption.bold())
                            }
                            HStack {
                                Image(systemName: "link").foregroundStyle(.cyan).font(.caption)
                                Text("URL-Befehle: carlyrics://stop und carlyrics://start")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        Text("Empfohlene Automation beim Fahren:")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text("In Kurzbefehle > Automation > 'Wenn CarPlay trennt' > Aktion 'Dynamic Island beenden'. Sobald du den Schlüssel ziehst, schließt sich die Dynamic Island automatisch!")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await observer.endAllLiveActivities()
                                    BackgroundKeepAliveManager.shared.stop()
                                    MotionManager.shared.stop()
                                    WarmupManager.shared.stop()
                                }
                            } label: {
                                Label("Jetzt beenden (Aus)", systemImage: "stop.circle.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .red))

                            Button {
                                Task {
                                    BackgroundKeepAliveManager.shared.start()
                                    MotionManager.shared.start()
                                    WarmupManager.shared.start()
                                    await observer.reattachOrCreateLiveActivity()
                                    observer.startTelemetryHeartbeat()
                                }
                            } label: {
                                Label("Jetzt starten (Ein)", systemImage: "play.circle.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .green))
                        }
                    }
                }

                // Benachrichtigung bei Erreichen der Betriebstemperatur
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Betriebstemperatur Benachrichtigung", systemImage: "bell.badge.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Sobald das Öl 80°C erreicht hat und der Motor betriebsbereit ist, erhältst du automatisch eine Push-Mitteilung mit Signalton – auch bei gesperrtem Bildschirm oder im Hintergrund.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            WarmupManager.shared.requestNotificationPermission()
                            let content = UNMutableNotificationContent()
                            content.title = "Motor ist warm"
                            content.body = "Öltemperatur: 80°C"
                            content.sound = .default
                            if #available(iOS 15.0, *) {
                                content.interruptionLevel = .timeSensitive
                            }
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                            let req = UNNotificationRequest(identifier: "test_warm_engine", content: content, trigger: trigger)
                            UNUserNotificationCenter.current().add(req)
                        } label: {
                            Label("Test-Benachrichtigung senden", systemImage: "paperplane.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(CockpitButtonStyle(color: .green))
                    }
                }

                // 2. CarPlay Audio-Verzögerung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CarPlay Audio-Latenz Kompensation", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Wireless CarPlay & Bluetooth puffern Audio um 2–3 Sekunden. Dieser Regler synchronisiert die Songtexte exakt auf den Zeitpunkt, an dem der Ton aus deinen Autolautsprechern kommt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Offset:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "-%.1f s", spotify.carPlayDelayCompensation))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(.cyan)
                        }

                        Slider(value: $spotify.carPlayDelayCompensation, in: 0.0...4.0, step: 0.1)
                            .tint(.cyan)

                        HStack {
                            Text("0.0s (USB Kabel)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("2.5s (Wireless CarPlay)").font(.caption2.bold()).foregroundStyle(.cyan)
                            Spacer()
                            Text("4.0s").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // 3. G-Kraft Sensor & Maximalwert Slider
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("G-Kraft Sensor & Maximalwert")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Stelle die maximale G-Kraft passend zu deinem Fahrzeug ein. Erschütterungen über diesem Wert (z. B. Schlaglöcher) werden gefiltert, und der G-Meter (G-Ball) skaliert sich dynamisch darauf.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Max. G-Kraft Limit:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.2f G", MotionManager.shared.maxG))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(.cyan)
                        }

                        Slider(value: Binding(
                            get: { MotionManager.shared.maxG },
                            set: { MotionManager.shared.maxG = $0 }
                        ), in: 0.5...3.0, step: 0.05)
                        .tint(.cyan)

                        HStack {
                            Text("0.5G (Komfort)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("1.2G (TFSI Serie)").font(.caption2.bold()).foregroundStyle(.cyan)
                            Spacer()
                            Text("3.0G (Rennstrecke)").font(.caption2).foregroundStyle(.secondary)
                        }

                        HStack {
                            Button {
                                MotionManager.shared.resetPeak()
                            } label: {
                                Label("Peak Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .secondary))

                            Spacer()

                            Button {
                                MotionManager.shared.calibrate()
                            } label: {
                                Label("Nullpunkt kalibrieren", systemImage: "scope")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .cyan))
                        }
                    }
                }

                // 4. Spotify Verbindung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Spotify Web API", systemImage: "waveform.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Da du nur Spotify nutzt, liest CarLyrics den aktuellen Song, die Millisekunden-Position und Pausen direkt von deinem Spotify-Konto.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if spotify.isAuthenticated {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Mit Spotify verbunden").font(.subheadline.bold())
                                Spacer()
                                Button("Trennen") {
                                    spotify.accessToken = ""
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            }
                        } else {
                            VStack(spacing: 10) {
                                SecureField("Spotify OAuth Access Token hier einfügen", text: $tokenInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                Button {
                                    spotify.accessToken = tokenInput
                                    spotify.startPolling()
                                } label: {
                                    Label("Token speichern & verbinden", systemImage: "arrow.right.circle.fill")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(CockpitButtonStyle(color: .green))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Cards (NowPlaying, Lyrics, Telemetry)
// ─────────────────────────────────────────────────────────────────────────────

struct NowPlayingCard: View {
    @ObservedObject var observer: MusicObserver

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: observer.isPlaying ? "music.note.list" : "pause.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: observer.isPlaying)

                VStack(alignment: .leading, spacing: 3) {
                    if observer.currentTrackTitle.isEmpty {
                        Text("Warte auf Musik…")
                            .font(.title3).foregroundStyle(.secondary)
                    } else {
                        Text(observer.currentTrackTitle)
                            .font(.title3.bold()).foregroundStyle(.white)
                            .lineLimit(1)
                        Text(observer.currentArtist)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            if observer.progress > 0 {
                ProgressView(value: observer.progress)
                    .tint(.cyan)
                    .padding(.top, 8)
            }
        }
    }
}

struct LyricsCard: View {
    @ObservedObject var observer: MusicObserver

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Live Songtext", systemImage: "text.quote")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if observer.isPlaying {
                        Text("SYNC")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }

                if observer.currentLine.isEmpty {
                    Text(observer.lyricsStatus.label)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        // 3 Zeilen davor (sanft angedeutet)
                        if !observer.previousLine3.isEmpty {
                            Text(observer.previousLine3)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.12))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine3)
                        }

                        // 2 Zeilen davor (leicht sichtbar)
                        if !observer.previousLine2.isEmpty {
                            Text(observer.previousLine2)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.24))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine2)
                        }

                        // 1 Zeile davor
                        if !observer.previousLine.isEmpty {
                            Text(observer.previousLine)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.42))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine)
                        }

                        // ═══ Aktuelle Zeile (Extra Groß & Leuchtend) ═══
                        Text(observer.currentLine)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .cyan.opacity(0.45), radius: 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.25), value: observer.currentLine)
                            .padding(.vertical, 4)

                        // 1 Zeile danach
                        if !observer.nextLine.isEmpty {
                            Text(observer.nextLine)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine)
                        }

                        // 2 Zeilen danach (leicht sichtbar)
                        if !observer.nextLine2.isEmpty {
                            Text(observer.nextLine2)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.24))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine2)
                        }

                        // 3 Zeilen danach (sanft angedeutet)
                        if !observer.nextLine3.isEmpty {
                            Text(observer.nextLine3)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.12))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine3)
                        }
                    }
                }
            }
        }
    }
}



// ─────────────────────────────────────────────────────────────────────────────
// MARK: Warmup Card
// ─────────────────────────────────────────────────────────────────────────────

struct WarmupCard: View {
    @ObservedObject var warmup : WarmupManager
    @ObservedObject var obd    : OBDManager

    var displayTemp: Int? {
        if obd.isEnabled {
            if obd.connectionState == .connected {
                return obd.liveOilTemp ?? obd.liveCoolantTemp.map { max(20, $0 - 8) }
            }
            return nil
        }
        return warmup.oilTempInt
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Label("Motor-Temperatur", systemImage: "thermometer.medium")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if obd.isEnabled {
                        if obd.connectionState == .connected {
                            Text("LIVE OBD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        } else if obd.connectionState == .scanning {
                            Text("SUCHE ADAPTER…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else if obd.connectionState == .connecting || obd.connectionState == .initializing {
                            Text("VERBINDE…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text("OBD GETRENNT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("2.0 TFSI SIMULATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                // Gauge (Skala 0 bis 110 °C, damit auch bei Winter-Kaltstarts 0...10°C kein Bereichsfehler auftritt)
                Gauge(value: Double(max(0, displayTemp ?? 0)), in: 0...110) {
                    Text("Temperatur")
                } currentValueLabel: {
                    Text(displayTemp != nil ? "\(displayTemp!)°C" : "-- °C")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)
                } minimumValueLabel: {
                    Text("0°").font(.caption2)
                } maximumValueLabel: {
                    Text("110°").font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(displayTemp != nil ? Gradient(colors: [.blue, .orange, .green]) : Gradient(colors: [.secondary.opacity(0.3)]))
                .frame(width: 120, height: 120)

                // Phasenhinweis & Saison-Modell
                VStack(spacing: 4) {
                    Text(phaseText(displayTemp))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)

                    if !obd.isEnabled || obd.connectionState != .connected {
                        Text("Safety-Modell: \(warmup.currentProfile.seasonName) • ca. \(warmup.currentProfile.estimatedMinutesTo80) Min. bis 80°C")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tempColor(_ t: Int) -> Color {
        if t < 60 { return .blue }
        if t < 80 { return .orange }
        return .green
    }

    private func phaseText(_ t: Int?) -> String {
        guard let t else {
            if obd.connectionState == .scanning {
                return "OBD aktiviert – Suche nach Bluetooth-Adapter…"
            } else if obd.connectionState == .connecting || obd.connectionState == .initializing {
                return "OBD verbindet – Lese Steuergerät aus…"
            } else {
                return "OBD aktiviert – Warte auf Adapter & Daten…"
            }
        }
        if t < 60 { return "Kaltstart – Max. 2.500 U/min, kein Ladedruck!" }
        if t < 80 { return "Öl wärmt auf – Gemäßigt fahren" }
        return "90°C erreicht – Voller Ladedruck frei! 🏁"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Boost Card (Ladedruck & Ansaugung)
// ─────────────────────────────────────────────────────────────────────────────

struct BoostCard: View {
    @ObservedObject var obd: OBDManager

    var boostVal: Double? {
        obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Ladedruck & Ansaugung", systemImage: "gauge.with.needle.fill")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if obd.isEnabled {
                        if obd.connectionState == .connected && obd.liveBoostBar != nil {
                            Text(obd.liveMAP != nil ? "LIVE (MAP)" : "LIVE (MAF)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        } else if obd.connectionState == .connected {
                            Text("OBD BEREIT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                        } else if obd.connectionState == .scanning {
                            Text("SUCHE ADAPTER…")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        } else {
                            Text("OBD GETRENNT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("SIMULATION (KEIN OBD)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let val = boostVal {
                            Text(String(format: "%.2f", val))
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .foregroundStyle(val > 0.8 ? .orange : (val > 0.1 ? .green : .cyan))
                        } else {
                            Text("--")
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text("BAR RELATIV (LADEDRUCK)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        if let iat = obd.liveIAT {
                            Text("Ansaugluft: \(iat) °C").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                        }
                        if let maf = obd.liveMAF {
                            Text(String(format: "Luftmasse: %.1f g/s", maf)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        }
                        if let load = obd.liveEngineLoad {
                            Text("Last: \(load) %").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
                        }
                        if !obd.isEnabled || obd.connectionState != .connected {
                            Text(obd.isEnabled ? "Warte auf OBD-Daten" : "Schalte OBD ein für Ladedruck")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Force Card & GBall
// ─────────────────────────────────────────────────────────────────────────────

// ── Runde G-Kraft Anzeige nach User-Design (mit Fadenkreuz, lila Bogen, 'G-KRAFT', Zahl und 'G') ──
struct GForceGaugeBadge: View {
    let currentG : Double
    var maxG     : Double = 1.2
    var size     : CGFloat = 130

    var body: some View {
        let ratio = min(max(currentG / max(0.4, maxG), 0.0), 1.0)
        let purpleColor = Color(red: 0.68, green: 0.35, blue: 0.98) // #ae5bf7

        ZStack {
            // Schwarzer runder Hintergrund
            Circle()
                .fill(Color.black.opacity(0.85))

            // Äußerer feiner Ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: size > 60 ? 3 : 2)

            // 4 Fadenkreuz-Markierungen (12, 3, 6, 9 Uhr)
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: size > 60 ? 1.5 : 1, height: size > 60 ? 6 : 3.5)
                    .offset(y: -(size / 2 - (size > 60 ? 3 : 2)))
                    .rotationEffect(.degrees(Double(deg)))
            }

            // Lila Bogen / Fortschrittsanzeige
            Circle()
                .trim(from: 0.0, to: CGFloat(max(0.04, ratio * 0.75)))
                .stroke(
                    LinearGradient(
                        colors: [purpleColor.opacity(0.4), purpleColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size > 60 ? 4.5 : 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.interactiveSpring(response: 0.2), value: ratio)

            // Text & Fadenkreuz-Layout
            VStack(spacing: size > 60 ? 3 : -1) {
                // Weißes Fadenkreuz Icon (wie im Bild)
                Image(systemName: "scope")
                    .font(.system(size: size > 60 ? 18 : 8, weight: .bold))
                    .foregroundStyle(.white)

                Text("G-KRAFT")
                    .font(.system(size: size > 60 ? 10 : 5, weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text(String(format: "%.1f", currentG))
                    .font(.system(size: size > 60 ? 24 : 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(purpleColor)

                Text("G")
                    .font(.system(size: size > 60 ? 8 : 4.5, weight: .black, design: .rounded))
                    .foregroundStyle(purpleColor.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}

struct GForceCard: View {
    @ObservedObject var motion: MotionManager

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Text("G-Kräfte Telemetrie")
                    .font(.headline).foregroundStyle(.cyan)

                HStack(spacing: 20) {
                    GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: 125)

                    GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG, maxG: motion.maxG)
                        .frame(width: 125, height: 125)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 20) {
                    VStack {
                        Text("AKTUELL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.currentGFormatted)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(motion.currentG, maxG: motion.maxG))
                    }
                    VStack {
                        Text("PEAK").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.peakGFormatted)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    VStack {
                        Text("MAX LIMIT").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(String(format: "%.2f G", motion.maxG))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // ── Slider für maximale G-Kräfte ────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Maximale G-Kraft (Skala & Limit):")
                            .font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f G", motion.maxG))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }

                    Slider(value: $motion.maxG, in: 0.5...3.0, step: 0.05)
                        .tint(.cyan)

                    HStack {
                        Text("0.5G (Komfort)").font(.system(size: 8)).foregroundStyle(.secondary)
                        Spacer()
                        Text("1.2G (TFSI Serie)").font(.system(size: 8).bold()).foregroundStyle(.cyan)
                        Spacer()
                        Text("3.0G (Track)").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        motion.resetPeak()
                    } label: {
                        Label("Peak Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .secondary))

                    Button {
                        motion.calibrate()
                    } label: {
                        Label("Nullpunkt setzen", systemImage: "scope")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .cyan))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct GBallView: View {
    let x        : Double
    let y        : Double
    let currentG : Double
    var maxG     : Double = 1.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r  = min(w, h) / 2 - 8

            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { frac in
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: r * 2 * frac, height: r * 2 * frac)
                }

                Rectangle().fill(Color.white.opacity(0.08)).frame(width: r * 2, height: 1)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: r * 2)

                Text("ACC").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(y: -(r - 6))
                Text("BRK").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(y: r - 6)
                Text("L").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(x: -(r - 6))
                Text("R").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).offset(x: r - 6)

                // Skalenwert für den äußeren Ring
                Text(String(format: "%.1fG", maxG))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.6))
                    .offset(x: r - 16, y: -(r - 16))

                Circle()
                    .fill(gColor(currentG, maxG: maxG))
                    .frame(width: 18, height: 18)
                    .shadow(color: gColor(currentG, maxG: maxG).opacity(0.8), radius: 8)
                    .offset(x: CGFloat(x) * r, y: -CGFloat(y) * r)
                    .animation(.interactiveSpring(response: 0.15), value: x)
                    .animation(.interactiveSpring(response: 0.15), value: y)
            }
            .frame(width: w, height: h)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Sheets (OBD Debug & Spotify Setup)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OBD Diagnostic & Protocol Workbench View (Labor & Tausende Methoden)
// ─────────────────────────────────────────────────────────────────────────────

public struct OBDDiagnosticWorkbenchView: View {
    @ObservedObject var obd: OBDManager
    var isPresentedAsSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var activeSection: Int = 0 // 0: Schnelltest, 1: Sensoren, 2: Terminal, 3: Bluetooth, 4: EA113 Ratgeber
    @State private var manualCommand: String = ""
    @State private var showCopiedToast: Bool = false

    public init(obd: OBDManager, isPresentedAsSheet: Bool = false) {
        self.obd = obd
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Obere Status-Leiste (Verbindung, Bordspannung, Reconnect)
                OBDStatusBarHeader(obd: obd)

                // Segment Picker
                Picker("Bereich", selection: $activeSection) {
                    Text("⚡ Methoden").tag(0)
                    Text("📊 Sensoren").tag(1)
                    Text("💻 Terminal").tag(2)
                    Text("📡 BT-Geräte").tag(3)
                    Text("📖 Ratgeber").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

                // Inhalt des aktiven Tabs
                Group {
                    switch activeSection {
                    case 0:
                        OBDMethodProbeSection(obd: obd)
                    case 1:
                        OBDSensorMatrixSection(obd: obd)
                    case 2:
                        OBDTerminalSection(obd: obd, manualCommand: $manualCommand, showCopiedToast: $showCopiedToast)
                    case 3:
                        OBDBluetoothScannerSection(obd: obd)
                    case 4:
                        OBDVAGGuideSection()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("OBD-II Diagnose & Labor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        obd.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    Text("✔ Log in Zwischenablage kopiert!")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.9), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Subviews for OBD Workbench
// ─────────────────────────────────────────────────────────────────────────────

struct OBDStatusBarHeader: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(obd.connectionState.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(obd.detailedStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let v = obd.batteryVoltage {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f V", v))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(voltageBgColor(v), in: Capsule())
                    .foregroundStyle(.white)
                }

                Toggle("", isOn: $obd.isEnabled)
                    .labelsHidden()
                    .tint(.green)
                    .onChange(of: obd.isEnabled) { _, enabled in
                        if enabled { obd.enableOBD() } else { obd.disableOBD() }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemBackground))
        }
    }

    private var statusColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected: return .green
        case .connecting, .initializing, .searchingECU: return .orange
        default: return .red
        }
    }

    private func voltageBgColor(_ v: Double) -> Color {
        if v >= 13.2 { return .blue.opacity(0.8) }
        if v >= 11.8 { return .green.opacity(0.8) }
        return .orange.opacity(0.8)
    }
}

struct OBDMethodProbeSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protokoll-Bruteforce & Schnelltest")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Testet nacheinander alle 7 VAG- und OBD-Protokolle mit Abfrage 0100.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if obd.isProbingProtocols {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.cyan)
                            Text(obd.detailedStatus)
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                            Spacer()
                            Button("Stoppen") {
                                obd.stopProtocolAutoProbe()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        }
                        .padding(.top, 4)
                    } else {
                        Button {
                            obd.runProtocolAutoProbe()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Protokoll-Schnelltest starten")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.black)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Manuelle Protokoll-Auswahl (Schnell-Erzwingen)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Protokoll manuell erzwingen:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(OBDProtocol.allCases) { proto in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proto.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(obd.selectedProtocol == proto ? .cyan : .white)
                                Text("Befehl: \(proto.elmCommand)\(proto.headerCommand != nil ? " + \(proto.headerCommand!)" : "")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if obd.selectedProtocol == proto {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cyan)
                            } else {
                                Button("Aktivieren") {
                                    obd.selectProtocol(proto)
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Testergebnisse-Liste
                if !obd.probeResults.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Testergebnisse (\(obd.probeResults.count) Methoden):")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ForEach(obd.probeResults) { res in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(statusColor(for: res.status))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(res.proto.rawValue)
                                            .font(.system(size: 13, weight: .bold))
                                        Spacer()
                                        if res.responseTimeMs > 0 {
                                            Text("\(res.responseTimeMs) ms")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(res.note.isEmpty ? res.rawResponse : res.note)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(statusColor(for: res.status))

                                    if !res.rawResponse.isEmpty && res.status == .success {
                                        Text("Antwort: \(res.rawResponse)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.green)
                                    }
                                }

                                if res.status == .success && obd.selectedProtocol != res.proto {
                                    Button("Nutzen") {
                                        obd.selectProtocol(res.proto)
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding(14)
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
    }

    private func statusColor(for status: ProtocolProbeResult.ProbeStatus) -> Color {
        switch status {
        case .success: return .green
        case .testing: return .yellow
        case .failed:  return .red
        case .noData:  return .orange
        case .timeout: return .secondary
        case .pending: return .gray.opacity(0.5)
        }
    }
}

struct OBDSensorMatrixSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Bordspannung & Zündungs-Zustand
                HStack {
                    Image(systemName: "car.side.fill")
                        .font(.title2)
                        .foregroundStyle(ignitionColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bordspannung / Zündungs-Status")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(obd.batteryVoltage != nil ? String(format: "%.1f V", obd.batteryVoltage!) : "Nicht ausgelesen")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(ignitionColor)
                        Text(ignitionDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                // Sensor Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SensorBox(title: "Kühlmittel (01 05)",
                              value: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!) °C" : "—",
                              status: obd.liveCoolantTemp != nil ? .green : .secondary)

                    SensorBox(title: "Öltemperatur (01 5C)",
                              value: obd.liveOilTemp != nil ? "\(obd.liveOilTemp!) °C" : "Modell",
                              status: obd.liveOilTemp != nil ? .green : .cyan,
                              badge: obd.liveOilTemp != nil ? "PID 015C" : "EA113 Sim")

                    SensorBox(title: "Ladedruck Relativ",
                              value: obd.liveBoostBar != nil ? String(format: "%.2f bar", obd.liveBoostBar!) : "—",
                              status: obd.liveBoostBar != nil ? .cyan : .secondary)

                    SensorBox(title: "Saugrohr MAP (01 0B)",
                              value: obd.liveMAP != nil ? "\(obd.liveMAP!) kPa" : "—",
                              status: obd.liveMAP != nil ? .white : .secondary)

                    SensorBox(title: "Drehzahl (01 0C)",
                              value: "\(obd.liveRPM) U/min",
                              status: obd.liveRPM > 0 ? .green : .secondary)

                    SensorBox(title: "Luftmasse MAF (01 10)",
                              value: obd.liveMAF != nil ? String(format: "%.1f g/s", obd.liveMAF!) : "—",
                              status: obd.liveMAF != nil ? .cyan : .secondary)

                    SensorBox(title: "Ansaugluft IAT (01 0F)",
                              value: obd.liveIAT != nil ? "\(obd.liveIAT!) °C" : "—",
                              status: obd.liveIAT != nil ? .cyan : .secondary)

                    SensorBox(title: "Motorlast (01 04)",
                              value: obd.liveEngineLoad != nil ? "\(obd.liveEngineLoad!) %" : "—",
                              status: obd.liveEngineLoad != nil ? .orange : .secondary)
                }

                // PID Bitmasken Auswertung
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unterstützte Steuergeräte-PIDs (Bosch MED9.1):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if obd.supportedPIDs.isEmpty {
                        Text("Noch keine PID-Quittung empfangen (Befehl 0100 senden).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 6) {
                            ForEach(Array(obd.supportedPIDs).sorted(), id: \.self) { pid in
                                Text(pidName(for: pid))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.cyan.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }

                    Text("ℹ Hinweis: PID 01 5C (Öltemperatur) wird von Bosch MED9.1 im Standard-OBD nicht geliefert. Die App nutzt dafür das präzise EA113 Modell.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
    }

    private var ignitionColor: Color {
        guard let v = obd.batteryVoltage else { return .secondary }
        if v >= 13.2 { return .blue }
        if v >= 11.8 { return .green }
        return .orange
    }

    private var ignitionDescription: String {
        guard let v = obd.batteryVoltage else { return "Zündung wird geprüft…" }
        if v >= 13.2 { return "Motor läuft & Lichtmaschine lädt" }
        if v >= 11.8 { return "Zündung Stufe 2 aktiv (Steuergerät ansprechbar)" }
        return "⚠️ Zündung evtl. AUS (Stufe 2 einschalten!)"
    }

    private func pidName(for pid: String) -> String {
        switch pid {
        case "0104": return "0104 (Last)"
        case "0105": return "0105 (Kühlmittel)"
        case "010B": return "010B (MAP)"
        case "010C": return "010C (Drehzahl)"
        case "010D": return "010D (Speed)"
        case "010F": return "010F (Ansaugluft)"
        case "0110": return "0110 (Luftmasse)"
        case "0111": return "0111 (Drosselkl.)"
        case "0133": return "0133 (Baro)"
        default:     return pid
        }
    }
}

struct SensorBox: View {
    let title: String
    let value: String
    let status: Color
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(status)
                }
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(status)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OBDTerminalSection: View {
    @ObservedObject var obd: OBDManager
    @Binding var manualCommand: String
    @Binding var showCopiedToast: Bool

    private let quickCommands = [
        "ATZ", "ATI", "ATRV", "ATDP",
        "ATSP6", "ATSP5", "ATSP0", "ATSH7E0",
        "0100", "0105", "010C", "010B", "0110", "015C",
        "2104", "2186"
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Action Bar
            HStack {
                Toggle("Manueller Modus", isOn: $obd.isManualTerminalMode)
                    .font(.caption.bold())
                    .labelsHidden()
                Text(obd.isManualTerminalMode ? "Manueller Modus (Polling AUS)" : "Auto-Polling AKTIV")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(obd.isManualTerminalMode ? .orange : .secondary)

                Spacer()

                Button {
                    obd.copyTerminalLogToClipboard()
                    withAnimation { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopiedToast = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Log kopieren")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.12), in: Capsule())
                }

                Button {
                    obd.clearTerminalLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)

            // Quick Command Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickCommands, id: \.self) { cmd in
                        Button {
                            obd.sendManualCommand(cmd)
                        } label: {
                            Text(cmd)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(chipColor(for: cmd), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Command Input Field
            HStack(spacing: 8) {
                TextField("Befehl senden (z.B. ATRV, 0100, ATSP6)…", text: $manualCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    obd.sendManualCommand(manualCommand)
                    manualCommand = ""
                } label: {
                    Text("Senden")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .disabled(manualCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            // Terminal Console Screen
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if obd.terminalEntries.isEmpty {
                        Text("// Terminal bereit. Sende einen Befehl oder starte den Schnelltest.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(obd.terminalEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(entry.timestamp)]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Text(entry.direction == .tx ? "TX >" : (entry.direction == .rx ? "RX <" : "SYS:"))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(entry.direction == .tx ? .cyan : (entry.direction == .rx ? .green : .white))

                                Text(entry.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(textColor(for: entry))
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    private func chipColor(for cmd: String) -> Color {
        if cmd.hasPrefix("ATSP") { return .indigo.opacity(0.6) }
        if cmd.hasPrefix("AT") { return .blue.opacity(0.5) }
        if cmd.hasPrefix("21") || cmd.hasPrefix("22") { return .purple.opacity(0.6) }
        return .cyan.opacity(0.5)
    }

    private func textColor(for entry: OBDTerminalEntry) -> Color {
        switch entry.style {
        case .success: return .green
        case .error:   return .red
        case .warning: return .orange
        case .normal:  return entry.direction == .tx ? .cyan : .white
        }
    }
}

struct OBDBluetoothScannerSection: View {
    @ObservedObject var obd: OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bluetooth LE Scanner")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Alle erkannten Bluetooth-Geräte in Reichweite.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        obd.startScan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Scan")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                if obd.discoveredDevices.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.cyan)
                        Text("Scanne nach Bluetooth-Geräten…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(30)
                } else {
                    ForEach(obd.discoveredDevices) { dev in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dev.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("UUID: \(dev.id.prefix(18))…  RSSI: \(dev.rssi) dBm")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Verbinden") {
                                obd.connectToDevice(id: dev.id)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.15), in: Capsule())
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
    }
}

struct OBDVAGGuideSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GuideCard(title: "1. Warum stand vorher 'obd bereit' aber keine Werte?",
                          content: "Der blaue ELM327 Mini verbindet sich sofort über Bluetooth mit deinem iPhone. Die Meldung 'obd bereit' hieß bisher nur, dass der Funk-Chip antwortete.\n\nDas Steuergerät im Auto antwortete jedoch nicht, weil billige Adapter beim automatischen Protokollsuchlauf (AT SP 0) oft hängen bleiben oder ein Timeout erzeugen.")

                GuideCard(title: "2. Zündschlüssel auf Stufe 2 drehen!",
                          content: "Die OBD-Dose hat Dauerplus (+12V von der Batterie), weshalb der Adapter immer leuchtet. Das Motorsteuergerät (Bosch MED9.1) schaltet sich jedoch erst ein, wenn der Zündschlüssel auf Stufe 2 gedreht wird (alle Kontrollleuchten im Tacho leuchten)!\n\nPrüfe im Reiter 'Sensoren' die Bordspannung: Bei Zündung Stufe 2 liegt sie typischerweise bei 12.0V – 12.6V.")

                GuideCard(title: "3. Empfohlenes Protokoll: CAN 11-Bit 500k",
                          content: "Der VW Golf 5 GTI EA113 (Motorcode AXX, BWA, BYD) nutzt für das Bosch MED9.1 Steuergerät standardmäßig:\n• Protokoll: ISO 15765-4 CAN 11-Bit 500k (Befehl: ATSP6)\n• Falls es nicht klappt: Wähle 'CAN 11-Bit 500k + 7E0 Header'\n• Falls dein Fahrzeug ein frühes Gateway hat: Wähle 'KWP2000 Fast (ATSP5)'.")

                GuideCard(title: "4. Besonderheit bei der Öltemperatur",
                          content: "Standard OBD-II PID 01 5C wird von der Bosch MED9.1 Software nicht standardmäßig geliefert (meldet 'NO DATA').\n\nDas ist normal bei VW EA113! CarLyrics nutzt dafür das integrierte, hochpräzise thermische Trägheitsmodell oder VAG Messwertblock 134.")
            }
            .padding()
        }
    }
}

struct GuideCard: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.cyan)
            Text(content)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SpotifySetupSheet: View {
    @ObservedObject var spotify: SpotifyManager
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var refreshToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Verbindungsstatus") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(spotify.isAuthenticated ? "Verbunden" : "Nicht verbunden")
                            .foregroundStyle(spotify.isAuthenticated ? .green : .red)
                    }
                    if let err = spotify.lastSyncError {
                        Text("Status: \(err)").font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("1-Klick Login (Dauerhaft)") {
                    Text("Um Spotify direkt abzufragen, erstelle eine kostenlose App im Spotify Developer Dashboard:")
                        .font(.caption).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. developer.spotify.com/dashboard öffnen").font(.caption2)
                        Text("2. 'Create App' anklicken").font(.caption2)
                        Text("3. Redirect URI eintragen:").font(.caption2)
                        Text("carlyrics://spotify-callback")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("4. Client ID kopieren und unten einfügen:").font(.caption2)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        TextField("Spotify Client ID", text: $clientId)
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !clientId.isEmpty {
                            Button {
                                clientId = ""
                                spotify.clientId = ""
                                UserDefaults.standard.removeObject(forKey: "spotify_client_id")
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !clientId.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WICHTIG bei 'redirect uri not matching config':")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                            Text("Falls du eine bestehende Client ID nutzt, öffne developer.spotify.com/dashboard -> deine App -> Settings -> trage unter 'Redirect URIs' exakt ein:")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("carlyrics://spotify-callback")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("und klicke ganz unten auf 'Save'!")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        spotify.clientId = clientId.trimmingCharacters(in: .whitespaces)
                        spotify.startWebAuthSession { success in
                            if success { dismiss() }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title3)
                            Text("Mit Spotify einloggen")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(CockpitButtonStyle(color: .green))
                    .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty)

                    if clientId.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("⚠ Trage zuerst deine Client ID ein, um 'client id invalid' zu verhindern.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Alternativ: Manueller Access Token") {
                    Text("Einmaliger 1-Stunden Token von developer.spotify.com:")
                        .font(.caption).foregroundStyle(.secondary)

                    TextField("Bearer Token", text: $token)
                        .font(.system(.caption, design: .monospaced))

                    Button("Speichern & Starten") {
                        spotify.accessToken = token
                        spotify.startPolling()
                        dismiss()
                    }
                    .disabled(token.isEmpty)
                }

                Section("Dauerbetrieb (Auto-Refresh)") {
                    Text("Optional: Mit Client ID und Refresh Token erneuert die App den Token während der Fahrt vollautomatisch:")
                        .font(.caption).foregroundStyle(.secondary)

                    TextField("Client ID", text: $clientId)
                        .font(.caption)
                    SecureField("Client Secret", text: $clientSecret)
                        .font(.caption)
                    TextField("Refresh Token", text: $refreshToken)
                        .font(.caption)

                    Button("Dauerhafte Verbindung speichern") {
                        if !clientId.isEmpty { spotify.clientId = clientId }
                        if !clientSecret.isEmpty { spotify.clientSecret = clientSecret }
                        if !refreshToken.isEmpty {
                            spotify.refreshToken = refreshToken
                            Task {
                                await spotify.refreshAccessToken()
                                spotify.startPolling()
                                dismiss()
                            }
                        }
                    }
                    .disabled(clientId.isEmpty || refreshToken.isEmpty)
                }
            }
            .navigationTitle("Spotify Connect")
            .onAppear {
                token = spotify.accessToken
                clientId = spotify.clientId
                clientSecret = spotify.clientSecret
                refreshToken = spotify.refreshToken
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Components & Helpers
// ─────────────────────────────────────────────────────────────────────────────

struct CockpitBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.06), Color.clear],
                center: .top, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct CockpitButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.3 : 0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

@MainActor
private func gColor(_ g: Double, maxG: Double? = nil) -> Color {
    let limit = max(0.3, maxG ?? MotionManager.shared.maxG)
    let ratio = g / limit
    if ratio < 0.35 {
        return .white
    } else if ratio < 0.65 {
        return .yellow
    } else if ratio < 0.88 {
        return .orange
    } else {
        return .red
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Test / Mock Injector View
// ─────────────────────────────────────────────────────────────────────────────

struct MockInjectorView: View {
    @ObservedObject var observer: MusicObserver
    @Environment(\.dismiss) private var dismiss
    @State private var title  = "Bohemian Rhapsody"
    @State private var artist = "Queen"
    @State private var album  = "A Night at the Opera"

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Song") {
                    TextField("Titel", text: $title)
                    TextField("Künstler", text: $artist)
                    TextField("Album", text: $album)

                    Button("Test-Track einspeisen") {
                        Task {
                            await observer.injectTrack(
                                title: title, artist: artist, album: album, duration: 354,
                                lrc: """
                                [00:00.00] Is this the real life?
                                [00:04.00] Is this just fantasy?
                                [00:08.00] Caught in a landslide
                                [00:12.00] No escape from reality
                                [00:16.00] Open your eyes
                                [00:20.00] Look up to the skies and see
                                """
                            )
                            dismiss()
                        }
                    }
                    .buttonStyle(CockpitButtonStyle(color: .cyan))
                }
            }
            .navigationTitle("Test Injektor")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}
