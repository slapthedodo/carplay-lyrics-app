// MARK: - HandyModusLandscapeComponents.swift
// Komponenten & Mini-Tiles für das Querformat-Dashboard
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Landscape Mini Stat Tile (Kompakt für 2x4 Performance Grid)
// ─────────────────────────────────────────────────────────────────────────────

public struct LandscapeStatTile: View {
    public let icon    : String
    public let label   : String
    public let value   : String
    public let unit    : String
    public let color   : Color
    public var warning : Bool = false

    public init(icon: String, label: String, value: String, unit: String, color: Color, warning: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.unit = unit
        self.color = color
        self.warning = warning
    }

    public var body: some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(warning ? .red : color)
                Spacer(minLength: 0)
                Text(unit)
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(warning ? .red : color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(warning ? 0.20 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(warning ? 0.45 : 0.14), lineWidth: 1)
                )
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Landscape G-Force Value Display Item
// ─────────────────────────────────────────────────────────────────────────────

public struct LandscapeGValueItem: View {
    public let label: String
    public let val: String
    public let color: Color

    public init(label: String, val: String, color: Color) {
        self.label = label
        self.val = val
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0.5) {
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
            Text(val)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: HandyModusLandscapeView Extension (Lyrics & Stats Grid)
// ─────────────────────────────────────────────────────────────────────────────

extension HandyModusLandscapeView {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Widescreen Lyrics Card
    // ─────────────────────────────────────────────────────────────────────────

    internal func landscapeLyricsCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Track Header
            HStack(spacing: 8) {
                Image(systemName: observer.isPlaying ? "music.note.list" : "pause.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(observer.isPlaying ? .cyan : .secondary)
                    .symbolEffect(.bounce, value: observer.isPlaying)

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(observer.currentTrackTitle.isEmpty ? "Kein Titel" : observer.currentTrackTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(observer.currentArtist.isEmpty ? "–" : observer.currentArtist)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                lyricsStatusBadge
            }
            .padding(.bottom, 4)

            // Progress Bar
            GeometryReader { pGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, Color(red: 0.3, green: 0.9, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: pGeo.size.width * CGFloat(observer.progress), height: 2.5)
                }
            }
            .frame(height: 2.5)
            .padding(.bottom, 5)

            // Lyrics Context: Prev, Current (highlighted), Next
            VStack(spacing: 2.5) {
                if !observer.previousLine.isEmpty {
                    Text(observer.previousLine)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }

                Text(observer.currentLine.isEmpty ? "♪" : observer.currentLine)
                    .font(.system(size: 15.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .cyan.opacity(0.65), radius: 8)
                    .lineLimit(2)
                    .id(observer.currentLine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.2), value: observer.currentLine)

                if !observer.nextLine.isEmpty {
                    Text(observer.nextLine)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 8-Tile Performance Stats Matrix
    // ─────────────────────────────────────────────────────────────────────────

    internal func landscapeStatsMatrix(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            // Row 1
            HStack(spacing: 5) {
                LandscapeStatTile(icon: "speedometer", label: "SPEED", value: speedStr, unit: "KM/H", color: .cyan)
                LandscapeStatTile(icon: "thermometer.medium", label: "WASSER", value: coolantStr, unit: "°C", color: .cyan, warning: coolantWarning)
                LandscapeStatTile(icon: "bolt.fill", label: "BATTERIE", value: battStr, unit: "VOLT", color: .yellow, warning: battWarning)
                LandscapeStatTile(icon: "waveform.path", label: "LUFTMASSE", value: mafStr, unit: "G/S", color: Color(red: 0.4, green: 0.8, blue: 1.0))
            }
            // Row 2
            HStack(spacing: 5) {
                LandscapeStatTile(icon: "wind", label: "ANSAUGLUFT", value: iatStr, unit: "°C", color: Color(red: 0.3, green: 0.9, blue: 0.8))
                LandscapeStatTile(icon: "gauge.open.with.lines.needle.33percent", label: "LAST", value: loadStr, unit: "%", color: .orange)
                LandscapeStatTile(icon: "flame.fill", label: "ABGAS", value: exhaustStr, unit: "°C", color: Color(red: 1.0, green: 0.45, blue: 0.1), warning: exhaustWarning)
                LandscapeStatTile(icon: "scope", label: "G-PEAK", value: String(format: "%.2f", motion.peakG), unit: "G", color: purple)
            }
        }
        .frame(width: width, height: height)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Computed Telemetry Properties
    // ─────────────────────────────────────────────────────────────────────────

    internal var speedStr: String {
        obd.isEnabled && obd.connectionState == .connected ? "\(obd.liveSpeed)" : "--"
    }

    internal var coolantStr: String {
        if let c = obd.liveCoolantTemp { return "\(c)" }
        return "--"
    }

    internal var battStr: String {
        if let v = obd.batteryVoltage { return String(format: "%.1f", v) }
        return "--"
    }

    internal var mafStr: String {
        if let m = obd.liveMAF { return String(format: "%.1f", m) }
        return "--"
    }

    internal var iatStr: String {
        if let t = obd.liveIAT { return "\(t)" }
        return "--"
    }

    internal var loadStr: String {
        if let l = obd.liveEngineLoad { return "\(l)" }
        return "--"
    }

    internal var exhaustStr: String {
        if let e = obd.estimatedExhaustTemp { return "\(e)" }
        return "--"
    }

    internal var battWarning: Bool {
        guard let v = obd.batteryVoltage else { return false }
        return v < 12.2 || v > 15.2
    }

    internal var exhaustWarning: Bool {
        guard let e = obd.estimatedExhaustTemp else { return false }
        return e > 780
    }

    internal var coolantWarning: Bool {
        guard let c = obd.liveCoolantTemp else { return false }
        return c > 105
    }

    @ViewBuilder
    internal var lyricsStatusBadge: some View {
        switch observer.lyricsStatus {
        case .loading:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.5).tint(.cyan)
                Text("Lyrics…")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.cyan)
            }
        case .loaded:
            Label("SYNC", systemImage: "waveform")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.green)
        case .error:
            Button {
                observer.retryLyrics()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "wifi.slash")
                    Text("RETRY")
                }
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.orange.opacity(0.15), in: Capsule())
            }
        case .idle:
            EmptyView()
        }
    }

    internal func connectionPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
    }

    internal var obdLabel: String {
        guard obd.isEnabled else { return "OBD AUS" }
        switch obd.connectionState {
        case .connected:                              return "OBD LIVE"
        case .scanning, .connecting, .initializing:  return "VERBINDET…"
        default:                                      return "OBD GETRENNT"
        }
    }

    internal var obdPillColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected:                              return .green
        case .scanning, .connecting, .initializing:  return .orange
        default:                                      return .red
        }
    }

    internal func gColor(_ g: Double, maxG: Double) -> Color {
        let ratio = maxG > 0 ? g / maxG : 0
        switch ratio {
        case ..<0.5: return .green
        case 0.5..<0.75: return .yellow
        default: return .red
        }
    }
}
