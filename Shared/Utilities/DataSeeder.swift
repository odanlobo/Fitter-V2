//
//  DataSeeder.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 14/05/25.
//

import Foundation
import SwiftData

/// Auxiliar para decodificar o catálogo de exercícios a partir de JSON.
struct ExerciseEntry: Decodable {
    let templateId: String
    let name: String
    let muscleGroup: String
    let legSubgroup: String?
    let equipment: String
    let gripVariation: String?
    let imageName: String?
}

struct DataSeeder {
    static func seedIfNeeded(into context: ModelContext) {
        // Verifica se já existem templates
        let request = FetchDescriptor<ExerciseTemplate>()
        if let existing: [ExerciseTemplate] = try? context.fetch(request), !existing.isEmpty {
            return // já populado
        }

        // Localiza o JSON no bundle
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            print("⚠️ exercises.json não encontrado no bundle")
            return
        }

        // Decodifica JSON
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ExerciseEntry].self, from: data)
        else {
            print("⚠️ Falha ao decodificar exercises.json")
            return
        }

        // Insere cada template no contexto
        for entry in entries {
            guard let group = MuscleGroup(rawValue: entry.muscleGroup) else { continue }
            let subgroup = entry.legSubgroup.flatMap { LegSubgroup(rawValue: $0) }
            let template = ExerciseTemplate(
                templateId:    entry.templateId,
                name:          entry.name,
                muscleGroup:   group,
                legSubgroup:   subgroup,
                equipment:     entry.equipment,
                gripVariation: entry.gripVariation,
                imageName:     entry.imageName
            )
            context.insert(template)
        }

        // Salva no contexto
        do {
            try context.save()
        } catch {
            print("❌ Erro ao salvar templates no banco: \(error)")
        }
    }
}
