/*
 * ReorderExerciseUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para reordenação de exercícios dentro de um plano de treino.
 *                   Implementa Clean Architecture com orquestração de operações de persistência e sincronização.
 *
 * ARQUITETURA:
 * - Orquestra WorkoutDataService (persistência local)
 * - Orquestra SyncWorkoutUseCase (sincronização remota - quando disponível)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: CRUD e reordenação de exercícios em planos
 * - SyncWorkoutUseCaseProtocol: Sincronização remota (item 23 - opcional)
 *
 * FLUXO DE EXECUÇÃO:
 * 1. Validação de entrada (exercícios válidos, mesmo plano)
 * 2. Reordenação via WorkoutDataService (atualiza campo 'order' de CDPlanExercise)
 * 3. Sincronização do plano via SyncWorkoutUseCase (quando disponível)
 * 4. Retorno do resultado com status de sincronização
 *
 * LÓGICA DE REORDENAÇÃO:
 * - Recebe array de CDPlanExercise na nova ordem desejada
 * - Atualiza campo 'order' de cada exercício (0, 1, 2...)
 * - Marca cloudSyncStatus como 'pending' para sincronização
 * - Marca o plano pai também como 'pending'
 *
 * CASOS DE USO:
 * - Drag & drop de exercícios dentro de um plano
 * - Reorganização manual por preferência do usuário
 * - Ordenação automática por grupos musculares, equipamento, etc.
 *
 * VALIDAÇÕES ESPECÍFICAS:
 * - Todos os exercícios devem pertencer ao mesmo plano
 * - Exercícios devem ter templates válidos
 * - Plano pai deve estar disponível
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 *
 * REFATORAÇÃO ITEM 22/61:
 * ✅ Use Case de reordenação de exercícios com orquestração
 * ✅ Injeção de WorkoutDataService
 * ✅ Preparado para SyncWorkoutUseCase (item 23)
 * ✅ Clean Architecture - sem acesso direto ao Core Data
 * ✅ Tratamento de erros específicos do domínio
 */

import Foundation

// MARK: - ReorderExerciseError

enum ReorderExerciseError: Error, LocalizedError {
    case invalidInput(String)
    case emptyList
    case duplicateExercises
    case planMismatch
    case planNotFound
    case templateMissing
    case reorderFailed(Error)
    case syncFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Dados inválidos para reordenação de exercícios: \(message)"
        case .emptyList:
            return "Lista de exercícios não pode estar vazia"
        case .duplicateExercises:
            return "Lista contém exercícios duplicados"
        case .planMismatch:
            return "Todos os exercícios devem pertencer ao mesmo plano"
        case .planNotFound:
            return "Plano de treino não encontrado para os exercícios"
        case .templateMissing:
            return "Um ou mais exercícios não têm template válido"
        case .reorderFailed(let error):
            return "Falha na reordenação dos exercícios: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização da reordenação: \(error.localizedDescription)"
        }
    }
}

// MARK: - ReorderExerciseInput

struct ReorderExerciseInput {
    let planExercises: [CDPlanExercise]
    let workoutPlan: CDWorkoutPlan? // Para validação adicional
    
    /// Validação dos dados de entrada
    func validate() throws {
        // Validar lista não vazia
        guard !planExercises.isEmpty else {
            throw ReorderExerciseError.emptyList
        }
        
        // Validar que não há duplicatas (baseado no ID)
        let uniqueIds = Set(planExercises.map { $0.safeId })
        guard uniqueIds.count == planExercises.count else {
            throw ReorderExerciseError.duplicateExercises
        }
        
        // Validar que todos os exercícios pertencem ao mesmo plano
        let plans = Set(planExercises.compactMap { $0.plan })
        guard plans.count <= 1 else {
            throw ReorderExerciseError.planMismatch
        }
        
        // Validar que existe um plano
        guard let commonPlan = plans.first else {
            throw ReorderExerciseError.planNotFound
        }
        
        // Se workoutPlan foi fornecido, validar que é o mesmo
        if let providedPlan = workoutPlan {
            guard commonPlan == providedPlan else {
                throw ReorderExerciseError.planMismatch
            }
        }
        
        // Validar que todos os exercícios têm templates válidos
        let exercisesWithoutTemplate = planExercises.filter { $0.template == nil }
        guard exercisesWithoutTemplate.isEmpty else {
            throw ReorderExerciseError.templateMissing
        }
        
        // Validar que todos os exercícios têm IDs válidos
        let invalidExercises = planExercises.filter { exercise in
            exercise.safeId.uuidString.isEmpty
        }
        guard invalidExercises.isEmpty else {
            throw ReorderExerciseError.invalidInput("Alguns exercícios têm IDs inválidos")
        }
    }
}

// MARK: - ReorderExerciseOutput

struct ReorderExerciseOutput {
    let reorderedExercises: [CDPlanExercise]
    let workoutPlan: CDWorkoutPlan
    let affectedCount: Int
    let syncStatus: ReorderExerciseSyncStatus
    let orderChanges: [ExerciseOrderChange]
}

