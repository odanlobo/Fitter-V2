//
//  HistorySet.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

// Shared/Models/HistorySet.swift
//
//  HistorySet.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class HistorySet {
    @Attribute(.unique) var id: UUID = UUID()

    // Meta do usuário vs. contagem automática
    var reps: Int               // número de repetições alvo definidas pelo usuário
    var repsCounter: Int?       // contagem de reps pelo modelo de ML

    // Dados de performance
    var weight: Double          // peso utilizado

    // timestamps da série
    var startTime: Date?        // início da série
    var endTime: Date?          // fim da série
    var timestamp: Date = Date()// marca de coleta dos sensores

    // tempo de descanso após esta série (em segundos)
    var restTime: Double?

    // Dados de sensores do Watch
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double

    var accelerationX: Double
    var accelerationY: Double
    var accelerationZ: Double

    var gravityX: Double
    var gravityY: Double
    var gravityZ: Double

    var attitudeRoll: Double
    var attitudePitch: Double
    var attitudeYaw: Double

    // Dados fisiológicos
    var heartRate: Int?         // batimentos por minuto
    var caloriesBurned: Double? // calorias queimadas

    @Relationship
    var exercise: HistoryExercise?

    init(
        reps: Int,
        weight: Double,
        startTime: Date? = nil,
        endTime: Date? = nil,
        timestamp: Date = Date(),
        restTime: Double? = nil,
        rotationX: Double,
        rotationY: Double,
        rotationZ: Double,
        accelerationX: Double,
        accelerationY: Double,
        accelerationZ: Double,
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double,
        attitudeRoll: Double,
        attitudePitch: Double,
        attitudeYaw: Double,
        heartRate: Int? = nil,
        caloriesBurned: Double? = nil,
        repsCounter: Int? = nil,
        exercise: HistoryExercise? = nil
    ) {
        self.reps = reps
        self.repsCounter = repsCounter
        self.weight = weight
        self.startTime = startTime
        self.endTime = endTime
        self.timestamp = timestamp
        self.restTime = restTime
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
        self.attitudeRoll = attitudeRoll
        self.attitudePitch = attitudePitch
        self.attitudeYaw = attitudeYaw
        self.heartRate = heartRate
        self.caloriesBurned = caloriesBurned
        self.exercise = exercise
    }
}
