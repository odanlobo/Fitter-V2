//
//  WorkoutHistory.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class WorkoutHistory {
    @Attribute(.unique) var id: UUID = UUID()

    var date: Date = Date()

    @Relationship(deleteRule: .cascade)
    var exercises: [HistoryExercise] = []

    init(date: Date = Date()) {
        self.date = date
    }
}
