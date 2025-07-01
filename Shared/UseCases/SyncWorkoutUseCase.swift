/*
 * SyncWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case central de sincronização para entidades Syncable.
 *                   Motor puro de sincronização chamado pelos outros Use Cases de CRUD.
 *
 * ARQUITETURA:
 * - Orquestra CloudSyncManager (sincronização com Firestore)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI ou persistência
 * - NÃO modifica entidades - apenas agenda sincronização
 *
 * DEPENDÊNCIAS:
 * - CloudSyncManager: Sincronização automática com Firestore
 * - Protocolo Syncable: Interface comum para todas as entidades sincronizáveis
 *
 * FLUXO DE EXECUÇÃO:
 * 1. Recebe entidade Syncable para sincronizar
 * 2. Agenda sincronização via CloudSyncManager
 * 3. Monitora resultado da sincronização
 * 4. Retorna status de sucesso/falha
 *
 * CASOS DE USO:
 * - Sincronização após criação de treino (CreateWorkoutUseCase)
 * - Sincronização após edição de treino (UpdateWorkoutUseCase)
 * - Sincronização após deleção de treino (DeleteWorkoutUseCase)
 * - Sincronização após reordenação (ReorderWorkoutUseCase/ReorderExerciseUseCase)
 * - Sincronização manual de entidades pendentes
 * - Sincronização em lote de múltiplas entidades
 *
 * ENTIDADES SUPORTADAS:
 * - CDWorkoutPlan (planos de treino)
 * - CDAppUser (usuários da aplicação)
 * - CDExerciseTemplate (templates de exercícios - futuro)
 * - CDWorkoutHistory (histórico de treinos - futuro)
 * - Qualquer entidade que implemente protocolo Syncable
 *
 * ESTRATÉGIAS DE SINCRONIZAÇÃO:
 * - Upload: Agenda entidade para envio ao Firestore
 * - Download: Força download de mudanças remotas
 * - Delete: Agenda deleção remota da entidade
 * - Full Sync: Sincronização completa de todas as entidades pendentes
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 * - Actor isolation para thread safety (CloudSyncManager)
 *
 * REFATORAÇÃO ITEM 23/61:
 * ✅ Motor puro de sincronização centralizado
 * ✅ Integração com CloudSyncManager existente
 * ✅ Interface compatível com todos os Use Cases CRUD
 * ✅ Clean Architecture - separação clara de responsabilidades
 * ✅ Preparado para múltiplos tipos de entidades
 */

import Foundation
import CoreData

// MARK: - SyncWorkoutError

enum SyncWorkoutError: Error, LocalizedError {
    case invalidEntity(String)
    case entityNotFound
    case syncSchedulingFailed(Error)
    case syncExecutionFailed(Error)
    case cloudSyncManagerUnavailable
    case unsupportedEntityType(String)
    case networkUnavailable
    case authenticationRequired
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidEntity(let message):
            return "Entidade inválida para sincronização: \(message)"
        case .entityNotFound:
            return "Entidade não encontrada para sincronização"
        case .syncSchedulingFailed(let error):
            return "Falha ao agendar sincronização: \(error.localizedDescription)"
        case .syncExecutionFailed(let error):
            return "Falha na execução da sincronização: \(error.localizedDescription)"
        case .cloudSyncManagerUnavailable:
            return "CloudSyncManager não está disponível"
        case .unsupportedEntityType(let type):
            return "Tipo de entidade não suportado para sincronização: \(type)"
        case .networkUnavailable:
            return "Rede não disponível para sincronização"
        case .authenticationRequired:
            return "Autenticação necessária para sincronização"
        case .quotaExceeded:
            return "Cota de sincronização excedida"
        }
    }
}

// MARK: - SyncWorkoutStrategy

enum SyncWorkoutStrategy {
    case upload        /// Agenda entidade para upload ao Firestore
    case download      /// Força download de mudanças remotas
    case delete        /// Agenda deleção remota da entidade
    case fullSync      /// Sincronização completa de todas as entidades pendentes
    case auto          /// Estratégia automática baseada no status da entidade
    
