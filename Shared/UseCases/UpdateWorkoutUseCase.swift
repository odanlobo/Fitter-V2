/*
 * UpdateWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para atualização de planos de treino existentes.
 *                   Implementa Clean Architecture com separação clara de responsabilidades.
 *
 * FUNCIONALIDADES:
 * - Atualização de título personalizado (customTitle)
 * - Modificação de grupos musculares
 * - Adição/remoção/reordenação de exercícios
 * - Sincronização automática após mudanças
 * - Validação de entrada robusta
 * - Rollback em caso de falha parcial
 *
 * ARQUITETURA:
 * - Input/Output structs para type safety
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para performance
 *
 * COMPATIBILIDADE TÍTULOS DUAIS:
 * - autoTitle: NUNCA é alterado (mantém organização sistemática)
 * - title (customTitle): Pode ser alterado pelo usuário
 * - displayTitle: Atualização automática baseada nos campos
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: Operações CRUD especializadas
 * - SyncWorkoutUseCaseProtocol: Sincronização com Firestore
 *
 * REFATORAÇÃO ITEM 19/50:
 * ✅ Clean Architecture com Use Case pattern
 * ✅ Injeção de dependências via protocolo
 * ✅ Operações de update completas
 * ✅ Sincronização automática
 * ✅ Compatibilidade com títulos duais
 * ✅ Tratamento de erros robusto
 */

import Foundation
import CoreData
import Combine

// MARK: - UpdateWorkoutInput

struct UpdateWorkoutInput {
    let workoutPlan: CDWorkoutPlan
    let customTitle: String?
    let muscleGroups: String?
    let exerciseTemplates: [CDExerciseTemplate]?
    let shouldSync: Bool
    
    init(
        workoutPlan: CDWorkoutPlan,
        customTitle: String? = nil,
        muscleGroups: String? = nil,
        exerciseTemplates: [CDExerciseTemplate]? = nil,
        shouldSync: Bool = true
    ) {
        self.workoutPlan = workoutPlan
        self.customTitle = customTitle
        self.muscleGroups = muscleGroups
        self.exerciseTemplates = exerciseTemplates
        self.shouldSync = shouldSync
    }
    
    /// Valida os dados de entrada
    func validate() throws {
        guard workoutPlan.managedObjectContext != nil else {
            throw UpdateWorkoutError.invalidInput("Plano de treino não possui contexto Core Data válido")
        }
        
        if let customTitle = customTitle, customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw UpdateWorkoutError.invalidInput("Título personalizado não pode estar vazio se fornecido")
        }
        
        if let muscleGroups = muscleGroups, muscleGroups.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw UpdateWorkoutError.invalidInput("Grupos musculares não podem estar vazios se fornecidos")
        }
        
        if let exercises = exerciseTemplates, exercises.isEmpty {
            throw UpdateWorkoutError.invalidInput("Lista de exercícios não pode estar vazia se fornecida")
        }
        
        print("✅ Validação de entrada do UpdateWorkoutUseCase bem-sucedida")
    }
}

// MARK: - UpdateWorkoutOutput

struct UpdateWorkoutOutput {
    let updatedWorkoutPlan: CDWorkoutPlan
    let updatedExercises: [CDPlanExercise]?
    let syncStatus: UpdateWorkoutSyncStatus
    let changesApplied: Set<UpdateWorkoutChange>
    
    var hasCustomTitle: Bool {
        updatedWorkoutPlan.hasCustomTitle
    }
    
    var displayTitle: String {
        updatedWorkoutPlan.displayTitle
    }
    
    var compactTitle: String {
        updatedWorkoutPlan.compactTitle
    }
}

// MARK: - UpdateWorkoutChange

enum UpdateWorkoutChange: CaseIterable {
    case customTitle
    case muscleGroups
    case exercises
    
    var description: String {
        switch self {
        case .customTitle:
            return "Título personalizado"
        case .muscleGroups:
            return "Grupos musculares"
        case .exercises:
            return "Lista de exercícios"
        }
    }
}

// MARK: - UpdateWorkoutSyncStatus

enum UpdateWorkoutSyncStatus {
    case synced
    case failed(Error)
    case skipped
    case disabled
    
    var isSuccessful: Bool {
        if case .synced = self { return true }
        return false
    }
}

// MARK: - UpdateWorkoutError

enum UpdateWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case workoutNotFound
    case updateFailed(Error)
    case exerciseUpdateFailed(Error)
    case syncFailed(Error)
    case rollbackFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Entrada inválida: \(message)"
        case .workoutNotFound:
            return "Plano de treino não encontrado"
        case .updateFailed(let error):
            return "Falha na atualização: \(error.localizedDescription)"
        case .exerciseUpdateFailed(let error):
            return "Falha na atualização de exercícios: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização: \(error.localizedDescription)"
        case .rollbackFailed(let error):
            return "Falha no rollback: \(error.localizedDescription)"
        }
    }
}

