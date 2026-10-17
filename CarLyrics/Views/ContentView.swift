// MARK: - ContentView.swift  (v2 — Dark Cockpit Edition)
// CarLyrics – full dark-cockpit UI mit Glassmorphism, SwiftUI Gauge,
// G-Force-Fadenkreuz und Warmfahr-Timer.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import MediaPlayer

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Root
// ─────────────────────────────────────────────────────────────────────────────

public struct ContentView: View {

    @StateObject private var observer = MusicObserver()
    @StateObject private var warmup   = WarmupManager()
    @StateObject private var motion   = MotionManager()

    @State private var showMockSheet  = false
    @State private var selectedTab    = 0

    public var body: some View {
        ZStack {
            // Mesh-style dark background
            CockpitBackground()

            TabView(selection: $selectedTab) {
                NowPlayingTab(observer: observer, warmup: warmup, motion: motion)
                    .tabItem { Label("Lyrics", systemImage: "music.note") }
                    .tag(0)

                TelemetryTab(warmup: warmup, motion: motion)
                    .tabItem { Label("Telemetry", systemImage: "gauge.with.needle") }
                    .tag(1)
            }
            .tint(.cyan)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMockSheet) {
            MockInjectorView(observer: observer)
        }
        .onAppear {
            observer.warmupManager = warmup
            observer.motionManager = motion
            motion.start()
            BackgroundKeepAliveManager.shared.start()
        }
        .onDisappear {
            motion.stop()
            BackgroundKeepAliveManager.shared.stop()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showMockSheet = true } label: {
                    Image(systemName: "testtube.2").foregroundStyle(.cyan)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Now Playing Tab
// ─────────────────────────────────────────────────────────────────────────────

struct NowPlayingTab: View {
    @ObservedObject var observer : MusicObserver
    @ObservedObject var warmup   : WarmupManager
    @ObservedObject var motion   : MotionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                NowPlayingCard(observer: observer)
                LyricsCard(observer: observer)
                MiniTelemetryCard(warmup: warmup, motion: motion)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Tab
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryTab: View {
    @ObservedObject var warmup  : WarmupManager
    @ObservedObject var motion  : MotionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WarmupCard(warmup: warmup)
                GForceCard(motion: motion)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Now Playing Card
// ─────────────────────────────────────────────────────────────────────────────

struct NowPlayingCard: View {
    @ObservedObject var observer: MusicObserver

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: observer.isPlaying
                      ? "music.note.list" : "pause.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: observer.isPlaying)

                VStack(alignment: .leading, spacing: 4) {
                    if observer.currentTrackTitle.isEmpty {
                        Text("No track playing")
                            .font(.title3).foregroundStyle(.secondary)
                    } else {
                        Text(observer.currentTrackTitle)
                            .font(.title3.bold()).foregroundStyle(.white)
                            .lineLimit(1)
                        Text(observer.currentArtist)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if observer.progress > 0 {
                ProgressView(value: observer.progress)
                    .tint(.cyan)
                    .padding(.top, 6)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Lyrics Card
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsCard: View {
    @ObservedObject var observer: MusicObserver

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Live Lyrics", systemImage: "text.quote")
                    .font(.headline).foregroundStyle(.cyan)

                if observer.currentLine.isEmpty {
                    Text(observer.lyricsStatus.label)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(observer.currentLine)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.25), value: observer.currentLine)

                    if !observer.nextLine.isEmpty {
                        Text(observer.nextLine)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: observer.nextLine)
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Mini Telemetry Card (on Lyrics tab)
// ─────────────────────────────────────────────────────────────────────────────

struct MiniTelemetryCard: View {
    @ObservedObject var warmup  : WarmupManager
    @ObservedObject var motion  : MotionManager

    var body: some View {
        GlassCard {
            HStack {
                // Oil temp
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: warmup.warmupProgress)
                            .stroke(warmupColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: warmup.warmupProgress)
                        Text("\(warmup.oilTempInt)°")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(warmupColor)
                    }
                    .frame(width: 54, height: 54)
                    Text("OIL TEMP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // G-force mini
                VStack(spacing: 4) {
                    Text(motion.currentGFormatted)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(gColor(motion.currentG))
                        .contentTransition(.numericText())
                    Text("PEAK \(motion.peakGFormatted)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Phase badge
                VStack(spacing: 4) {
                    Text(warmup.phase.rawValue)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(warmupColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(warmupColor.opacity(0.15),
                                    in: Capsule())
                    Text(warmup.isRunning ? warmup.elapsedFormatted : "--:--")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var warmupColor: Color {
        switch warmup.phase {
        case .cold:    return .blue
        case .warming: return .orange
        case .ready:   return .green
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Warmup Card (full, on Telemetry tab)
// ─────────────────────────────────────────────────────────────────────────────

struct WarmupCard: View {
    @ObservedObject var warmup: WarmupManager

    private var warmupColor: Color {
        switch warmup.phase {
        case .cold:    return .blue
        case .warming: return .orange
        case .ready:   return .green
        }
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Label("Motor Warmfahr-Assistent", systemImage: "thermometer.medium")
                    .font(.headline).foregroundStyle(.cyan)

                // SwiftUI Gauge
                Gauge(value: warmup.warmupProgress) {
                    Text("Aufwärmen")
                } currentValueLabel: {
                    Text("\(warmup.oilTempInt)°C")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(warmupColor)
                } minimumValueLabel: {
                    Text("\(Int(warmup.startTemp))°").font(.caption2)
                } maximumValueLabel: {
                    Text("90°").font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(
                    Gradient(colors: [.blue, .orange, .green])
                )
                .frame(width: 120, height: 120)

                // Phase label
                Text(warmup.phase.label)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(warmupColor)
                    .padding(.horizontal)

                // Timer
                if warmup.isRunning {
                    Text(warmup.elapsedFormatted)
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white)
                }

                // Controls
                HStack(spacing: 16) {
                    Button {
                        warmup.start(cold: true)
                    } label: {
                        Label("Kaltstart", systemImage: "thermometer.snowflake")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .blue))

                    Button {
                        warmup.start(cold: false)
                    } label: {
                        Label("Warmstart", systemImage: "flame.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .orange))

                    Button {
                        warmup.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .gray))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Force Card (with crosshair / G-Ball)
// ─────────────────────────────────────────────────────────────────────────────

struct GForceCard: View {
    @ObservedObject var motion: MotionManager

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Label("G-Kräfte", systemImage: "gyroscope")
                    .font(.headline).foregroundStyle(.cyan)

                // G-Ball crosshair
                GBallView(x: motion.normalizedX, y: motion.normalizedY,
                          currentG: motion.currentG)
                    .frame(width: 200, height: 200)

                // Readings row
                HStack(spacing: 24) {
                    VStack {
                        Text("AKTUELL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(motion.currentGFormatted)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(gColor(motion.currentG))
                            .contentTransition(.numericText())
                    }
                    VStack {
                        Text("PEAK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(motion.peakGFormatted)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }

                // Controls
                HStack(spacing: 12) {
                    Button {
                        motion.calibrate()
                    } label: {
                        Label("Nullpunkt", systemImage: "scope")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .cyan))

                    Button {
                        motion.resetPeak()
                    } label: {
                        Label("Peak Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                    }
                    .buttonStyle(CockpitButtonStyle(color: .gray))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Ball (interactive G-Force Crosshair)
// ─────────────────────────────────────────────────────────────────────────────

struct GBallView: View {
    let x        : Double   // -1 … +1  (lateral)
    let y        : Double   // -1 … +1  (longitudinal)
    let currentG : Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2 - 8

            ZStack {
                // Grid rings
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { frac in
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: r * 2 * frac, height: r * 2 * frac)
                }

                // Cross hairs
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: r * 2, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: r * 2)

                // Labels
                Text("ACC").font(.system(size: 8)).foregroundStyle(.secondary)
                    .offset(y: -(r - 6))
                Text("BRK").font(.system(size: 8)).foregroundStyle(.secondary)
                    .offset(y: r - 6)

                // G-Ball dot
                Circle()
                    .fill(gColor(currentG))
                    .frame(width: 18, height: 18)
                    .shadow(color: gColor(currentG).opacity(0.8), radius: 8)
                    .offset(
                        x: CGFloat(x) * r,
                        y: -CGFloat(y) * r   // flip Y: positive = acceleration = up
                    )
                    .animation(.interactiveSpring(response: 0.15), value: x)
                    .animation(.interactiveSpring(response: 0.15), value: y)
            }
            .frame(width: w, height: h)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Cockpit background
// ─────────────────────────────────────────────────────────────────────────────

struct CockpitBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Subtle gradient bloom — simulates instrument panel glow
            RadialGradient(
                colors: [Color.cyan.opacity(0.06), Color.clear],
                center: .top, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Reusable components
// ─────────────────────────────────────────────────────────────────────────────

struct GlassCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
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

struct CockpitButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.3 : 0.12),
                        in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-color helper (shared in both targets via LyricsModels)
// ─────────────────────────────────────────────────────────────────────────────

private func gColor(_ g: Double) -> Color {
    switch g {
    case ..<0.3:  return .white
    case ..<0.6:  return .yellow
    case ..<0.9:  return .orange
    default:      return .red
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Mock Injector Sheet
// ─────────────────────────────────────────────────────────────────────────────

struct MockInjectorView: View {
    let observer: MusicObserver
    @Environment(\.dismiss) private var dismiss

    @State private var title   = "Bohemian Rhapsody"
    @State private var artist  = "Queen"
    @State private var lrcText = MockLRC.bohemianRhapsody

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Info") {
                    TextField("Title",  text: $title)
                    TextField("Artist", text: $artist)
                }
                Section("Custom LRC") {
                    TextEditor(text: $lrcText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Test Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Inject") {
                        Task {
                            await observer.injectTrack(
                                title: title, artist: artist,
                                lrc: lrcText.isEmpty ? nil : lrcText
                            )
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

enum MockLRC {
    static let bohemianRhapsody = """
[ti:Bohemian Rhapsody]
[ar:Queen]
[00:00.00]Is this the real life?
[00:04.50]Is this just fantasy?
[00:09.10]Caught in a landslide
[00:13.70]No escape from reality
[00:18.20]Open your eyes
[00:20.80]Look up to the skies and see
[00:25.40]I'm just a poor boy, I need no sympathy
[00:31.50]Because it's easy come, easy go
[00:34.90]Little high, little low
[00:38.30]Anyway the wind blows
[00:41.60]Doesn't really matter to me, to me
"""
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Preview
// ─────────────────────────────────────────────────────────────────────────────

#Preview {
    ContentView()
}
