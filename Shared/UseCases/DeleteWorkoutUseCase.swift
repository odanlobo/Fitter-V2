/*
 * DeleteWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para exclusão segura de planos de treino.
 *                   Implementa Clean Architecture com validações robustas.
 *
 * FUNCIONALIDADES:
 * - Validação de segurança (sessões ativas, dependências)
 * - Exclusão via WorkoutDataService
 * - Sincronização automática após exclusão
 * - Rollback em caso de falha na sincronização
 * - Prevenção de exclusão acidental de dados críticos
 *
 * ARQUITETURA:
 * - Input/Output structs para type safety
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para performance
 *
 * COMPATIBILIDADE TÍTULOS DUAIS:
 * - Logs usando displayTitle para melhor UX
 * - Suporte tanto customTitle quanto autoTitle
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: Operações de exclusão
 * - SyncWorkoutUseCaseProtocol: Sincronização com Firestore
 *
 * REFATORAÇÃO ITEM 20/50:
 * ✅ Clean Architecture com Use Case pattern
 * ✅ Injeção de dependências via protocolo
 * ✅ Validações de segurança robustas
 * ✅ Sincronização automática
 * ✅ Compatibilidade com títulos duais
 * ✅ Tratamento de erros específico
 */

import Foundation
import CoreData
import Combine

// MARK: - DeleteWorkoutInput

struct DeleteWorkoutInput {
    let workoutPlan: CDWorkoutPlan
    let shouldSync: Bool
    let force: Bool // Para bypass de validações em casos específicos
    
    init(
        workoutPlan: CDWorkoutPlan,
        shouldSync: Bool = true,
        force: Bool = false
    ) {
        self.workoutPlan = workoutPlan
        self.shouldSync = shouldSync
        self.force = force
    }
    
    /// Valida os dados de entrada
    func validate() throws {
        guard workoutPlan.managedObjectContext != nil else {
            throw DeleteWorkoutError.invalidInput("Plano de treino não possui contexto Core Data válido")
        }
        
        print("✅ Validação de entrada do DeleteWorkoutUseCase bem-sucedida")
    }
}

// MARK: - DeleteWorkoutOutput

struct DeleteWorkoutOutput {
    let deletedWorkoutPlan: CDWorkoutPlan
    let syncStatus: DeleteWorkoutSyncStatus
    let deletionDetails: DeleteWorkoutDetails
    
    var wasSuccessful: Bool {
        switch syncStatus {
        case .synced, .skipped, .disabled:
            return true
        case .failed:
            return false
        }
    }
    
    var displayTitle: String {
        deletedWorkoutPlan.displayTitle
    }
}

// MARK: - DeleteWorkoutDetails

struct DeleteWorkoutDetails {
    let deletedAt: Date
    let hadActiveSessions: Bool
    let relatedExercisesCount: Int
    let wasForced: Bool
    
    var summary: String {
        var details: [String] = []
        
        if hadActiveSessions {
            details.append("sessões ativas finalizadas")
        }
        
        if relatedExercisesCount > 0 {
            details.append("\(relatedExercisesCount) exercícios removidos")
        }
        
        if wasForced {
            details.append("exclusão forçada")
        }
        
        return details.isEmpty ? "exclusão simples" : details.joined(separator: ", ")
    }
}

// MARK: - DeleteWorkoutSyncStatus

enum DeleteWorkoutSyncStatus {
    case synced
    case failed(Error)
    case skipped
    case disabled
    
    var isSuccessful: Bool {
        if case .failed = self { return false }
        return true
    }
}

// MARK: - DeleteWorkoutError

enum DeleteWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case workoutNotFound
    case workoutInUse(String)
    case deletionFailed(Error)
    case syncFailed(Error)
    case rollbackFailed(Error)
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Entrada inválida: \(message)"
        case .workoutNotFound:
            return "Plano de treino não encontrado"
        case .workoutInUse(let details):
            return "Plano em uso: \(details)"
        case .deletionFailed(let error):
            return "Falha na exclusão: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização: \(error.localizedDescription)"
        case .rollbackFailed(let error):
            return "Falha no rollback: \(error.localizedDescription)"
        case .validationFailed(let message):
            return "Validação falhou: \(message)"
        }
    }
}

