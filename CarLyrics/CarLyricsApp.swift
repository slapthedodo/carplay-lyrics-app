// MARK: - CarLyricsApp.swift
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import AppIntents
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}

@main
struct CarLyricsApp: App {

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        WarmupManager.shared.requestNotificationPermission()

        // Services & Sensoren direkt bei App-Start aktivieren (sowohl Vorder- als auch Hintergrund/CarPlay)
        MotionManager.shared.start()
        WarmupManager.shared.start()
        BackgroundKeepAliveManager.shared.start()
        _ = MusicObserver.shared
    }

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
                WarmupManager.shared.stop()
            }
        } else if host == "start" || host == "start-live-activity" || path.contains("start") {
            Task { @MainActor in
                BackgroundKeepAliveManager.shared.start()
                MotionManager.shared.start()
                WarmupManager.shared.start()
                await MusicObserver.shared.reattachOrCreateLiveActivity()
                MusicObserver.shared.startTelemetryHeartbeat()
            }
        } else if host == "cockpit" || path.contains("cockpit") {
            Task { @MainActor in
                BackgroundKeepAliveManager.shared.start()
                await MusicObserver.shared.reattachOrCreateLiveActivity()
                MusicObserver.shared.pushActivityUpdate(force: true)
                MusicObserver.shared.scheduleWidgetReload(force: true)
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
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        MusicObserver.shared.forceDynamicIslandActive = true
        BackgroundKeepAliveManager.shared.start()
        MotionManager.shared.start()
        WarmupManager.shared.start()
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
        MusicObserver.shared.forceDynamicIslandActive = false
        await MusicObserver.shared.endAllLiveActivities()
        BackgroundKeepAliveManager.shared.stop()
        MotionManager.shared.stop()
        WarmupManager.shared.stop()
        return .result()
    }
}

public struct ToggleDynamicIslandIntent: AppIntent {
    public static var title: LocalizedStringResource = "Dynamic Island umschalten"
    public static var description = IntentDescription("Schaltet die CarLyrics Dynamic Island ein oder aus.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if MusicObserver.shared.hasActiveLiveActivity {
            MusicObserver.shared.forceDynamicIslandActive = false
            await MusicObserver.shared.endAllLiveActivities()
            BackgroundKeepAliveManager.shared.stop()
            MotionManager.shared.stop()
            WarmupManager.shared.stop()
        } else {
            MusicObserver.shared.forceDynamicIslandActive = true
            BackgroundKeepAliveManager.shared.start()
            MotionManager.shared.start()
            WarmupManager.shared.start()
            await MusicObserver.shared.reattachOrCreateLiveActivity()
            MusicObserver.shared.startTelemetryHeartbeat()
        }
        return .result()
    }
}

// AppShortcutsProvider (Siri-Phrases) entfernt – verursachte Konflikte mit
// Blitzer-App Ruhemodus-Automation. Die Intents oben bleiben in der
// iOS Kurzbefehle-App verfügbar und können dort manuell hinzugefügt werden.
