import ComposableArchitecture
import SwiftUI
import UIKit

struct BrowseView: View {
    let store: StoreOf<BrowseFeature>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The lockup grows with the type scale so it stays proportionate to the title beneath it.
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 72

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            switch store.loadState {
            case .failed(let message):
                failed(message)
            case .loaded:
                picker
            case .loading:
                ProgressView("Loading vocabulary…")
                    .brandType(.bodySmall)
                    .tint(Brand.textMuted)
                    .foregroundStyle(Brand.textMuted)
            }
        }
        .navigationTitle("Citizen Café")
        .task { store.send(.task) }
    }

    // MARK: - Selection

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Space.lg) {
                header

                VStack(spacing: 0) {
                    menuRow(
                        title: "Tier",
                        value: store.selectedTier,
                        options: store.tiers,
                        label: { $0 },
                        select: { store.send(.tierSelected($0)) }
                    )

                    Divider().overlay(Brand.line)

                    menuRow(
                        title: "Level",
                        value: store.selectedLevel,
                        options: store.levels,
                        label: { $0 },
                        dotColor: { Self.levelColor(for: $0) },
                        select: { store.send(.levelSelected($0)) }
                    )

                    // Only levels with more than one content pack get a type selector.
                    if store.requiresTypeSelection {
                        Divider().overlay(Brand.line)

                        menuRow(
                            title: "Pack",
                            value: store.selectedType.map { "Pack \($0)" },
                            options: store.types,
                            label: { "Pack \($0)" },
                            select: { store.send(.typeSelected($0)) }
                        )
                    }
                }
                .background(Brand.raised, in: RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous))
                .hairlineBorder(radius: Brand.Radius.card)

                Button {
                    store.send(.startStudyingButtonTapped)
                } label: {
                    Text("Start studying")
                        .brandType(.buttonLabel)
                        .foregroundStyle(Brand.charcoal)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            store.canStartStudying ? Brand.yellow : Brand.line,
                            in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
                        )
                }
                .disabled(!store.canStartStudying)

                if let note = offlineNote {
                    Label(note, systemImage: "arrow.down.circle")
                        .brandType(.metaSmall)
                        .foregroundStyle(Brand.textMuted)
                }
            }
            .padding(Brand.Space.lg)
        }
    }

    /// The logo is decorative here: the navigation bar already announces "Citizen Café", so
    /// exposing the mark again would just make VoiceOver repeat the brand name.
    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Space.md) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous))
                // The mark's lower half is white, which would otherwise dissolve into the
                // off-white surface — the hairline is what keeps it reading as a lockup.
                .hairlineBorder(radius: Brand.Radius.control)
                .accessibilityHidden(true)

            Text("Choose what to study")
                .brandType(.h1)
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private var offlineNote: String? {
        switch store.source {
        case .bundled: "Offline — showing the words bundled with the app."
        case .cache: "Offline — showing the words saved on this device."
        case .none, .remote: nil
        }
    }

    private func menuRow<Option: Hashable>(
        title: String,
        value: String?,
        options: [Option],
        label: @escaping (Option) -> String,
        dotColor: ((String) -> Color?)? = nil,
        select: @escaping (Option) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    select(option)
                } label: {
                    menuItemLabel(label(option), dotColor: dotColor)
                }
            }
        } label: {
            // Side by side until the text outgrows the row: at accessibility sizes a long value
            // like "Foundation" would otherwise wrap mid-word against the title.
            let label = Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Brand.Space.sm) {
                        rowTitle(title)
                        HStack { rowValue(value, dotColor: dotColor); Spacer(); chevron }
                    }
                } else {
                    HStack {
                        rowTitle(title)
                        Spacer()
                        rowValue(value, dotColor: dotColor)
                        chevron
                    }
                }
            }

            label
                .brandType(.uiLabel)
                .padding(Brand.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(options.isEmpty)
        .accessibilityLabel("\(title): \(value ?? "not chosen")")
        .accessibilityIdentifier("picker.\(title)")
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title).foregroundStyle(Brand.textPrimary)
    }

    private func rowValue(_ value: String?, dotColor: ((String) -> Color?)? = nil) -> some View {
        HStack(spacing: Brand.Space.sm) {
            if let value, let color = dotColor?(value) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            Text(value ?? "Choose")
                .foregroundStyle(value == nil ? Brand.textMuted : Brand.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// A menu item's label is bridged to a native `UIMenu` entry: its icon is always forced to
    /// the menu's monochrome tint, so `foregroundStyle` on an SF Symbol is silently ignored. The
    /// only way to keep the actual color is to bake it into a bitmap and mark it `.original`.
    @ViewBuilder
    private func menuItemLabel(_ text: String, dotColor: ((String) -> Color?)?) -> some View {
        if let color = dotColor?(text) {
            Label {
                Text(text)
            } icon: {
                Image(uiImage: Self.dotImage(for: color))
                    .renderingMode(.original)
            }
        } else {
            Text(text)
        }
    }

    private static func dotImage(for color: Color) -> UIImage {
        let diameter: CGFloat = 14
        return UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { _ in
            UIColor(color).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .brandType(.metaSmall)
            .foregroundStyle(Brand.textMuted)
    }

    /// Levels are literally named after colors, so the dot just resolves the name to its asset
    /// catalog swatch — same convention as every other `Brand` color.
    private static func levelColor(for level: String) -> Color? {
        levelAssetNameByLevel[level].map { Color($0) }
    }

    private static let levelAssetNameByLevel: [String: String] = [
        "Red": "LevelRed",
        "Orange": "LevelOrange",
        "Pink": "LevelPink",
        "Yellow": "LevelYellow",
        "Light Blue": "LevelLightBlue",
        "Blue": "LevelBlue",
        "Lime": "LevelLime",
        "Green": "LevelGreen",
        "Dark Green": "LevelDarkGreen",
        "Turquoise": "LevelTurquoise",
        "Indigo": "LevelIndigo",
        "Purple": "LevelPurple",
    ]

    // MARK: - Error

    private func failed(_ message: String) -> some View {
        VStack(spacing: Brand.Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Brand.textMuted)

            Text("Couldn't load the vocabulary")
                .brandType(.h2)
                .foregroundStyle(Brand.textPrimary)

            Text(message)
                .brandType(.bodySmall)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)

            Button("Try again") { store.send(.retryButtonTapped) }
                .brandType(.buttonLabel)
                .foregroundStyle(Brand.charcoal)
                .padding(.horizontal, Brand.Space.lg)
                .frame(height: 48)
                .background(Brand.yellow, in: Capsule())
                .padding(.top, Brand.Space.sm)
        }
        .padding(Brand.Space.xl)
    }
}
