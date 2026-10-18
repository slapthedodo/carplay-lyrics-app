// MARK: - HandyModusLyricsPanel.swift
// Großes Lyrics-Panel mit 5-Zeilen-Kontext für den Handy-Modus
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLyricsPanel: View {
    @ObservedObject public var observer: MusicObserver

    public init(observer: MusicObserver) {
        self.observer = observer
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Track header
            trackHeader
                .padding(.bottom, 10)

            // Progress bar
            progressBar
                .padding(.bottom, 12)

            // Lyrics context
            lyricsContext
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
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
        VStack(spacing: 6) {
            if observer.currentLine.isEmpty && observer.lyricsStatus != .loaded {
                statusPlaceholder
            } else {
                contextLine(observer.previousLine2, scale: 0.78, opacity: 0.22)
                contextLine(observer.previousLine,  scale: 0.85, opacity: 0.38)

                // Active line — bright + glow
                Text(observer.currentLine.isEmpty ? "♪" : observer.currentLine)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .cyan.opacity(0.55), radius: 10)
                    .padding(.vertical, 4)
                    .id(observer.currentLine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.22), value: observer.currentLine)

                contextLine(observer.nextLine,  scale: 0.85, opacity: 0.38)
                contextLine(observer.nextLine2, scale: 0.78, opacity: 0.22)
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
            Label("OFFLINE", systemImage: "wifi.slash")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
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
