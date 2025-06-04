//
//  WatchApp.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 08/05/25.
//

import SwiftUI
import SwiftData

@main
struct Fitter_V2_Watch_AppApp: App {
    @StateObject private var connectivity = ConnectivityManager.shared
    
    var body: some Scene {
        WindowGroup {
            if connectivity.isAuthenticated {
                WatchView()
            } else {
                PendingLoginView()
            }
        }
        // ← **injeção idêntica** do mesmo container compartilhado
        .modelContainer(PersistenceController.shared.container)
    }
}
