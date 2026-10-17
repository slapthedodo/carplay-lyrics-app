// MARK: - CarLyricsApp.swift
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import AppIntents

@main
struct CarLyricsApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "carlyrics" else { return }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        if host == "stop" || host == "stop-live-activity" || path.contains("stop") {
            Task { @MainActor in
                await MusicObserver.shared.endAllLiveActivities()
                BackgroundKeepAliveManager.shared.stop()
                MotionManager.shared.stop()
            }
        } else if host == "start" || host == "start-live-activity" || path.contains("start") {
            Task { @MainActor in
                BackgroundKeepAliveManager.shared.start()
                MotionManager.shared.start()
                await MusicObserver.shared.reattachOrCreateLiveActivity()
                MusicObserver.shared.startTelemetryHeartbeat()
            }
        } else if host == "toggle" || path.contains("toggle") {
            Task { @MainActor in
                if MusicObserver.shared.liveActivity != nil {
                    await MusicObserver.shared.endAllLiveActivities()
                    BackgroundKeepAliveManager.shared.stop()
                    MotionManager.shared.stop()
                } else {
                    BackgroundKeepAliveManager.shared.start()
                    MotionManager.shared.start()
                    await MusicObserver.shared.reattachOrCreateLiveActivity()
                    MusicObserver.shared.startTelemetryHeartbeat()
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Apple Shortcuts (Kurzbefehle App) Integration
// ─────────────────────────────────────────────────────────────────────────────

public struct StartDynamicIslandIntent: AppIntent {
    public static var title: LocalizedStringResource = "Dynamic Island starten"
    public static var description = IntentDescription("Startet die CarLyrics Dynamic Island mit Live-Telemetrie und Lyrics.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        BackgroundKeepAliveManager.shared.start()
        MotionManager.shared.start()
        await MusicObserver.shared.reattachOrCreateLiveActivity()
        MusicObserver.shared.startTelemetryHeartbeat()
        return .result()
    }
}

public struct StopDynamicIslandIntent: AppIntent {
    public static var title: LocalizedStringResource = "Dynamic Island beenden"
    public static var description = IntentDescription("Beendet die CarLyrics Dynamic Island und entfernt sie sofort vom Bildschirm.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await MusicObserver.shared.endAllLiveActivities()
        BackgroundKeepAliveManager.shared.stop()
        MotionManager.shared.stop()
        return .result()
    }
}

public struct ToggleDynamicIslandIntent: AppIntent {
    public static var title: LocalizedStringResource = "Dynamic Island umschalten"
    public static var description = IntentDescription("Schaltet die CarLyrics Dynamic Island ein oder aus.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if MusicObserver.shared.liveActivity != nil {
            await MusicObserver.shared.endAllLiveActivities()
            BackgroundKeepAliveManager.shared.stop()
            MotionManager.shared.stop()
        } else {
            BackgroundKeepAliveManager.shared.start()
            MotionManager.shared.start()
            await MusicObserver.shared.reattachOrCreateLiveActivity()
            MusicObserver.shared.startTelemetryHeartbeat()
        }
        return .result()
    }
}

public struct CarLyricsShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDynamicIslandIntent(),
            phrases: [
                "Starte \(.applicationName) Dynamic Island",
                "Starte \(.applicationName) Cockpit",
                "Starte \(.applicationName)"
            ],
            shortTitle: "Dynamic Island starten",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: StopDynamicIslandIntent(),
            phrases: [
                "Beende \(.applicationName) Dynamic Island",
                "Stoppe \(.applicationName) Cockpit",
                "Beende \(.applicationName)"
            ],
            shortTitle: "Dynamic Island beenden",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: ToggleDynamicIslandIntent(),
            phrases: [
                "Schalte \(.applicationName) um",
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Cockpit umschalten",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
    }
}
