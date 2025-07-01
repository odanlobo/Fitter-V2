/*
 * ReorderWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para reordenação de planos de treino.
 *                   Implementa Clean Architecture com orquestração de operações de persistência e sincronização.
 *
 * ARQUITETURA:
 * - Orquestra WorkoutDataService (persistência local)
 * - Orquestra SyncWorkoutUseCase (sincronização remota - quando disponível)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: CRUD e reordenação de planos de treino
 * - SyncWorkoutUseCaseProtocol: Sincronização remota (item 23 - opcional)
 *
 * FLUXO DE EXECUÇÃO:
 * 1. Validação de entrada (planos válidos, mesma ordem)
 * 2. Reordenação via WorkoutDataService (atualiza campo 'order')
 * 3. Sincronização via SyncWorkoutUseCase (quando disponível)
 * 4. Retorno do resultado com status de sincronização
 *
 * LÓGICA DE REORDENAÇÃO:
 * - Recebe array de CDWorkoutPlan na nova ordem desejada
 * - Atualiza campo 'order' de cada plano (0, 1, 2...)
 * - Marca cloudSyncStatus como 'pending' para sincronização
 * - Preserva títulos duais (autoTitle/customTitle) inalterados
 *
 * CASOS DE USO:
 * - Drag & drop de cards de treino na UI
 * - Reorganização manual por preferência do usuário
 * - Ordenação automática por critérios (alfabética, data, etc.)
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 *
 * REFATORAÇÃO ITEM 21/61:
 * ✅ Use Case de reordenação com orquestração
 * ✅ Injeção de WorkoutDataService
 * ✅ Preparado para SyncWorkoutUseCase (item 23)
 * ✅ Clean Architecture - sem acesso direto ao Core Data
 * ✅ Tratamento de erros específicos do domínio
 */

import Foundation

// MARK: - ReorderWorkoutError

enum ReorderWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case emptyList
    case duplicateWorkouts
    case reorderFailed(Error)
    case syncFailed(Error)
    case userMismatch
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Dados inválidos para reordenação: \(message)"
        case .emptyList:
            return "Lista de treinos não pode estar vazia"
        case .duplicateWorkouts:
            return "Lista contém treinos duplicados"
        case .reorderFailed(let error):
            return "Falha na reordenação dos treinos: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização da reordenação: \(error.localizedDescription)"
        case .userMismatch:
            return "Todos os treinos devem pertencer ao mesmo usuário"
        }
    }
}

// MARK: - ReorderWorkoutInput

struct ReorderWorkoutInput {
    let workoutPlans: [CDWorkoutPlan]
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    
    /// Validação dos dados de entrada
    func validate() throws {
        // Validar lista não vazia
        guard !workoutPlans.isEmpty else {
            throw ReorderWorkoutError.emptyList
        }
        
        // Validar que não há duplicatas (baseado no ID)
        let uniqueIds = Set(workoutPlans.map { $0.safeId })
        guard uniqueIds.count == workoutPlans.count else {
            throw ReorderWorkoutError.duplicateWorkouts
        }
        
        // ✅ LOGIN OBRIGATÓRIO: Validar ownership de todos os treinos
        let allBelongToUser = workoutPlans.allSatisfy { plan in
            plan.user == user
        }
        guard allBelongToUser else {
            throw ReorderWorkoutError.userMismatch
        }
        
        // Validar que todos os treinos têm IDs válidos
        let invalidPlans = workoutPlans.filter { plan in
            plan.safeId.uuidString.isEmpty
        }
        guard invalidPlans.isEmpty else {
            throw ReorderWorkoutError.invalidInput("Alguns treinos têm IDs inválidos")
        }
    }
}

// MARK: - ReorderWorkoutOutput

struct ReorderWorkoutOutput {
    let reorderedPlans: [CDWorkoutPlan]
    let affectedCount: Int
    let syncStatus: ReorderSyncStatus
    let orderChanges: [OrderChange]
}

struct OrderChange {
    let planId: UUID
    let planTitle: String
    let oldOrder: Int32
    let newOrder: Int32
}

enum ReorderSyncStatus {
    case synced
    case pending
    case failed(Error)
    case disabled // Quando SyncWorkoutUseCase não está disponível
}

// MARK: - ReorderWorkoutUseCaseProtocol

