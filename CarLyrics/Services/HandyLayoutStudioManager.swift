// MARK: - HandyLayoutStudioManager.swift
// Freies 2D Studio-Layout-System für das Handy-Cockpit
// Ermöglicht freies Verschieben (X, Y), Skalieren/Ziehen (Breite, Höhe), Mehrfach-Markierung und Reset
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct WidgetFreeformTransform: Codable, Equatable {
    public var x: CGFloat = 0
    public var y: CGFloat = 0
    public var widthOffset: CGFloat = 0
    public var heightOffset: CGFloat = 0
    public var scale: CGFloat = 1.0

    public init(x: CGFloat = 0, y: CGFloat = 0, widthOffset: CGFloat = 0, heightOffset: CGFloat = 0, scale: CGFloat = 1.0) {
        self.x = x
        self.y = y
        self.widthOffset = widthOffset
        self.heightOffset = heightOffset
        self.scale = scale
    }
}

public final class HandyLayoutStudioManager: ObservableObject {
    public static let shared = HandyLayoutStudioManager()

    @AppStorage("carlyrics_studio_edit_mode") public var isEditModeActive: Bool = false
    @Published public var selectedWidgetId: String? = nil
    @Published public var transforms: [String: WidgetFreeformTransform] = [:]

    private let storageKey = "carlyrics_freeform_transforms_v2"

    public init() {
        loadTransforms()
    }

    public func transform(for id: String) -> WidgetFreeformTransform {
        transforms[id] ?? WidgetFreeformTransform()
    }

    public func setPosition(id: String, x: CGFloat, y: CGFloat) {
        var current = transform(for: id)
        current.x = x
        current.y = y
        transforms[id] = current
        saveTransforms()
    }

    public func setSize(id: String, widthOffset: CGFloat, heightOffset: CGFloat) {
        var current = transform(for: id)
        current.widthOffset = widthOffset
        current.heightOffset = heightOffset
        transforms[id] = current
        saveTransforms()
    }

    public func resetAll() {
        transforms.removeAll()
        selectedWidgetId = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func saveTransforms() {
        if let data = try? JSONEncoder().encode(transforms) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTransforms() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: WidgetFreeformTransform].self, from: data) {
            self.transforms = decoded
        }
    }

    public func exportJSON() -> String {
        let export: [String: Any] = [
            "version": 2,
            "transforms": transforms.mapValues { [
                "x": $0.x,
                "y": $0.y,
                "widthOffset": $0.widthOffset,
                "heightOffset": $0.heightOffset,
                "scale": $0.scale
            ] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Freeform Canvas Item Wrapper
// ─────────────────────────────────────────────────────────────────────────────

public struct FreeformStudioItem<Content: View>: View {
    public let id: String
    public let title: String
    @ObservedObject private var studio = HandyLayoutStudioManager.shared
    @ViewBuilder public let content: () -> Content

    @State private var dragStartPos: CGPoint = .zero
    @State private var dragCurrentOffset: CGSize = .zero
    @State private var resizeStartSize: CGSize = .zero
    @State private var resizeCurrentDelta: CGSize = .zero

    public init(id: String, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.content = content
    }

    private var isSelected: Bool {
        studio.selectedWidgetId == id
    }

    private var currentTransform: WidgetFreeformTransform {
        studio.transform(for: id)
    }

    public var body: some View {
        let activeX = currentTransform.x + dragCurrentOffset.width
        let activeY = currentTransform.y + dragCurrentOffset.height
        let activeW = max(-100, currentTransform.widthOffset + resizeCurrentDelta.width)
        let activeH = max(-60, currentTransform.heightOffset + resizeCurrentDelta.height)

        ZStack(alignment: .bottomTrailing) {
            content()
                .padding(.horizontal, activeW > 0 ? activeW / 2 : 0)
                .frame(minHeight: max(40, 60 + activeH))
                .contentShape(Rectangle())
                .onTapGesture {
                    if studio.isEditModeActive {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            studio.selectedWidgetId = (studio.selectedWidgetId == id) ? nil : id
                        }
                    }
                }

            // Wenn Studio-Modus aktiv: Interaktiver Rahmen & Griffe
            if studio.isEditModeActive {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isSelected ? Color.cyan : Color.white.opacity(0.2),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 4])
                        )
                        .shadow(color: isSelected ? Color.cyan.opacity(0.6) : .clear, radius: 8)

                    // Titel-Pill bei Selektion
                    if isSelected {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text(title)
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.cyan, in: Capsule())
                            .offset(x: 10, y: -10)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        // Resize-Griff unten rechts
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.black)
                            )
                            .shadow(color: Color.cyan.opacity(0.8), radius: 6)
                            .offset(x: 8, y: 8)
                            .gesture(
                                DragGesture()
                                    .onChanged { val in
                                        resizeCurrentDelta = val.translation
                                    }
                                    .onEnded { val in
                                        studio.setSize(
                                            id: id,
                                            widthOffset: currentTransform.widthOffset + val.translation.width,
                                            heightOffset: currentTransform.heightOffset + val.translation.height
                                        )
                                        resizeCurrentDelta = .zero
                                    }
                            )
                    }
                }
                .allowsHitTesting(isSelected)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            guard isSelected else { return }
                            dragCurrentOffset = val.translation
                        }
                        .onEnded { val in
                            guard isSelected else { return }
                            studio.setPosition(
                                id: id,
                                x: currentTransform.x + val.translation.width,
                                y: currentTransform.y + val.translation.height
                            )
                            dragCurrentOffset = .zero
                        }
                )
            }
        }
        .offset(x: activeX, y: activeY)
    }
}