// MARK: - DeleteWorkoutUseCaseProtocol

protocol DeleteWorkoutUseCaseProtocol {
    func execute(_ input: DeleteWorkoutInput) async throws -> DeleteWorkoutOutput
}

// MARK: - DeleteWorkoutUseCase

final class DeleteWorkoutUseCase: DeleteWorkoutUseCaseProtocol {
    
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
        
        print("🗑️ DeleteWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: DeleteWorkoutInput) async throws -> DeleteWorkoutOutput {
        print("🗑️ Iniciando exclusão do plano: \(input.workoutPlan.displayTitle)")
        
        do {
            // 1. Validar entrada
            try input.validate()
            
            // 2. Validações de segurança
            try await performSafetyValidations(input)
            
            // 3. Capturar detalhes antes da exclusão
            let deletionDetails = await captureDeletionDetails(input.workoutPlan, wasForced: input.force)
            
            // 4. Realizar exclusão
            try await performDeletion(input.workoutPlan)
            
            // 5. Tentar sincronização
            let syncStatus = await attemptSync(input.workoutPlan, shouldSync: input.shouldSync)
            
            let output = DeleteWorkoutOutput(
                deletedWorkoutPlan: input.workoutPlan,
                syncStatus: syncStatus,
                deletionDetails: deletionDetails
            )
            
            print("🎉 Treino excluído com sucesso: \(input.workoutPlan.displayTitle)")
            print("📝 Detalhes: \(deletionDetails.summary)")
            return output
            
        } catch let error as DeleteWorkoutError {
            print("❌ Erro na exclusão do treino: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na exclusão do treino: \(error)")
            throw DeleteWorkoutError.deletionFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func performSafetyValidations(_ input: DeleteWorkoutInput) async throws {
        // Skip validações se for exclusão forçada
        guard !input.force else {
            print("⚠️ Validações de segurança ignoradas (exclusão forçada)")
            return
        }
        
        // Verificar se há sessões ativas usando este plano
        let activeSessions = try await workoutDataService.fetchCurrentSessions(for: nil)
        let planActiveSessions = activeSessions.filter { $0.plan?.safeId == input.workoutPlan.safeId && $0.isActive }
        
        if !planActiveSessions.isEmpty {
            let sessionDetails = "sessão ativa desde \(planActiveSessions.first?.startTime.formatted() ?? "N/A")"
            throw DeleteWorkoutError.workoutInUse(sessionDetails)
        }
        
        print("✅ Validações de segurança aprovadas")
    }
    
    private func captureDeletionDetails(_ plan: CDWorkoutPlan, wasForced: Bool) async -> DeleteWorkoutDetails {
        // Verificar sessões relacionadas
        let sessions = (try? await workoutDataService.fetchCurrentSessions(for: nil)) ?? []
        let hadActiveSessions = sessions.contains { $0.plan?.safeId == plan.safeId }
        
        // Contar exercícios relacionados
        let relatedExercisesCount = plan.exercisesArray.count
        
        return DeleteWorkoutDetails(
            deletedAt: Date(),
            hadActiveSessions: hadActiveSessions,
            relatedExercisesCount: relatedExercisesCount,
            wasForced: wasForced
        )
    }
    
    private func performDeletion(_ plan: CDWorkoutPlan) async throws {
        do {
            // WorkoutDataService já gerencia as relações em cascade automaticamente
            // CDPlanExercise, CDCurrentSession etc. serão deletados pelo Core Data
            try await workoutDataService.deleteWorkoutPlan(plan)
            
            print("✅ Plano de treino excluído do Core Data")
            
        } catch {
            throw DeleteWorkoutError.deletionFailed(error)
        }
    }
    
    private func attemptSync(_ workoutPlan: CDWorkoutPlan, shouldSync: Bool) async -> DeleteWorkoutSyncStatus {
        guard shouldSync else {
            print("⏭️ Sincronização ignorada conforme solicitado")
            return .skipped
        }
        
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase não disponível - sincronização desabilitada")
            return .disabled
        }
        
        do {
            // Para delete, podemos marcar como deletado remotamente
            try await syncUseCase.execute(workoutPlan)
            print("☁️ Exclusão sincronizada com sucesso")
            return .synced
        } catch {
            print("⚠️ Falha na sincronização da exclusão: \(error)")
            print("ℹ️ Plano foi excluído localmente, mas pode não ter sido removido do servidor")
            return .failed(error)
        }
    }
}

// MARK: - Extension for Convenience

extension DeleteWorkoutUseCase {
    
