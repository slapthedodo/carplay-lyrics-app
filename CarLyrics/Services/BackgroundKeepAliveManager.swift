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
import os

public final class BackgroundKeepAliveManager {

    public static let shared = BackgroundKeepAliveManager()

    private let engine   = AVAudioEngine()
    private let player   = AVAudioPlayerNode()
    private let log      = Logger(subsystem: "com.carlyrics", category: "BGKeepAlive")
    private var isActive = false

    private init() {
        setupEngine()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func start() {
        guard !isActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers + bluetooth → Spotify / Apple Music / CarPlay keep playing uninterrupted
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            try engine.start()
            scheduleBuffer()
            player.play()
            isActive = true
            log.info("Background keep-alive started.")
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
        log.info("Background keep-alive stopped.")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func setupEngine() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Mute output to zero volume — no audible sound
        engine.mainMixerNode.outputVolume = 0
    }

    private func scheduleBuffer() {
        // 3 Sekunden lautloser Puffer — verhindert CPU-Wakeup-Stalls in iOS im Hintergrund
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
