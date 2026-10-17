// MARK: - MusicObserver.swift  (v2 — Rate-limited + Telemetry)
// CarLyrics – drives Live Activity with rate-limit protection.
// ─────────────────────────────────────────────────────────────────────────────
//
// Update policy (ActivityKit rate-limit guard):
//   • activity.update() is called ONLY when:
//       a) currentLine actually changes   (immediate)
//       b) currentG crosses a ±0.05 G delta threshold  (G-peak event)
//       c) At most every 2.5 s for telemetry heartbeat
//   • The 100 ms timer runs locally for smooth UI — it does NOT trigger updates.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import MediaPlayer
import ActivityKit
import Combine
import CoreMotion

@MainActor
public final class MusicObserver: ObservableObject {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published state
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
    // MARK: Injected managers (set from CarLyricsApp)
    // ─────────────────────────────────────────────────────────────────────────

    public var warmupManager : WarmupManager?
    public var motionManager : MotionManager?

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private state
    // ─────────────────────────────────────────────────────────────────────────

    private let player    = MPMusicPlayerController.systemMusicPlayer
    private var lyrics    : ParsedLyrics?
    private var duration  : TimeInterval = 0
    private var lineTimer : Timer?

    // ActivityKit
    private var liveActivity : Activity<LyricsAttributes>?

    // Rate-limit state
    private var lastActivityUpdate   : Date      = .distantPast
    private let telemetryInterval    : TimeInterval = 2.5   // max heartbeat cadence
    private var lastSentG            : Double    = 0
    private let gDeltaThreshold      : Double    = 0.05

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        setupNotifications()
        player.beginGeneratingPlaybackNotifications()
        syncCurrentItem()
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
        lineTimer?.invalidate()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Mock / Test injection
    // ─────────────────────────────────────────────────────────────────────────

    public func injectTrack(title: String,
                            artist: String,
                            album: String = "",
                            duration: TimeInterval = 0,
                            lrc: String? = nil) async {
        currentTrackTitle = title
        currentArtist     = artist
        currentAlbum      = album
        self.duration     = duration
        isPlaying         = true

        if let lrc { await LyricsService.shared.injectMock(title: title, artist: artist, lrc: lrc) }
        await loadLyrics(title: title, artist: artist, album: album, duration: duration)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Notifications
    // ─────────────────────────────────────────────────────────────────────────

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
        NotificationCenter.default.addObserver(
            self, selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
    }

    @objc private func nowPlayingItemChanged() { syncCurrentItem() }

    @objc private func playbackStateChanged() {
        isPlaying = player.playbackState == .playing
        isPlaying ? startLineTimer() : stopLineTimer()
        Task { await updateLiveActivity(force: false) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Track loading
    // ─────────────────────────────────────────────────────────────────────────

    private func syncCurrentItem() {
        guard let item = player.nowPlayingItem else { handleNoTrack(); return }
        let title  = item.title  ?? ""
        let artist = item.artist ?? ""
        let album  = item.albumTitle ?? ""
        let dur    = item.playbackDuration
        guard title != currentTrackTitle || artist != currentArtist else { return }

        currentTrackTitle = title
        currentArtist     = artist
        currentAlbum      = album
        duration          = dur
        isPlaying         = player.playbackState == .playing
        lyrics            = nil
        currentLine       = ""
        nextLine          = ""

        Task { await loadLyrics(title: title, artist: artist, album: album, duration: dur) }
    }

    private func handleNoTrack() {
        stopLineTimer()
        currentTrackTitle = ""
        currentArtist     = ""
        currentLine       = ""
        nextLine          = ""
        isPlaying         = false
        Task { await endLiveActivity() }
    }

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
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 100 ms Line Timer (LOCAL only — does NOT call activity.update every tick)
    // ─────────────────────────────────────────────────────────────────────────

    private func startLineTimer() {
        lineTimer?.invalidate()
        lineTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopLineTimer() { lineTimer?.invalidate(); lineTimer = nil }

    private func tick() {
        guard let lyrics else { return }
        let time = player.currentPlaybackTime
        if duration > 0 { progress = min(time / duration, 1.0) }

        guard let idx = lyrics.activeIndex(at: time) else { return }
        let newCurrent = lyrics.lines[idx].text
        let newNext    = idx + 1 < lyrics.lines.count ? lyrics.lines[idx + 1].text : ""

        let lineChanged = (newCurrent != currentLine || newNext != nextLine)
        currentLine = newCurrent
        nextLine    = newNext

        // Rate-limit guard: only push to ActivityKit under specific conditions
        let now     = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)
        let currentGVal = motionManager?.currentG ?? 0
        let gPeak       = abs(currentGVal - lastSentG) >= gDeltaThreshold

        if lineChanged || gPeak || elapsed >= telemetryInterval {
            lastSentG = currentGVal
            Task { await updateLiveActivity(force: lineChanged) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    private func startLiveActivity(title: String, artist: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endLiveActivity()

        let attrs   = LyricsAttributes(trackId: "\(artist)|\(title)")
        let content = ActivityContent(state: makeState(), staleDate: nil)
        do {
            liveActivity = try Activity<LyricsAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
        } catch {
            print("[CarLyrics] Live Activity start failed: \(error)")
        }
    }

    private func updateLiveActivity(force: Bool) async {
        guard let activity = liveActivity else { return }
        lastActivityUpdate = Date()
        let content = ActivityContent(state: makeState(), staleDate: nil)
        await activity.update(content)
    }

    private func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        var final = makeState()
        final.isPlaying = false
        let content = ActivityContent(state: final, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        liveActivity = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: State builder
    // ─────────────────────────────────────────────────────────────────────────

    private func makeState() -> LyricsAttributes.ContentState {
        let wm = warmupManager
        let mm = motionManager
        return LyricsAttributes.ContentState(
            currentLine    : currentLine,
            nextLine       : nextLine,
            songTitle      : currentTrackTitle,
            artist         : currentArtist,
            progress       : progress,
            isPlaying      : isPlaying,
            currentG       : mm?.currentG ?? 0,
            peakG          : mm?.peakG    ?? 0,
            gVectorX       : mm?.gX       ?? 0,
            gVectorY       : mm?.gY       ?? 0,
            oilTemp        : wm?.oilTempInt     ?? 20,
            warmupProgress : wm?.warmupProgress ?? 0,
            warmupPhase    : wm?.phase          ?? .cold,
            isEngineWarm   : wm?.isEngineWarm   ?? false
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: LyricsStatus
// ─────────────────────────────────────────────────────────────────────────────

public enum LyricsStatus: Equatable {
    case idle, loading, loaded
    case error(String)

    var label: String {
        switch self {
        case .idle:         return "Waiting for music…"
        case .loading:      return "Fetching lyrics…"
        case .loaded:       return "Lyrics loaded"
        case .error(let m): return "⚠ \(m)"
        }
    }
}
