//
//  HistoryExercise.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class HistoryExercise {
    @Attribute(.unique) var id: UUID = UUID()

    var order: Int
    var name: String

    @Relationship(deleteRule: .cascade)
    var sets: [HistorySet] = []

    @Relationship
    var history: WorkoutHistory?

    init(order: Int,
         name: String,
         history: WorkoutHistory? = nil)
    {
        self.order = order
        self.name = name
        self.history = history
    }
}
