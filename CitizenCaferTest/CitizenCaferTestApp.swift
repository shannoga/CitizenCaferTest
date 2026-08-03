//
//  CitizenCaferTestApp.swift
//  CitizenCaferTest
//
//  Created by Shani Hajbi on 03/08/2026.
//

import ComposableArchitecture
import SwiftUI

@main
struct CitizenCaferTestApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        BrandTypography.applyNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
        }
    }
}
