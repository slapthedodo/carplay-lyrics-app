// MARK: - OBDPerformanceTimer.swift
// 0–100 km/h Drag & Performance Timer für CarLyrics
// Vollautomatische Launch-Erkennung & 100% High-Speed Prioritäts-Abfrage
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
            } else if state == .disabled {
                state = .idle
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

    // ── Interne Zeitmessung ──
    private var startTimestamp: CFAbsoluteTime? = nil
    private var stoppedAtZeroTimestamp: CFAbsoluteTime? = nil

    /// Signalisiert der OBD-Polling-Schleife, dass JETZT 100% Bandbreite
    /// ausschließlich für Geschwindigkeitsabfragen (01 0D) reserviert werden muss!
    @Published public var isDedicatedSpeedPollingRequired: Bool = false

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

    /// Wird bei jedem Eintreffen einer neuen Geschwindigkeit (PID 01 0D) aufgerufen
    @MainActor
    public func updateSpeed(_ speed: Int) {
        liveSpeed = speed
        guard isEnabled else {
            isDedicatedSpeedPollingRequired = false
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        switch state {
        case .idle, .completed, .aborted:
            if speed == 0 {
                if stoppedAtZeroTimestamp == nil {
                    stoppedAtZeroTimestamp = now
                } else if now - stoppedAtZeroTimestamp! >= 1.2 {
                    // Auto steht seit >1.2 Sekunden ruhig: Scharfschalten für Launch!
                    state = .armed
                    currentElapsedTime = 0.0
                    timeTo60 = nil
                    timeTo100 = nil
                }
            } else {
                stoppedAtZeroTimestamp = nil
            }

        case .armed:
            if speed > 0 {
                // LAUNCH ERKANNT! Stoppuhr startet sofort
                state = .running
                startTimestamp = now
                currentElapsedTime = 0.0
                isDedicatedSpeedPollingRequired = true
            }

        case .running:
            guard let start = startTimestamp else { return }
            let elapsed = now - start
            currentElapsedTime = elapsed

            // 0–60 km/h Zwischenzeit
            if speed >= 60 && timeTo60 == nil {
                timeTo60 = elapsed
            }

            // 0–100 km/h ZIEL ERREICHT!
            if speed >= 100 {
                timeTo100 = elapsed
                last0to100 = elapsed
                state = .completed
                isDedicatedSpeedPollingRequired = false // Normale Abfrage wieder aufnehmen

                if best0to100 == nil || elapsed < best0to100! {
                    best0to100 = elapsed
                    UserDefaults.standard.set(elapsed, forKey: "CarLyrics_Best_0_100")
                }
                stoppedAtZeroTimestamp = nil
            } else if speed == 0 && elapsed > 2.0 {
                // Angehalten bevor 100 erreicht wurden
                state = .aborted
                isDedicatedSpeedPollingRequired = false
                stoppedAtZeroTimestamp = now
            }
        }
    }

    @MainActor
    public func manualArm() {
        state = .armed
        currentElapsedTime = 0.0
        timeTo60 = nil
        timeTo100 = nil
        stoppedAtZeroTimestamp = CFAbsoluteTimeGetCurrent()
    }

    @MainActor
    public func reset() {
        state = .idle
        currentElapsedTime = 0.0
        timeTo60 = nil
        timeTo100 = nil
        isDedicatedSpeedPollingRequired = false
        startTimestamp = nil
        stoppedAtZeroTimestamp = nil
    }
}
