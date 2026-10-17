// MARK: - LyricsCard.swift
// Synchronisierte Songtext-Anzeige mit sanftem Vor-/Rücklauf
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct LyricsCard: View {
    @ObservedObject var observer: MusicObserver

    public init(observer: MusicObserver) {
        self.observer = observer
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Live Songtext", systemImage: "text.quote")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    if observer.isPlaying {
                        Text("SYNC")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }

                if observer.currentLine.isEmpty {
                    Text(observer.lyricsStatus.label)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        // 3 Zeilen davor
                        if !observer.previousLine3.isEmpty {
                            Text(observer.previousLine3)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.12))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine3)
                        }

                        // 2 Zeilen davor
                        if !observer.previousLine2.isEmpty {
                            Text(observer.previousLine2)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.24))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine2)
                        }

                        // 1 Zeile davor
                        if !observer.previousLine.isEmpty {
                            Text(observer.previousLine)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.42))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.previousLine)
                        }

                        // ═══ Aktuelle Zeile (Extra Groß & Leuchtend) ═══
                        Text(observer.currentLine)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .cyan.opacity(0.45), radius: 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.25), value: observer.currentLine)
                            .padding(.vertical, 4)

                        // 1 Zeile danach
                        if !observer.nextLine.isEmpty {
                            Text(observer.nextLine)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine)
                        }

                        // 2 Zeilen danach
                        if !observer.nextLine2.isEmpty {
                            Text(observer.nextLine2)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.24))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine2)
                        }

                        // 3 Zeilen danach
                        if !observer.nextLine3.isEmpty {
                            Text(observer.nextLine3)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.12))
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: observer.nextLine3)
                        }
                    }
                }
            }
        }
    }
}
