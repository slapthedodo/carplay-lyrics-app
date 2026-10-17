// MARK: - CockpitUIComponents.swift
// Reusable Styling-Komponenten & Hilfsfunktionen für das Cockpit
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct CockpitBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.06), Color.clear],
                center: .top, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}

public struct GlassCard<Content: View>: View {
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

public struct CockpitButtonStyle: ButtonStyle {
    let color: Color
    public init(color: Color) { self.color = color }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.3 : 0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

@MainActor
public func gColor(_ g: Double, maxG: Double? = nil) -> Color {
    let limit = max(0.3, maxG ?? MotionManager.shared.maxG)
    let ratio = g / limit
    if ratio < 0.35 {
        return .white
    } else if ratio < 0.65 {
        return .yellow
    } else if ratio < 0.88 {
        return .orange
    } else {
        return .red
    }
}

public struct MockInjectorView: View {
    @ObservedObject var observer: MusicObserver
    @Environment(\.dismiss) private var dismiss
    @State private var title  = "Bohemian Rhapsody"
    @State private var artist = "Queen"
    @State private var album  = "A Night at the Opera"

    public init(observer: MusicObserver) {
        self.observer = observer
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Test Song") {
                    TextField("Titel", text: $title)
                    TextField("Künstler", text: $artist)
                    TextField("Album", text: $album)

                    Button("Test-Track einspeisen") {
                        Task {
                            await observer.injectTrack(
                                title: title, artist: artist, album: album, duration: 354,
                                lrc: """
                                [00:00.00] Is this the real life?
                                [00:04.00] Is this just fantasy?
                                [00:08.00] Caught in a landslide
                                [00:12.00] No escape from reality
                                [00:16.00] Open your eyes
                                [00:20.00] Look up to the skies and see
                                """
                            )
                            dismiss()
                        }
                    }
                    .buttonStyle(CockpitButtonStyle(color: .cyan))
                }
            }
            .navigationTitle("Test Injektor")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}