struct ExerciseOrderChange {
    let exerciseId: UUID
    let exerciseName: String
    let oldOrder: Int32
    let newOrder: Int32
}

enum ReorderExerciseSyncStatus {
    case synced
    case pending
    case failed(Error)
    case disabled // Quando SyncWorkoutUseCase não está disponível
}

// MARK: - ReorderExerciseUseCaseProtocol

protocol ReorderExerciseUseCaseProtocol {
    func execute(_ input: ReorderExerciseInput) async throws -> ReorderExerciseOutput
}

// SyncWorkoutUseCaseProtocol removed - now using real implementation from item 23

// MARK: - ReorderExerciseUseCase

final class ReorderExerciseUseCase: ReorderExerciseUseCaseProtocol {
    
    // MARK: - Properties
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil // Optional for testing - should be provided in production
    ) {
        self.workoutDataService = workoutDataService
        self.syncUseCase = syncUseCase
        
        print("🔄 ReorderExerciseUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: ReorderExerciseInput) async throws -> ReorderExerciseOutput {
        print("🔄 Iniciando reordenação de \(input.planExercises.count) exercícios")
        
        do {
            // 1. Validar entrada
            try input.validate()
            print("✅ Validação de entrada concluída")
            
            // 2. Obter o plano (garantido pela validação)
            guard let workoutPlan = input.planExercises.first?.plan else {
                throw ReorderExerciseError.planNotFound
            }
            
            // 3. Capturar estado original para tracking
            let orderChanges = captureOrderChanges(input.planExercises)
            
            // 4. Reordenar via WorkoutDataService
            try await workoutDataService.reorderPlanExercises(input.planExercises, in: workoutPlan)
            print("✅ Reordenação persistida localmente")
            
            // 5. Tentar sincronização do plano (se disponível)
            let syncStatus = await attemptSyncPlan(workoutPlan)
            
            let output = ReorderExerciseOutput(
                reorderedExercises: input.planExercises,
                workoutPlan: workoutPlan,
                affectedCount: input.planExercises.count,
                syncStatus: syncStatus,
                orderChanges: orderChanges
            )
            
            print("🎉 Reordenação de exercícios concluída: \(input.planExercises.count) exercícios no plano \(workoutPlan.displayTitle)")
            logOrderChanges(orderChanges)
            
            return output
            
        } catch let error as ReorderExerciseError {
            print("❌ Erro na reordenação de exercícios: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na reordenação de exercícios: \(error)")
            throw ReorderExerciseError.reorderFailed(error)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func captureOrderChanges(_ exercises: [CDPlanExercise]) -> [ExerciseOrderChange] {
        return exercises.enumerated().compactMap { index, exercise in
            let newOrder = Int32(index)
            let oldOrder = exercise.order
            
            // Só registra se houve mudança
            guard newOrder != oldOrder else { return nil }
            
            return ExerciseOrderChange(
                exerciseId: exercise.safeId,
                exerciseName: exercise.template?.safeName ?? "Exercício desconhecido",
                oldOrder: oldOrder,
                newOrder: newOrder
            )
        }
    }
    
    private func attemptSyncPlan(_ plan: CDWorkoutPlan) async -> ReorderExerciseSyncStatus {
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase não disponível - sincronização desabilitada")
            return .disabled
        }
        
        print("🔄 Tentando sincronizar plano após reordenação de exercícios...")
        
        do {
            try await syncUseCase.execute(plan)
            print("✅ Plano sincronizado com sucesso após reordenação de exercícios")
            return .synced
        } catch {
            print("❌ Falha na sincronização do plano \(plan.displayTitle): \(error)")
            return .failed(error)
        }
    }
    
    private func logOrderChanges(_ changes: [ExerciseOrderChange]) {
        guard !changes.isEmpty else {
            print("ℹ️ Nenhuma mudança de ordem detectada nos exercícios")
            return
        }
        
        print("📋 Mudanças de ordem detectadas nos exercícios:")
        for change in changes {
            print("   • \(change.exerciseName): posição \(change.oldOrder) → \(change.newOrder)")
        }
    }
}

// MARK: - Convenience Extensions

extension ReorderExerciseUseCase {
    
    /// Método de conveniência para reordenar exercícios de um plano específico
    func reorderExercisesInPlan(
        _ exercises: [CDPlanExercise],
        plan: CDWorkoutPlan
    ) async throws -> ReorderExerciseOutput {
        let input = ReorderExerciseInput(planExercises: exercises, workoutPlan: plan)
        return try await execute(input)
    }
    
    /// Método de conveniência para reordenar exercícios sem validação de plano explícita
    func reorderExercises(_ exercises: [CDPlanExercise]) async throws -> ReorderExerciseOutput {
        let input = ReorderExerciseInput(planExercises: exercises, workoutPlan: nil)
        return try await execute(input)
    }
} 