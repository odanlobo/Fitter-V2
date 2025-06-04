//
//  PersistenceController.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()
    let container: ModelContainer

    private init() {
        do {
            container = try ModelContainer(
                for: AppUser.self,
                     ExerciseTemplate.self,
                     WorkoutPlan.self,
                     PlanExercise.self,
                     WorkoutHistory.self,
                     HistoryExercise.self,
                     HistorySet.self
            )
            
            // Popular templates de exercício se necessário (assincronamente na MainActor)
            let containerInstance = container
            Task { @MainActor in
                DataSeeder.seedIfNeeded(into: containerInstance.mainContext)
            }
            
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
}
