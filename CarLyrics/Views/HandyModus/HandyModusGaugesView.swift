// MARK: - HandyModusGaugesView.swift
// RPM-Tachometer, Ladedruck-Arc und Öltemperatur-Ring für den Handy-Modus
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: RPM Tachometer Arc  (0 – 7000 RPM, Redline 6500)
// ─────────────────────────────────────────────────────────────────────────────

public struct RPMTachometerView: View {
    public let rpm: Int
    public var maxRPM: Int = 7000
    public var redlineRPM: Int = 6500
    public var size: CGFloat = 160

    public init(rpm: Int, maxRPM: Int = 7000, redlineRPM: Int = 6500, size: CGFloat = 160) {
        self.rpm = rpm
        self.maxRPM = maxRPM
        self.redlineRPM = redlineRPM
        self.size = size
    }

    private var ratio: Double {
        min(1.0, Double(max(0, rpm)) / Double(max(1, maxRPM)))
    }

    private var redlineRatio: Double {
        Double(redlineRPM) / Double(maxRPM)
    }

    private var arcColor: Color {
        let r = ratio
        if r < 0.55 { return .cyan }
        if r < 0.82 { return .green }
        if r < redlineRatio { return .orange }
        return .red
    }

    public var body: some View {
        ZStack {
            // Background track
            Circle()
                .trim(from: 0.10, to: 0.90)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Redline zone
            Circle()
                .trim(from: 0.10 + 0.80 * redlineRatio, to: 0.90)
                .stroke(Color.red.opacity(0.25), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Live fill arc
            Circle()
                .trim(from: 0.10, to: 0.10 + CGFloat(ratio) * 0.80)
                .stroke(
                    LinearGradient(
                        colors: [arcColor.opacity(0.6), arcColor],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.interactiveSpring(response: 0.18), value: ratio)
                .shadow(color: arcColor.opacity(0.7), radius: 8)

            // Center text
            VStack(spacing: 2) {
                Text("\(rpm)")
                    .font(.system(size: size * 0.22, weight: .black, design: .monospaced))
                    .foregroundStyle(arcColor)
                    .minimumScaleFactor(0.5)
                    .animation(.interactiveSpring(response: 0.18), value: rpm)
                Text("RPM")
                    .font(.system(size: size * 0.09, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Boost Arc  (−0.5 … +1.5 bar)
// ─────────────────────────────────────────────────────────────────────────────

public struct BoostArcView: View {
    public let boost: Double?   // in Bar relativ (nil = kein OBD)
    public var size: CGFloat = 140

    public init(boost: Double?, size: CGFloat = 140) {
        self.boost = boost
        self.size = size
    }

    private static let minBar = -0.5
    private static let maxBar =  1.5

    private var ratio: Double {
        guard let b = boost else { return 0.0 }
        let normalised = (b - Self.minBar) / (Self.maxBar - Self.minBar)
        return min(1.0, max(0.0, normalised))
    }

    private var zeroRatio: Double {
        (0.0 - Self.minBar) / (Self.maxBar - Self.minBar)
    }

    private var boostColor: Color {
        guard let b = boost else { return .secondary }
        if b < -0.1  { return .cyan }
        if b < 0.5   { return Color(red: 0.3, green: 0.9, blue: 0.5) }
        if b < 1.0   { return .orange }
        return Color(red: 1.0, green: 0.3, blue: 0.15)
    }

    public var body: some View {
        ZStack {
            // Background track
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Zero line tick
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 2, height: size * 0.10)
                .offset(y: -(size / 2 - size * 0.06))
                .rotationEffect(.degrees(135 + 360 * 0.76 * zeroRatio))

            // Fill arc from zero
            let low  = 0.12 + CGFloat(min(ratio, zeroRatio)) * 0.76
            let high = 0.12 + CGFloat(max(ratio, zeroRatio)) * 0.76
            Circle()
                .trim(from: low, to: max(low + 0.001, high))
                .stroke(
                    LinearGradient(
                        colors: [boostColor.opacity(0.5), boostColor],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.interactiveSpring(response: 0.14), value: ratio)
                .shadow(color: boostColor.opacity(0.8), radius: 7)

            // Center text
            VStack(spacing: 1) {
                if let b = boost {
                    Text(String(format: "%+.2f", b))
                        .font(.system(size: size * 0.18, weight: .black, design: .monospaced))
                        .foregroundStyle(boostColor)
                        .animation(.interactiveSpring(response: 0.14), value: b)
                } else {
                    Text("--")
                        .font(.system(size: size * 0.18, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("BAR")
                    .font(.system(size: size * 0.085, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text("LADEDRUCK")
                    .font(.system(size: size * 0.06, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Oil Temp Ring  (0 – 130°C)
// ─────────────────────────────────────────────────────────────────────────────

public struct OilTempRingView: View {
    public let tempC: Int?
    public var size: CGFloat = 120

    public init(tempC: Int?, size: CGFloat = 120) {
        self.tempC = tempC
        self.size = size
    }

    private var ratio: Double {
        guard let t = tempC else { return 0.0 }
        return min(1.0, max(0.0, Double(t) / 130.0))
    }

    private var tempColor: Color {
        guard let t = tempC else { return .secondary }
        if t < 50  { return .cyan }
        if t < 80  { return Color(red: 0.2, green: 0.8, blue: 1.0) }
        if t < 100 { return Color(red: 0.3, green: 0.9, blue: 0.5) }
        if t < 115 { return .orange }
        return .red
    }

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0.12, to: 0.12 + CGFloat(ratio) * 0.76)
                .stroke(
                    LinearGradient(
                        colors: [tempColor.opacity(0.5), tempColor],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.interactiveSpring(response: 0.3), value: ratio)
                .shadow(color: tempColor.opacity(0.7), radius: 6)

            VStack(spacing: 1) {
                if let t = tempC {
                    Text("\(t)°")
                        .font(.system(size: size * 0.20, weight: .black, design: .monospaced))
                        .foregroundStyle(tempColor)
                } else {
                    Text("--°")
                        .font(.system(size: size * 0.20, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("ÖL °C")
                    .font(.system(size: size * 0.09, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widescreen Racing Tacho Console (Landscape-Native)
// ─────────────────────────────────────────────────────────────────────────────

public struct WidescreenTachoConsole: View {
    @ObservedObject public var obd: OBDManager
    public var width: CGFloat
    public var height: CGFloat

    public init(obd: OBDManager, width: CGFloat, height: CGFloat) {
        self.obd = obd
        self.width = width
        self.height = height
    }

    private var rpmRatio: Double {
        min(1.0, max(0.0, Double(obd.liveRPM) / 7000.0))
    }

    public var body: some View {
        VStack(spacing: 3) {
            // ── 1. Shift-Light LED Bar (F1 / GT3 Style) ──────────────────────
            shiftLightBar
                .padding(.horizontal, 10)
                .padding(.top, 4)

            // ── 2. Triple Cluster (Öl links | Speed & RPM Mitte | Boost rechts) ─
            HStack(alignment: .center, spacing: 4) {
                // Links: Öl-Pod
                oilPod
                    .frame(maxWidth: .infinity)

                // Mitte: Digital Speedometer & Hero RPM
                centerHeroPod
                    .frame(maxWidth: .infinity * 1.35)

                // Rechts: Ladedruck Pod
                boostPod
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    // ── LED Shift-Light Bar ───────────────────────────────────────────────────

    private var shiftLightBar: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<14, id: \.self) { idx in
                let threshold = Double(idx + 1) / 14.0
                let isLit = rpmRatio >= threshold
                let color: Color = idx < 6 ? .green : (idx < 10 ? .yellow : (idx < 12 ? .orange : .red))

                RoundedRectangle(cornerRadius: 2)
                    .fill(isLit ? color : Color.white.opacity(0.08))
                    .frame(height: 5.5)
                    .shadow(color: isLit ? color.opacity(0.8) : .clear, radius: 4)
            }
        }
    }

    // ── Center Hero Pod: Speed & RPM ──────────────────────────────────────────

    private var centerHeroPod: some View {
        VStack(spacing: 0) {
            // KM/H Digit Display
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(obd.isEnabled && obd.connectionState == .connected ? "\(obd.liveSpeed)" : "--")
                    .font(.system(size: min(34, height * 0.28), weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("KM/H")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // RPM Mini Tachometer Arc (Compact)
            RPMTachometerView(rpm: obd.liveRPM, size: min(92, height * 0.52))

            Text(obd.isEnabled && obd.connectionState == .connected ? "LIVE OBD" : "SIMULATION")
                .font(.system(size: 6.5, weight: .black, design: .rounded))
                .foregroundStyle(obd.isEnabled && obd.connectionState == .connected ? .green.opacity(0.8) : .cyan.opacity(0.8))
        }
    }

    // ── Left Pod: Oil Temperature ─────────────────────────────────────────────

    private var oilPod: some View {
        VStack(spacing: 2) {
            OilTempRingView(tempC: obd.effectiveOilTemp, size: min(78, height * 0.48))
            Text(obd.hasOilTempPID ? "ÖL DIREKT" : "ÖL MODELL")
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // ── Right Pod: Boost Pressure ─────────────────────────────────────────────

    private var boostPod: some View {
        VStack(spacing: 2) {
            BoostArcView(
                boost: obd.isEnabled && obd.connectionState == .connected ? obd.liveBoostBar : nil,
                size: min(78, height * 0.48)
            )
            Text(obd.liveMAP != nil ? "MAP DIREKT" : "MAF BERECHN.")
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}
