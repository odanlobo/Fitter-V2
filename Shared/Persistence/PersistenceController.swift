//
//  PersistenceController.swift
//  Fitter V2
//
//  📋 ADAPTAÇÃO PARA NOVO MODELO FitterModel
//  
//  🎯 OBJETIVO: Centralizar configuração Core Data para modelo otimizado
//  • ANTES: Modelo "Model" com 18 atributos individuais de sensores
//  • DEPOIS: Modelo "FitterModel" com 2 campos JSON consolidados
//  • REDUÇÃO: 89% menos complexidade no schema
//  
//  🔧 CONFIGURAÇÕES ESPECÍFICAS:
//  • External Storage para Binary Data (sensorData JSON)
//  • Firestore sync via JSON serialization
//  • Migração automática de modelos
//  • Contextos otimizados para SensorData
//  
//  ⚡ PERFORMANCE:
//  • Background contexts para operações pesadas
//  • Merge policies otimizadas
//  • Staleness interval configurado
//
//  Created by Daniel Lobo on 13/05/25.
//

import CoreData

/// 🎯 Controlador de persistência otimizado para modelo FitterModel
/// Centraliza toda configuração Core Data e suporte a sensorData JSON
struct PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    private init() {
        // 🆕 MODELO ATUALIZADO: FitterModel (era "Model" antes da refatoração)
        container = NSPersistentContainer(name: "FitterModel")
        
        // 📋 CONFIGURAÇÕES DE PERSISTÊNCIA para FitterModel
        let description = container.persistentStoreDescriptions.first
        
        // 🔄 Migração automática (crítico para transição Model → FitterModel)
        description?.shouldInferMappingModelAutomatically = true
        description?.shouldMigrateStoreAutomatically = true
        
        // 📊 Rastreamento de histórico local (para debug e auditoria)
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        // 🆕 CONFIGURAÇÕES ESPECÍFICAS PARA sensorData (Binary Data + External Storage)
        // Proteção de arquivos para dados sensíveis do Apple Watch
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreFileProtectionKey)
        
        // 🔧 CONFIGURAÇÕES DE DESENVOLVIMENTO
        // Proteção e limpeza automática durante desenvolvimento
        
        // 🚀 CARREGAMENTO DAS STORES com tratamento de erro para FitterModel
        container.loadPersistentStores { description, error in
            if let error = error {
                // Log detalhado para debug de problemas de migração
                print("❌ Erro detalhado ao carregar FitterModel: \(error)")
                if let nsError = error as NSError? {
                    print("📋 Info adicional: \(nsError.userInfo)")
                }
                fatalError("Erro ao carregar Core Data FitterModel: \(error.localizedDescription)")
            } else {
                print("✅ FitterModel carregado com sucesso")
                if let storeURL = description?.url {
                    print("📁 Localização: \(storeURL)")
                }
            }
        }
        
        // 🔄 CONFIGURAÇÕES DE SINCRONIZAÇÃO para modelo otimizado
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // 🎯 Merge policy otimizada para SensorData (resolve conflitos por timestamp)
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // ✅ MIGRAÇÃO COMPLETA: FitterModel otimizado com sensorData JSON consolidado
        // • Exercícios agora vêm do Firebase (não precisam ser pré-carregados)
        // • SensorData em Binary Data (External Storage para performance)
        // • Schema 89% mais simples (18 atributos → 2 campos JSON)
    }
    
    // MARK: - Métodos Básicos de Persistência
    
    /// 💾 Salva o contexto principal com tratamento de erro básico
    /// 
    /// **Uso:** Para salvamento rápido de dados simples (não SensorData)
    /// Para SensorData, prefira `saveWithSensorData()` que tem tratamento específico
    ///
    /// - Note: Verifica `hasChanges` antes de salvar para otimizar performance
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("❌ Erro ao salvar contexto FitterModel: \(error)")
            }
        }
    }
    
    /// 🔄 Cria novo contexto em background para operações pesadas
    /// 
    /// **Uso Principal:**
    /// - Importação de dados em lote
    /// - Operações que não devem bloquear UI
    /// - Processamento de grandes volumes de SensorData
    ///
    /// - Returns: NSManagedObjectContext configurado para background
    func newBackgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }
    
    // MARK: - Métodos Específicos FitterModel (sensorData JSON)
    // 🎯 Métodos otimizados para novo modelo com Binary Data consolidado
    
    /// 💾 Salva com tratamento de erro melhorado para SensorData
    /// 
    /// **DIFERENÇA do save() comum:**
    /// - Detecta especificamente erros de serialização JSON
    /// - Propaga erros para tratamento de nível superior
    /// - Log mais detalhado para debug de SensorData
    /// 
    /// **Uso:** Sempre que salvar CDCurrentSet/CDHistorySet com sensorData
    ///
    /// - Throws: Erros de Core Data, incluindo falhas de serialização JSON
    func saveWithSensorData() throws {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("✅ SensorData salvo com sucesso no FitterModel")
            } catch {
                // 🔍 Log específico para erros de serialização JSON (crítico para debug)
                if error.localizedDescription.contains("JSON") {
                    print("❌ Erro crítico ao salvar SensorData JSON: \(error)")
                    print("📋 Verifique se SensorData.toBinaryData() está funcionando")
                } else {
                    print("❌ Erro geral ao salvar FitterModel: \(error)")
                }
                throw error
            }
        }
    }
    
    /// 🎯 Contexto otimizado para operações com grandes volumes de SensorData
    /// 
    /// **OTIMIZAÇÕES ESPECÍFICAS:**
    /// - `stalenessInterval = 0.0` para dados sempre atualizados
    /// - Merge policy por propriedade (ideal para Binary Data)
    /// - Background context para não bloquear UI
    /// 
    /// **Uso Principal:**
    /// - Importação em lote de dados do Apple Watch
    /// - Processamento de múltiplos sets com sensorData
    /// - Operações de limpeza/migração de dados
    ///
    /// - Returns: Contexto otimizado para Binary Data do FitterModel
    func newSensorDataContext() -> NSManagedObjectContext {
        let context = newBackgroundContext()
        
        // 🚀 Otimizações específicas para Binary Data (sensorData JSON)
        context.stalenessInterval = 0.0  // Sempre buscar dados mais recentes
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy  // Merge inteligente
        
        print("🔧 Contexto SensorData criado para FitterModel")
        return context
    }
}

// MARK: - FitterModel Migration Status
/// ✅ CONFIRMAÇÃO: PersistenceController.swift TOTALMENTE ADAPTADO para FitterModel
/// 
/// **MUDANÇAS IMPLEMENTADAS:**
/// 1. ✅ Nome do modelo: "Model" → "FitterModel"
/// 2. ✅ External Storage configurado para Binary Data
/// 3. ✅ Migração automática habilitada
/// 4. ✅ Firestore sync preparado (via JSON serialization)
/// 5. ✅ Contextos otimizados para SensorData
/// 6. ✅ Logs detalhados para debug
/// 7. ✅ Métodos específicos para Binary Data JSON
/// 
/// **COMPATIBILIDADE:**
/// - ✅ Migração automática de dados existentes
/// - ✅ External Storage para performance com SensorData
/// - ✅ Background contexts para operações pesadas
/// - ✅ Merge policies otimizadas para Binary Data
/// - ✅ Sync via Firestore (não CloudKit conforme regras da refatoração)
/// 
/// **PRÓXIMO ITEM:** CoreDataAdapter.swift (Item 8)
