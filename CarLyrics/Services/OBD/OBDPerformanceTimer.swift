// MARK: - OBDPerformanceTimer.swift
// 0–100 km/h Drag & Performance Timer für CarLyrics
// Professioneller Dragy/VBox-Algorithmus mit linearer Sub-Tick-Interpolation,
// 60-FPS Display-Ticker & 100% High-Speed Prioritäts-Abfrage (nur aktiv wenn Schalter AN)
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

public enum PerformanceRunState: String {
    case disabled  = "Inaktiv (Schalter aus)"
    case idle      = "Bereit (Warte auf Stillstand)"
    case armed     = "Launch bereit! (Tritt drauf!)"
    case running   = "Messe 0–100 km/h…"
    case completed = "Lauf beendet!"
    case aborted   = "Abgebrochen"
}

public final class OBDPerformanceTimer: ObservableObject {
    public static let shared = OBDPerformanceTimer()

    @Published public var state: PerformanceRunState = .disabled
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "carlyrics_drag_timer_armed")
            if !isEnabled {
                reset()
                state = .disabled
                isDedicatedSpeedPollingRequired = false
            } else if state == .disabled {
                state = .idle
                if liveSpeed == 0 {
                    manualArm()
                }
            }
        }
    }

    // ── Live Messdaten ──
    @Published public var liveSpeed: Int = 0
    @Published public var currentElapsedTime: Double = 0.0
    @Published public var timeTo60: Double? = nil
    @Published public var timeTo100: Double? = nil
    @Published public var last0to100: Double? = nil
    @Published public var best0to100: Double? = nil

    /// Signalisiert der OBD-Polling-Schleife, dass JETZT 100% Bandbreite
    /// ausschließlich für Geschwindigkeitsabfragen (01 0D) reserviert werden muss!
    /// Nur aktiv wenn Schalter AN und Auto im Stand (armed) oder beim Messen (running)!
    @Published public var isDedicatedSpeedPollingRequired: Bool = false

    // ── Interne Zeitmessung & Interpolation (Dragy/VBox Standard) ──
    private var startTimestamp: CFAbsoluteTime? = nil
    private var stoppedAtZeroTimestamp: CFAbsoluteTime? = nil
    private var prevSpeed: Int = 0
    private var prevSpeedTimestamp: CFAbsoluteTime = 0
    private var lastZeroTimestamp: CFAbsoluteTime? = nil

    // ── 60-FPS UI Ticker (verhindert Display-Ruckler bei OBD-Latenzen) ──
    private var displayTimer: Timer? = nil

    public init() {
        // Scharfschalt-Zustand laden (Standard: AUS)
        let savedArmed = UserDefaults.standard.bool(forKey: "carlyrics_drag_timer_armed")
        self.isEnabled = savedArmed
        self.state = savedArmed ? .idle : .disabled

        // Bestzeit laden
        let savedBest = UserDefaults.standard.double(forKey: "CarLyrics_Best_0_100")
        if savedBest > 0.1 {
            best0to100 = savedBest
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Geschwindigkeitseingang & Messlogik
    // ─────────────────────────────────────────────────────────────────────────

    /// Wird synchron bei jedem Eintreffen einer neuen Geschwindigkeit (PID 01 0D) aufgerufen
    public func updateSpeed(_ speed: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        liveSpeed = speed

        guard isEnabled else {
            isDedicatedSpeedPollingRequired = false
            prevSpeed = speed
            prevSpeedTimestamp = now
            return
        }

        switch state {
        case .disabled:
            isDedicatedSpeedPollingRequired = false

        case .idle, .completed, .aborted:
            if speed == 0 {
                lastZeroTimestamp = now
                if stoppedAtZeroTimestamp == nil {
                    stoppedAtZeroTimestamp = now
                } else if now - stoppedAtZeroTimestamp! >= 1.0 {
                    // Auto steht seit > 1 Sekunde ruhig: Für Launch scharfschalten!
                    state = .armed
                    isDedicatedSpeedPollingRequired = true // Ab jetzt 100% Speed-Prio für sofortige Starterkennung!
                    currentElapsedTime = 0.0
                    timeTo60 = nil
                    timeTo100 = nil
                }
            } else {
                stoppedAtZeroTimestamp = nil
                isDedicatedSpeedPollingRequired = false
            }

        case .armed:
            if speed == 0 {
                lastZeroTimestamp = now
                isDedicatedSpeedPollingRequired = true
            } else if speed > 0 {
                // ── LAUNCH ERKANNT! ──────────────────────────────────────────
                // Sub-Tick Interpolation: Ermittle exakten Zeitpunkt der ersten Bewegung (> 0.5 km/h)
                let t0 = lastZeroTimestamp ?? prevSpeedTimestamp
                let v0 = Double(max(0, prevSpeed))
                let v1 = Double(speed)
                let frac = (v1 > v0) ? max(0.0, min(1.0, (0.5 - v0) / (v1 - v0))) : 0.0
                let interpolatedStart = t0 + frac * (now - t0)

                startTimestamp = interpolatedStart
                state = .running
                isDedicatedSpeedPollingRequired = true
                currentElapsedTime = max(0.0, now - interpolatedStart)

                startDisplayTicker()
            }

        case .running:
            guard let start = startTimestamp else { return }
            let rawElapsed = now - start

            // ── 0–60 km/h Zwischenzeit mit linearer Interpolation ─────────
            if speed >= 60 && timeTo60 == nil {
                if prevSpeed < 60 && speed > prevSpeed {
                    let frac = Double(60 - prevSpeed) / Double(speed - prevSpeed)
                    let exactTime = prevSpeedTimestamp + frac * (now - prevSpeedTimestamp)
                    timeTo60 = max(0.05, exactTime - start)
                } else {
                    timeTo60 = rawElapsed
                }
            }

            // ── 0–100 km/h ZIEL ERREICHT! (Lineare Dragy-Interpolation) ────
            if speed >= 100 {
                let finalElapsed: Double
                if prevSpeed < 100 && speed > prevSpeed {
                    let frac = Double(100 - prevSpeed) / Double(speed - prevSpeed)
                    let exactTime = prevSpeedTimestamp + frac * (now - prevSpeedTimestamp)
                    finalElapsed = max(0.1, exactTime - start)
                } else {
                    finalElapsed = rawElapsed
                }

                timeTo100 = finalElapsed
                last0to100 = finalElapsed
                currentElapsedTime = finalElapsed

                stopDisplayTicker()
                state = .completed
                isDedicatedSpeedPollingRequired = false // Normale Cockpit-Abfrage sofort wiederherstellen

                if best0to100 == nil || finalElapsed < best0to100! {
                    best0to100 = finalElapsed
                    UserDefaults.standard.set(finalElapsed, forKey: "CarLyrics_Best_0_100")
                }
                stoppedAtZeroTimestamp = nil

            } else if speed == 0 && rawElapsed > 2.0 {
                // Vor 100 km/h angehalten -> Abbruch
                stopDisplayTicker()
                state = .aborted
                isDedicatedSpeedPollingRequired = false
                stoppedAtZeroTimestamp = now
            }
        }

        prevSpeed = speed
        prevSpeedTimestamp = now
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Display Ticker (Flüssige 60 FPS Stoppuhr)
    // ─────────────────────────────────────────────────────────────────────────

    private func startDisplayTicker() {
        stopDisplayTicker()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTimestamp, self.state == .running else { return }
            self.currentElapsedTime = CFAbsoluteTimeGetCurrent() - start
        }
        if let timer = displayTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopDisplayTicker() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Manuelle Steuerung
    // ─────────────────────────────────────────────────────────────────────────

    public func manualArm() {
        guard isEnabled else { return }
        stopDisplayTicker()
        state = .armed
        currentElapsedTime = 0.0
        timeTo60 = nil
        timeTo100 = nil
        stoppedAtZeroTimestamp = CFAbsoluteTimeGetCurrent()
        lastZeroTimestamp = stoppedAtZeroTimestamp
        isDedicatedSpeedPollingRequired = true
    }

    public func reset() {
        stopDisplayTicker()
        state = isEnabled ? .idle : .disabled
        currentElapsedTime = 0.0
        timeTo60 = nil
        timeTo100 = nil
        isDedicatedSpeedPollingRequired = false
        startTimestamp = nil
        stoppedAtZeroTimestamp = nil
        lastZeroTimestamp = nil
        prevSpeed = 0
    }
}
