// MARK: - ContentView.swift
// Root Coordinator für CarLyrics (Cockpit, Diagnose-Labor & Setup)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import MediaPlayer

public struct ContentView: View {

    @ObservedObject private var observer = MusicObserver.shared
    @ObservedObject private var warmup   = WarmupManager.shared
    @ObservedObject private var motion   = MotionManager.shared
    @ObservedObject private var spotify  = SpotifyManager.shared
    @ObservedObject private var obd      = OBDManager.shared

    @State private var showMockSheet    = false
    @State private var showSpotifySheet = false
    @State private var showOBDSheet     = false
    @State private var selectedTab      = 0

    public init() {}

    public var body: some View {
        ZStack {
            CockpitBackground()

            TabView(selection: $selectedTab) {
                CockpitTabView(observer: observer,
                               warmup: warmup,
                               motion: motion,
                               obd: obd,
                               onOpenDiagnostics: { selectedTab = 1 })
                    .tabItem { Label("Cockpit", systemImage: "gauge.with.needle") }
                    .tag(0)

                OBDDiagnosticWorkbenchView(obd: obd, isPresentedAsSheet: false)
                    .tabItem { Label("OBD Labor", systemImage: "wrench.and.screwdriver.fill") }
                    .tag(1)

                HandyModusView(observer: observer,
                               obd: obd,
                               motion: motion,
                               warmup: warmup)
                    .tabItem { Label("Handy", systemImage: "iphone.gen3") }
                    .tag(2)

                PedalVisualizerView(obd: obd, motion: motion)
                    .tabItem { Label("Pedale", systemImage: "pedal.accelerator") }
                    .tag(3)

                KupplungTutorialView(obd: obd)
                    .tabItem { Label("Fahren", systemImage: "car.fill") }
                    .tag(4)

                SettingsTabView(spotify: spotify, obd: obd, observer: observer)
                    .tabItem { Label("Setup", systemImage: "gearshape.fill") }
                    .tag(5)
            }
            .tint(.cyan)
            .onChange(of: selectedTab) { newTab in
                switch newTab {
                case 3:
                    obd.focusMode = .pedalOnly
                case 4:
                    obd.focusMode = .minimal
                default:
                    obd.focusMode = .standard
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMockSheet) {
            MockInjectorView(observer: observer)
        }
        .sheet(isPresented: $showSpotifySheet) {
            SpotifySetupSheet(spotify: spotify)
        }
        .sheet(isPresented: $showOBDSheet) {
            OBDDiagnosticWorkbenchView(obd: obd, isPresentedAsSheet: true)
        }
        .onAppear {
            observer.warmupManager = warmup
            observer.motionManager = motion

            if !warmup.isRunning {
                warmup.start(cold: true)
            }
            motion.start()
            BackgroundKeepAliveManager.shared.start()

            Task {
                await observer.reattachOrCreateLiveActivity()
            }
            observer.startTelemetryHeartbeat()

            if spotify.isAuthenticated {
                spotify.startPolling()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showOBDSheet = true } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(obdColor)
                            .frame(width: 8, height: 8)
                        Text(obd.isEnabled ? "OBD: \(obd.connectionState.rawValue)" : "OBD: Sim")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSpotifySheet = true } label: {
                    Image(systemName: spotify.isAuthenticated ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(spotify.isAuthenticated ? .green : .secondary)
                }
            }
        }
    }

    private var obdColor: Color {
        guard obd.isEnabled else { return .secondary }
        switch obd.connectionState {
        case .connected:    return .green
        case .connecting, .initializing, .scanning: return .orange
        default:            return .red
        }
    }
}
