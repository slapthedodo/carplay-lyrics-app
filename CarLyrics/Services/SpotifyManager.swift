// MARK: - SpotifyManager.swift
// CarLyrics – Direkte Spotify Web API Integration für sekundengenaue Wiedergabe,
// Titelabfrage und einstellbare Latenzkompensation für CarPlay Audio-Puffer.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Combine
import AuthenticationServices
import UIKit
import CryptoKit

final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

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

public struct SpotifyQueueResponse: Decodable {
    public let currently_playing: SpotifyTrack?
    public let queue: [SpotifyTrack]?
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
            UserDefaults(suiteName: "group.com.carlyrics")?.set(accessToken, forKey: "spotify_access_token")
            isAuthenticated = !accessToken.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @Published public var refreshToken    : String = "" {
        didSet {
            UserDefaults.standard.set(refreshToken, forKey: "spotify_refresh_token")
            UserDefaults(suiteName: "group.com.carlyrics")?.set(refreshToken, forKey: "spotify_refresh_token")
        }
    }
    @Published public var clientId        : String = "" {
        didSet {
            UserDefaults.standard.set(clientId, forKey: "spotify_client_id")
            UserDefaults(suiteName: "group.com.carlyrics")?.set(clientId, forKey: "spotify_client_id")
        }
    }
    @Published public var clientSecret    : String = "" {
        didSet {
            UserDefaults.standard.set(clientSecret, forKey: "spotify_client_secret")
            UserDefaults(suiteName: "group.com.carlyrics")?.set(clientSecret, forKey: "spotify_client_secret")
        }
    }

    @Published public var trackTitle      : String = ""
    @Published public var artistName      : String = ""
    @Published public var albumName       : String = ""
    @Published public var durationSeconds : TimeInterval = 0
    @Published public var isPlaying       : Bool = false

    /// Einstellbare CarPlay Audio-Verzögerung in Sekunden (Standard: 2.5s für Wireless CarPlay)
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

