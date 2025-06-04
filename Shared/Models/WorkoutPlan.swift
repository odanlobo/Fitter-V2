//
//  WorkoutPlan.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade)
    var exercises: [PlanExercise] = []
    var order: Int = 0
    
    // Novo: Relacionamento para AppUser (multiusuário)
    @Relationship var user: AppUser?
    
    /// Exibe os grupos musculares concatenados em ordem de seleção
    var muscleGroups: String {
        exercises
            .compactMap { $0.template?.muscleGroup.rawValue.capitalized }
            .joined(separator: " + ")
    }
    
    /// Validações antes de salvar
    var isValid: Bool {
        !exercises.isEmpty && !title.isEmpty
    }
    
    /// Inicializador padrão (útil em previews e criação sem exercícios iniciais)
    init(
        title: String,
        createdAt: Date = Date(),
        order: Int = 0,
        user: AppUser? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.order = order
        self.user = user
    }
    
    /// Inicializador para carregar um treino já existente com ao menos um exercício
    init(
        title: String,
        initialExercise: PlanExercise,
        createdAt: Date = Date(),
        order: Int = 0,
        user: AppUser? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.order = order
        self.exercises = [initialExercise]
        self.user = user
    }
    
    /// Verifica se o plano está pronto para salvar
    func validateForSave() throws {
        guard !exercises.isEmpty else {
            throw WorkoutPlanError.noExercises
        }
        guard !title.isEmpty else {
            throw WorkoutPlanError.noTitle
        }
    }
}

// MARK: - Comparable

extension WorkoutPlan {
    static func < (lhs: WorkoutPlan, rhs: WorkoutPlan) -> Bool {
        lhs.order < rhs.order
    }
}

enum WorkoutPlanError: LocalizedError {
    case noExercises
    case noTitle
    
    var errorDescription: String? {
        switch self {
            case .noExercises:
                return "Um plano de treino deve ter pelo menos um exercício"
            case .noTitle:
                return "O plano de treino precisa ter um título"
        }
    }
}
