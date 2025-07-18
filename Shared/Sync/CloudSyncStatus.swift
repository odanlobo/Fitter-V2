//
//  CloudSyncStatus.swift
//  Fitter V2
//
//  📋 ESTADOS DE SINCRONIZAÇÃO SIMPLIFICADOS (ITEM 10 DA REFATORAÇÃO)
//  
//  🎯 OBJETIVO: Simplificar complexidade da sincronização
//  • ANTES: 5 estados complexos (synced, pendingUpload, uploading, conflict, error)
//  • DEPOIS: 2 estados essenciais (pending, synced)
//  • REDUÇÃO: 60% menos estados para melhor performance e manutenibilidade
//  
//  🔄 FLUXO SIMPLIFICADO:
//  1. Dados criados/modificados → Status = .pending
//  2. Sync bem-sucedido → Status = .synced
//  3. Conflitos/erros → Retry automático (sem estados intermediários)
//  
//  ⚡ BENEFÍCIOS:
//  • Performance: Menos queries de status complexo
//  • Manutenibilidade: Lógica de sync mais simples
//  • Reliability: Retry automático sem estados de erro persistentes
//  • UI: Indicadores mais claros (apenas "sincronizado" ou "pendente")
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation

// MARK: - Cloud Sync Status (Simplificado)
/// 🎯 Estados de sincronização otimizados para Firestore
/// Apenas 2 estados essenciais para máxima simplicidade e performance
enum CloudSyncStatus: Int16, CaseIterable {
    case pending = 0    /// Dados pendentes de sincronização (inclui novos, modificados, erros)
    case synced = 1     /// Dados sincronizados com sucesso
    
    var description: String {
        switch self {
        case .pending: return "Pendente"
        case .synced: return "Sincronizado"
        }
    }
    
    var emoji: String {
        switch self {
        case .pending: return "⏳"
        case .synced: return "✅"
        }
    }
    
    /// Para compatibilidade com UI - retorna true se precisa sync
    var needsSync: Bool {
        return self == .pending
    }
}

// MARK: - Syncable Protocol (Simplificado)
/// 🎯 Protocolo otimizado para sincronização com Firestore
/// Apenas funcionalidades essenciais para performance máxima
protocol Syncable {
    var coreDataId: UUID { get }
    var syncStatus: CloudSyncStatus { get set }
    var lastModified: Date? { get set }
    
    mutating func markForSync()
    mutating func markAsSynced()
}

extension Syncable {
    /// Marca entidade como pendente de sincronização
    mutating func markForSync() {
        syncStatus = .pending
        lastModified = Date()
    }
    
    /// Marca entidade como sincronizada com sucesso
    mutating func markAsSynced() {
        syncStatus = .synced
        // lastModified não é alterado - preserva timestamp original
    }
    
    /// Para compatibilidade - indica se precisa ser sincronizado
    var needsSync: Bool {
        return syncStatus.needsSync
    }
}

// MARK: - Sync Event (Simplificado)
/// 🎯 Evento de sincronização otimizado para logging/debug
/// Apenas informações essenciais para troubleshooting
struct SyncEvent {
    let entityType: String
    let entityId: UUID
    let action: SyncAction
    let timestamp: Date
    let success: Bool
    
    init(entityType: String, entityId: UUID, action: SyncAction, success: Bool = true) {
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.timestamp = Date()
        self.success = success
    }
}

/// 🎯 Ações de sincronização simplificadas
enum SyncAction: String, CaseIterable {
    case upload = "upload"       /// Upload para Firestore
    case download = "download"   /// Download do Firestore
    case delete = "delete"       /// Deletar no Firestore
    
    var description: String {
        switch self {
        case .upload: return "Enviando"
        case .download: return "Baixando" 
        case .delete: return "Deletando"
        }
    }
} 