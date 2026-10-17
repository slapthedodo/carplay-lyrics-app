// MARK: - ContentView.swift  (v3 — Spotify + OBD-II Cockpit Edition)
// CarLyrics – Dark Cockpit UI mit Spotify-Verbindung, CarPlay-Audioverzögerung,
// OBD-II Live-Daten vs. TFSI-Simulation und G-Ball.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import MediaPlayer

public struct ContentView: View {

    @StateObject private var observer = MusicObserver()
    @StateObject private var warmup   = WarmupManager()
    @StateObject private var motion   = MotionManager()
    @ObservedObject private var spotify = SpotifyManager.shared
    @ObservedObject private var obd     = OBDManager.shared

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

                SettingsTab(spotify: spotify, obd: obd)
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

            if spotify.isAuthenticated {
                spotify.startPolling()
            }
        }
        .onDisappear {
            motion.stop()
            BackgroundKeepAliveManager.shared.stop()
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
    @State private var tokenInput: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. CarPlay Audio-Verzögerung
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

                // 2. Spotify Verbindung
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

                // 3. Info & Hinweise
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Hinweis zu VW & OBD-II", systemImage: "info.circle")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Bei vielen VW / VAG Modellen mit 2.0 TFSI wird PID 01 5C (Öltemperatur) über Standard-OBD2 als 'NO DATA' beantwortet. CarLyrics nutzt in diesem Fall automatisch die Kühlmitteltemperatur (PID 01 05) mit TFSI-Offset oder fällt auf das thermische Simulationsmodell zurück.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    var currentTemp: Int {
        if obd.isEnabled && obd.connectionState == .connected {
            return obd.liveOilTemp ?? (obd.liveCoolantTemp.map { max(20, $0 - 8) } ?? warmup.oilTempInt)
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
                            .trim(from: 0, to: warmup.warmupProgress)
                            .stroke(tempColor(currentTemp), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(currentTemp)°")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(tempColor(currentTemp))
                    }
                    .frame(width: 52, height: 52)
                    Text(obd.isEnabled ? "OBD ÖL" : "SIM ÖL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
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

                // Status
                VStack(spacing: 4) {
                    let phase = currentTemp < 60 ? "KALT" : (currentTemp < 80 ? "AUFWÄRMEN" : "BEREIT")
                    Text(phase)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tempColor(currentTemp))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tempColor(currentTemp).opacity(0.15), in: Capsule())

                    if obd.isEnabled && obd.liveRPM > 0 {
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

    var displayTemp: Int {
        if obd.isEnabled && obd.connectionState == .connected {
            return obd.liveOilTemp ?? (obd.liveCoolantTemp.map { max(20, $0 - 8) } ?? warmup.oilTempInt)
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
                        Text("LIVE OBD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }

                // Gauge
                Gauge(value: Double(displayTemp), in: 20...110) {
                    Text("Temperatur")
                } currentValueLabel: {
                    Text("\(displayTemp)°C")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(tempColor(displayTemp))
                } minimumValueLabel: {
                    Text("20°").font(.caption2)
                } maximumValueLabel: {
                    Text("110°").font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.blue, .orange, .green]))
                .frame(width: 120, height: 120)

                // Phasenhinweis
                Text(phaseText(displayTemp))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(tempColor(displayTemp))
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

    private func phaseText(_ t: Int) -> String {
        if t < 60 { return "Kaltstart – Max. 2.500 U/min, kein Ladedruck!" }
        if t < 80 { return "Öl wärmt auf – Gemäßigt fahren" }
        return "90°C erreicht – Voller Ladedruck frei! 🏁"
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
                Label("G-Kräfte (Auto-Kalibrierend)", systemImage: "gyroscope")
                    .font(.headline).foregroundStyle(.cyan)

                GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG)
                    .frame(width: 200, height: 200)

                HStack(spacing: 24) {
                    VStack {
                        Text("AKTUELL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.currentGFormatted)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(motion.currentG))
                    }
                    VStack {
                        Text("PEAK").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(motion.peakGFormatted)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
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

                Text("ACC").font(.system(size: 8)).foregroundStyle(.secondary).offset(y: -(r - 6))
                Text("BRK").font(.system(size: 8)).foregroundStyle(.secondary).offset(y: r - 6)

                Circle()
                    .fill(gColor(currentG))
                    .frame(width: 18, height: 18)
                    .shadow(color: gColor(currentG).opacity(0.8), radius: 8)
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

                Section("1-Klick Login") {
                    Text("Melde dich direkt über Safari mit deinem Spotify-Konto an:")
                        .font(.caption).foregroundStyle(.secondary)

                    Button {
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

private func gColor(_ g: Double) -> Color {
    switch g {
    case ..<0.3:  return .white
    case ..<0.6:  return .yellow
    case ..<0.9:  return .orange
    default:      return .red
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
