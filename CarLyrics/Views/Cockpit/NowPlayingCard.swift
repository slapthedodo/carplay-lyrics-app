// MARK: - NowPlayingCard.swift
// Aktueller Song, Künstler, Album & Wiedergabe-Fortschritt
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct NowPlayingCard: View {
    @ObservedObject var observer: MusicObserver

    public init(observer: MusicObserver) {
        self.observer = observer
    }

    public var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: observer.isPlaying ? "music.note.list" : "pause.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: observer.isPlaying)

                VStack(alignment: .leading, spacing: 3) {
                    if observer.currentTrackTitle.isEmpty {
                        Text("Warte auf Musik…")
                            .font(.title3).foregroundStyle(.secondary)
                    } else {
                        Text(observer.currentTrackTitle)
                            .font(.title3.bold()).foregroundStyle(.white)
                            .lineLimit(1)
                        Text(observer.currentArtist)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            if observer.progress > 0 {
                ProgressView(value: observer.progress)
                    .tint(.cyan)
                    .padding(.top, 8)
            }
        }
    }
}
