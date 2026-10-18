// MARK: - BackgroundKeepAliveManager.swift
// CarLyrics – keeps the app alive in the background via a silent AVAudioPlayer,
// WITHOUT interrupting Spotify / Apple Music or CarPlay audio.
// ─────────────────────────────────────────────────────────────────────────────
// Strategy:
//   • Category  : .playback (UIBackgroundModes includes 'audio')
//   • Options   : .mixWithOthers + .allowBluetooth + .allowBluetoothA2DP
//   • Content   : Infinite-looping (-1) in-memory silent 16-bit PCM WAV (all zeros)
//   • Volume    : 0.01 (active audio queue rendering in mediaserverd, mathematically 0 sound)
//   • Effect    : iOS mediaserverd maintains continuous background audio assertion;
//                 Live Activity and telemetry updates never freeze when screen is locked!
// ─────────────────────────────────────────────────────────────────────────────

import AVFoundation
import UIKit
import os

public final class BackgroundKeepAliveManager: NSObject, AVAudioPlayerDelegate {

    public static let shared = BackgroundKeepAliveManager()

    private var audioPlayer: AVAudioPlayer?
    private let log = Logger(subsystem: "com.carlyrics", category: "BGKeepAlive")
    private var isActive = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
        setupNotifications()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    public func start() {
        guard !isActive || audioPlayer?.isPlaying != true else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)

            if audioPlayer == nil {
                let silentData = Self.createSilentWAVData()
                let player = try AVAudioPlayer(data: silentData)
                player.delegate = self
                player.numberOfLoops = -1
                player.volume = 0.01
                player.prepareToPlay()
                self.audioPlayer = player
            }

            if audioPlayer?.isPlaying != true {
                audioPlayer?.play()
            }

            isActive = true
            log.info("Background keep-alive active via AVAudioPlayer.")
        } catch {
            log.error("Failed to start keep-alive: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard isActive else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
        endBackgroundTask()
        log.info("Background keep-alive stopped.")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Interruption & Route Change Resilience
    // ─────────────────────────────────────────────────────────────────────────

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        if isActive && audioPlayer?.isPlaying != true {
            log.info("Audio route changed -> ensuring keep-alive continues.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }
    }

    @objc private func handleDidEnterBackground() {
        guard isActive else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CarLyricsKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        if audioPlayer?.isPlaying != true {
            start()
        }
    }

    @objc private func handleWillEnterForeground() {
        endBackgroundTask()
        if isActive && audioPlayer?.isPlaying != true {
            start()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: In-Memory Silent WAV Generator
    // ─────────────────────────────────────────────────────────────────────────

    private static func createSilentWAVData() -> Data {
        let sampleRate: UInt32 = 44100
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationSeconds: UInt32 = 2
        let numSamples = sampleRate * durationSeconds
        let subChunk2Size = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let chunkSize = 36 + subChunk2Size
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        var data = Data()
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // "fmt " subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let subChunk1Size: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subChunk1Size.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // "data" subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: subChunk2Size.littleEndian) { Array($0) })

        // PCM silent samples (zeros)
        data.append(Data(count: Int(subChunk2Size)))
        return data
    }
}
