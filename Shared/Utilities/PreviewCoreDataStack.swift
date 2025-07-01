//
//  PreviewCoreDataStack.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/06/25.
//

import CoreData

struct PreviewCoreDataStack {
    static let shared: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Model")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load preview store: \(error)")
            }
        }
        
        // Cria dados mock simples para previews (sem depender do JSON)
        createMockExercisesForPreview(in: container.viewContext)
        
        // Cria usuário, treinos, histórico e sessão ativa
        PreviewDataLoader.populatePreviewData(in: container.viewContext)
        return container
    }()
    
    /// Cria exercícios mock simples para previews
    private static func createMockExercisesForPreview(in context: NSManagedObjectContext) {
        // Exercícios básicos para testes de preview
        let mockExercises = [
            ("chest_1", "Supino Reto", "chest", "Barra", "Pronada"),
            ("back_1", "Puxada Aberta", "back", "Polia", "Pronada"),
            ("shoulders_1", "Desenvolvimento", "shoulders", "Halteres", "Neutra"),
            ("biceps_1", "Rosca Direta", "biceps", "Barra", "Pronada"),
            ("legs_1", "Agachamento", "legs", "Peso do Corpo", nil)
        ]
        
        for (templateId, name, muscleGroup, equipment, grip) in mockExercises {
            let template = CDExerciseTemplate(context: context)
            template.id = UUID()
            template.templateId = templateId
            template.name = name
            template.muscleGroup = muscleGroup
            template.equipment = equipment
            template.gripVariation = grip
            template.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        }
        
        try? context.save()
        print("✅ Mock exercises criados para preview")
    }
}
