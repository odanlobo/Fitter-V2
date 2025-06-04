//
//  PreviewData.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 17/05/25.
//

import SwiftUI
import SwiftData

@MainActor
class PreviewData {
    /// Usuário fictício único para preview (id fixo)
    static let sharedMockUser: AppUser = {
        AppUser(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Daniel Lobo",
            birthDate: Calendar.current.date(from: DateComponents(year: 1995, month: 5, day: 15))!,
            height: 1.78,
            weight: 75.0,
            provider: "mock",
            providerId: "mock_id",
            email: "daniel@example.com",
            profilePictureURL: nil,
            locale: "pt_BR",
            gender: "masculino"
        )
    }()

    static var container: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(
                for: WorkoutPlan.self,
                PlanExercise.self,
                ExerciseTemplate.self,
                WorkoutHistory.self,
                HistoryExercise.self,
                HistorySet.self,
                AppUser.self,
                configurations: config
            )
            populateData(container: container)
            return container
        } catch {
            fatalError("Erro ao criar container para preview: \(error)")
        }
    }
    
    /// Usuário fictício para preview
    static var mockUser: AppUser {
        sharedMockUser
    }
    
    private static func populateData(container: ModelContainer) {
        let context = container.mainContext
        
        let user = sharedMockUser
        context.insert(user)
        
        let templates = createExerciseTemplates()
        templates.forEach { context.insert($0) }
        
        let plans = createWorkoutPlans(templates: templates, user: user)
        for plan in plans {
            plan.user = user
            context.insert(plan)
            plan.exercises.forEach { context.insert($0) }
        }
        try? context.save()
        
        let histories = createWorkoutHistory(templates: templates)
        for hist in histories {
            context.insert(hist)
            hist.exercises.forEach { ex in
                context.insert(ex)
                ex.sets.forEach { context.insert($0) }
            }
        }
    }
    
    /// Templates de exercício fictícios
    static func createExerciseTemplates() -> [ExerciseTemplate] {
        [
            ExerciseTemplate(templateId: "peitoral_1", name: "Supino Reto", muscleGroup: .chest, equipment: "Barra"),
            ExerciseTemplate(templateId: "peitoral_2", name: "Supino Inclinado", muscleGroup: .chest, equipment: "Halteres"),
            ExerciseTemplate(templateId: "peitoral_3", name: "Crucifixo", muscleGroup: .chest, equipment: "Máquina"),
            ExerciseTemplate(templateId: "costas_1", name: "Puxada Frontal", muscleGroup: .back, equipment: "Polia"),
            ExerciseTemplate(templateId: "costas_2", name: "Remada Curvada", muscleGroup: .back, equipment: "Barra"),
            ExerciseTemplate(templateId: "costas_3", name: "Remada Sentada", muscleGroup: .back, equipment: "Máquina"),
            ExerciseTemplate(templateId: "pernas_1", name: "Agachamento Livre", muscleGroup: .legs, equipment: "Barra"),
            ExerciseTemplate(templateId: "pernas_2", name: "Leg Press", muscleGroup: .legs, equipment: "Máquina"),
            ExerciseTemplate(templateId: "pernas_3", name: "Extensora", muscleGroup: .legs, equipment: "Máquina"),
            ExerciseTemplate(templateId: "ombros_1", name: "Desenvolvimento", muscleGroup: .shoulders, equipment: "Barra"),
            ExerciseTemplate(templateId: "ombros_2", name: "Elevação Lateral", muscleGroup: .shoulders, equipment: "Halteres"),
            ExerciseTemplate(templateId: "biceps_1", name: "Rosca Direta", muscleGroup: .biceps, equipment: "Barra"),
            ExerciseTemplate(templateId: "biceps_2", name: "Rosca Martelo", muscleGroup: .biceps, equipment: "Halteres"),
            ExerciseTemplate(templateId: "triceps_1", name: "Tríceps Polia", muscleGroup: .triceps, equipment: "Polia"),
            ExerciseTemplate(templateId: "triceps_2", name: "Francês", muscleGroup: .triceps, equipment: "Haltere")
        ]
    }
    
    /// Planos de treino fictícios
    static func createWorkoutPlans(templates: [ExerciseTemplate], user: AppUser) -> [WorkoutPlan] {
        let planA = WorkoutPlan(title: "Treino A", user: user)
        planA.exercises = [
            PlanExercise(order: 0, plan: planA, template: templates[0]),
            PlanExercise(order: 1, plan: planA, template: templates[1]),
            PlanExercise(order: 2, plan: planA, template: templates[13]),
            PlanExercise(order: 3, plan: planA, template: templates[14])
        ]
        
        let planB = WorkoutPlan(title: "Treino B", user: user)
        planB.exercises = [
            PlanExercise(order: 0, plan: planB, template: templates[3]),
            PlanExercise(order: 1, plan: planB, template: templates[4]),
            PlanExercise(order: 2, plan: planB, template: templates[11]),
            PlanExercise(order: 3, plan: planB, template: templates[12])
        ]
        
        let planC = WorkoutPlan(title: "Treino C", user: user)
        planC.exercises = [
            PlanExercise(order: 0, plan: planC, template: templates[6]),
            PlanExercise(order: 1, plan: planC, template: templates[7]),
            PlanExercise(order: 2, plan: planC, template: templates[9]),
            PlanExercise(order: 3, plan: planC, template: templates[10])
        ]
        
        return [planA, planB, planC]
    }
    
    /// Históricos de treino fictícios
    private static func createWorkoutHistory(templates: [ExerciseTemplate]) -> [WorkoutHistory] {
        let today = Date()
        let calendar = Calendar.current
        func createHistory(date: Date, exercises: [(Int, Int, Int, Double)]) -> WorkoutHistory {
            let history = WorkoutHistory(date: date)
            history.exercises = exercises.enumerated().map { idx, entry in
                let exercise = HistoryExercise(order: idx, name: templates[entry.0].name)
                exercise.sets = (0..<entry.1).map { _ in
                    HistorySet(
                        reps: entry.2,
                        weight: entry.3,
                        rotationX: 0, rotationY: 0, rotationZ: 0,
                        accelerationX: 0, accelerationY: 0, accelerationZ: 0,
                        gravityX: 0, gravityY: 0, gravityZ: 0,
                        attitudeRoll: 0, attitudePitch: 0, attitudeYaw: 0
                    )
                }
                return exercise
            }
            return history
        }
        return [
            createHistory(date: today, exercises: [(0,4,12,60),(1,3,10,20),(13,4,12,25),(14,3,15,10)]),
            createHistory(date: calendar.date(byAdding: .day, value: -2, to: today)!, exercises: [(3,4,10,70),(4,3,12,50),(11,4,12,30),(12,3,12,16)]),
            createHistory(date: calendar.date(byAdding: .day, value: -4, to: today)!, exercises: [(6,4,8,100),(7,3,12,150),(9,4,10,40),(10,3,15,10)])
        ]
    }
}

// MARK: - Extensão para usar mock em previews
extension View {
    func withMockData() -> some View {
        @MainActor func getContainer() -> ModelContainer {
            PreviewData.container
        }
        return self.modelContainer(getContainer())
    }
}
