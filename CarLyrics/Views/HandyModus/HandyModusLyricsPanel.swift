// MARK: - HandyModusLyricsPanel.swift
// Großes Lyrics-Panel mit 5-Zeilen-Kontext für den Handy-Modus
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLyricsPanel: View {
    @ObservedObject public var observer: MusicObserver
    public var isCompact: Bool

    public init(observer: MusicObserver, isCompact: Bool = false) {
        self.observer = observer
        self.isCompact = isCompact
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Track header
            trackHeader
                .padding(.bottom, isCompact ? 6 : 10)

            // Progress bar
            progressBar
                .padding(.bottom, isCompact ? 8 : 12)

            // Lyrics context
            lyricsContext
        }
        .padding(.horizontal, isCompact ? 14 : 20)
        .padding(.vertical, isCompact ? 10 : 16)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 18 : 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 18 : 24)
                        .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Subviews
    // ─────────────────────────────────────────────────────────────────────────

    private var trackHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: observer.isPlaying ? "music.note.list" : "pause.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(observer.isPlaying ? .cyan : .secondary)
                .symbolEffect(.bounce, value: observer.isPlaying)

            VStack(alignment: .leading, spacing: 1) {
                Text(observer.currentTrackTitle.isEmpty ? "Kein Titel" : observer.currentTrackTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(observer.currentArtist.isEmpty ? "–" : observer.currentArtist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            lyricsStatusBadge
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 3)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, Color(red: 0.3, green: 0.9, blue: 1.0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(observer.progress), height: 3)
                    .animation(.linear(duration: 0.1), value: observer.progress)
            }
        }
        .frame(height: 3)
    }

    private var lyricsContext: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            if observer.currentLine.isEmpty && observer.lyricsStatus != .loaded {
                statusPlaceholder
            } else {
                if !isCompact {
                    contextLine(observer.previousLine2, scale: 0.78, opacity: 0.22)
                }
                contextLine(observer.previousLine,  scale: 0.85, opacity: 0.38)

                // Active line — bright + glow
                Text(observer.currentLine.isEmpty ? "♪" : observer.currentLine)
                    .font(.system(size: isCompact ? 15 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .cyan.opacity(0.55), radius: 10)
                    .padding(.vertical, isCompact ? 2 : 4)
                    .id(observer.currentLine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.22), value: observer.currentLine)

                contextLine(observer.nextLine,  scale: 0.85, opacity: 0.38)
                if !isCompact {
                    contextLine(observer.nextLine2, scale: 0.78, opacity: 0.22)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func contextLine(_ text: String, scale: CGFloat, opacity: Double) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(opacity))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: text)
        }
    }

    @ViewBuilder
    private var lyricsStatusBadge: some View {
        switch observer.lyricsStatus {
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.cyan)
                Text("Lyrics…")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan)
            }
        case .loaded:
            Label("SYNC", systemImage: "waveform")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.green)
        case .error:
            Button {
                observer.retryLyrics()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "wifi.slash")
                    Text("OFFLINE (RETRY)")
                }
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: Capsule())
            }
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusPlaceholder: some View {
        switch observer.lyricsStatus {
        case .idle:
            Text("Starte Musik …")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        case .loading:
            HStack(spacing: 8) {
                ProgressView().tint(.cyan)
                Text("Lyrics werden geladen …")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .error(let msg):
            VStack(spacing: 6) {
                Image(systemName: "music.note.slash")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        case .loaded:
            Text("♪")
                .font(.largeTitle)
                .foregroundStyle(.cyan.opacity(0.4))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widescreen Cinematic Lyrics Console (Landscape-Native Holographic HUD)
// ─────────────────────────────────────────────────────────────────────────────

public struct WidescreenLyricsConsole: View {
    @ObservedObject public var observer: MusicObserver
    public var width: CGFloat
    public var height: CGFloat

    public init(observer: MusicObserver, width: CGFloat, height: CGFloat) {
        self.observer = observer
        self.width = width
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ── 1. Track Metadata Bar ─────────────────────────────────────────
            HStack(spacing: 8) {
                // Live Dynamic Audio Equalizer
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(observer.isPlaying ? Color.cyan : Color.secondary)
                            .frame(width: 2.5, height: observer.isPlaying ? (i % 2 == 0 ? 12 : 7) : 4)
                            .animation(.easeInOut(duration: 0.3).repeatForever().delay(Double(i) * 0.08), value: observer.isPlaying)
                    }
                }
                .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(observer.currentTrackTitle.isEmpty ? "Keine Wiedergabe" : observer.currentTrackTitle)
                        .font(.system(size: min(13, height * 0.09), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(observer.currentArtist.isEmpty ? "CarLyrics Cockpit" : observer.currentArtist)
                        .font(.system(size: min(9.5, height * 0.065), weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Sync status badge
                widescreenStatusBadge
            }
            .padding(.horizontal, 4)

            // ── 2. Laser Thin Progress Bar ────────────────────────────────────
            GeometryReader { pGeo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 2)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, Color(red: 0.3, green: 0.9, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: pGeo.size.width * CGFloat(observer.progress), height: 2)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Spacer(minLength: 2)

            // ── 3. Cinematic Lyrics Teleprompter ─────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                // Previous Line (only if tall enough)
                if height >= 160 && !observer.previousLine.isEmpty {
                    Text(observer.previousLine)
                        .font(.system(size: min(11, height * 0.075), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }

                // Active Current Line (Hero Glow)
                Text(observer.currentLine.isEmpty ? "♪ Keine Wiedergabe" : observer.currentLine)
                    .font(.system(size: min(16, height * 0.16), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .cyan.opacity(0.80), radius: 10)
                    .lineLimit(height < 140 ? 1 : 2)
                    .id(observer.currentLine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.22), value: observer.currentLine)

                // Next Line (Upcoming)
                if !observer.nextLine.isEmpty {
                    Text(observer.nextLine)
                        .font(.system(size: min(10, height * 0.09), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var widescreenStatusBadge: some View {
        switch observer.lyricsStatus {
        case .loading:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.5).tint(.cyan)
                Text("Lyrics…").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.cyan)
            }
        case .loaded:
            Label("SYNC", systemImage: "waveform")
                .font(.system(size: 7.5, weight: .black))
                .foregroundStyle(.green)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
        case .error:
            Button { observer.retryLyrics() } label: {
                HStack(spacing: 2) { Image(systemName: "wifi.slash"); Text("RETRY") }
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(.orange)
                    .padding(.horizontal, 4).padding(.vertical, 1.5).background(Color.orange.opacity(0.15), in: Capsule())
            }
        case .idle:
            EmptyView()
        }
    }
}

