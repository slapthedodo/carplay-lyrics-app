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
    /// Geschätzte Abgastemperatur für EA113 2.0 TFSI ohne Direktmessung.
    /// Formel: IAT + 180 + RPM/80 + Load*5.5 + BoostBar*110, clamped 200–900°C
    var estimatedExhaustTemp: Int? {
        guard isEnabled, connectionState == .connected,
              let iat  = liveIAT,
              let load = liveEngineLoad else { return nil }
        let rpmFactor   = Double(liveRPM) / 80.0
        let loadFactor  = Double(load) * 5.5
        let boostFactor = (liveBoostBar ?? 0.0) * 110.0
        let est = Double(iat) + 180.0 + rpmFactor + loadFactor + boostFactor
        return Int(min(900, max(200, est)))
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
