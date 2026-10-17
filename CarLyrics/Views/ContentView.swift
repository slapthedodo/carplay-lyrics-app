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
                NowPlayingTab(observer: observer, warmup: warmup, motion: motion, obd: obd)
                    .tabItem { Label("Lyrics", systemImage: "music.note") }
                    .tag(0)

                TelemetryTab(warmup: warmup, motion: motion, obd: obd)
                    .tabItem { Label("Telemetrie", systemImage: "gauge.with.needle") }
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
            OBDDebugSheet(obd: obd)
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
                HStack(spacing: 12) {
                    // Spotify Button
                    Button { showSpotifySheet = true } label: {
                        Image(systemName: spotify.isAuthenticated ? "waveform.circle.fill" : "waveform.circle")
                            .foregroundStyle(spotify.isAuthenticated ? .green : .secondary)
                    }

                    // Test-Injektor
                    Button { showMockSheet = true } label: {
                        Image(systemName: "testtube.2").foregroundStyle(.cyan)
                    }
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
// MARK: Now Playing Tab
// ─────────────────────────────────────────────────────────────────────────────

struct NowPlayingTab: View {
    @ObservedObject var observer : MusicObserver
    @ObservedObject var warmup   : WarmupManager
    @ObservedObject var motion   : MotionManager
    @ObservedObject var obd      : OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                NowPlayingCard(observer: observer)
                LyricsCard(observer: observer)
                MiniTelemetryCard(warmup: warmup, motion: motion, obd: obd)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Tab
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Tab
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryTab: View {
    @ObservedObject var warmup : WarmupManager
    @ObservedObject var motion : MotionManager
    @ObservedObject var obd    : OBDManager

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // OBD Toggle Card
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Datenquelle für Öltemperatur")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(obd.isEnabled ? "ELM327 Bluetooth Adapter (Live)" : "TFSI 2.0L Simulation")
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
                        Label("G-Kraft Sensor & Maximalwert", systemImage: "gyroscope")
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

                // 4. CarPlay & Widgets Erklärung
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Widgets in CarPlay & Sperrbildschirm", systemImage: "car.circle.fill")
                            .font(.headline).foregroundStyle(.yellow)
                        Text("• CarPlay: Apple erlaubt auf dem CarPlay-Display nur autorisierte Navigations-/Audio-Apps. Das Now Playing Widget auf dem CarPlay Dashboard wird automatisch von Spotify/CarPlay versorgt.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("• Dynamic Island im Auto: Die CarLyrics Dynamic Island und der Live-Banner bleiben oben auf deinem iPhone oder im Sperrbildschirm in der Halterung immer sichtbar.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("• iOS Widgets: Du kannst jetzt die neuen 'CarLyrics Cockpit' Widgets (Öl, Boost, G-Ball) direkt auf deinem iPhone Home- & Sperrbildschirm hinzufügen!")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
                }

                // 5. Hinweis zu VW & OBD-II
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Hinweis zu VW & OBD-II", systemImage: "info.circle")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Bei vielen VW / VAG Modellen mit 2.0 TFSI wird PID 01 5C (Öltemperatur) über Standard-OBD2 als 'NO DATA' beantwortet. CarLyrics nutzt in diesem Fall automatisch die Kühlmitteltemperatur (PID 01 05) mit TFSI-Offset oder fällt auf das thermische Simulationsmodell zurück.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 6. FaceTime beim Fahren (Kamera-Fix)
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("FaceTime mit Kamera beim Fahren", systemImage: "video.fill")
                            .font(.headline).foregroundStyle(.cyan)
                        Text("iOS schaltet beim Verbinden mit dem Auto automatisch den Fokus 'Fahren' ein, der die Kamera sperrt.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Lösung: Gehe in Einstellungen > Fokus > Fahren und deaktiviere die automatische Aktivierung mit CarPlay/Bluetooth. In der Handyhalterung bleibt die Kamera dann während der Fahrt aktiv!")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
                }

                // 7. Blitzer.de während Anrufen (Audio-Fix)
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Blitzer-App Ton während Telefonaten", systemImage: "speaker.wave.3.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text("Bei Telefonaten schaltet das Auto auf Mono-Telefonie um und dämpft andere Apps.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Lösung: Stelle in Blitzer.de unter Einstellungen > Audio > Audioausgang auf 'Gerätelautsprecher'. Die Warnungen kommen dann glasklar aus deinem iPhone-Lautsprecher, selbst wenn du telefonierst!")
                            .font(.caption.bold()).foregroundStyle(.white)
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
                        .padding(.vertical, 12)
                } else {
                    // Aktive Zeile mit Leuchteffekt (Hoher Kontrast fürs Auto)
                    Text(observer.currentLine)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .cyan.opacity(0.35), radius: 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.25), value: observer.currentLine)

                    if !observer.nextLine.isEmpty {
                        Text(observer.nextLine)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: observer.nextLine)
                    }
                }
            }
        }
    }
}

struct MiniTelemetryCard: View {
    @ObservedObject var warmup : WarmupManager
    @ObservedObject var motion : MotionManager
    @ObservedObject var obd    : OBDManager

