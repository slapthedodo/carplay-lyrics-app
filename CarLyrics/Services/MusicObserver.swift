// MARK: - MusicObserver.swift  (v3 — Modular Player & Telemetry Observer)
// CarLyrics – verbindet Spotify, System-Player, OBD-II und Warmup mit ActivityKit.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import MediaPlayer
import ActivityKit
import Combine
import CoreMotion
import WidgetKit
import AVFoundation
import UIKit

@MainActor
public final class MusicObserver: ObservableObject {

    public static let shared = MusicObserver()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published State
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var currentTrackTitle : String       = ""
    @Published public var currentArtist     : String       = ""
    @Published public var currentAlbum      : String       = ""
    @Published public var isPlaying         : Bool         = false
    @Published public var previousLine3     : String       = ""  // 3 Zeilen davor
    @Published public var previousLine2     : String       = ""  // 2 Zeilen davor
    @Published public var previousLine      : String       = ""  // 1 Zeile davor
    @Published public var currentLine       : String       = ""
    @Published public var nextLine          : String       = ""  // 1 Zeile danach
    @Published public var nextLine2         : String       = ""  // 2 Zeilen danach
    @Published public var nextLine3         : String       = ""  // 3 Zeilen danach
    @Published public var lyricsStatus      : LyricsStatus = .idle
    @Published public var progress          : Double       = 0
    @Published public var isCarOrActiveConnected : Bool   = true
    @Published public var disconnectedSeconds     : Int    = 0
    public var autoDismissEnabled                : Bool   = true

    /// Zeitstempel der letzten Vordergrund-Aktivität (verhindert vorzeitiges Beenden beim Sperren/Testen)
    public var lastForegroundTime : Date = Date()

