// MARK: - MusicObserverLiveActivity.swift
// CarLyrics – ActivityKit Engine & Live Activity Lifecycle for MusicObserver
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import ActivityKit
import WidgetKit
import CoreMotion
import UIKit

extension MusicObserver {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Accessors & Widget Reload
    // ─────────────────────────────────────────────────────────────────────────

    public var hasActiveLiveActivity: Bool {
        return activeActivity != nil
    }

    /// Liefert garantiert nur eine echte, aktive Activity zurück (ignoriert .ended & .dismissed)
    public var activeActivity: Activity<LyricsAttributes>? {
        if let current = liveActivity, current.activityState == .active {
            return current
        }
        if let existing = Activity<LyricsAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.liveActivity = existing
            return existing
        }
        return nil
    }

    /// Intelligenter Widget-Reload: Schont Apples tägliches WidgetKit-Reload-Budget (40-70 Aufrufe/Tag),
    /// damit Widgets NIEMALS einfrieren, aber bei Trackwechsel sofort aktualisieren.
    public func scheduleWidgetReload(force: Bool = false) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWidgetReloadTime)
        if force || elapsed >= 25.0 {
            lastWidgetReloadTime = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    public func handleFastGForceChange(currentG: Double, peakG: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)
        // 120ms Mindestabstand (ermöglicht blitzschnelle, flüssige Dynamic Island G-Kraft Reaktion)
        if elapsed >= 0.12 {
            pushActivityUpdate(force: true)
        } else if !pendingActivityUpdate {
            pendingActivityUpdate = true
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Push Engine (Serialisiert, kein Dead-Lock, kein Throttling)
    // ─────────────────────────────────────────────────────────────────────────

    public func pushActivityUpdate(force: Bool = false) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityUpdate)

        // Apple Rate-Limit Schutz:
        // Bei Songtext-Zeilenwechsel & G-Kraft Peaks: min 0.12s Abstand (flüssige 8 Hz Updates)
        // Bei reinem Telemetrie-Heartbeat: min 0.8s Abstand
        let minAllowed = force ? 0.12 : 0.8
        if !force && elapsed < minAllowed {
            return
        }

        if isUpdatingActivity {
            pendingActivityUpdate = true
            return
        }

        isUpdatingActivity = true
        lastActivityUpdate = now

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isUpdatingActivity = false
                if self.pendingActivityUpdate {
                    self.pendingActivityUpdate = false
                    // Sofort ohne künstliche Verzögerung nachschieben!
                    Task { @MainActor [weak self] in
                        self?.pushActivityUpdate(force: true)
                    }
                }
            }

            guard let activity = self.activeActivity else {
                await self.reattachOrCreateLiveActivity()
                return
            }

            let state = self.makeState()
            // staleDate: nil -> iOS setzt die Dynamic Island NIEMALS versehentlich auf .stale
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ActivityKit Lifecycle (Robuste Anbindung & Auto-Cleanup)
    // ─────────────────────────────────────────────────────────────────────────

    public func reattachOrCreateLiveActivity() async {
        guard isCarOrActive else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Erst alle toten oder beendeten Activities sauber aus dem System entfernen
        let all = Activity<LyricsAttributes>.activities
        for old in all where old.activityState != .active {
            await old.end(nil, dismissalPolicy: .immediate)
        }

        let activeList = Activity<LyricsAttributes>.activities.filter { $0.activityState == .active }
        if let existing = activeList.first {
            self.liveActivity = existing
            for extra in activeList.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            pushActivityUpdate(force: true)
        } else {
            let title = currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle
            let artist = currentArtist.isEmpty ? "Motor-Monitor" : currentArtist
            await startNewLiveActivity(title: title, artist: artist)
        }
    }

    public func resetLiveActivities() async {
        await endAllLiveActivities()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await reattachOrCreateLiveActivity()
    }

    public func endAllLiveActivities() async {
        for act in Activity<LyricsAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
    }

    public func startNewLiveActivity(title: String, artist: String) async {
        guard isCarOrActive else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let _ = activeActivity {
            pushActivityUpdate(force: true)
            return
        }

        // Alle beendeten oder alten Leichen vor Neuanlage sofort abräumen
        for act in Activity<LyricsAttributes>.activities where act.activityState != .active {
            await act.end(nil, dismissalPolicy: .immediate)
        }

        let attrs   = LyricsAttributes(trackId: "\(artist)|\(title)")
        let content = ActivityContent(state: makeState(), staleDate: nil)
        do {
            let newActivity = try Activity<LyricsAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
            self.liveActivity = newActivity
            lastActivityUpdate = Date()
        } catch {
            print("[CarLyrics] Live Activity start failed: \(error)")
        }
    }

    public func endLiveActivity() async {
        if let activity = activeActivity {
            var final = makeState()
            final.isPlaying = false
            let content = ActivityContent(state: final, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            self.liveActivity = nil
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: State Builder (mit OBD-II Fallback & Telemetrie)
    // ─────────────────────────────────────────────────────────────────────────

    public func makeState() -> LyricsAttributes.ContentState {
        let wm = warmupManager
        let mm = motionManager

        let oilTemp: Int?
        let isEngineWarm: Bool
        let effectiveBoost: Double?
        let effectiveCoolant: Int?
        let effectiveIAT: Int?
        let effectiveMAF: Double?

        if obd.isEnabled {
            if obd.connectionState == .connected {
                let temp = obd.effectiveOilTemp ?? wm?.oilTempInt ?? 20
                oilTemp = temp
                isEngineWarm = temp >= 80
                effectiveBoost = obd.liveBoostBar ?? 0.0
                effectiveCoolant = obd.liveCoolantTemp ?? (temp >= 70 ? 90 : max(temp, temp + 8))
                effectiveIAT = obd.liveIAT ?? 20
                effectiveMAF = obd.liveMAF ?? 3.5
            } else {
                // Solange OBD noch sucht oder verbindet: Sanfter Übergang mit Standby-Werten
                let simOil = wm?.oilTempInt ?? 20
                oilTemp = simOil
                isEngineWarm = wm?.isEngineWarm ?? false
                effectiveBoost = 0.0
                effectiveCoolant = simOil >= 70 ? 90 : max(simOil, simOil + 8)
                effectiveIAT = 20
                effectiveMAF = 3.5
            }
        } else {
            // Reines TFSI Simulationsmodell (Kein OBD)
            let simOil = wm?.oilTempInt ?? 20
            oilTemp = simOil
            isEngineWarm = wm?.isEngineWarm ?? false
            effectiveBoost = nil
            effectiveCoolant = simOil >= 70 ? 90 : max(simOil, simOil + 8)
            effectiveIAT = nil
            effectiveMAF = nil
        }

        let progressVal = wm?.warmupProgress ?? 0
        let phaseVal    = wm?.phase ?? .cold

        let cleanTitle = currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle
        let cleanArtist = currentArtist.isEmpty ? "Motor-Monitor" : currentArtist
        let cleanLyric = currentLine.isEmpty ? (currentTrackTitle.isEmpty ? "Öl- & Telemetrie-Monitor" : "♪") : currentLine

        let curStr = Self.formatTime(currentPlaybackTime)
        let totStr = duration > 0 ? Self.formatTime(duration) : (currentPlaybackTime > 0 ? Self.formatTime(currentPlaybackTime + 180) : "3:45")

        // Zentral in App-Group UserDefaults & Shared JSON Container speichern
        let sharedData = TelemetrySharedData(
            oilTemp: oilTemp,
            coolantTemp: effectiveCoolant,
            boostBar: effectiveBoost,
            currentG: mm?.currentG ?? 0,
            peakG: mm?.peakG ?? 0,
            iat: effectiveIAT,
            maf: effectiveMAF,
            phase: phaseVal,
            warmupProgress: progressVal,
            songTitle: cleanTitle,
            artist: cleanArtist,
            previousLine2: previousLine2,
            previousLine: previousLine,
            currentLine: cleanLyric,
            nextLine: nextLine,
            nextLine2: nextLine2,
            currentTimeStr: curStr,
            totalTimeStr: totStr,
            progress: progress,
            isPlaying: isPlaying,
            sessionStartTime: UserDefaults.standard.double(forKey: "carlyrics_warmup_started_at"),
            sessionStartTemp: UserDefaults.standard.double(forKey: "carlyrics_warmup_start_temp"),
            updatedAt: Date()
        )
        TelemetrySharedStore.save(sharedData)

        return LyricsAttributes.ContentState(
            currentLine    : currentLine.isEmpty ? (currentTrackTitle.isEmpty ? "Öl- & Telemetrie-Monitor" : "♪") : currentLine,
            nextLine       : nextLine,
            songTitle      : currentTrackTitle.isEmpty ? "TFSI 2.0 Telemetrie" : currentTrackTitle,
            artist         : currentArtist.isEmpty ? "Motor-Monitor" : currentArtist,
            progress       : progress,
            isPlaying      : isPlaying,
            currentG       : mm?.currentG ?? 0,
            peakG          : mm?.peakG    ?? 0,
            gVectorX       : mm?.gX       ?? 0,
            gVectorY       : mm?.gY       ?? 0,
            oilTemp        : oilTemp,
            coolantTemp    : effectiveCoolant,
            boostBar       : effectiveBoost,
            iatTemp        : effectiveIAT,
            mafVal         : effectiveMAF,
            warmupProgress : progressVal,
            warmupPhase    : phaseVal,
            isEngineWarm   : isEngineWarm
        )
    }
}
