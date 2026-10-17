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
import WidgetKit

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

    public var hasActiveLiveActivity: Bool {
        return activeActivity != nil
    }

    /// Liefert garantiert nur eine echte, aktive Activity zurück (ignoriert .ended & .dismissed)
    public var activeActivity: Activity<LyricsAttributes>? {
        if let current = liveActivity, current.activityState == .active {
            return current
        }
        if let existing = Activity<LyricsAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.liveActivity = existing
            return existing
        }
        return nil
    }

    // Rate-Limit, Serialisierung & Queue State (Apple ActivityKit Schutz)
    private var lastActivityUpdate     : Date   = .distantPast
    private var lastSentG              : Double = 0
    private var isUpdatingActivity     : Bool   = false
    private var pendingActivityUpdate  : Bool   = false

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

            // Dynamic Island sofort mit dem neuen Songtitel aktualisieren
            pushActivityUpdate(force: true)

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
            pushActivityUpdate(force: false)
        }
    }

    private func handleNoTrack() {
        stopLineTimer()
        currentTrackTitle = ""
        currentArtist     = ""
        previousLine      = ""
        currentLine       = ""
        nextLine          = ""
        isPlaying         = false
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
        // Aktualisiert alle 2 Sekunden Motordaten und G-Kräfte, ohne Apples Rate-Limit zu verletzen
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.activeActivity == nil {
                    await self.reattachOrCreateLiveActivity()
                } else {
                    self.pushActivityUpdate(force: false)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
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
                    // Bei Zeilenwechsel sofort die Dynamic Island aktualisieren!
                    pushActivityUpdate(force: true)
                }
            }
        }

        // Telemetrie Check (G-Kraft Spitze erfassen – blitzschnell & reaktiv)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)
        let currentGVal = motionManager?.currentG ?? 0
        let gDelta = abs(currentGVal - lastSentG)

        // Wenn G-Kraft sich spürbar ändert (>0.06G) und min 0.35s vergangen sind:
        if gDelta >= 0.06 && elapsed >= 0.35 {
            lastSentG = currentGVal
            pushActivityUpdate(force: true)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Push Engine (Serialisiert, kein Dead-Lock, kein Throttling)
    // ─────────────────────────────────────────────────────────────────────────

    public func pushActivityUpdate(force: Bool = false) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)

        // Apple Rate-Limit Schutz mit FrequentUpdates:
        // Bei Songtext-Zeilenwechsel & G-Kraft Peaks: min 0.25s Abstand
        // Bei reinem Telemetrie-Update: min 0.8s Abstand
        let minAllowed = force ? 0.25 : 0.8
        if !force && elapsed < minAllowed {
            return
        }

        if isUpdatingActivity {
            pendingActivityUpdate = true
            return
        }

        isUpdatingActivity = true
        lastActivityUpdate = now

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isUpdatingActivity = false
                if self.pendingActivityUpdate {
                    self.pendingActivityUpdate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.pushActivityUpdate(force: true)
                    }
                }
            }

            guard let activity = self.activeActivity else {
                await self.reattachOrCreateLiveActivity()
                return
            }

            let state = self.makeState()
            // staleDate: nil -> iOS setzt die Dynamic Island NIEMALS versehentlich auf .stale
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Lifecycle (Robuste Anbindung & Auto-Cleanup)
    // ─────────────────────────────────────────────────────────────────────────

    public func reattachOrCreateLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Erst alle toten oder beendeten Activities sauber aus dem System entfernen
        let all = Activity<LyricsAttributes>.activities
        for old in all where old.activityState != .active {
            await old.end(nil, dismissalPolicy: .immediate)
        }

        let activeList = Activity<LyricsAttributes>.activities.filter { $0.activityState == .active }
        if let existing = activeList.first {
            self.liveActivity = existing
            for extra in activeList.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            pushActivityUpdate(force: true)
        } else {
            let title = currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle
            let artist = currentArtist.isEmpty ? "Motor-Monitor" : currentArtist
            await startNewLiveActivity(title: title, artist: artist)
        }
    }

    public func resetLiveActivities() async {
        await endAllLiveActivities()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await reattachOrCreateLiveActivity()
    }

    public func endAllLiveActivities() async {
        for act in Activity<LyricsAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
    }

    private func startNewLiveActivity(title: String, artist: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let _ = activeActivity {
            pushActivityUpdate(force: true)
            return
        }

        // Alle beendeten oder alten Leichen vor Neuanlage sofort abräumen
        for act in Activity<LyricsAttributes>.activities where act.activityState != .active {
            await act.end(nil, dismissalPolicy: .immediate)
        }

        let attrs   = LyricsAttributes(trackId: "\(artist)|\(title)")
        let content = ActivityContent(state: makeState(), staleDate: nil)
        do {
            let newActivity = try Activity<LyricsAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
            self.liveActivity = newActivity
            lastActivityUpdate = Date()
        } catch {
            print("[CarLyrics] Live Activity start failed: \(error)")
        }
    }

    public func endLiveActivity() async {
        if let activity = activeActivity {
            var final = makeState()
            final.isPlaying = false
            let content = ActivityContent(state: final, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            self.liveActivity = nil
        }
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
        let effectiveIAT: Int?
        let effectiveMAF: Double?

        if obd.isEnabled {
            if obd.connectionState == .connected {
                if let realOil = obd.liveOilTemp {
                    oilTemp = realOil
                    isEngineWarm = realOil >= 80
                } else if let coolant = obd.liveCoolantTemp {
                    // VW EA113 2.0 TFSI: Kühlmittel erwärmt sich über den Öl-Wasser-Wärmetauscher zuerst
                    let baseOil = max(20, coolant - 8)
                    let loadBonus = (coolant >= 85 && (obd.liveRPM > 2600 || (obd.liveBoostBar ?? 0) > 0.2)) ? min(15, max(0, Int((obd.liveBoostBar ?? 0) * 10))) : 0
                    let estimatedOil = baseOil + loadBonus
                    oilTemp = estimatedOil
                    isEngineWarm = estimatedOil >= 80
                } else {
                    oilTemp = wm?.oilTempInt ?? 20
                    isEngineWarm = false
                }
                effectiveBoost = obd.liveBoostBar ?? 0.0
                effectiveCoolant = obd.liveCoolantTemp ?? max(20, (wm?.oilTempInt ?? 20) + 10)
                effectiveIAT = obd.liveIAT ?? 20
                effectiveMAF = obd.liveMAF ?? 3.5
            } else {
                // Solange OBD noch sucht oder verbindet: Sanfter Übergang mit Standby-Werten
                let simOil = wm?.oilTempInt ?? 20
                oilTemp = simOil
                isEngineWarm = wm?.isEngineWarm ?? false
                effectiveBoost = 0.0
                effectiveCoolant = simOil > 70 ? 90 : max(20, simOil + 10)
                effectiveIAT = 20
                effectiveMAF = 3.5
            }
        } else {
            // Reines TFSI Simulationsmodell
            let simOil = wm?.oilTempInt ?? 20
            oilTemp = simOil
            isEngineWarm = wm?.isEngineWarm ?? false
            effectiveBoost = nil
            effectiveCoolant = simOil > 70 ? 90 : max(20, simOil + 10)
            effectiveIAT = nil
            effectiveMAF = nil
        }

        let progressVal = wm?.warmupProgress ?? 0
        let phaseVal    = wm?.phase ?? .cold

        // Werte für Home- & Sperrbildschirm-Widgets speichern (sowohl standard als auch AppGroup)
        let groupDefaults = UserDefaults(suiteName: "group.com.carlyrics")
        let def = UserDefaults.standard

        if let oilTemp {
            def.set(oilTemp, forKey: "widget_oil_temp")
            groupDefaults?.set(oilTemp, forKey: "widget_oil_temp")
        } else {
            def.removeObject(forKey: "widget_oil_temp")
            groupDefaults?.removeObject(forKey: "widget_oil_temp")
        }
        if let effectiveBoost {
            def.set(effectiveBoost, forKey: "widget_boost_bar")
            groupDefaults?.set(effectiveBoost, forKey: "widget_boost_bar")
        } else {
            def.removeObject(forKey: "widget_boost_bar")
            groupDefaults?.removeObject(forKey: "widget_boost_bar")
        }
        if let effectiveCoolant {
            def.set(effectiveCoolant, forKey: "widget_coolant_temp")
            groupDefaults?.set(effectiveCoolant, forKey: "widget_coolant_temp")
        } else {
            def.removeObject(forKey: "widget_coolant_temp")
            groupDefaults?.removeObject(forKey: "widget_coolant_temp")
        }
        if let mm {
            def.set(mm.currentG, forKey: "widget_current_g")
            groupDefaults?.set(mm.currentG, forKey: "widget_current_g")
            def.set(mm.peakG, forKey: "widget_peak_g")
            groupDefaults?.set(mm.peakG, forKey: "widget_peak_g")
        }
        if let effectiveIAT {
            def.set(effectiveIAT, forKey: "widget_iat")
            groupDefaults?.set(effectiveIAT, forKey: "widget_iat")
        }
        if let effectiveMAF {
            def.set(effectiveMAF, forKey: "widget_maf")
            groupDefaults?.set(effectiveMAF, forKey: "widget_maf")
        }

        let cleanTitle = currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle
        let cleanArtist = currentArtist.isEmpty ? "Motor-Monitor" : currentArtist
        let cleanLyric = currentLine.isEmpty ? (currentTrackTitle.isEmpty ? "Öl- & Telemetrie-Monitor" : "♪") : currentLine

        def.set(cleanTitle, forKey: "widget_song_title")
        groupDefaults?.set(cleanTitle, forKey: "widget_song_title")
        def.set(cleanArtist, forKey: "widget_artist")
        groupDefaults?.set(cleanArtist, forKey: "widget_artist")
        def.set(cleanLyric, forKey: "widget_current_line")
        groupDefaults?.set(cleanLyric, forKey: "widget_current_line")
        def.set(nextLine, forKey: "widget_next_line")
        groupDefaults?.set(nextLine, forKey: "widget_next_line")
        def.set(progress, forKey: "widget_song_progress")
        groupDefaults?.set(progress, forKey: "widget_song_progress")
        def.set(phaseVal.rawValue, forKey: "widget_warmup_phase")
        groupDefaults?.set(phaseVal.rawValue, forKey: "widget_warmup_phase")
        def.set(progressVal, forKey: "widget_warmup_progress")
        groupDefaults?.set(progressVal, forKey: "widget_warmup_progress")

        WidgetCenter.shared.reloadAllTimelines()

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
            iatTemp        : effectiveIAT,
            mafVal         : effectiveMAF,
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