    /// Prüft ob ein echtes CarPlay-Display oder CarPlay- / Auto-Audioausgang aktiv ist
    public var isCarPlayConnected: Bool {
        let hasCarPlayScreen = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }
        let hasCarAudio = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == .carAudio || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }
        return hasCarPlayScreen || hasCarAudio
    }

    /// Aktiv wenn:
    /// - App im Vordergrund aktiv ist
    /// - ODER CarPlay verbunden ist
    /// - ODER Musik läuft (Spotify oder Apple Music)
    /// - ODER OBD verbunden ist
    /// - ODER die App vor weniger als 600s im Vordergrund war (z.B. Sperrbildschirm-Test auf der Couch / im Stand)
    public var isCarOrActive: Bool {
        if UIApplication.shared.applicationState == .active {
            lastForegroundTime = Date()
            return true
        }
        if isCarPlayConnected { return true }
        if obd.connectionState == .connected { return true }
        if isPlaying { return true }
        if Date().timeIntervalSince(lastForegroundTime) < 600.0 { return true }
        return false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Subsystem References
    // ─────────────────────────────────────────────────────────────────────────

    public var warmupManager : WarmupManager? = WarmupManager.shared
    public var motionManager : MotionManager? = MotionManager.shared
    public let spotify       = SpotifyManager.shared
    public let obd           = OBDManager.shared

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Internal & Private State
    // ─────────────────────────────────────────────────────────────────────────

    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    private var lyrics       : ParsedLyrics?
    var duration             : TimeInterval = 0
    public private(set) var currentPlaybackTime: TimeInterval = 0

    public static func formatTime(_ t: TimeInterval) -> String {
        guard t > 0, !t.isNaN, !t.isInfinite else { return "0:00" }
        let s = Int(t)
        let m = s / 60
        let remS = s % 60
        return String(format: "%d:%02d", m, remS)
    }

    private var lineTimer      : DispatchSourceTimer?
    private var telemetryTimer : DispatchSourceTimer?
    private let timerQueue     = DispatchQueue(label: "com.carlyrics.musicobserver.timer", qos: .userInteractive)
    private var cancellables   : Set<AnyCancellable> = []

    // ActivityKit State (genutzt von MusicObserverLiveActivity.swift)
    var liveActivity           : Activity<LyricsAttributes>?
    var lastActivityUpdate     : Date   = .distantPast
    var lastSentG              : Double = 0
    var lastSentOilTemp        : Int?   = nil
    var lastSentCoolant        : Int?   = nil
    var lastSentPhase          : WarmupPhase? = nil
    var isUpdatingActivity     : Bool   = false
    var pendingActivityUpdate  : Bool   = false
    var lastWidgetReloadTime   : Date   = .distantPast
    var lastTelemetryPush      : Date   = .distantPast

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        setupNotifications()
        systemPlayer.beginGeneratingPlaybackNotifications()

        // Spotify Polling starten falls authentifiziert
        if spotify.isAuthenticated {
            spotify.startPolling()
        }

        // Spotify Observer einhängen
        spotify.$trackTitle.combineLatest(spotify.$artistName, spotify.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] title, artist, isPlaying in
                guard let self, self.spotify.isAuthenticated else { return }
                self.handleSpotifyTrack(title: title, artist: artist, isPlaying: isPlaying)
            }
            .store(in: &cancellables)

        // CoreMotion starten & ultraschnelle G-Kraft-Benachrichtigung einhängen
        MotionManager.shared.start()
        MotionManager.shared.onGChange = { [weak self] currentG, peakG in
            Task { @MainActor [weak self] in
                self?.handleFastGForceChange(currentG: currentG, peakG: peakG)
            }
        }

        // Initialer Check
        if !spotify.isAuthenticated {
            syncSystemItem()
        }

        // Live Activity & Telemetrie-Heartbeat sofort starten (immer sichtbar)
        startTelemetryHeartbeat()
    }

    deinit {
        systemPlayer.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
        lineTimer?.cancel()
        lineTimer = nil
        telemetryTimer?.cancel()
        telemetryTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Track Handling (Spotify & System)
    // ─────────────────────────────────────────────────────────────────────────

    private func handleSpotifyTrack(title: String, artist: String, isPlaying: Bool) {
        guard !title.isEmpty, !artist.isEmpty else {
            if !isPlaying { self.isPlaying = false }
            return
        }

        self.isPlaying = isPlaying

        // Neuer Track?
        if title != currentTrackTitle || artist != currentArtist {
            currentTrackTitle = title
            currentArtist     = artist
            currentAlbum      = spotify.albumName
            duration          = spotify.durationSeconds
            lyrics            = nil
            currentLine       = ""
            nextLine          = ""

            // Dynamic Island & Kacheln sofort mit neuem Track aktualisieren
            pushActivityUpdate(force: true)
            scheduleWidgetReload(force: true)

            Task {
                await loadLyrics(title: title, artist: artist, album: spotify.albumName, duration: spotify.durationSeconds)
            }
        } else {
            pushActivityUpdate(force: false)
        }

        if isPlaying && lineTimer == nil {
            startLineTimer()
        }
    }

    private func syncSystemItem() {
        guard !spotify.isAuthenticated else { return }
        guard let item = systemPlayer.nowPlayingItem else { handleNoTrack(); return }
        let title  = item.title  ?? ""
        let artist = item.artist ?? ""
        let album  = item.albumTitle ?? ""
        let dur    = item.playbackDuration
        guard title != currentTrackTitle || artist != currentArtist else { return }

        currentTrackTitle = title
        currentArtist     = artist
        currentAlbum      = album
        duration          = dur
        isPlaying         = systemPlayer.playbackState == .playing
        lyrics            = nil
        previousLine      = ""
        currentLine       = ""
        nextLine          = ""

        pushActivityUpdate(force: true)
        scheduleWidgetReload(force: true)
        Task { await loadLyrics(title: title, artist: artist, album: album, duration: dur) }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: systemPlayer)
        NotificationCenter.default.addObserver(
            self, selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange, object: systemPlayer)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(carPlayRouteChanged),
            name: UIScreen.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(carPlayRouteChanged),
            name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(carPlayRouteChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func carPlayRouteChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isCarOrActive && self.activeActivity == nil {
                await self.reattachOrCreateLiveActivity()
            }
        }
    }

    @objc private func appWillTerminate() {
        let all = Activity<LyricsAttributes>.activities
        for activity in all {
            Task.detached {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    @objc private func nowPlayingItemChanged() {
        if !spotify.isAuthenticated { syncSystemItem() }
    }

    @objc private func playbackStateChanged() {
        if !spotify.isAuthenticated {
            isPlaying = systemPlayer.playbackState == .playing
            isPlaying ? startLineTimer() : stopLineTimer()
            pushActivityUpdate(force: false)
            scheduleWidgetReload(force: true)
        }
    }

    private func handleNoTrack() {
        stopLineTimer()
        currentTrackTitle   = ""
        currentArtist       = ""
        previousLine3       = ""
        previousLine2       = ""
        previousLine        = ""
        currentLine         = ""
        nextLine            = ""
        nextLine2           = ""
        nextLine3           = ""
        currentPlaybackTime = 0
        isPlaying           = false
        pushActivityUpdate(force: false)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lyrics Fetch
    // ─────────────────────────────────────────────────────────────────────────

    private func loadLyrics(title: String, artist: String,
                            album: String, duration: TimeInterval) async {
        lyricsStatus = .loading
        do {
            let parsed = try await LyricsService.shared.fetchLyrics(
                title: title, artist: artist, album: album, duration: duration)
            lyrics       = parsed
            lyricsStatus = .loaded
            startLineTimer()
            pushActivityUpdate(force: true)
        } catch {
            lyricsStatus = .error(error.localizedDescription)
            // Trotz Lyrics-Fehler die Live Activity für Motortelemetrie aktiv halten
            pushActivityUpdate(force: true)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 100 ms Line Timer mit Audio-Delay & Rate-Limit
    // ─────────────────────────────────────────────────────────────────────────

    private func startLineTimer() {
        stopLineTimer()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.resume()
        lineTimer = timer
    }

    private func stopLineTimer() {
        lineTimer?.cancel()
        lineTimer = nil
    }

    public func startTelemetryHeartbeat() {
        telemetryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let connected = self.isCarOrActive
                self.isCarOrActiveConnected = connected

                if connected {
                    self.disconnectedSeconds = 0
                    // Falls Keep-Alive pausiert war, wieder aktivieren
                    BackgroundKeepAliveManager.shared.start()

                    // IMMER Telemetrie-Speicher für Widgets schreiben
                    _ = self.makeState()

                    if self.activeActivity == nil {
                        await self.reattachOrCreateLiveActivity()
                    } else {
                        // Dynamic Island Öltemperatur-Update:
                        // Nur pushen wenn mindestens 3 Sekunden seit dem letzten
                        // Telemetrie-Push vergangen sind, um ActivityKit nicht zu
                        // überlasten. Lyric-Updates in tick() nutzen force:true und
                        // behalten so immer Vorrang.
                        let now = Date()
                        if now.timeIntervalSince(self.lastTelemetryPush) >= 3.0 {
                            let currentOil = self.obd.effectiveOilTemp ?? self.warmupManager?.oilTempInt
                            let currentCoolant = self.obd.liveCoolantTemp
                            let currentPhase = self.warmupManager?.phase

                            if currentOil != self.lastSentOilTemp || currentCoolant != self.lastSentCoolant || currentPhase != self.lastSentPhase {
                                self.lastSentOilTemp = currentOil
                                self.lastSentCoolant = currentCoolant
                                self.lastSentPhase = currentPhase
                            }
                            // Telemetrie nutzt NIE force:true — Lyric-Updates sollen
                            // stets höhere Priorität in der ActivityKit-Queue haben.
                            self.lastTelemetryPush = now
                            self.pushActivityUpdate(force: false)
                        }
                    }
                    // Widgets im Hintergrund schonend aktualisieren
                    self.scheduleWidgetReload(force: false)
                } else {
                    self.disconnectedSeconds += 1

                    // Erst nach 30 Sekunden ohne Verbindung/Musik im Hintergrund beenden:
                    if self.autoDismissEnabled && self.disconnectedSeconds >= 30 {
                        await self.endAllLiveActivities()
                        BackgroundKeepAliveManager.shared.stop()
                    }

                    _ = self.makeState()
                }
            }
        }
        timer.resume()
        telemetryTimer = timer
    }

    private func tick() {
        // Aktuelle Zeit ermitteln (Spotify mit CarPlay-Delay Kompensation ODER System Player)
        let time: TimeInterval
        if spotify.isAuthenticated {
            time = spotify.calculatedPlaybackTime()
        } else {
            time = max(0, systemPlayer.currentPlaybackTime - spotify.carPlayDelayCompensation)
        }

        currentPlaybackTime = time
        if duration > 0 { progress = min(time / duration, 1.0) }

        if let lyrics = lyrics {
            if let idx = lyrics.activeIndex(at: time) {
                let newPrev3   = idx > 2 ? lyrics.lines[idx - 3].text : ""
                let newPrev2   = idx > 1 ? lyrics.lines[idx - 2].text : ""
                let newPrev    = idx > 0 ? lyrics.lines[idx - 1].text : ""
                let newCurrent = lyrics.lines[idx].text
                let newNext    = idx + 1 < lyrics.lines.count ? lyrics.lines[idx + 1].text : ""
                let newNext2   = idx + 2 < lyrics.lines.count ? lyrics.lines[idx + 2].text : ""
                let newNext3   = idx + 3 < lyrics.lines.count ? lyrics.lines[idx + 3].text : ""

                let lineChanged = (newCurrent != currentLine || newNext != nextLine || newPrev != previousLine)
                if lineChanged {
                    previousLine3 = newPrev3
                    previousLine2 = newPrev2
                    previousLine  = newPrev
                    currentLine   = newCurrent
                    nextLine      = newNext
                    nextLine2     = newNext2
                    nextLine3     = newNext3
                    // Live Activity sofort mit neuer Textzeile aktualisieren (min 0.3s Abstand schützt vor Throttling)
                    pushActivityUpdate(force: true)
                    // CarPlay- & Homescreen-LyricsWidget synchron im Hintergrund nachziehen
                    scheduleWidgetReload(force: true)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Test / Mock Injektor
    // ─────────────────────────────────────────────────────────────────────────

    public func injectTrack(title: String, artist: String, album: String = "", duration: TimeInterval = 0, lrc: String? = nil) async {
        currentTrackTitle = title
        currentArtist     = artist
        currentAlbum      = album
        self.duration     = duration
        isPlaying         = true
        if let lrc { await LyricsService.shared.injectMock(title: title, artist: artist, lrc: lrc) }
        await loadLyrics(title: title, artist: artist, album: album, duration: duration)
    }
}
