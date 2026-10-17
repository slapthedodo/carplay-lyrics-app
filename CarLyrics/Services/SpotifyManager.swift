// MARK: - SpotifyManager.swift
// CarLyrics – Direkte Spotify Web API Integration für sekundengenaue Wiedergabe,
// Titelabfrage und einstellbare Latenzkompensation für CarPlay Audio-Puffer.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Combine

public struct SpotifyCurrentlyPlaying: Decodable {
    public let is_playing : Bool?
    public let progress_ms: Int?
    public let timestamp  : Int64?
    public let item       : SpotifyTrack?
}

public struct SpotifyTrack: Decodable {
    public let id          : String?
    public let name        : String?
    public let duration_ms : Int?
    public let artists     : [SpotifyArtist]?
    public let album       : SpotifyAlbum?
}

public struct SpotifyArtist: Decodable {
    public let name: String?
}

public struct SpotifyAlbum: Decodable {
    public let name: String?
}

@MainActor
public final class SpotifyManager: ObservableObject {

    public static let shared = SpotifyManager()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Published State
    // ─────────────────────────────────────────────────────────────────────────

    @Published public var isAuthenticated : Bool   = false
    @Published public var accessToken     : String = "" {
        didSet {
            UserDefaults.standard.set(accessToken, forKey: "spotify_access_token")
            isAuthenticated = !accessToken.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @Published public var trackTitle      : String = ""
    @Published public var artistName      : String = ""
    @Published public var albumName       : String = ""
    @Published public var durationSeconds : TimeInterval = 0
    @Published public var isPlaying       : Bool = false

    /// Einstellbare CarPlay Audio-Verzögerung in Sekunden (Standard: 2.7s für Wireless CarPlay)
    /// Wenn das Auto den Ton 2-3s später wiedergibt als Spotify ihn streamt,
    /// zieht dieser Offset die Zeit ab, sodass Text und Lautsprecher exakt synchron sind!
    @Published public var carPlayDelayCompensation : Double = 2.5 {
        didSet {
            UserDefaults.standard.set(carPlayDelayCompensation, forKey: "carplay_audio_delay")
        }
    }

    @Published public var lastSyncError: String? = nil

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private State
    // ─────────────────────────────────────────────────────────────────────────

    private var pollTimer        : Timer?
    private var baseProgressSec  : TimeInterval = 0
    private var lastSnapshotDate : Date = Date()
    private let session          = URLSession.shared

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        if let savedToken = UserDefaults.standard.string(forKey: "spotify_access_token") {
            self.accessToken = savedToken
            self.isAuthenticated = !savedToken.isEmpty
        }
        let savedDelay = UserDefaults.standard.double(forKey: "carplay_audio_delay")
        if savedDelay > 0 {
            self.carPlayDelayCompensation = savedDelay
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func startPolling() {
        pollTimer?.invalidate()
        fetchCurrentlyPlaying()

        // Fragt alle 1.5 Sekunden den Spotify Server ab für Drift-Korrektur und Track-Wechsel
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchCurrentlyPlaying()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Berechnet die präzise aktuelle Wiedergabezeit unter Berücksichtigung
    /// der Zeit seit dem letzten Server-Snapshot UND der CarPlay Lautsprecher-Verzögerung.
    public func calculatedPlaybackTime() -> TimeInterval {
        guard isPlaying else { return max(0, baseProgressSec - carPlayDelayCompensation) }
        let elapsedSinceSnapshot = Date().timeIntervalSince(lastSnapshotDate)
        let rawTime = baseProgressSec + elapsedSinceSnapshot
        // Audio-Delay abziehen, damit der Text mit dem verspäteten Autosound übereinstimmt!
        return max(0, rawTime - carPlayDelayCompensation)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: API Fetch
    // ─────────────────────────────────────────────────────────────────────────

    public func fetchCurrentlyPlaying() {
        guard isAuthenticated, !accessToken.isEmpty else { return }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        Task {
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResp = response as? HTTPURLResponse {
                    if httpResp.statusCode == 204 {
                        // Nichts wird abgespielt
                        self.isPlaying = false
                        return
                    }
                    if httpResp.statusCode == 401 {
                        self.lastSyncError = "Token abgelaufen"
                        return
                    }
                }

                let current = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: data)
                self.lastSyncError = nil

                self.isPlaying = current.is_playing ?? false
                if let ms = current.progress_ms {
                    self.baseProgressSec = Double(ms) / 1000.0
                    self.lastSnapshotDate = Date()
                }

                if let track = current.item {
                    self.trackTitle = track.name ?? ""
                    self.artistName = track.artists?.first?.name ?? ""
                    self.albumName  = track.album?.name ?? ""
                    if let durMs = track.duration_ms {
                        self.durationSeconds = Double(durMs) / 1000.0
                    }
                }
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }
}
