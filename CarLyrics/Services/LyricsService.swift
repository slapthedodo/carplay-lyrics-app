// MARK: - LyricsService.swift
// CarLyrics – async service that fetches LRC lyrics from LRCLIB.
// ─────────────────────────────────────────────────────────────────────────────
//
// Primary:  https://lrclib.net/api/get?track_name=…&artist_name=…&album_name=…&duration=…
// Fallback: https://lrclib.net/api/search?q=<artist>+<title>  (uses first result)
//
// LRCLIB is a free, open-source, no-key API. Responses include
// "syncedLyrics" (LRC) or "plainLyrics" (plain text, no timestamps).
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Response Models (LRCLIB)
// ─────────────────────────────────────────────────────────────────────────────

private struct LRCLibResponse: Decodable {
    let id           : Int?
    let trackName    : String?
    let artistName   : String?
    let syncedLyrics : String?
    let plainLyrics  : String?
}

private struct LRCLibSearchResponse: Decodable {
    let results: [LRCLibResponse]

    // The API wraps results in a top-level array, not an object key.
    // We decode it as an array directly in the service.
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Errors
// ─────────────────────────────────────────────────────────────────────────────

public enum LyricsServiceError: LocalizedError {
    case noSyncedLyrics
    case networkError(Error)
    case decodingError(Error)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .noSyncedLyrics:           return "Keine synchronisierten Lyrics gefunden."
        case .networkError:             return "Keine Verbindung zum Lyrics-Server."
        case .decodingError:            return "Songtext-Format wird nicht unterstützt."
        case .invalidURL:               return "Ungültige Song-Anfrage."
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: LyricsService
// ─────────────────────────────────────────────────────────────────────────────

public actor LyricsService {

    public static let shared = LyricsService()

    private let session: URLSession
    private var cache: [String: ParsedLyrics] = [:]
    private var failedTracks: Set<String> = []

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func clearFailedTracks() {
        failedTracks.removeAll()
    }

    /// Returns synced lyrics for the given track.
    /// Throws `LyricsServiceError` if nothing is found.
    public func fetchLyrics(title: String,
                            artist: String,
                            album: String = "",
                            duration: TimeInterval? = nil) async throws -> ParsedLyrics {
        let cacheKey = "\(artist)|\(title)".lowercased().trimmingCharacters(in: .whitespaces)
        if let cached = cache[cacheKey] { return cached }
        if failedTracks.contains(cacheKey) { throw LyricsServiceError.noSyncedLyrics }

        do {
            return try await performFetch(title: title, artist: artist, album: album, duration: duration, cacheKey: cacheKey)
        } catch LyricsServiceError.networkError {
            // Einmaliger automatischer Retry nach 1.2s bei kurzem Netzwerkaussetzer (z.B. Funkloch)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return try await performFetch(title: title, artist: artist, album: album, duration: duration, cacheKey: cacheKey)
        }
    }

    private func performFetch(title: String,
                              artist: String,
                              album: String,
                              duration: TimeInterval?,
                              cacheKey: String) async throws -> ParsedLyrics {
        // 1. Precise lookup
        if let result = try? await fetchExact(title: title,
                                              artist: artist,
                                              album: album,
                                              duration: duration) {
            cache[cacheKey] = result
            return result
        }

        // 2. Fuzzy search fallback
        do {
            let result = try await fetchSearch(title: title, artist: artist)
            cache[cacheKey] = result
            return result
        } catch LyricsServiceError.noSyncedLyrics {
            // Nur echte 404 / leere Lyrics cachen, niemals temporäre Netzwerkfehler!
            failedTracks.insert(cacheKey)
            throw LyricsServiceError.noSyncedLyrics
        } catch {
            throw error
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func fetchExact(title: String,
                            artist: String,
                            album: String,
                            duration: TimeInterval?) async throws -> ParsedLyrics {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name",  value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let dur = duration {
            items.append(URLQueryItem(name: "duration", value: String(Int(dur))))
        }
        components.queryItems = items

        guard let url = components.url else { throw LyricsServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("CarLyrics/1.0 (iOS; slapthedodo@github)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            response = r
        } catch {
            throw LyricsServiceError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw LyricsServiceError.noSyncedLyrics
            }
            guard http.statusCode == 200 else {
                throw LyricsServiceError.networkError(URLError(.badServerResponse))
            }
        }

        let resp: LRCLibResponse
        do {
            resp = try JSONDecoder().decode(LRCLibResponse.self, from: data)
        } catch {
            throw LyricsServiceError.noSyncedLyrics
        }

        guard let lrc = resp.syncedLyrics, !lrc.isEmpty else {
            throw LyricsServiceError.noSyncedLyrics
        }
        return LRCParser.parse(lrc, title: title, artist: artist)
    }

    private func fetchSearch(title: String, artist: String) async throws -> ParsedLyrics {
        let query = "\(artist) \(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://lrclib.net/api/search?q=\(query)") else {
            throw LyricsServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("CarLyrics/1.0 (iOS; slapthedodo@github)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            response = r
        } catch {
            throw LyricsServiceError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw LyricsServiceError.noSyncedLyrics
            }
            guard http.statusCode == 200 else {
                throw LyricsServiceError.networkError(URLError(.badServerResponse))
            }
        }

        let results: [LRCLibResponse]
        do {
            results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
        } catch {
            throw LyricsServiceError.noSyncedLyrics
        }

        guard let first = results.first(where: { $0.syncedLyrics != nil }),
              let lrc = first.syncedLyrics, !lrc.isEmpty else {
            throw LyricsServiceError.noSyncedLyrics
        }

        return LRCParser.parse(lrc,
                               title: first.trackName ?? title,
                               artist: first.artistName ?? artist)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Mock / Test helpers
// ─────────────────────────────────────────────────────────────────────────────

public extension LyricsService {

    /// Inject a hand-crafted LRC string directly into the cache (for previews/testing).
    func injectMock(title: String, artist: String, lrc: String) {
        let parsed = LRCParser.parse(lrc, title: title, artist: artist)
        cache["\(artist)|\(title)"] = parsed
    }
}
