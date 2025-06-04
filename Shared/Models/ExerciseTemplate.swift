//
//  ExerciseTemplate.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import SwiftData

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest, back, shoulders, biceps, triceps, legs, core
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .chest:     return "Peitoral"
        case .back:      return "Costas"
        case .shoulders: return "Ombros"
        case .biceps:    return "Bíceps"
        case .triceps:   return "Tríceps"
        case .legs:      return "Pernas"
        case .core:      return "Abdômen"
        }
    }
}

enum LegSubgroup: String, CaseIterable, Identifiable, Codable {
    case quadriceps     = "Quadríceps"
    case hamstrings     = "Posterior de Coxa"
    case glutes         = "Glúteos"
    case calves         = "Panturrilha"
    var id: String { rawValue }
}

@Model
final class ExerciseTemplate {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var templateId: String

    /// Nome do exercício
    var name: String

    /// Grupo muscular principal
    var muscleGroup: MuscleGroup

    /// Subdivisão de perna (preenchido apenas se muscleGroup == .legs)
    var legSubgroup: LegSubgroup?

    /// Equipamento utilizado
    var equipment: String

    /// Variação de pegada (Pronada, Supinada, Neutra)
    var gripVariation: String?

    /// Nome do asset de imagem (opcional)
    var imageName: String?

    /// Relação com PlanExercise
    @Relationship(deleteRule: .cascade, inverse: \PlanExercise.template)
    var planExercises: [PlanExercise]

    init(
        id: UUID = UUID(),
        templateId: String,
        name: String,
        muscleGroup: MuscleGroup,
        legSubgroup: LegSubgroup? = nil,
        equipment: String,
        gripVariation: String? = nil,
        imageName: String? = nil,
        planExercises: [PlanExercise] = []
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.muscleGroup = muscleGroup
        self.legSubgroup = legSubgroup
        self.equipment = equipment
        self.gripVariation = gripVariation
        self.imageName = imageName
        self.planExercises = planExercises
    }
}
