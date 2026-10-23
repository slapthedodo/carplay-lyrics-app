// MARK: - HandyModusStatsBar.swift
// Statistische Werte: IAT, MAF, Batterie, Speed, Auspufftemperatur (geschätzt)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Einzelne Stat-Kachel
// ─────────────────────────────────────────────────────────────────────────────

struct StatTile: View {
    let icon    : String
    let label   : String
    let value   : String
    let unit    : String
    let color   : Color
    var warning : Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(warning ? .red : color)

            Text(value)
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundStyle(warning ? .red : color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(unit)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)

            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(warning ? 0.15 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(warning ? 0.35 : 0.12), lineWidth: 1)
                )
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Auspuff-Temp Kalkulation (EA113 2.0 TFSI Schätzmodell)
// ─────────────────────────────────────────────────────────────────────────────

public extension OBDManager {
    /// Liefert die thermisch geglättete Abgastemperatur (PT1-gefiltert, kein Springen)
    var estimatedExhaustTemp: Int? {
        liveEGT
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Stats Bar (2-Reihen Grid)
// ─────────────────────────────────────────────────────────────────────────────

public struct HandyModusStatsBar: View {
    @ObservedObject public var obd    : OBDManager
    @ObservedObject public var motion : MotionManager

    public init(obd: OBDManager, motion: MotionManager) {
        self.obd    = obd
        self.motion = motion
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Computed display values
    // ─────────────────────────────────────────────────────────────────────────

    private var speedStr: String {
        obd.isEnabled && obd.connectionState == .connected ? "\(obd.liveSpeed)" : "--"
    }

    private var iatStr: String {
        if let t = obd.liveIAT { return "\(t)" }
        return "--"
    }

    private var mafStr: String {
        if let m = obd.liveMAF { return String(format: "%.1f", m) }
        return "--"
    }

    private var battStr: String {
        if let v = obd.batteryVoltage { return String(format: "%.1f", v) }
        return "--"
    }

    private var loadStr: String {
        if let l = obd.liveEngineLoad { return "\(l)" }
        return "--"
    }

    private var exhaustStr: String {
        if let e = obd.estimatedExhaustTemp { return "\(e)" }
        return "--"
    }

    private var battWarning: Bool {
        guard let v = obd.batteryVoltage else { return false }
        return v < 12.2 || v > 15.2
    }

    private var exhaustWarning: Bool {
        guard let e = obd.estimatedExhaustTemp else { return false }
        return e > 780
    }

    private var coolantStr: String {
        if let c = obd.liveCoolantTemp { return "\(c)" }
        return "--"
    }

    private var coolantWarning: Bool {
        guard let c = obd.liveCoolantTemp else { return false }
        return c > 105
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Body
    // ─────────────────────────────────────────────────────────────────────────

    public var body: some View {
        VStack(spacing: 8) {
            // Row 1
            HStack(spacing: 8) {
                StatTile(icon: "speedometer",        label: "SPEED",    value: speedStr,   unit: "KM/H",  color: .cyan)
                StatTile(icon: "thermometer.medium", label: "KÜHLWASSER",value: coolantStr, unit: "°C",   color: .cyan,   warning: coolantWarning)
                StatTile(icon: "bolt.fill",          label: "BATTERIE", value: battStr,    unit: "VOLT",  color: .yellow, warning: battWarning)
                StatTile(icon: "waveform.path",      label: "LUFTMASSE", value: mafStr,    unit: "G/S",   color: Color(red: 0.4, green: 0.8, blue: 1.0))
            }
            // Row 2
            HStack(spacing: 8) {
                StatTile(icon: "wind",               label: "ANSAUGLUFT", value: iatStr,   unit: "°C",   color: Color(red: 0.3, green: 0.9, blue: 0.8))
                StatTile(icon: "gauge.open.with.lines.needle.33percent",
                                                     label: "LAST",      value: loadStr,  unit: "%",    color: .orange)
                StatTile(icon: "flame.fill",         label: "ABGAS EST.",value: exhaustStr, unit: "°C", color: Color(red: 1.0, green: 0.45, blue: 0.1), warning: exhaustWarning)
                StatTile(icon: "scope",              label: "G-PEAK",    value: String(format: "%.2f", motion.peakG), unit: "G", color: Color(red: 0.68, green: 0.35, blue: 0.98))
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Widescreen Telemetry Flight-Bar (MoTeC-Style Continuous Strip)
// ─────────────────────────────────────────────────────────────────────────────

public struct WidescreenTelemetryRibbon: View {
    @ObservedObject public var obd: OBDManager
    @ObservedObject public var motion: MotionManager
    public var width: CGFloat
    public var height: CGFloat

    private let purple = Color(red: 0.68, green: 0.35, blue: 0.98)

    public init(obd: OBDManager, motion: MotionManager, width: CGFloat, height: CGFloat) {
        self.obd = obd
        self.motion = motion
        self.width = width
        self.height = height
    }

    private var coolantWarning: Bool { guard let c = obd.liveCoolantTemp else { return false }; return c > 105 }
    private var battWarning: Bool    { guard let v = obd.batteryVoltage else { return false }; return v < 12.2 || v > 15.2 }
    private var exhaustWarning: Bool { guard let e = obd.estimatedExhaustTemp else { return false }; return e > 780 }

    public var body: some View {
        HStack(spacing: 0) {
            flightMetric(
                label: "ANSAUGLUFT",
                val: obd.liveIAT != nil ? "\(obd.liveIAT!)°C" : "--",
                icon: "wind",
                color: Color(red: 0.3, green: 0.9, blue: 0.8),
                warning: false
            )
            divider
            flightMetric(
                label: "LUFTMASSE",
                val: obd.liveMAF != nil ? String(format: "%.1f g/s", obd.liveMAF!) : "--",
                icon: "waveform.path",
                color: Color(red: 0.4, green: 0.8, blue: 1.0),
                warning: false
            )
            divider
            flightMetric(
                label: "MOTORLAST",
                val: obd.liveEngineLoad != nil ? "\(obd.liveEngineLoad!)%" : "--",
                icon: "gauge.medium",
                color: .orange,
                warning: false
            )
            divider
            flightMetric(
                label: "ABGAS (EST)",
                val: obd.estimatedExhaustTemp != nil ? "\(obd.estimatedExhaustTemp!)°C" : "--",
                icon: "flame.fill",
                color: exhaustWarning ? .red : Color(red: 1.0, green: 0.45, blue: 0.1),
                warning: exhaustWarning
            )
            divider
            flightMetric(
                label: "KÜHLWASSER",
                val: obd.liveCoolantTemp != nil ? "\(obd.liveCoolantTemp!)°C" : "--",
                icon: "thermometer.medium",
                color: coolantWarning ? .red : .green,
                warning: coolantWarning
            )
            divider
            flightMetric(
                label: "BORDNETZ",
                val: obd.batteryVoltage != nil ? String(format: "%.1f V", obd.batteryVoltage!) : "--",
                icon: "bolt.fill",
                color: battWarning ? .red : .yellow,
                warning: battWarning
            )
            divider
            flightMetric(
                label: "LATERAL-G",
                val: String(format: "%.2f G", abs(motion.gX)),
                icon: "arrow.left.and.right",
                color: purple,
                warning: false
            )
            divider
            flightMetric(
                label: "G-PEAK",
                val: String(format: "%.2f G", motion.peakG),
                icon: "scope",
                color: purple,
                warning: false
            )
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: height * 0.50)
    }

    private func flightMetric(label: String, val: String, icon: String, color: Color, warning: Bool) -> some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2.5) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(warning ? .red : color)
                Text(label)
                    .font(.system(size: 6.5, weight: .black, design: .rounded))
                    .foregroundStyle(warning ? .red : .white.opacity(0.40))
                    .lineLimit(1)
            }

            Text(val)
                .font(.system(size: 11.5, weight: .black, design: .monospaced))
                .foregroundStyle(warning ? .red : color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