    private var pollTimer        : DispatchSourceTimer?
    private let pollQueue        = DispatchQueue(label: "com.carlyrics.spotify.poll", qos: .utility)
    private var baseProgressSec  : TimeInterval = 0
    private var lastSnapshotDate : Date = Date()
    private let session          = URLSession.shared

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    public init() {
        let appGroup = UserDefaults(suiteName: "group.com.carlyrics")
        if let savedToken = UserDefaults.standard.string(forKey: "spotify_access_token") ?? appGroup?.string(forKey: "spotify_access_token") {
            self.accessToken = savedToken
            self.isAuthenticated = !savedToken.isEmpty
        }
        if let savedRefresh = UserDefaults.standard.string(forKey: "spotify_refresh_token") ?? appGroup?.string(forKey: "spotify_refresh_token") {
            self.refreshToken = savedRefresh
        }
        if let savedClient = UserDefaults.standard.string(forKey: "spotify_client_id") ?? appGroup?.string(forKey: "spotify_client_id") {
            self.clientId = savedClient
        }
        if let savedSecret = UserDefaults.standard.string(forKey: "spotify_client_secret") ?? appGroup?.string(forKey: "spotify_client_secret") {
            self.clientSecret = savedSecret
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
        stopPolling()
        fetchCurrentlyPlaying()

        // Fragt alle 1.5 Sekunden den Spotify Server ab für Drift-Korrektur und Track-Wechsel auch im Hintergrund
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: pollQueue)
        timer.schedule(deadline: .now() + 1.5, repeating: .milliseconds(1500), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.fetchCurrentlyPlaying()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    public func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// Tauscht das gespeicherte Refresh-Token automatisch gegen ein neues 1-Stunden-AccessToken ein
    public func refreshAccessToken() async {
        guard !refreshToken.isEmpty, !clientId.isEmpty else { return }

        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId)
        ]
        if !clientSecret.isEmpty {
            let authStr = "\(clientId):\(clientSecret)"
            if let authData = authStr.data(using: .utf8) {
                req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        req.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, _) = try await session.data(for: req)
            struct TokenResponse: Decodable {
                let access_token: String
                let refresh_token: String?
            }
            let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.accessToken = resp.access_token
            if let newRefresh = resp.refresh_token {
                self.refreshToken = newRefresh
            }
            self.lastSyncError = nil
        } catch {
            self.lastSyncError = "Token Refresh fehlgeschlagen: \(error.localizedDescription)"
        }
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
                        self.isPlaying = false
                        return
                    }
                    if httpResp.statusCode == 401 {
                        // Automatischer Refresh wenn Refresh-Token vorhanden
                        if !self.refreshToken.isEmpty {
                            await self.refreshAccessToken()
                            return
                        } else {
                            self.lastSyncError = "Token abgelaufen (Bitte erneuern)"
                            return
                        }
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
                    let newTitle = track.name ?? ""
                    let newArtist = track.artists?.first?.name ?? ""
                    let trackChanged = (newTitle != self.trackTitle || newArtist != self.artistName)

                    self.trackTitle = newTitle
                    self.artistName = newArtist
                    self.albumName  = track.album?.name ?? ""
                    if let durMs = track.duration_ms {
                        self.durationSeconds = Double(durMs) / 1000.0
                    }

                    if trackChanged {
                        self.prefetchUpcomingQueue()
                    }
                }
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    /// Lädt die nächsten 3 Songs aus der Spotify-Warteschlange vorab herunter (Prefetch)
    private func prefetchUpcomingQueue() {
        guard isAuthenticated, !accessToken.isEmpty else { return }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 4
        let request = req

        Task.detached(priority: .utility) { [session = self.session] in
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let queueResp = try? JSONDecoder().decode(SpotifyQueueResponse.self, from: data),
                  let queue = queueResp.queue else { return }

            for track in queue.prefix(3) {
                let title = track.name ?? ""
                let artist = track.artists?.first?.name ?? ""
                let album = track.album?.name ?? ""
                let dur = track.duration_ms.map { Double($0) / 1000.0 }
                if !title.isEmpty && !artist.isEmpty {
                    await LyricsService.shared.prefetchLyrics(title: title, artist: artist, album: album, duration: dur)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 1-Klick Browser Login (ASWebAuthenticationSession)
    // ─────────────────────────────────────────────────────────────────────────

    private var authSession: ASWebAuthenticationSession?
    private let authContext = AuthPresentationContext()

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func startWebAuthSession(completion: @escaping (Bool) -> Void) {
        let cid = clientId.trimmingCharacters(in: .whitespaces)
        guard !cid.isEmpty else {
            self.lastSyncError = "Bitte trage zuerst deine Spotify Client ID ein (developer.spotify.com)."
            completion(false)
            return
        }
        let redirect = "carlyrics://spotify-callback"
        let scope = "user-read-currently-playing%20user-read-playback-state"

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)

        let urlStr = "https://accounts.spotify.com/authorize?client_id=\(cid)&response_type=code&redirect_uri=\(redirect)&scope=\(scope)&code_challenge_method=S256&code_challenge=\(challenge)"

        guard let authURL = URL(string: urlStr) else {
            completion(false)
            return
        }

        authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "carlyrics") { [weak self] callbackURL, error in
            guard let self else { return }
            guard error == nil, let callbackURL else {
                completion(false)
                return
            }

            // Auswertung des Query-Codes: ?code=...
            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                Task { @MainActor in
                    await self.exchangeCodeForToken(code: code, verifier: verifier, clientId: cid, redirectUri: redirect, completion: completion)
                }
            } else {
                completion(false)
            }
        }
        authSession?.presentationContextProvider = authContext
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    private func exchangeCodeForToken(code: String, verifier: String, clientId: String, redirectUri: String, completion: @escaping (Bool) -> Void) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            completion(false)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        if !clientSecret.isEmpty {
            let authStr = "\(clientId):\(clientSecret)"
            if let authData = authStr.data(using: .utf8) {
                req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }
        req.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, _) = try await session.data(for: req)
            struct TokenResponse: Decodable {
                let access_token: String
                let refresh_token: String?
            }
            let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.accessToken = resp.access_token
            if let newRefresh = resp.refresh_token {
                self.refreshToken = newRefresh
            }
            self.startPolling()
            self.lastSyncError = nil
            completion(true)
        } catch {
            self.lastSyncError = "Token-Tausch fehlgeschlagen: \(error.localizedDescription)"
            completion(false)
        }
    }
}
