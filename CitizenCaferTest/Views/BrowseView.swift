import ComposableArchitecture
import SwiftUI

struct BrowseView: View {
    let store: StoreOf<BrowseFeature>

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
                Text("Choose what to study")
                    .font(.brandDisplay(30))
                    .foregroundStyle(Brand.textPrimary)

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
                        .font(.headline)
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
                        .font(.footnote)
                        .foregroundStyle(Brand.textMuted)
                }
            }
            .padding(Brand.Space.lg)
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
        select: @escaping (Option) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { select(option) }
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
                Text(value ?? "Choose")
                    .foregroundStyle(value == nil ? Brand.textMuted : Brand.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Brand.textMuted)
            }
            .padding(Brand.Space.md)
        }
        .disabled(options.isEmpty)
        .accessibilityLabel("\(title): \(value ?? "not chosen")")
    }

    // MARK: - Error

    private func failed(_ message: String) -> some View {
        VStack(spacing: Brand.Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Brand.textMuted)

            Text("Couldn't load the vocabulary")
                .font(.brandDisplay(22))
                .foregroundStyle(Brand.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)

            Button("Try again") { store.send(.retryButtonTapped) }
                .font(.headline)
                .foregroundStyle(Brand.charcoal)
                .padding(.horizontal, Brand.Space.lg)
                .frame(height: 48)
                .background(Brand.yellow, in: Capsule())
                .padding(.top, Brand.Space.sm)
        }
        .padding(Brand.Space.xl)
    }
}