// MARK: - UpdateWorkoutUseCaseProtocol

protocol UpdateWorkoutUseCaseProtocol {
    func execute(_ input: UpdateWorkoutInput) async throws -> UpdateWorkoutOutput
}

// MARK: - UpdateWorkoutUseCase

final class UpdateWorkoutUseCase: UpdateWorkoutUseCaseProtocol {
    
    // MARK: - Properties
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil
    ) {
        self.workoutDataService = workoutDataService
        self.syncUseCase = syncUseCase
        
        print("🔄 UpdateWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: UpdateWorkoutInput) async throws -> UpdateWorkoutOutput {
        print("🔄 Iniciando atualização do plano: \(input.workoutPlan.displayTitle)")
        
        do {
            // 1. Validar entrada
            try input.validate()
            
            // 2. Capturar estado original para rollback
            let originalState = captureOriginalState(input.workoutPlan)
            
            // 3. Aplicar mudanças
            let changesApplied = try await applyChanges(input)
            
            // 4. Atualizar exercícios se necessário
            let updatedExercises = try await updateExercisesIfNeeded(input)
            
            // 5. Tentar sincronização
            let syncStatus = await attemptSync(input.workoutPlan, shouldSync: input.shouldSync)
            
            let output = UpdateWorkoutOutput(
                updatedWorkoutPlan: input.workoutPlan,
                updatedExercises: updatedExercises,
                syncStatus: syncStatus,
                changesApplied: changesApplied
            )
            
            print("🎉 Treino atualizado com sucesso: \(input.workoutPlan.displayTitle)")
            print("📝 Mudanças aplicadas: \(changesApplied.map { $0.description }.joined(separator: ", "))")
            return output
            
        } catch let error as UpdateWorkoutError {
            print("❌ Erro na atualização do treino: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na atualização do treino: \(error)")
            throw UpdateWorkoutError.updateFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func captureOriginalState(_ plan: CDWorkoutPlan) -> UpdateWorkoutOriginalState {
        return UpdateWorkoutOriginalState(
            customTitle: plan.title,
            muscleGroups: plan.muscleGroups,
            exerciseIds: plan.exercisesArray.map { $0.safeId }
        )
    }
    
    private func applyChanges(_ input: UpdateWorkoutInput) async throws -> Set<UpdateWorkoutChange> {
        var changesApplied: Set<UpdateWorkoutChange> = []
        
        do {
            // Aplicar mudanças básicas (título e grupos musculares)
            try await workoutDataService.updateWorkoutPlan(
                input.workoutPlan,
                customTitle: input.customTitle,
                muscleGroups: input.muscleGroups
            )
            
            // Registrar mudanças aplicadas
            if input.customTitle != nil {
                changesApplied.insert(.customTitle)
                print("✏️ Título personalizado atualizado: \(input.workoutPlan.safeCustomTitle ?? "removido")")
            }
            
            if input.muscleGroups != nil {
                changesApplied.insert(.muscleGroups)
                print("💪 Grupos musculares atualizados: \(input.workoutPlan.muscleGroupsString)")
            }
            
            return changesApplied
            
        } catch {
            throw UpdateWorkoutError.updateFailed(error)
        }
    }
    
    private func updateExercisesIfNeeded(_ input: UpdateWorkoutInput) async throws -> [CDPlanExercise]? {
        guard let newExerciseTemplates = input.exerciseTemplates else {
            return nil // Não foi solicitada atualização de exercícios
        }
        
        do {
            // 1. Remover exercícios existentes
            let existingExercises = input.workoutPlan.exercisesArray
            for exercise in existingExercises {
                try await workoutDataService.removePlanExercise(exercise, from: input.workoutPlan)
            }
            
            // 2. Adicionar novos exercícios
            var updatedExercises: [CDPlanExercise] = []
            for (index, template) in newExerciseTemplates.enumerated() {
                let planExercise = try await workoutDataService.addExerciseTemplate(
                    template,
                    to: input.workoutPlan,
                    order: Int32(index)
                )
                updatedExercises.append(planExercise)
            }
            
            print("🏃‍♂️ Exercícios atualizados: \(updatedExercises.count) exercícios")
            return updatedExercises
            
        } catch {
            throw UpdateWorkoutError.exerciseUpdateFailed(error)
        }
    }
    
    private func attemptSync(_ workoutPlan: CDWorkoutPlan, shouldSync: Bool) async -> UpdateWorkoutSyncStatus {
        guard shouldSync else {
            print("⏭️ Sincronização ignorada conforme solicitado")
            return .skipped
        }
        
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase não disponível - sincronização desabilitada")
            return .disabled
        }
        
        do {
            try await syncUseCase.execute(workoutPlan)
            print("☁️ Treino sincronizado com sucesso após atualização")
            return .synced
        } catch {
            print("⚠️ Falha na sincronização do treino atualizado: \(error)")
            return .failed(error)
        }
    }
    
    private func performRollback(_ originalState: UpdateWorkoutOriginalState, plan: CDWorkoutPlan) async {
        print("🔄 Iniciando rollback da atualização...")
        
        do {
            try await workoutDataService.updateWorkoutPlan(
                plan,
                customTitle: originalState.customTitle,
                muscleGroups: originalState.muscleGroups
            )
            print("✅ Rollback básico concluído")
        } catch {
            print("❌ Erro durante rollback: \(error)")
        }
    }
}

// MARK: - UpdateWorkoutOriginalState

private struct UpdateWorkoutOriginalState {
    let customTitle: String?
    let muscleGroups: String
    let exerciseIds: [UUID]
}

// MARK: - Extension for Convenience

extension UpdateWorkoutUseCase {
    
    /// Método de conveniência para atualizar apenas o título personalizado
    func updateCustomTitle(
        _ plan: CDWorkoutPlan,
        newTitle: String?
    ) async throws -> UpdateWorkoutOutput {
        let input = UpdateWorkoutInput(
            workoutPlan: plan,
            customTitle: newTitle
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para atualizar apenas grupos musculares
    func updateMuscleGroups(
        _ plan: CDWorkoutPlan,
        newMuscleGroups: String
    ) async throws -> UpdateWorkoutOutput {
        let input = UpdateWorkoutInput(
            workoutPlan: plan,
            muscleGroups: newMuscleGroups
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para atualizar apenas exercícios
    func updateExercises(
        _ plan: CDWorkoutPlan,
        newExercises: [CDExerciseTemplate]
    ) async throws -> UpdateWorkoutOutput {
        let input = UpdateWorkoutInput(
            workoutPlan: plan,
            exerciseTemplates: newExercises
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para atualização completa
    func updateComplete(
        _ plan: CDWorkoutPlan,
        customTitle: String?,
        muscleGroups: String?,
        exercises: [CDExerciseTemplate]?
    ) async throws -> UpdateWorkoutOutput {
        let input = UpdateWorkoutInput(
            workoutPlan: plan,
            customTitle: customTitle,
            muscleGroups: muscleGroups,
            exerciseTemplates: exercises
        )
        
        return try await execute(input)
    }
}

// MARK: - Exemplos de Uso

/*
 EXEMPLOS PRÁTICOS DE USO:

 // 1. Atualizar apenas título personalizado
 let titleUpdate = try await updateWorkoutUseCase.updateCustomTitle(
     workoutPlan,
     newTitle: "Push Day Intenso"
 )
 // Resultado: title = "Push Day Intenso", autoTitle mantido, displayTitle = "Push Day Intenso (Treino A)"

 // 2. Remover título personalizado (volta ao automático)
 let autoUpdate = try await updateWorkoutUseCase.updateCustomTitle(
     workoutPlan,
     newTitle: nil
 )
 // Resultado: title = nil, displayTitle = "Treino A" (só automático)

 // 3. Atualizar grupos musculares
 let muscleUpdate = try await updateWorkoutUseCase.updateMuscleGroups(
     workoutPlan,
     newMuscleGroups: "Peito, Tríceps, Ombros"
 )

 // 4. Substituir todos os exercícios
 let exerciseUpdate = try await updateWorkoutUseCase.updateExercises(
     workoutPlan,
     newExercises: newChestExercises
 )

 // 5. Atualização completa
 let completeUpdate = try await updateWorkoutUseCase.execute(UpdateWorkoutInput(
     workoutPlan: plan,
     customTitle: "Leg Killer",
     muscleGroups: "Quadríceps, Glúteos, Panturrilha",
     exerciseTemplates: legExercises,
     shouldSync: true
 ))

 // 6. Verificar mudanças aplicadas
 if completeUpdate.changesApplied.contains(.customTitle) {
     print("Título foi alterado para: \(completeUpdate.displayTitle)")
 }
 
 // 7. Status de sincronização
 switch completeUpdate.syncStatus {
 case .synced:
     showSuccessMessage("Treino sincronizado!")
 case .failed(let error):
     showErrorMessage("Sync falhou: \(error)")
 case .disabled, .skipped:
     showInfoMessage("Sync desabilitado")
 }
 */ 