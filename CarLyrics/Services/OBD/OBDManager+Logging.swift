// MARK: - OBDManager+Logging.swift
// Terminal Logging & Debug Entry Helpers für OBDManager
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit

extension OBDManager {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Terminal Logging Helpers
    // ─────────────────────────────────────────────────────────────────────────

    public func sendManualCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logTx(trimmed)
        sendCommandRaw(trimmed)
    }

    public func copyTerminalLogToClipboard() {
        let lines = terminalEntries.map { entry in
            let dir = entry.direction == .tx ? "TX > " : (entry.direction == .rx ? "RX < " : "SYS: ")
            return "[\(entry.timestamp)] \(dir)\(entry.text)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = lines
        logSystem("✔ Log in die Zwischenablage kopiert (\(terminalEntries.count) Zeilen).")
    }

    public func clearTerminalLogs() {
        terminalEntries.removeAll()
        debugLogs.removeAll()
    }

    internal func logTx(_ text: String) {
        appendTerminal(direction: .tx, text: text, style: .normal)
    }

    internal func logRx(_ text: String) {
        let style: OBDTerminalEntry.EntryStyle
        if text.contains("41") || text.contains("OK") {
            style = .success
        } else if text.contains("ERROR") || text.contains("UNABLE") || text.contains("STOPPED") {
            style = .error
        } else if text.contains("SEARCHING") || text.contains("NODATA") {
            style = .warning
        } else {
            style = .normal
        }
        appendTerminal(direction: .rx, text: text, style: style)
    }

    internal func logSystem(_ text: String) {
        appendTerminal(direction: .system, text: text, style: .normal)
    }

    private func appendTerminal(direction: OBDTerminalEntry.Direction, text: String, style: OBDTerminalEntry.EntryStyle) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let entry = OBDTerminalEntry(timestamp: time, direction: direction, text: text, style: style)
        terminalEntries.insert(entry, at: 0)
        if terminalEntries.count > 300 { terminalEntries.removeLast() }

        let prefix = direction == .tx ? "TX: " : (direction == .rx ? "RX: " : "")
        debugLogs.insert("[\(time)] \(prefix)\(text)", at: 0)
        if debugLogs.count > 60 { debugLogs.removeLast() }
    }
}
