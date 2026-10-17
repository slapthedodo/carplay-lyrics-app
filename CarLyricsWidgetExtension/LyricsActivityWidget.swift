// MARK: - LyricsActivityWidget.swift  (v2 — Telemetrie-Edition)
// CarLyrics Widget Extension
// Dynamic Island (Compact / Expanded / Minimal) + Lock Screen / CarPlay Banner
// ─────────────────────────────────────────────────────────────────────────────

import ActivityKit
import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widget entry
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in

            // ── Lock Screen / CarPlay Banner ──────────────────────────────
            LockScreenBannerView(state: context.state)

        } dynamicIsland: { context in
            DynamicIsland {

                // ── Expanded ─────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    OilTempBadge(
                        temp     : context.state.oilTemp,
                        progress : context.state.warmupProgress,
                        phase    : context.state.warmupPhase
                    )
                    .frame(width: 52, height: 52)
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    GForceCompact(
                        currentG: context.state.currentG,
                        peakG   : context.state.peakG
                    )
                    .frame(width: 56)
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        // Track info
                        Text(context.state.songTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Current lyric line
                        Text(context.state.currentLine.isEmpty
                             ? "♪" : context.state.currentLine)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // Next line preview
                        if !context.state.nextLine.isEmpty {
                            Text(context.state.nextLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        // Warmup status bar
                        WarmupStatusBar(state: context.state)
                            .frame(height: 3)
                    }
                    .padding(.bottom, 6)
                }

            } compactLeading: {
                // ── Oil Temp ring ─────────────────────────────────────────
                OilTempBadge(
                    temp     : context.state.oilTemp,
                    progress : context.state.warmupProgress,
                    phase    : context.state.warmupPhase
                )
                .frame(width: 26, height: 26)

            } compactTrailing: {
                // ── Live G-Force ──────────────────────────────────────────
                Text(String(format: "%.1fG", context.state.currentG))
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(gColor(context.state.currentG))
                    .contentTransition(.numericText())

            } minimal: {
                OilTempBadge(
                    temp     : context.state.oilTemp,
                    progress : context.state.warmupProgress,
                    phase    : context.state.warmupPhase
                )
                .frame(width: 20, height: 20)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Lock Screen / CarPlay Banner  (primary presentation)
// ─────────────────────────────────────────────────────────────────────────────

/// High-contrast layout for in-car glanceability:
///   Row 1 — Sport Telemetry Bar (temp + progress + G-force)
///   Row 2 — Current lyric (20 pt bold)
///   Row 3 — Next lyric (15 pt, subdued)
///   Row 4 — Song progress bar
struct LockScreenBannerView: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Telemetry bar ─────────────────────────────────────────────
            TelemetryBar(state: state)

            Divider().overlay(Color.white.opacity(0.15))

            // ── Current lyric — 20 pt bold ────────────────────────────────
            Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // ── Next lyric ────────────────────────────────────────────────
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            // ── Song progress bar ─────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * state.progress, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.88))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Telemetry Bar
// ─────────────────────────────────────────────────────────────────────────────

struct TelemetryBar: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {

            // Oil temp badge
            OilTempBadge(
                temp     : state.oilTemp,
                progress : state.warmupProgress,
                phase    : state.warmupPhase
            )
            .frame(width: 40, height: 40)

            // Warmup label
            VStack(alignment: .leading, spacing: 1) {
                Text(state.warmupPhase.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(phaseColor(state.warmupPhase))
                Text(state.warmupPhase.label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // G-Force column
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.2f G", state.currentG))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(gColor(state.currentG))
                Text("PEAK \(String(format: "%.2f", state.peakG))G")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Oil Temp Badge (ring + °C label)
// ─────────────────────────────────────────────────────────────────────────────

struct OilTempBadge: View {
    let temp     : Int
    let progress : Double
    let phase    : WarmupPhase

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(phaseColor(phase),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            Text("\(temp)°")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(phaseColor(phase))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: G-Force Compact (for expanded trailing)
// ─────────────────────────────────────────────────────────────────────────────

struct GForceCompact: View {
    let currentG : Double
    let peakG    : Double

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", currentG))
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .foregroundStyle(gColor(currentG))
                .contentTransition(.numericText())
            Text("G")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("↑\(String(format: "%.2f", peakG))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Warmup Status Bar
// ─────────────────────────────────────────────────────────────────────────────

struct WarmupStatusBar: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(phaseColor(state.warmupPhase))
                    .frame(width: geo.size.width * state.warmupProgress)
                    .animation(.easeOut(duration: 0.5), value: state.warmupProgress)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Color helpers (usable in Widget Extension without UIColor)
// ─────────────────────────────────────────────────────────────────────────────

func phaseColor(_ phase: WarmupPhase) -> Color {
    switch phase {
    case .cold:    return .blue
    case .warming: return .orange
    case .ready:   return .green
    }
}

func gColor(_ g: Double) -> Color {
    switch g {
    case ..<0.3:  return .white
    case ..<0.6:  return .yellow
    case ..<0.9:  return .orange
    default:      return .red
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Previews
// ─────────────────────────────────────────────────────────────────────────────

#Preview("Lock Screen – Warming", as: .content,
         using: LyricsAttributes(trackId: "preview")) {
    LyricsActivityWidget()
} contentStates: {
    LyricsAttributes.ContentState(
        currentLine    : "Caught in a landslide",
        nextLine       : "No escape from reality",
        songTitle      : "Bohemian Rhapsody",
        artist         : "Queen",
        progress       : 0.35,
        isPlaying      : true,
        currentG       : 0.42,
        peakG          : 0.81,
        gVectorX       : -0.3,
        gVectorY       : 0.27,
        oilTemp        : 67,
        warmupProgress : 0.68,
        warmupPhase    : .warming,
        isEngineWarm   : false
    )
    LyricsAttributes.ContentState(
        currentLine    : "Open your eyes",
        nextLine       : "Look up to the skies and see",
        songTitle      : "Bohemian Rhapsody",
        artist         : "Queen",
        progress       : 0.60,
        isPlaying      : true,
        currentG       : 0.08,
        peakG          : 0.81,
        oilTemp        : 90,
        warmupProgress : 1.0,
        warmupPhase    : .ready,
        isEngineWarm   : true
    )
}
