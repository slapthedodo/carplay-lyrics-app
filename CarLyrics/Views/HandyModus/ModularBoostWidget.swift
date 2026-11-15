// MARK: - ModularBoostWidget.swift
// Voll modularer, frei anpassbarer Ladedruck-Balken für den Handy-Modus
// Unterstützt: Quer (Horizontal), Hochkant (Vertikal), Rund (Arc), 4 Dicken & Peak-Hold
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public enum BoostWidgetOrientation: String, Codable, CaseIterable {
    case horizontal = "Quer"
    case vertical   = "Hochkant"
    case arc        = "Rund"
}

public enum BoostWidgetThickness: String, Codable, CaseIterable {
    case thin    = "Dünn"
    case medium  = "Normal"
    case thick   = "Dick"
    case massive = "Massiv"

    public var barPoints: CGFloat {
        switch self {
        case .thin:    return 8
        case .medium:  return 16
        case .thick:   return 26
        case .massive: return 40
        }
    }
}

public struct BoostWidgetConfig: Codable, Equatable {
    public var orientation: BoostWidgetOrientation = .horizontal
    public var thickness: BoostWidgetThickness = .medium
    public var showNumeric: Bool = true
    public var showPeak: Bool = true
    public var customWidth: CGFloat = 0 // 0 = flexibel
    public var customHeight: CGFloat = 0

    public init(
        orientation: BoostWidgetOrientation = .horizontal,
        thickness: BoostWidgetThickness = .medium,
        showNumeric: Bool = true,
        showPeak: Bool = true,
        customWidth: CGFloat = 0,
        customHeight: CGFloat = 0
    ) {
        self.orientation = orientation
        self.thickness = thickness
        self.showNumeric = showNumeric
        self.showPeak = showPeak
        self.customWidth = customWidth
        self.customHeight = customHeight
    }
}

public struct ModularBoostWidget: View {
    public let boost: Double?
    @ObservedObject private var studio = HandyLayoutStudioManager.shared

    @State private var peakBoost: Double = 0.0
    @State private var peakTimerTask: Task<Void, Never>? = nil

    public init(boost: Double?) {
        self.boost = boost
    }

    private var config: BoostWidgetConfig {
        studio.boostConfig
    }

    private static let minBar: Double = -0.5
    private static let maxBar: Double = 1.5

    private var effectiveBoost: Double {
        boost ?? 0.0
    }

    private var ratio: Double {
        let clamped = max(Self.minBar, min(Self.maxBar, effectiveBoost))
        return (clamped - Self.minBar) / (Self.maxBar - Self.minBar)
    }

    private var zeroRatio: Double {
        (0.0 - Self.minBar) / (Self.maxBar - Self.minBar)
    }

    private var boostColor: Color {
        guard let b = boost else { return .secondary }
        if b < -0.05 { return .cyan }
        if b < 0.60  { return Color(red: 0.3, green: 0.95, blue: 0.45) }
        if b < 1.10  { return .orange }
        return Color(red: 1.0, green: 0.25, blue: 0.15)
    }

