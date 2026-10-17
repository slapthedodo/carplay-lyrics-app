// MARK: - BackgroundKeepAliveManager.swift
// CarLyrics – keeps the app alive in the background via a silent AVAudioSession,
// WITHOUT interrupting Spotify / Apple Music.
// ─────────────────────────────────────────────────────────────────────────────
//
// Strategy:
//   • Category  : .playback   (needed for background audio capability)
//   • Options   : .mixWithOthers  → other audio continues uninterrupted
//   • Content   : 1-frame silent AVAudioPCMBuffer looped via AVAudioPlayerNode
//   • Effect    : iOS keeps the process alive; Live Activity updates fire on time
//
// Usage:
//   BackgroundKeepAliveManager.shared.start()
//   BackgroundKeepAliveManager.shared.stop()
// ─────────────────────────────────────────────────────────────────────────────

import AVFoundation
import UIKit
import os

public final class BackgroundKeepAliveManager {

    public static let shared = BackgroundKeepAliveManager()

    private let engine   = AVAudioEngine()
    private let player   = AVAudioPlayerNode()
    private let log      = Logger(subsystem: "com.carlyrics", category: "BGKeepAlive")
    private var isActive = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        setupEngine()
        setupNotifications()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func start() {
        guard !isActive || !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers + bluetooth → Spotify / Apple Music / CarPlay laufen 100% ungestört weiter
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)

            if !engine.isRunning {
                try engine.start()
            }
            scheduleBuffer()
            player.play()
            isActive = true
            log.info("Background keep-alive active and running.")
        } catch {
            log.error("Failed to start keep-alive: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard isActive else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false,
            options: .notifyOthersOnDeactivation)
        isActive = false
        endBackgroundTask()
        log.info("Background keep-alive stopped.")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Interruption & Hardware Configuration Resilience
    // ─────────────────────────────────────────────────────────────────────────

    private func setupNotifications() {
        // Audio-Unterbrechungen (Anrufe, Siri, Blitzer-Warnung)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Bluetooth / CarPlay Verbindung / Trennung
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        // Hardware-Konfigurationsänderung von iOS
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )

        // App wechselt in den Hintergrund -> Sicherheits-Puffer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            log.info("Audio interruption began.")
        case .ended:
            log.info("Audio interruption ended -> restarting keep-alive.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.start()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        if isActive && (!engine.isRunning || !player.isPlaying) {
            log.info("Audio route changed -> restarting keep-alive.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        if isActive {
            log.info("Audio engine configuration changed -> re-configuring engine.")
            setupEngine()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }
    }

    @objc private func handleDidEnterBackground() {
        guard isActive else { return }
        // Begin temporary background task to guarantee seamless audio continuation
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CarLyricsKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func setupEngine() {
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Mute output to zero volume — no audible sound
        engine.mainMixerNode.outputVolume = 0
    }

    private func scheduleBuffer() {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            memset(channelData, 0, Int(frameCount) * MemoryLayout<Float>.size)
        }

        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    }
}
