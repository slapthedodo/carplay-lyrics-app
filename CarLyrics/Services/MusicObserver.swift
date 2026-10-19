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

    /// Prüft ob ein echtes Apple CarPlay Display oder die dedizierte CarPlay-Audio-Route aktiv ist
    public var isRealCarPlayActive: Bool {
        let hasCarPlayScreen = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }
        let hasCarAudio = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
        return hasCarPlayScreen || hasCarAudio
    }

    /// Dynamic Island & Live Activity dürfen NUR aktiv sein, wenn:
    /// 1. Die App MINIMIERT / im Hintergrund ist (nicht im Vordergrund)
    /// 2. UND das iPhone mit echtem CarPlay verbunden ist!
    public var shouldDynamicIslandBeActive: Bool {
        let isMinimized = (UIApplication.shared.applicationState != .active)
        return isMinimized && isRealCarPlayActive
    }

    /// Prüft ob ein echtes CarPlay-Display oder CarPlay- / Auto-Audioausgang aktiv ist
    public var isCarPlayConnected: Bool {
        let hasCarPlayScreen = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }
        let hasCarAudio = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == .carAudio ||
            $0.portType == .airPlay ||
            $0.portType == .usbAudio ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP ||
            $0.portType == .bluetoothLE
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
    var telemetryTimer         : DispatchSourceTimer?
    let timerQueue             = DispatchQueue(label: "com.carlyrics.musicobserver.timer", qos: .userInteractive)
    private var cancellables   : Set<AnyCancellable> = []

    // ActivityKit State (genutzt von MusicObserverLiveActivity.swift)
    var liveActivity           : Activity<LyricsAttributes>?
    var lastActivityUpdate     : Date   = .distantPast
    var lastLyricUpdate        : Date   = .distantPast
    var lastSentG              : Double = 0
    var lastSentOilTemp        : Int?   = nil
    var lastSentCoolant        : Int?   = nil
    var lastSentPhase          : WarmupPhase? = nil
    var lastSentBoost          : Double? = nil
    var isUpdatingActivity     : Bool   = false
    var pendingActivityUpdate  : Bool   = false
    var lastWidgetReloadTime   : Date   = .distantPast
    var lastTelemetryPush      : Date   = .distantPast

    // Präzise Wall-Clock Interpolation für System-Player im Sperrbildschirm / Hintergrund / CarPlay
    private var systemPlaybackBaseTime : TimeInterval = 0
    private var systemPlaybackBaseDate : Date = Date()

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

    public func syncSystemItem() {
        guard !spotify.isAuthenticated else { return }
        guard let item = systemPlayer.nowPlayingItem else {
            if isPlaying || !currentTrackTitle.isEmpty {
                handleNoTrack()
            }
            return
        }
        let title  = item.title  ?? ""
        let artist = item.artist ?? ""
        let album  = item.albumTitle ?? ""
        let dur    = item.playbackDuration
        let statePlaying = (systemPlayer.playbackState == .playing)

        let trackChanged = (title != currentTrackTitle || artist != currentArtist)

        if trackChanged {
            currentTrackTitle = title
            currentArtist     = artist
            currentAlbum      = album
            duration          = dur
            isPlaying         = statePlaying
            systemPlaybackBaseTime = max(0, systemPlayer.currentPlaybackTime)
            systemPlaybackBaseDate = Date()
            lyrics            = nil
            previousLine3     = ""
            previousLine2     = ""
            previousLine      = ""
            currentLine       = ""
            nextLine          = ""
            nextLine2         = ""
            nextLine3         = ""

            pushActivityUpdate(force: true)
            scheduleWidgetReload(force: true)
            Task { await loadLyrics(title: title, artist: artist, album: album, duration: dur) }
        } else {
            // Track unverändert: Playback-Zustand & Zeit-Drift synchronisieren
            if isPlaying != statePlaying {
                isPlaying = statePlaying
                if isPlaying {
                    systemPlaybackBaseTime = max(0, systemPlayer.currentPlaybackTime)
                    systemPlaybackBaseDate = Date()
                    startLineTimer()
                } else {
                    stopLineTimer()
                }
                pushActivityUpdate(force: false)
                scheduleWidgetReload(force: true)
            } else if statePlaying {
                // Bei aktiver Wiedergabe: Resync der Baseline wenn Drift > 1.5s (z.B. User hat gespult)
                let sampledTime = systemPlayer.currentPlaybackTime
                let expectedTime = systemPlaybackBaseTime + Date().timeIntervalSince(systemPlaybackBaseDate)
                if abs(sampledTime - expectedTime) > 1.5 {
                    systemPlaybackBaseTime = max(0, sampledTime)
                    systemPlaybackBaseDate = Date()
                }
            }
        }

        if isPlaying && lineTimer == nil {
            startLineTimer()
        }
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
            self, selector: #selector(handleAppStateOrRouteChanged),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppStateOrRouteChanged),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppStateOrRouteChanged),
            name: UIScreen.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppStateOrRouteChanged),
            name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppStateOrRouteChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleAppStateOrRouteChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.shouldDynamicIslandBeActive {
                if self.activeActivity == nil {
                    await self.reattachOrCreateLiveActivity()
                }
            } else {
                // Wenn die App im Vordergrund geöffnet ist ODER kein CarPlay aktiv ist: Live Activity aus
                if self.activeActivity != nil {
                    await self.endAllLiveActivities()
                }
            }

            // CarPlay-Gating für OBD Bluetooth (Batterieschutz Golf 5 Kl. 30):
            if !self.isRealCarPlayActive {
                self.obd.carPlayDidDisconnect()
            } else if self.obd.isEnabled && self.obd.connectionState == .disconnected {
                self.obd.carPlayGatedScan()
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

    private func tick() {
        // Aktuelle Zeit: Spotify Delay-Kompensation ODER System-Player mit Wall-Clock Interpolation
        let time: TimeInterval
        if spotify.isAuthenticated {
            time = spotify.calculatedPlaybackTime()
        } else {
            if isPlaying {
                let elapsed = Date().timeIntervalSince(systemPlaybackBaseDate)
                time = max(0, systemPlaybackBaseTime + elapsed - spotify.carPlayDelayCompensation)
            } else {
                time = max(0, systemPlaybackBaseTime - spotify.carPlayDelayCompensation)
            }
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

    public func retryLyrics() {
        guard !currentTrackTitle.isEmpty else { return }
        Task {
            await LyricsService.shared.clearFailedTracks()
            await loadLyrics(title: currentTrackTitle, artist: currentArtist, album: currentAlbum, duration: duration)
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
