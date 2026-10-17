// MARK: - SpotifySetupSheet.swift
// Spotify Authentifizierungs-Modal (1-Klick OAuth & Token Eingabe)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct SpotifySetupSheet: View {
    @ObservedObject var spotify: SpotifyManager
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var refreshToken = ""

    public init(spotify: SpotifyManager) {
        self.spotify = spotify
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Verbindungsstatus") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(spotify.isAuthenticated ? "Verbunden" : "Nicht verbunden")
                            .foregroundStyle(spotify.isAuthenticated ? .green : .red)
                    }
                    if let err = spotify.lastSyncError {
                        Text("Status: \(err)").font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("1-Klick Login (Dauerhaft)") {
                    Text("Um Spotify direkt abzufragen, erstelle eine kostenlose App im Spotify Developer Dashboard:")
                        .font(.caption).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. developer.spotify.com/dashboard öffnen").font(.caption2)
                        Text("2. 'Create App' anklicken").font(.caption2)
                        Text("3. Redirect URI eintragen:").font(.caption2)
                        Text("carlyrics://spotify-callback")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("4. Client ID kopieren und unten einfügen:").font(.caption2)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        TextField("Spotify Client ID", text: $clientId)
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !clientId.isEmpty {
                            Button {
                                clientId = ""
                                spotify.clientId = ""
                                UserDefaults.standard.removeObject(forKey: "spotify_client_id")
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !clientId.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WICHTIG bei 'redirect uri not matching config':")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                            Text("Falls du eine bestehende Client ID nutzt, öffne developer.spotify.com/dashboard -> deine App -> Settings -> trage unter 'Redirect URIs' exakt ein:")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("carlyrics://spotify-callback")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("und klicke ganz unten auf 'Save'!")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        spotify.clientId = clientId.trimmingCharacters(in: .whitespaces)
                        spotify.startWebAuthSession { success in
                            if success { dismiss() }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title3)
                            Text("Mit Spotify einloggen")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(CockpitButtonStyle(color: .green))
                    .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty)

                    if clientId.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("⚠ Trage zuerst deine Client ID ein, um 'client id invalid' zu verhindern.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Alternativ: Manueller Access Token") {
                    Text("Einmaliger 1-Stunden Token von developer.spotify.com:")
                        .font(.caption).foregroundStyle(.secondary)

                    TextField("Bearer Token", text: $token)
                        .font(.system(.caption, design: .monospaced))

                    Button("Speichern & Starten") {
                        spotify.accessToken = token
                        spotify.startPolling()
                        dismiss()
                    }
                    .disabled(token.isEmpty)
                }

                Section("Dauerbetrieb (Auto-Refresh)") {
                    Text("Optional: Mit Client ID und Refresh Token erneuert die App den Token während der Fahrt vollautomatisch:")
                        .font(.caption).foregroundStyle(.secondary)

                    TextField("Client ID", text: $clientId)
                        .font(.caption)
                    SecureField("Client Secret", text: $clientSecret)
                        .font(.caption)
                    TextField("Refresh Token", text: $refreshToken)
                        .font(.caption)

                    Button("Dauerhafte Verbindung speichern") {
                        if !clientId.isEmpty { spotify.clientId = clientId }
                        if !clientSecret.isEmpty { spotify.clientSecret = clientSecret }
                        if !refreshToken.isEmpty {
                            spotify.refreshToken = refreshToken
                            Task {
                                await spotify.refreshAccessToken()
                                spotify.startPolling()
                                dismiss()
                            }
                        }
                    }
                    .disabled(clientId.isEmpty || refreshToken.isEmpty)
                }
            }
            .navigationTitle("Spotify Connect")
            .onAppear {
                token = spotify.accessToken
                clientId = spotify.clientId
                clientSecret = spotify.clientSecret
                refreshToken = spotify.refreshToken
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