protocol ReorderWorkoutUseCaseProtocol {
    func execute(_ input: ReorderWorkoutInput) async throws -> ReorderWorkoutOutput
}

// SyncWorkoutUseCaseProtocol removed - now using real implementation from item 23

// MARK: - ReorderWorkoutUseCase

final class ReorderWorkoutUseCase: ReorderWorkoutUseCaseProtocol {
    
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
        
        print("🔄 ReorderWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: ReorderWorkoutInput) async throws -> ReorderWorkoutOutput {
        print("🔄 Iniciando reordenação de \(input.workoutPlans.count) treinos")
        
        do {
            // 1. Validar entrada
            try input.validate()
            print("✅ Validação de entrada concluída")
            
            // 2. Capturar estado original para tracking
            let orderChanges = captureOrderChanges(input.workoutPlans)
            
            // 3. Reordenar via WorkoutDataService
            try await workoutDataService.reorderWorkoutPlans(input.workoutPlans)
            print("✅ Reordenação persistida localmente")
            
            // 4. Tentar sincronização (se disponível)
            let syncStatus = await attemptSyncAllPlans(input.workoutPlans)
            
            let output = ReorderWorkoutOutput(
                reorderedPlans: input.workoutPlans,
                affectedCount: input.workoutPlans.count,
                syncStatus: syncStatus,
                orderChanges: orderChanges
            )
            
            print("🎉 Reordenação concluída: \(input.workoutPlans.count) treinos")
            logOrderChanges(orderChanges)
            
            return output
            
        } catch let error as ReorderWorkoutError {
            print("❌ Erro na reordenação: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na reordenação: \(error)")
            throw ReorderWorkoutError.reorderFailed(error)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func captureOrderChanges(_ plans: [CDWorkoutPlan]) -> [OrderChange] {
        return plans.enumerated().compactMap { index, plan in
            let newOrder = Int32(index)
            let oldOrder = plan.order
            
            // Só registra se houve mudança
            guard newOrder != oldOrder else { return nil }
            
            return OrderChange(
                planId: plan.safeId,
                planTitle: plan.displayTitle,
                oldOrder: oldOrder,
                newOrder: newOrder
            )
        }
    }
    
    private func attemptSyncAllPlans(_ plans: [CDWorkoutPlan]) async -> ReorderSyncStatus {
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase não disponível - sincronização desabilitada")
            return .disabled
        }
        
        print("🔄 Tentando sincronizar \(plans.count) treinos reordenados...")
        
        var failedSyncs: [Error] = []
        
        for plan in plans {
            do {
                try await syncUseCase.execute(plan)
            } catch {
                print("❌ Falha na sincronização do treino \(plan.displayTitle): \(error)")
                failedSyncs.append(error)
            }
        }
        
        if failedSyncs.isEmpty {
            print("✅ Todos os treinos sincronizados com sucesso")
            return .synced
        } else if failedSyncs.count == plans.count {
            print("❌ Falha na sincronização de todos os treinos")
            return .failed(failedSyncs.first!)
        } else {
            print("⚠️ Sincronização parcial: \(failedSyncs.count)/\(plans.count) falharam")
            return .pending
        }
    }
    
    private func logOrderChanges(_ changes: [OrderChange]) {
        guard !changes.isEmpty else {
            print("ℹ️ Nenhuma mudança de ordem detectada")
            return
        }
        
        print("📋 Mudanças de ordem detectadas:")
        for change in changes {
            print("   • \(change.planTitle): posição \(change.oldOrder) → \(change.newOrder)")
        }
    }
}

// MARK: - Convenience Extensions

extension ReorderWorkoutUseCase {
    
    /// Método de conveniência para reordenar treinos de um usuário específico
    func reorderUserWorkouts(_ plans: [CDWorkoutPlan], for user: CDAppUser) async throws -> ReorderWorkoutOutput {
        let input = ReorderWorkoutInput(workoutPlans: plans, user: user)
        return try await execute(input)
    }
    
    /// Método de conveniência para reordenar treinos (sempre valida ownership)
    func reorderWorkouts(_ plans: [CDWorkoutPlan], for user: CDAppUser) async throws -> ReorderWorkoutOutput {
        let input = ReorderWorkoutInput(workoutPlans: plans, user: user)
        return try await execute(input)
    }
} 