    public var body: some View {
        Group {
            switch config.orientation {
            case .horizontal:
                horizontalBarView
            case .vertical:
                verticalBarView
            case .arc:
                BoostArcView(boost: boost, size: 120)
            }
        }
        .onChange(of: effectiveBoost) { _, newB in
            if newB > peakBoost {
                peakBoost = newB
                peakTimerTask?.cancel()
                peakTimerTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.8)) {
                        peakBoost = max(0.0, effectiveBoost)
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Horizontaler Ladedruck-Balken (Quer)
    // ─────────────────────────────────────────────────────────────────────────

    private var horizontalBarView: some View {
        VStack(spacing: 6) {
            // Header Info
            if config.showNumeric {
                HStack(alignment: .lastTextBaseline) {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(boostColor)
                        Text("LADEDRUCK")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    if config.showPeak && peakBoost > 0.05 {
                        Text(String(format: "PEAK %+.2f", peakBoost))
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }

                    if let b = boost {
                        Text(String(format: "%+.2f", b))
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(boostColor)
                        Text("BAR")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        Text("--.-- BAR")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Der eigentliche dynamische Balken
            GeometryReader { geo in
                let w = geo.size.width
                let h = config.thickness.barPoints
                let zeroX = w * CGFloat(zeroRatio)
                let currentX = w * CGFloat(ratio)

                ZStack(alignment: .leading) {
                    // Hintergrund-Track mit Glass-Effekt
                    RoundedRectangle(cornerRadius: h / 2)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: h / 2)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )

                    // Vakuum-Markierung (-0.5 bis 0 bar in cyan)
                    if currentX < zeroX {
                        let fillW = max(2, zeroX - currentX)
                        RoundedRectangle(cornerRadius: h / 2)
                            .fill(LinearGradient(colors: [.cyan.opacity(0.5), .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: fillW, height: h)
                            .offset(x: currentX)
                            .shadow(color: .cyan.opacity(0.7), radius: 6)
                    } else {
                        // Ladedruck-Füllung (0 bis +1.5 bar in Grün/Orange/Rot)
                        let fillW = max(2, currentX - zeroX)
                        RoundedRectangle(cornerRadius: h / 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, boostColor],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: fillW, height: h)
                            .offset(x: zeroX)
                            .shadow(color: boostColor.opacity(0.8), radius: 8)
                    }

                    // 0.0 Bar Null-Linien Markierung
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: h + 4)
                        .offset(x: zeroX - 1)
                        .shadow(color: .white.opacity(0.8), radius: 3)

                    // Peak Hold Marker
                    if config.showPeak && peakBoost > 0 {
                        let peakX = w * CGFloat(min(1.0, (peakBoost - Self.minBar) / (Self.maxBar - Self.minBar)))
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2.5, height: h + 4)
                            .offset(x: max(0, min(w - 2.5, peakX - 1.25)))
                            .shadow(color: .orange, radius: 4)
                    }
                }
                .frame(height: h)
            }
            .frame(height: config.thickness.barPoints + 4)

            // Skala-Beschriftung
            HStack {
                Text("-0.5")
                Spacer()
                Text("0.0")
                Spacer()
                Text("+0.5")
                Spacer()
                Text("+1.0")
                Spacer()
                Text("+1.5 BAR")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Vertikaler Ladedruck-Balken (Hochkant)
    // ─────────────────────────────────────────────────────────────────────────

    private var verticalBarView: some View {
        HStack(spacing: 12) {
            // Vertikaler Runway
            GeometryReader { geo in
                let h = geo.size.height
                let w = config.thickness.barPoints
                let zeroY = h * (1.0 - CGFloat(zeroRatio))
                let currentY = h * (1.0 - CGFloat(ratio))

                ZStack(alignment: .bottom) {
                    // Track
                    RoundedRectangle(cornerRadius: w / 2)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: w / 2).stroke(Color.white.opacity(0.15), lineWidth: 0.8))

                    // Fill
                    if currentY > zeroY {
                        // Vakuum
                        let fillH = max(2, currentY - zeroY)
                        RoundedRectangle(cornerRadius: w / 2)
                            .fill(Color.cyan)
                            .frame(width: w, height: fillH)
                            .offset(y: -(h - currentY))
                    } else {
                        // Überdruck
                        let fillH = max(2, zeroY - currentY)
                        RoundedRectangle(cornerRadius: w / 2)
                            .fill(
                                LinearGradient(colors: [boostColor, .green], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: w, height: fillH)
                            .offset(y: -(h - zeroY))
                            .shadow(color: boostColor.opacity(0.8), radius: 8)
                    }

                    // Null-Linie
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: w + 4, height: 2)
                        .offset(y: -(h - zeroY - 1))
                }
                .frame(width: w)
            }
            .frame(width: config.thickness.barPoints + 4, height: max(120, config.customHeight > 0 ? config.customHeight : 150))

            // Text daneben
            VStack(alignment: .leading, spacing: 4) {
                Text("LADEDRUCK")
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                if let b = boost {
                    Text(String(format: "%+.2f", b))
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(boostColor)
                    Text("BAR")
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Text("--.--")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if config.showPeak && peakBoost > 0.05 {
                    Text(String(format: "MAX: %+.2f", peakBoost))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}
