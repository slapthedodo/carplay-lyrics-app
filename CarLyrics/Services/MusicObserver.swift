// MARK: - MusicObserver.swift  (v3 — Spotify + OBD-II + Strict Rate-Limit)
// CarLyrics – verbindet Spotify, System-Player, OBD-II und Warmup mit ActivityKit.
// ─────────────────────────────────────────────────────────────────────────────
//
// Rate-Limit Schutz:
//   • Striktes Mindestintervall: 0.8s zwischen zwei activity.update() Aufrufen.
//   • Ausnahme: Zeilenwechsel (lineChanged) triggert sofort, setzt aber den Throttle zurück.
//   • Telemetrie & G-Kräfte werden gebündelt und max. alle 2.5s übertragen.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import MediaPlayer
import ActivityKit
import Combine
import CoreMotion

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
    @Published public var currentLine       : String       = ""
    @Published public var nextLine          : String       = ""
    @Published public var lyricsStatus      : LyricsStatus = .idle
    @Published public var progress          : Double       = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Subsystem References
    // ─────────────────────────────────────────────────────────────────────────

    public var warmupManager : WarmupManager? = WarmupManager.shared
    public var motionManager : MotionManager? = MotionManager.shared
    public let spotify       = SpotifyManager.shared
    public let obd           = OBDManager.shared

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private State
    // ─────────────────────────────────────────────────────────────────────────

    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    private var lyrics       : ParsedLyrics?
    private var duration     : TimeInterval = 0
    private var lineTimer        : Timer?
    private var telemetryTimer   : Timer?
    private var cancellables     : Set<AnyCancellable> = []

    // ActivityKit
    private var liveActivity : Activity<LyricsAttributes>?

    // Rate-Limit & Throttle State
    private var lastActivityUpdate : Date         = .distantPast
    private let minUpdateInterval  : TimeInterval = 0.8   // Strenger Schutz vor Apple Throttling
    private let telemetryInterval  : TimeInterval = 2.0   // Regelmäßiges Telemetrie-Update
    private var lastSentG          : Double       = 0
    private let gDeltaThreshold    : Double       = 0.08  // Erst ab 0.08G Delta aktualisieren

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        setupNotifications()
        systemPlayer.beginGeneratingPlaybackNotifications()

        // Spotify Observer einhängen
        spotify.$trackTitle.combineLatest(spotify.$artistName, spotify.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] title, artist, isPlaying in
                guard let self, self.spotify.isAuthenticated else { return }
                self.handleSpotifyTrack(title: title, artist: artist, isPlaying: isPlaying)
            }
            .store(in: &cancellables)

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
        lineTimer?.invalidate()
        telemetryTimer?.invalidate()
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

            Task {
                await loadLyrics(title: title, artist: artist, album: spotify.albumName, duration: spotify.durationSeconds)
            }
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
        currentLine       = ""
        nextLine          = ""

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
            Task { await updateLiveActivity(force: false) }
        }
    }

    private func handleNoTrack() {
        stopLineTimer()
        currentTrackTitle = ""
        currentArtist     = ""
        currentLine       = ""
        nextLine          = ""
        isPlaying         = false
        Task { await updateLiveActivity(force: false) }
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
            await startLiveActivity(title: title, artist: artist)
        } catch {
            lyricsStatus = .error(error.localizedDescription)
            // Trotz Lyrics-Fehler die Live Activity für Motortelemetrie aktiv halten
            await updateLiveActivity(force: true)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 100 ms Line Timer mit Audio-Delay & Rate-Limit
    // ─────────────────────────────────────────────────────────────────────────

    private func startLineTimer() {
        lineTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        lineTimer = timer
    }

    private func stopLineTimer() { lineTimer?.invalidate(); lineTimer = nil }

    public func startTelemetryHeartbeat() {
        telemetryTimer?.invalidate()
        // Aktualisiert alle 1.5 Sekunden die Motordaten und G-Kräfte in Dynamic Island & Sperrbildschirm auch im Hintergrund
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.liveActivity == nil {
                    await self.reattachOrCreateLiveActivity()
                } else {
                    await self.updateLiveActivity(force: false)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryTimer = timer
    }

    private func tick() {
        guard let lyrics else { return }

        // Aktuelle Zeit ermitteln (Spotify mit CarPlay-Delay Kompensation ODER System Player)
        let time: TimeInterval
        if spotify.isAuthenticated {
            time = spotify.calculatedPlaybackTime()
        } else {
            time = max(0, systemPlayer.currentPlaybackTime - spotify.carPlayDelayCompensation)
        }

        if duration > 0 { progress = min(time / duration, 1.0) }

        guard let idx = lyrics.activeIndex(at: time) else { return }
        let newCurrent = lyrics.lines[idx].text
        let newNext    = idx + 1 < lyrics.lines.count ? lyrics.lines[idx + 1].text : ""

        let lineChanged = (newCurrent != currentLine || newNext != nextLine)
        currentLine = newCurrent
        nextLine    = newNext

        // ── Verfeinerter Rate-Limit Schutz ──────────────────────────────────
        let now     = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)
        let currentGVal = motionManager?.currentG ?? 0
        let gPeak       = abs(currentGVal - lastSentG) >= gDeltaThreshold

        // Regel:
        // 1. Wenn die Zeile wechselt: SOFORT updaten (außer < 0.2s nach letztem Call)
        // 2. Telemetrie/G-Peak: NUR updaten, wenn mindestens 0.8s vergangen sind!
        if lineChanged {
            if elapsed >= 0.2 {
                lastSentG = currentGVal
                Task { await updateLiveActivity(force: true) }
            }
        } else if elapsed >= minUpdateInterval {
            if gPeak || elapsed >= telemetryInterval {
                lastSentG = currentGVal
                Task { await updateLiveActivity(force: false) }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Lifecycle (Robuste Anbindung & Auto-Cleanup)
    // ─────────────────────────────────────────────────────────────────────────

    public func reattachOrCreateLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let all = Activity<LyricsAttributes>.activities
        if let existing = all.first {
            // Re-Attach an bestehende Activity anstatt eine tote Leiche im System zu lassen!
            self.liveActivity = existing
            for extra in all.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            await updateLiveActivity(force: true)
        } else {
            let title = currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle
            let artist = currentArtist.isEmpty ? "Motor-Monitor" : currentArtist
            await startLiveActivity(title: title, artist: artist)
        }
    }

    public func resetLiveActivities() async {
        for act in Activity<LyricsAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
        await reattachOrCreateLiveActivity()
    }

    public func endAllLiveActivities() async {
        for act in Activity<LyricsAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
    }

    private func startLiveActivity(title: String, artist: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if liveActivity != nil {
            await updateLiveActivity(force: true)
            return
        }

        // Falls noch eine alte Activity im System existiert, sofort re-attachen
        if let existing = Activity<LyricsAttributes>.activities.first {
            self.liveActivity = existing
            await updateLiveActivity(force: true)
            return
        }

        let attrs   = LyricsAttributes(trackId: "\(artist)|\(title)")
        // staleDate: 8 Sekunden -> Schützt davor, dass die Dynamic Island nach App-Kill einfriert!
        let content = ActivityContent(state: makeState(), staleDate: Date().addingTimeInterval(8))
        do {
            liveActivity = try Activity<LyricsAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
        } catch {
            print("[CarLyrics] Live Activity start failed: \(error)")
        }
    }

    private func updateLiveActivity(force: Bool) async {
        guard let activity = liveActivity else {
            await reattachOrCreateLiveActivity()
            return
        }
        lastActivityUpdate = Date()
        // Frisches staleDate von 8s: Solange App läuft, wird es alle 1.5s verlängert.
        // Wird die App gekillt, blendet iOS die Activity nach 8s automatisch sauber aus!
        let content = ActivityContent(state: makeState(), staleDate: Date().addingTimeInterval(8))
        await activity.update(content)
    }

    public func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        var final = makeState()
        final.isPlaying = false
        let content = ActivityContent(state: final, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        liveActivity = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: State Builder (mit OBD-II Fallback & Telemetrie)
    // ─────────────────────────────────────────────────────────────────────────

    private func makeState() -> LyricsAttributes.ContentState {
        let wm = warmupManager
        let mm = motionManager

        let oilTemp: Int?
        let isEngineWarm: Bool
        let effectiveBoost: Double?
        let effectiveCoolant: Int?

        if obd.isEnabled {
            if obd.connectionState == .connected {
                if let realOil = obd.liveOilTemp {
                    oilTemp = realOil
                    isEngineWarm = realOil >= 80
                } else if let coolant = obd.liveCoolantTemp {
                    // VW Fallback: Kühlmittel ca. 5-10°C wärmer als Öl in der Aufwärmphase
                    let estimatedOil = max(20, coolant - 8)
                    oilTemp = estimatedOil
                    isEngineWarm = estimatedOil >= 80
                } else {
                    oilTemp = nil
                    isEngineWarm = false
                }
                effectiveBoost = obd.liveBoostBar
                effectiveCoolant = obd.liveCoolantTemp
            } else {
                // OBD ist aktiviert, aber noch nicht verbunden oder wartet auf Daten -> direkt "--"
                oilTemp = nil
                isEngineWarm = false
                effectiveBoost = nil
                effectiveCoolant = nil
            }
        } else {
            // Reines TFSI Simulationsmodell
            let simOil = wm?.oilTempInt ?? 20
            oilTemp = simOil
            isEngineWarm = wm?.isEngineWarm ?? false
            effectiveBoost = nil
            effectiveCoolant = simOil > 70 ? 90 : max(20, simOil + 10)
        }

        let progressVal = wm?.warmupProgress ?? 0
        let phaseVal    = wm?.phase ?? .cold

        // Werte für Home- & Sperrbildschirm-Widgets speichern
        if let oilTemp {
            UserDefaults.standard.set(oilTemp, forKey: "widget_oil_temp")
        } else {
            UserDefaults.standard.removeObject(forKey: "widget_oil_temp")
        }
        if let effectiveBoost {
            UserDefaults.standard.set(effectiveBoost, forKey: "widget_boost_bar")
        } else {
            UserDefaults.standard.removeObject(forKey: "widget_boost_bar")
        }
        if let effectiveCoolant {
            UserDefaults.standard.set(effectiveCoolant, forKey: "widget_coolant_temp")
        } else {
            UserDefaults.standard.removeObject(forKey: "widget_coolant_temp")
        }

        return LyricsAttributes.ContentState(
            currentLine    : currentLine.isEmpty ? (currentTrackTitle.isEmpty ? "Öl- & Telemetrie-Monitor" : "♪") : currentLine,
            nextLine       : nextLine,
            songTitle      : currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle,
            artist         : currentArtist.isEmpty ? "Motor-Monitor" : currentArtist,
            progress       : progress,
            isPlaying      : isPlaying,
            currentG       : mm?.currentG ?? 0,
            peakG          : mm?.peakG    ?? 0,
            gVectorX       : mm?.gX       ?? 0,
            gVectorY       : mm?.gY       ?? 0,
            oilTemp        : oilTemp,
            coolantTemp    : effectiveCoolant,
            boostBar       : effectiveBoost,
            warmupProgress : progressVal,
            warmupPhase    : phaseVal,
            isEngineWarm   : isEngineWarm
        )
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
