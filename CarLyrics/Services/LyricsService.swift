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
        case .noSyncedLyrics:           return "No synced lyrics available."
        case .networkError(let e):      return "Network error: \(e.localizedDescription)"
        case .decodingError(let e):     return "Decoding error: \(e.localizedDescription)"
        case .invalidURL:               return "Invalid URL."
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

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns synced lyrics for the given track.
    /// Throws `LyricsServiceError` if nothing is found.
    public func fetchLyrics(title: String,
                            artist: String,
                            album: String = "",
                            duration: TimeInterval? = nil) async throws -> ParsedLyrics {
        let cacheKey = "\(artist)|\(title)"
        if let cached = cache[cacheKey] { return cached }

        // 1. Precise lookup
        if let result = try? await fetchExact(title: title,
                                              artist: artist,
                                              album: album,
                                              duration: duration) {
            cache[cacheKey] = result
            return result
        }

        // 2. Fuzzy search fallback
        let result = try await fetchSearch(title: title, artist: artist)
        cache[cacheKey] = result
        return result
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

        let data: Data
        do {
            let (d, _) = try await session.data(from: url)
            data = d
        } catch {
            throw LyricsServiceError.networkError(error)
        }

        let resp: LRCLibResponse
        do {
            resp = try JSONDecoder().decode(LRCLibResponse.self, from: data)
        } catch {
            throw LyricsServiceError.decodingError(error)
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

        let data: Data
        do {
            let (d, _) = try await session.data(from: url)
            data = d
        } catch {
            throw LyricsServiceError.networkError(error)
        }

        let results: [LRCLibResponse]
        do {
            results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
        } catch {
            throw LyricsServiceError.decodingError(error)
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
