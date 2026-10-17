// MARK: - CockpitTabView.swift
// Cockpit Hauptseite mit Songtexten, Ladedruck, Öltemperatur & G-Kräften
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct CockpitTabView: View {
    @ObservedObject var observer : MusicObserver
    @ObservedObject var warmup   : WarmupManager
    @ObservedObject var motion   : MotionManager
    @ObservedObject var obd      : OBDManager
    public var onOpenDiagnostics : () -> Void = {}

    public init(observer: MusicObserver,
                warmup: WarmupManager,
                motion: MotionManager,
                obd: OBDManager,
                onOpenDiagnostics: @escaping () -> Void = {}) {
        self.observer = observer
        self.warmup = warmup
        self.motion = motion
        self.obd = obd
        self.onOpenDiagnostics = onOpenDiagnostics
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                NowPlayingCard(observer: observer)
                LyricsCard(observer: observer)

                // OBD Toggle Card & Schnellzugriff Labor
                GlassCard {
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Datenquelle")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(obd.isEnabled ? "OBD Live (\(obd.detailedStatus))" : "TFSI Simulation")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(obd.isEnabled ? .green : .cyan)
                            }
                            Spacer()
                            Toggle("", isOn: $obd.isEnabled)
                                .labelsHidden()
                                .tint(.green)
                                .onChange(of: obd.isEnabled) { _, enabled in
                                    if enabled { obd.enableOBD() } else { obd.disableOBD() }
                                }
                        }
                        if obd.isEnabled {
                            Button {
                                onOpenDiagnostics()
                            } label: {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                    Text("Diagnose & Labor öffnen")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                WarmupCard(warmup: warmup, obd: obd)
                BoostCard(obd: obd)
                GForceCard(motion: motion)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}