    var currentTemp: Int? {
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
            HStack {
                // Öltemperatur Ring
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: currentTemp != nil ? warmup.warmupProgress : 0)
                            .stroke(currentTemp != nil ? tempColor(currentTemp!) : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(currentTemp != nil ? "\(currentTemp!)°" : "--")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(currentTemp != nil ? tempColor(currentTemp!) : .secondary)
                    }
                    .frame(width: 52, height: 52)
                    Text(obd.isEnabled ? (obd.connectionState == .connected ? "OBD LIVE" : "OBD...") : "SIM ÖL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(obd.isEnabled ? (obd.connectionState == .connected ? .green : .orange) : .secondary)
                }

                Spacer()

                // G-Force Live
                VStack(spacing: 3) {
                    Text(motion.currentGFormatted)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(gColor(motion.currentG))
                        .contentTransition(.numericText())
                    Text("PEAK \(motion.peakGFormatted)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status & Ladedruck
                VStack(spacing: 4) {
                    if let t = currentTemp {
                        let phase = t < 60 ? "KALT" : (t < 80 ? "AUFWÄRMEN" : "BEREIT")
                        Text(phase)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(tempColor(t))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tempColor(t).opacity(0.15), in: Capsule())
                    } else {
                        Text(obd.connectionState == .connected ? "LESE DATEN…" : "OBD WARTET")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }

                    if obd.isEnabled && obd.connectionState == .connected, let boost = obd.liveBoostBar {
                        Text(String(format: "%.2f b", boost))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    } else if obd.isEnabled && obd.liveRPM > 0 {
                        Text("\(obd.liveRPM) U/min")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func tempColor(_ t: Int) -> Color {
        if t < 60 { return .blue }
        if t < 80 { return .orange }
        return .green
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

                // Gauge
                Gauge(value: Double(displayTemp ?? 20), in: 20...110) {
                    Text("Temperatur")
                } currentValueLabel: {
                    Text(displayTemp != nil ? "\(displayTemp!)°C" : "-- °C")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)
                } minimumValueLabel: {
                    Text("20°").font(.caption2)
                } maximumValueLabel: {
                    Text("110°").font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(displayTemp != nil ? Gradient(colors: [.blue, .orange, .green]) : Gradient(colors: [.secondary.opacity(0.3)]))
                .frame(width: 120, height: 120)

                // Phasenhinweis
                Text(phaseText(displayTemp))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(displayTemp != nil ? tempColor(displayTemp!) : .secondary)
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
                            Text("LIVE OBD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        } else if obd.connectionState == .connected {
                            Text("KEIN SENSOR (VW)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
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
                        Text("BAR RELATIV (MAP - BARO)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        if let map = obd.liveMAP {
                            Text("MAP: \(map) kPa").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                        }
                        if let iat = obd.liveIAT {
                            Text("IAT: \(iat) °C").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.cyan)
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

struct GForceCard: View {
    @ObservedObject var motion: MotionManager

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Label("G-Kräfte Telemetrie", systemImage: "gyroscope")
                    .font(.headline).foregroundStyle(.cyan)

                GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG, maxG: motion.maxG)
                    .frame(width: 200, height: 200)

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

struct OBDDebugSheet: View {
    @ObservedObject var obd: OBDManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    HStack {
                        Text("Verbindung")
                        Spacer()
                        Text(obd.connectionState.rawValue)
                            .foregroundStyle(obd.connectionState == .connected ? .green : .orange)
                    }
                    Toggle("OBD-Adapter aktiv", isOn: $obd.isEnabled)
                        .onChange(of: obd.isEnabled) { _, val in
                            if val { obd.enableOBD() } else { obd.disableOBD() }
                        }
                }

                Section("Ausgelesene Live-Werte") {
                    HStack {
                        Text("Öltemperatur (PID 01 5C)")
                        Spacer()
                        Text(obd.liveOilTemp != nil ? "\(obd.liveOilTemp!) °C" : "Nicht unterstützt (VW)")
                            .foregroundStyle(obd.liveOilTemp != nil ? .green : .secondary)
                    }
                    HStack {
                        Text("Kühlmitteltemp (PID 01 05)")
                        Spacer()
                        Text(obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!) °C" : "—")
                            .foregroundStyle(.cyan)
                    }
                    HStack {
                        Text("Ladedruck (Relativ)")
                        Spacer()
                        Text(obd.liveBoostBar != nil ? String(format: "%.2f bar", obd.liveBoostBar!) : "—")
                            .foregroundStyle(.cyan)
                    }
                    HStack {
                        Text("Saugrohrdruck (PID 01 0B MAP)")
                        Spacer()
                        Text(obd.liveMAP != nil ? "\(obd.liveMAP!) kPa" : "—")
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Text("Ansauglufttemp (PID 01 0F IAT)")
                        Spacer()
                        Text(obd.liveIAT != nil ? "\(obd.liveIAT!) °C" : "—")
                            .foregroundStyle(.cyan)
                    }
                    HStack {
                        Text("Motorlast (PID 01 04)")
                        Spacer()
                        Text(obd.liveEngineLoad != nil ? "\(obd.liveEngineLoad!) %" : "—")
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Text("Motordrehzahl (RPM)")
                        Spacer()
                        Text("\(obd.liveRPM) U/min")
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Geschwindigkeit")
                        Spacer()
                        Text("\(obd.liveSpeed) km/h")
                    }
                }

                Section("Adapter Kommunikations-Log (Hex/ASCII)") {
                    ForEach(obd.debugLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
            .navigationTitle("OBD-II Diagnose")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
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
