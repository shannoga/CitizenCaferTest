import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            BrowseView(store: store.scope(state: \.browse, action: \.browse))
        } destination: { pathStore in
            switch pathStore.case {
            case .study(let studyStore):
                StudyView(store: studyStore)
            }
        }
        .tint(Brand.textPrimary)
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
