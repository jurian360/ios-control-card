//
//  Control_CardApp.swift
//  Control Card
//
//  Created by Raoul Brahim on 11-03-2025.
//

import SwiftUI

@main
struct Control_CardApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