    var description: String {
        switch self {
        case .upload: return "Upload"
        case .download: return "Download"
        case .delete: return "Delete"
        case .fullSync: return "Sincronização Completa"
        case .auto: return "Automático"
        }
    }
}

// MARK: - SyncWorkoutResult

struct SyncWorkoutResult {
    let entityId: UUID?
    let entityType: String
    let strategy: SyncWorkoutStrategy
    let success: Bool
    let error: Error?
    let timestamp: Date
    
    init(
        entityId: UUID?,
        entityType: String,
        strategy: SyncWorkoutStrategy,
        success: Bool,
        error: Error? = nil
    ) {
        self.entityId = entityId
        self.entityType = entityType
        self.strategy = strategy
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - SyncWorkoutUseCaseProtocol

protocol SyncWorkoutUseCaseProtocol {
    /// Sincroniza uma entidade específica
    func execute(_ entity: any Syncable) async throws
    
    /// Sincroniza uma entidade com estratégia específica
    func execute(_ entity: any Syncable, strategy: SyncWorkoutStrategy) async throws -> SyncWorkoutResult
    
    /// Sincroniza múltiplas entidades em lote
    func executeBatch(_ entities: [any Syncable]) async throws -> [SyncWorkoutResult]
    
    /// Força sincronização completa de todas as entidades pendentes
    func syncAllPendingEntities() async throws
    
    /// Agenda deleção remota de uma entidade por ID
    func scheduleRemoteDeletion(entityId: UUID) async throws
}

// MARK: - SyncWorkoutUseCase

final class SyncWorkoutUseCase: SyncWorkoutUseCaseProtocol {
    
    // MARK: - Properties
    
    private let cloudSyncManager: CloudSyncManager
    
    // MARK: - Initialization
    
    init(cloudSyncManager: CloudSyncManager = CloudSyncManager.shared) {
        self.cloudSyncManager = cloudSyncManager
        print("🔄 SyncWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    /// Sincroniza uma entidade usando estratégia automática
    func execute(_ entity: any Syncable) async throws {
        let entityType = String(describing: type(of: entity))
        print("🔄 Sincronizando \(entityType)")
        
        guard let entityId = entity.id else {
            throw SyncWorkoutError.invalidEntity("Entidade não possui ID válido")
        }
        
        do {
            if entity.needsSync {
                await cloudSyncManager.scheduleUpload(entityId: entityId)
                print("✅ Sincronização agendada para \(entityType)")
            } else {
                print("ℹ️ Entidade \(entityType) já sincronizada")
            }
        } catch {
            print("❌ Falha na sincronização de \(entityType): \(error)")
            throw SyncWorkoutError.syncExecutionFailed(error)
        }
    }
    
    /// Sincroniza uma entidade com estratégia específica
    func execute(_ entity: any Syncable, strategy: SyncWorkoutStrategy) async throws -> SyncWorkoutResult {
        let entityType = String(describing: type(of: entity))
        print("🔄 Iniciando sincronização \(strategy.description) para \(entityType)")
        
        do {
            // 1. Validar entidade
            try validateEntity(entity)
            
            // 2. Executar estratégia de sincronização
            switch strategy {
            case .upload:
                try await executeUpload(entity)
            case .download:
                try await executeDownload()
            case .delete:
                try await executeDelete(entity)
            case .fullSync:
                try await executeFullSync()
            case .auto:
                try await executeAuto(entity)
            }
            
            let result = SyncWorkoutResult(
                entityId: entity.id,
                entityType: entityType,
                strategy: strategy,
                success: true
            )
            
            print("✅ Sincronização \(strategy.description) concluída para \(entityType)")
            return result
            
        } catch {
            print("❌ Falha na sincronização \(strategy.description) para \(entityType): \(error)")
            
            let result = SyncWorkoutResult(
                entityId: entity.id,
                entityType: entityType,
                strategy: strategy,
                success: false,
                error: error
            )
            
            throw SyncWorkoutError.syncExecutionFailed(error)
        }
    }
    
    /// Sincroniza múltiplas entidades em lote
    func executeBatch(_ entities: [any Syncable]) async throws -> [SyncWorkoutResult] {
        print("🔄 Iniciando sincronização em lote de \(entities.count) entidades")
        
        var results: [SyncWorkoutResult] = []
        
        for entity in entities {
            do {
                let result = try await execute(entity, strategy: .auto)
                results.append(result)
            } catch {
                let entityType = String(describing: type(of: entity))
                let failedResult = SyncWorkoutResult(
                    entityId: entity.id,
                    entityType: entityType,
                    strategy: .auto,
                    success: false,
                    error: error
                )
                results.append(failedResult)
                print("❌ Falha na sincronização da entidade \(entityType): \(error)")
            }
        }
        
        let successCount = results.filter { $0.success }.count
        print("📊 Sincronização em lote concluída: \(successCount)/\(entities.count) sucessos")
        
        return results
    }
    
    /// Força sincronização completa de todas as entidades pendentes
    func syncAllPendingEntities() async throws {
        print("🔄 Iniciando sincronização completa de todas as entidades pendentes")
        
        do {
            await cloudSyncManager.syncPendingChanges()
            print("✅ Sincronização completa concluída")
        } catch {
            print("❌ Falha na sincronização completa: \(error)")
            throw SyncWorkoutError.syncExecutionFailed(error)
        }
    }
    
    /// Agenda deleção remota de uma entidade por ID
    func scheduleRemoteDeletion(entityId: UUID) async throws {
        print("🗑️ Agendando deleção remota da entidade: \(entityId)")
        
        do {
            await cloudSyncManager.scheduleDeletion(entityId: entityId)
            print("✅ Deleção remota agendada: \(entityId)")
        } catch {
            print("❌ Falha ao agendar deleção remota: \(error)")
            throw SyncWorkoutError.syncSchedulingFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func validateEntity(_ entity: any Syncable) throws {
        // Validar que a entidade tem ID
        guard entity.id != nil else {
            throw SyncWorkoutError.invalidEntity("Entidade não possui ID válido")
        }
        
        // Validar tipo de entidade suportado
        let entityType = String(describing: type(of: entity))
        let supportedTypes = ["CDWorkoutPlan", "CDAppUser", "CDExerciseTemplate", "CDWorkoutHistory"]
        
        let isSupported = supportedTypes.contains { supportedType in
            entityType.contains(supportedType)
        }
        
        guard isSupported else {
            throw SyncWorkoutError.unsupportedEntityType(entityType)
        }
    }
    
    private func executeUpload(_ entity: any Syncable) async throws {
        guard let entityId = entity.id else {
            throw SyncWorkoutError.invalidEntity("Entidade não possui ID para upload")
        }
        
        await cloudSyncManager.scheduleUpload(entityId: entityId)
    }
    
    private func executeDownload() async throws {
        await cloudSyncManager.syncPendingChanges()
    }
    
    private func executeDelete(_ entity: any Syncable) async throws {
        guard let entityId = entity.id else {
            throw SyncWorkoutError.invalidEntity("Entidade não possui ID para deleção")
        }
        
        await cloudSyncManager.scheduleDeletion(entityId: entityId)
    }
    
    private func executeFullSync() async throws {
        await cloudSyncManager.syncPendingChanges()
    }
    
    private func executeAuto(_ entity: any Syncable) async throws {
        if entity.needsSync {
            try await executeUpload(entity)
        }
        // Se já sincronizado, não faz nada
    }
}

// MARK: - Convenience Extensions

extension SyncWorkoutUseCase {
    
    /// Método de conveniência para sincronizar um plano de treino
    func syncWorkoutPlan(_ plan: CDWorkoutPlan) async throws {
        try await execute(plan)
    }
    
    /// Método de conveniência para sincronizar um usuário
    func syncUser(_ user: CDAppUser) async throws {
        try await execute(user)
    }
    
    /// Método de conveniência para agendar upload de uma entidade
    func scheduleUpload(_ entity: any Syncable) async throws {
        _ = try await execute(entity, strategy: .upload)
    }
    
    /// Método de conveniência para força download de mudanças remotas
    func forceDownload() async throws {
        // Cria uma entidade dummy para usar a estratégia de download
        let dummyPlan = CDWorkoutPlan()
        dummyPlan.id = UUID()
        _ = try await execute(dummyPlan, strategy: .download)
    }
} 