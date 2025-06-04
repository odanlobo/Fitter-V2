//
//  AppUser.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class AppUser {
    @Attribute(.unique) var id: UUID = UUID()

    // Dados básicos do usuário
    var name: String
    var birthDate: Date
    var height: Double
    var weight: Double

    // Autenticação social (opcional)
    var provider: String?    // "google", "facebook", "apple", etc.
    var providerId: String  // ID retornado pela rede social

    // Perfil
    var email: String?
    var profilePictureURL: URL?
    var locale: String?
    var gender: String?

    // Controle de sessão
    var lastLoginDate: Date?
    var createdAt: Date = Date()
    var updatedAt: Date?

    // Relações
    @Relationship(deleteRule: .cascade)
    var workoutPlans: [WorkoutPlan] = []

    @Relationship(deleteRule: .cascade)
    var workoutHistories: [WorkoutHistory] = []

    init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        height: Double,
        weight: Double,
        provider: String?,
        providerId: String,
        email: String?,
        profilePictureURL: URL?,
        locale: String?,
        gender: String?
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.height = height
        self.weight = weight
        self.provider = provider
        self.providerId = providerId
        self.email = email
        self.profilePictureURL = profilePictureURL
        self.locale = locale
        self.gender = gender
    }
}
