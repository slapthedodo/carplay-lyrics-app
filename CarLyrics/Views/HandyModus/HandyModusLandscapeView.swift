// MARK: - HandyModusLandscapeView.swift
// Widescreen Racing Cockpit für den Querformat-Einsatz im Handy-Halter
// Inspiriert vom Hochkantformat: Gauges, G-Kräfte, Lyrics & 8-Tile Stats Matrix
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct HandyModusLandscapeView: View {
    @ObservedObject public var observer : MusicObserver
    @ObservedObject public var obd      : OBDManager
    @ObservedObject public var motion   : MotionManager
    @ObservedObject public var warmup   : WarmupManager

    private let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public init(observer: MusicObserver,
                obd:      OBDManager,
                motion:   MotionManager,
                warmup:   WarmupManager) {
        self.observer = observer
        self.obd      = obd
        self.motion   = motion
        self.warmup   = warmup
    }

    public var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let leadPad = max(insets.leading, 12)
            let trailPad = max(insets.trailing, 12)
            let bottomPad = max(insets.bottom, 6)
            let topPad = max(insets.top, 4)

            let usableW = geo.size.width - leadPad - trailPad
            let usableH = geo.size.height - topPad - bottomPad

            let topBarH: CGFloat = 24
            let vSpacing: CGFloat = 6
            let hSpacing: CGFloat = 10
            let availableH = max(260, usableH - topBarH - vSpacing)

            let leftW = (usableW - hSpacing) * 0.48
            let rightW = (usableW - hSpacing) * 0.52

            let gaugesCardH = availableH * 0.54
            let gForceCardH = availableH * 0.46 - vSpacing
            let lyricsCardH = availableH * 0.58
            let statsCardH  = availableH * 0.42 - vSpacing

            VStack(spacing: vSpacing) {
                topBar.frame(width: usableW, height: topBarH)

                HStack(alignment: .top, spacing: hSpacing) {
                    VStack(spacing: vSpacing) {
                        landscapeGaugesCard(width: leftW, height: gaugesCardH)
                        landscapeGForceCard(width: leftW, height: gForceCardH)
                    }
                    .frame(width: leftW, height: availableH)

                    VStack(spacing: vSpacing) {
                        landscapeLyricsCard(width: rightW, height: lyricsCardH)
                        landscapeStatsMatrix(width: rightW, height: statsCardH)
                    }
                    .frame(width: rightW, height: availableH)
                }
                .frame(width: usableW, height: availableH)
            }
            .padding(.leading, leadPad)
            .padding(.trailing, trailPad)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(
            Group {
                if obd.isColdOverloaded {
                    ColdEngineOverloadFlashOverlay(title: obd.coldOverloadMessage, detail: obd.coldOverloadDetail)
                }
            }
        )
    }

    // ── 1. Top Status Bar ─────────────────────────────────────────────────────

    private var topBar: some View {
        HStack(spacing: 8) {
            connectionPill(label: obdLabel, color: obdPillColor, icon: "cable.connector")
            if !obd.isEnabled {
                connectionPill(label: "SIMULATION", color: .cyan, icon: "waveform")
            }
            Spacer()
            if !observer.currentTrackTitle.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "music.note").font(.system(size: 8)).foregroundStyle(.cyan)
                    Text("\(observer.currentTrackTitle) • \(observer.currentArtist)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.yellow)
                Text("Kein Standby").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.yellow.opacity(0.85))
            }
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Color.yellow.opacity(0.12), in: Capsule())
        }
    }

    // ── 2. Left Column: Main Gauges Card ──────────────────────────────────────

    private func landscapeGaugesCard(width: CGFloat, height: CGFloat) -> some View {
        let rpmSize  = min(118, height * 0.70)
        let ringSize = min(86, height * 0.54)

        return HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 2) {
                OilTempRingView(tempC: obd.effectiveOilTemp, size: ringSize)
                Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.35))
            }.frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                RPMTachometerView(rpm: obd.liveRPM, size: rpmSize)
                Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                    .font(.system(size: 7, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.35))
            }.frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                BoostArcView(boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil, size: ringSize)
                Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.35))
            }.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // ── 3. Left Column: G-Kräfte Scope Card ───────────────────────────────────

    private func landscapeGForceCard(width: CGFloat, height: CGFloat) -> some View {
        let gBallSize = min(72, height * 0.56)
        let badgeSize = min(66, height * 0.52)

        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.system(size: 9.5, weight: .bold)).foregroundStyle(purple)
                Text("G-KRÄFTE").font(.system(size: 9, weight: .black, design: .rounded)).foregroundStyle(purple.opacity(0.85))
                Spacer()
                Button { motion.calibrate() } label: {
                    if motion.isCalibrating {
                        HStack(spacing: 2.5) {
                            ProgressView().scaleEffect(0.5).tint(purple)
                            Text("1s…").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundStyle(purple)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2).background(purple.opacity(0.2), in: Capsule())
                    } else {
                        HStack(spacing: 2.5) { Image(systemName: "scope"); Text("Nullpunkt") }
                            .font(.system(size: 7.5, weight: .bold)).foregroundStyle(purple.opacity(0.95))
                            .padding(.horizontal, 5).padding(.vertical, 2).background(purple.opacity(0.14), in: Capsule())
                    }
                }.disabled(motion.isCalibrating)

                Button { motion.resetPeak() } label: {
                    HStack(spacing: 2.5) { Image(systemName: "arrow.counterclockwise"); Text("Peak") }
                        .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.orange.opacity(0.9))
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange.opacity(0.14), in: Capsule())
                }
            }

            HStack(alignment: .center, spacing: 8) {
                GBallView(x: motion.normalizedX, y: motion.normalizedY, currentG: motion.currentG, maxG: motion.maxG)
                    .frame(width: gBallSize, height: gBallSize)
                    .background(Circle().fill(Color.black.opacity(0.45)))

                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        gValueItem(label: "AKTUELL", val: motion.currentGFormatted, color: gColor(motion.currentG, maxG: motion.maxG))
                        gValueItem(label: "PEAK", val: motion.peakGFormatted, color: .orange)
                    }
                    HStack(spacing: 6) {
                        gValueItem(label: "LATERAL", val: String(format: "%.2fG", abs(motion.gX)), color: purple.opacity(0.85))
                        gValueItem(label: "LÄNGS", val: String(format: "%.2fG", abs(motion.gY)), color: purple.opacity(0.85))
                    }
                }.frame(maxWidth: .infinity)

                GForceGaugeBadge(currentG: motion.currentG, maxG: motion.maxG, size: badgeSize)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(purple.opacity(0.22), lineWidth: 1))
        )
    }

    private func gValueItem(label: String, val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0.5) {
            Text(label).font(.system(size: 6, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.35))
            Text(val).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 4. Right Column: Widescreen Lyrics Card ───────────────────────────────

    private func landscapeLyricsCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: observer.isPlaying ? "music.note.list" : "pause.circle.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(observer.isPlaying ? .cyan : .secondary)
                    .symbolEffect(.bounce, value: observer.isPlaying)
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(observer.currentTrackTitle.isEmpty ? "Kein Titel" : observer.currentTrackTitle)
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(observer.currentArtist.isEmpty ? "–" : observer.currentArtist)
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                lyricsStatusBadge
            }.padding(.bottom, 4)

            GeometryReader { pGeo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 2.5)
                    Capsule().fill(LinearGradient(colors: [.cyan, Color(red: 0.3, green: 0.9, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: pGeo.size.width * CGFloat(observer.progress), height: 2.5)
                }
            }.frame(height: 2.5).padding(.bottom, 5)

            VStack(spacing: 2.5) {
                if !observer.previousLine.isEmpty {
                    Text(observer.previousLine)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                }
                Text(observer.currentLine.isEmpty ? "♪" : observer.currentLine)
                    .font(.system(size: 15.5, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).shadow(color: .cyan.opacity(0.65), radius: 8).lineLimit(2)
                    .id(observer.currentLine)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                    .animation(.easeInOut(duration: 0.2), value: observer.currentLine)
                if !observer.nextLine.isEmpty {
                    Text(observer.nextLine)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.18), lineWidth: 1))
        )
    }

    // ── 5. Right Column: 8-Tile Performance Stats Matrix ──────────────────────

    private func landscapeStatsMatrix(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                LandscapeStatTile(icon: "speedometer", label: "SPEED", value: speedStr, unit: "KM/H", color: .cyan)
                LandscapeStatTile(icon: "thermometer.medium", label: "WASSER", value: coolantStr, unit: "°C", color: .cyan, warning: coolantWarning)
                LandscapeStatTile(icon: "bolt.fill", label: "BATTERIE", value: battStr, unit: "VOLT", color: .yellow, warning: battWarning)
                LandscapeStatTile(icon: "waveform.path", label: "LUFTMASSE", value: mafStr, unit: "G/S", color: Color(red: 0.4, green: 0.8, blue: 1.0))
            }
            HStack(spacing: 5) {
                LandscapeStatTile(icon: "wind", label: "ANSAUGLUFT", value: iatStr, unit: "°C", color: Color(red: 0.3, green: 0.9, blue: 0.8))
                LandscapeStatTile(icon: "gauge.open.with.lines.needle.33percent", label: "LAST", value: loadStr, unit: "%", color: .orange)
                LandscapeStatTile(icon: "flame.fill", label: "ABGAS", value: exhaustStr, unit: "°C", color: Color(red: 1.0, green: 0.45, blue: 0.1), warning: exhaustWarning)
                LandscapeStatTile(icon: "scope", label: "G-PEAK", value: String(format: "%.2f", motion.peakG), unit: "G", color: purple)
            }
        }.frame(width: width, height: height)
    }

    // ── 6. Computed Telemetry & Helpers ───────────────────────────────────────

    private var speedStr: String   { obd.isEnabled && obd.connectionState == .connected ? "\(obd.liveSpeed)" : "--" }
    private var coolantStr: String { obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!)" : "--" }
    private var battStr: String    { obd.batteryVoltage != nil ? String(format: "%.1f", obd.batteryVoltage!) : "--" }
    private var mafStr: String     { obd.liveMAF != nil ? String(format: "%.1f", obd.liveMAF!) : "--" }
    private var iatStr: String     { obd.liveIAT != nil ? "\(obd.liveIAT!)" : "--" }
    private var loadStr: String    { obd.liveEngineLoad != nil ? "\(obd.liveEngineLoad!)" : "--" }
    private var exhaustStr: String { obd.estimatedExhaustTemp != nil ? "\(obd.estimatedExhaustTemp!)" : "--" }
    private var battWarning: Bool  { guard let v = obd.batteryVoltage else { return false }; return v < 12.2 || v > 15.2 }
    private var exhaustWarning: Bool { guard let e = obd.estimatedExhaustTemp else { return false }; return e > 780 }
    private var coolantWarning: Bool { guard let c = obd.liveCoolantTemp else { return false }; return c > 105 }

    @ViewBuilder
    private var lyricsStatusBadge: some View {
        switch observer.lyricsStatus {
        case .loading:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.5).tint(.cyan)
                Text("Lyrics…").font(.system(size: 8, weight: .bold)).foregroundStyle(.cyan)
            }
        case .loaded:
            Label("SYNC", systemImage: "waveform").font(.system(size: 8, weight: .black)).foregroundStyle(.green)
        case .error:
            Button { observer.retryLyrics() } label: {
                HStack(spacing: 2) { Image(systemName: "wifi.slash"); Text("RETRY") }
                    .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.orange)
                    .padding(.horizontal, 4).padding(.vertical, 1.5).background(Color.orange.opacity(0.15), in: Capsule())
            }
        case .idle:
            EmptyView()
        }
    }

    private func connectionPill(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Image(systemName: icon).font(.system(size: 7.5, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 7.5, weight: .black, design: .rounded)).foregroundStyle(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
    }

    private var obdLabel: String {
        guard obd.isEnabled else { return "OBD AUS" }
        switch obd.connectionState {
        case .connected: return "OBD LIVE"
        case .scanning, .connecting, .initializing: return "VERBINDET…"
        default: return "OBD GETRENNT"
        }
    }

    private var obdPillColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .initializing: return .orange
        default: return .red
        }
    }

    private func gColor(_ g: Double, maxG: Double) -> Color {
        let ratio = maxG > 0 ? g / maxG : 0
        switch ratio {
        case ..<0.5: return .green
        case 0.5..<0.75: return .yellow
        default: return .red
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Landscape Mini Stat Tile
// ─────────────────────────────────────────────────────────────────────────────

private struct LandscapeStatTile: View {
    let icon    : String
    let label   : String
    let value   : String
    let unit    : String
    let color   : Color
    var warning : Bool = false

    var body: some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(warning ? .red : color)
                Spacer(minLength: 0)
                Text(unit).font(.system(size: 6.5, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.4))
            }
            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(warning ? .red : color).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
        }
        .padding(.horizontal, 5).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(warning ? 0.20 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(warning ? 0.45 : 0.14), lineWidth: 1))
        )
    }
}
