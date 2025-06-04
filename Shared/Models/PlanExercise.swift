//
//  PlanExercise.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class PlanExercise {
    @Attribute(.unique) var id: UUID = UUID()
    var order: Int

    // removendo o inverse
    @Relationship(deleteRule: .cascade)
    var plan: WorkoutPlan?

    @Relationship
    var template: ExerciseTemplate?

    init(
      order: Int,
      plan: WorkoutPlan? = nil,
      template: ExerciseTemplate? = nil
    ) {
        self.order = order
        self.plan = plan
        self.template = template
    }
}