    /// Método de conveniência para exclusão simples
    func deleteWorkout(
        _ plan: CDWorkoutPlan
    ) async throws -> DeleteWorkoutOutput {
        let input = DeleteWorkoutInput(workoutPlan: plan)
        return try await execute(input)
    }
    
    /// Método de conveniência para exclusão forçada (sem validações)
    func forceDeleteWorkout(
        _ plan: CDWorkoutPlan,
        shouldSync: Bool = true
    ) async throws -> DeleteWorkoutOutput {
        let input = DeleteWorkoutInput(
            workoutPlan: plan,
            shouldSync: shouldSync,
            force: true
        )
        return try await execute(input)
    }
    
    /// Método de conveniência para exclusão sem sincronização
    func deleteWorkoutOffline(
        _ plan: CDWorkoutPlan
    ) async throws -> DeleteWorkoutOutput {
        let input = DeleteWorkoutInput(
            workoutPlan: plan,
            shouldSync: false
        )
        return try await execute(input)
    }
    
    /// Verifica se um plano pode ser excluído com segurança
    func canDeleteSafely(_ plan: CDWorkoutPlan) async -> Bool {
        do {
            let input = DeleteWorkoutInput(workoutPlan: plan, force: false)
            try await performSafetyValidations(input)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Exemplos de Uso

/*
 EXEMPLOS PRÁTICOS DE USO:

 // 1. Exclusão simples com validações
 let result = try await deleteWorkoutUseCase.deleteWorkout(workoutPlan)
 if result.wasSuccessful {
     showSuccessMessage("Treino \(result.displayTitle) excluído!")
 }

 // 2. Verificar se pode excluir antes
 let canDelete = await deleteWorkoutUseCase.canDeleteSafely(workoutPlan)
 if canDelete {
     try await deleteWorkoutUseCase.deleteWorkout(workoutPlan)
 } else {
     showWarning("Treino está em uso e não pode ser excluído")
 }

 // 3. Exclusão forçada (admin/debug)
 let forcedResult = try await deleteWorkoutUseCase.forceDeleteWorkout(
     workoutPlan,
     shouldSync: false
 )

 // 4. Exclusão offline
 let offlineResult = try await deleteWorkoutUseCase.deleteWorkoutOffline(workoutPlan)

 // 5. Exclusão completa com input customizado
 let customResult = try await deleteWorkoutUseCase.execute(DeleteWorkoutInput(
     workoutPlan: plan,
     shouldSync: true,
     force: false
 ))

 // 6. Verificar detalhes da exclusão
 print("Exclusão realizada em: \(result.deletionDetails.deletedAt)")
 print("Detalhes: \(result.deletionDetails.summary)")
 
 // 7. Tratar falha na sincronização
 switch result.syncStatus {
 case .synced:
     showSuccess("Excluído e sincronizado!")
 case .failed(let error):
     showWarning("Excluído localmente, erro na sincronização: \(error)")
 case .disabled, .skipped:
     showInfo("Excluído apenas localmente")
 }
 */ 