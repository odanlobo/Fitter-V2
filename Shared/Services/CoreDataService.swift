//
//  CoreDataService.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import CoreData
import Combine

/// Protocolo para operações de Core Data
/// Facilita testes e mock das operações de dados
protocol CoreDataServiceProtocol {
    var viewContext: NSManagedObjectContext { get }
    var backgroundContext: NSManagedObjectContext { get }
    
    // MARK: - Basic Operations
    func save() throws
    func saveBackground() async throws
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T]
    func create<T: NSManagedObject>(_ entityType: T.Type) -> T
    func delete(_ object: NSManagedObject)
    
    // MARK: - Advanced Operations
    func performBackgroundTask<T>(_ operation: @escaping (NSManagedObjectContext) throws -> T) async throws -> T
    func object<T: NSManagedObject>(with objectID: NSManagedObjectID, in context: NSManagedObjectContext?) -> T?
    
    // MARK: - Batch Operations
    func batchInsert(entityName: String, objects: [[String: Any]], batchSize: Int) async throws -> Int
    func batchUpdate(entityName: String, predicate: NSPredicate, propertiesToUpdate: [String: Any]) async throws -> Int
    func batchDelete(entityName: String, predicate: NSPredicate) async throws -> Int
    func performBatchTransaction<T>(_ operations: [(NSManagedObjectContext) throws -> T]) async throws -> [T]
    
    // MARK: - Pagination & Performance
    func fetchPaginated<T: NSManagedObject>(_ request: NSFetchRequest<T>, page: Int, pageSize: Int) throws -> [T]
    func fetchWithLimit<T: NSManagedObject>(_ request: NSFetchRequest<T>, limit: Int) throws -> [T]
    func count<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int
    func fetchOptimized<T: NSManagedObject>(_ request: NSFetchRequest<T>, faultingLimit: Int, prefetchRelationships: [String]) throws -> [T]
    func fetchPaginatedAsync<T: NSManagedObject>(_ request: NSFetchRequest<T>, page: Int, pageSize: Int) async throws -> [T]
    
    // MARK: - Test Helpers
    func clearAllData(for entityName: String) async throws
    func countObjects(for entityName: String) throws -> Int
    func hasUnsavedChanges() -> Bool
    func rollback()
    func reset()
    func createTestData<T: NSManagedObject>(entityName: String, count: Int, configureObject: (T, Int) -> Void) throws -> [T]
    func fetchForTesting<T: NSManagedObject>(entityName: String, predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?, limit: Int?) throws -> [T]
}

/// Serviço centralizado para operações de Core Data
/// 
/// Responsabilidades:
/// - Operações CRUD genéricas
/// - Gerenciamento de contextos (main/background)
/// - Tratamento de erros de persistência
/// - Abstração do PersistenceController
/// 
/// ⚡ Clean Architecture:
/// - Camada de infraestrutura separada da UI
/// - Interface definida para facilitar testes
/// - Injeção de dependência via protocolo
final class CoreDataService: CoreDataServiceProtocol {
    
    // MARK: - Properties
    
    private let persistenceController: PersistenceController
    
    /// Contexto principal do Core Data (main thread)
    var viewContext: NSManagedObjectContext {
        return persistenceController.viewContext
    }
    
    /// Contexto background do Core Data para operações pesadas
    var backgroundContext: NSManagedObjectContext {
        return persistenceController.backgroundContext
    }
    
    // MARK: - Initialization
    
    /// Inicializa o serviço com dependência injetada
    /// - Parameter persistenceController: Controlador de persistência
    init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.persistenceController = persistenceController
    }
    
    // MARK: - Core Data Operations
    
    /// Salva o contexto principal com tratamento de erro
    /// - Throws: Erro de Core Data se a operação falhar
    func save() throws {
        guard viewContext.hasChanges else { 
            print("📁 CoreDataService: Nenhuma mudança para salvar")
            return 
        }
        
        do {
            try viewContext.save()
            print("✅ CoreDataService: Contexto principal salvo com sucesso")
        } catch {
            print("❌ CoreDataService: Erro ao salvar contexto principal: \(error)")
            throw CoreDataError.saveFailed(error)
        }
    }
    
    /// Salva contexto background de forma assíncrona
    /// - Throws: Erro de Core Data se a operação falhar
    func saveBackground() async throws {
        try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    guard self.backgroundContext.hasChanges else {
                        print("📁 CoreDataService: Nenhuma mudança no contexto background")
                        continuation.resume()
                        return
                    }
                    
                    try self.backgroundContext.save()
                    print("✅ CoreDataService: Contexto background salvo com sucesso")
                    continuation.resume()
                } catch {
                    print("❌ CoreDataService: Erro ao salvar contexto background: \(error)")
                    continuation.resume(throwing: CoreDataError.saveFailed(error))
                }
            }
        }
    }
    
    /// Executa fetch request no contexto principal
    /// - Parameter request: NSFetchRequest configurado
    /// - Returns: Array de objetos do tipo especificado
    /// - Throws: Erro de Core Data se a operação falhar
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        do {
            let results = try viewContext.fetch(request)
            print("📊 CoreDataService: Fetch executado - \(results.count) objetos retornados")
            return results
        } catch {
            print("❌ CoreDataService: Erro no fetch: \(error)")
            throw CoreDataError.fetchFailed(error)
        }
    }
    
    // MARK: - Pagination & Performance
    // 📄 Otimizações para grandes volumes de dados
    
    /// Executa fetch com paginação
    /// - Parameters:
    ///   - request: NSFetchRequest configurado
    ///   - page: Número da página (começando em 0)
    ///   - pageSize: Tamanho da página
    /// - Returns: Array de objetos da página solicitada
    func fetchPaginated<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        page: Int,
        pageSize: Int = 20
    ) throws -> [T] {
        request.fetchLimit = pageSize
        request.fetchOffset = page * pageSize
        
        do {
            let results = try viewContext.fetch(request)
            print("📄 CoreDataService: Fetch paginado - página \(page), \(results.count) objetos")
            return results
        } catch {
            print("❌ CoreDataService: Erro no fetch paginado: \(error)")
            throw CoreDataError.fetchFailed(error)
        }
    }
    
    /// Executa fetch com limite de resultados
    /// - Parameters:
    ///   - request: NSFetchRequest configurado
    ///   - limit: Limite máximo de resultados
    /// - Returns: Array de objetos limitado
    func fetchWithLimit<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        limit: Int
    ) throws -> [T] {
        request.fetchLimit = limit
        
        do {
            let results = try viewContext.fetch(request)
            print("📊 CoreDataService: Fetch limitado - \(results.count)/\(limit) objetos")
            return results
        } catch {
            print("❌ CoreDataService: Erro no fetch limitado: \(error)")
            throw CoreDataError.fetchFailed(error)
        }
    }
    
    /// Conta o total de objetos sem carregar todos na memória
    /// - Parameter request: NSFetchRequest configurado
    /// - Returns: Número total de objetos
    func count<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int {
        do {
            let count = try viewContext.count(for: request)
            print("📊 CoreDataService: Count executado - \(count) objetos")
            return count
        } catch {
            print("❌ CoreDataService: Erro no count: \(error)")
            throw CoreDataError.fetchFailed(error)
        }
    }
    
    /// Executa fetch com otimizações de performance
    /// - Parameters:
    ///   - request: NSFetchRequest configurado
    ///   - faultingLimit: Limite para faulting (padrão: 20)
    ///   - prefetchRelationships: Relacionamentos para prefetch
    /// - Returns: Array de objetos otimizado
    func fetchOptimized<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        faultingLimit: Int = 20,
        prefetchRelationships: [String] = []
    ) throws -> [T] {
        // Configurações de performance
        request.fetchBatchSize = faultingLimit
        request.relationshipKeyPathsForPrefetching = prefetchRelationships
        request.returnsObjectsAsFaults = false
        
        do {
            let results = try viewContext.fetch(request)
            print("⚡ CoreDataService: Fetch otimizado - \(results.count) objetos, batch size: \(faultingLimit)")
            return results
        } catch {
            print("❌ CoreDataService: Erro no fetch otimizado: \(error)")
            throw CoreDataError.fetchFailed(error)
        }
    }
    
    /// Executa fetch assíncrono com paginação
    /// - Parameters:
    ///   - request: NSFetchRequest configurado
    ///   - page: Número da página
    ///   - pageSize: Tamanho da página
    /// - Returns: Array de objetos da página
    func fetchPaginatedAsync<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        page: Int,
        pageSize: Int = 20
    ) async throws -> [T] {
        return try await performBackgroundTask { context in
            let backgroundRequest = request.copy() as! NSFetchRequest<T>
            backgroundRequest.fetchLimit = pageSize
            backgroundRequest.fetchOffset = page * pageSize
            
            let results = try context.fetch(backgroundRequest)
            print("📄 CoreDataService: Fetch paginado assíncrono - página \(page), \(results.count) objetos")
            return results
        }
    }
    
    /// Cria nova instância de uma entidade no contexto principal
    /// - Parameter entityType: Tipo da entidade a ser criada
    /// - Returns: Nova instância da entidade
    func create<T: NSManagedObject>(_ entityType: T.Type) -> T {
        let entity = T(context: viewContext)
        print("➕ CoreDataService: Nova entidade \(entityType) criada")
        return entity
    }
    
    /// Remove objeto do contexto
    /// - Parameter object: Objeto a ser removido
    func delete(_ object: NSManagedObject) {
        viewContext.delete(object)
        print("🗑️ CoreDataService: Objeto \(type(of: object)) marcado para remoção")
    }
    
    // MARK: - Advanced Operations
    
    /// Executa operação em contexto background
    /// - Parameter operation: Operação a ser executada
    /// - Returns: Resultado da operação
    func performBackgroundTask<T>(_ operation: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceController.container.performBackgroundTask { context in
                do {
                    let result = try operation(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Batch Operations
    // 🚀 Operações em lote para performance com grandes volumes de dados
    
    /// Executa operação de inserção em lote
    /// - Parameters:
    ///   - entityName: Nome da entidade
    ///   - objects: Array de dicionários com dados para inserção
    ///   - batchSize: Tamanho do lote (padrão: 100)
    /// - Returns: Número de objetos inseridos
    func batchInsert(
        entityName: String,
        objects: [[String: Any]],
        batchSize: Int = 100
    ) async throws -> Int {
        guard !objects.isEmpty else {
            print("⚠️ CoreDataService: Lista vazia para batch insert")
            return 0
        }
        
        return try await performBackgroundTask { context in
            let batchInsert = NSBatchInsertRequest(entityName: entityName, objects: objects)
            batchInsert.resultType = .count
            
            let result = try context.execute(batchInsert) as? NSBatchInsertResult
            let insertedCount = result?.result as? Int ?? 0
            
            print("✅ CoreDataService: Batch insert concluído - \(insertedCount) objetos inseridos")
            return insertedCount
        }
    }
    
    /// Executa operação de atualização em lote
    /// - Parameters:
    ///   - entityName: Nome da entidade
    ///   - predicate: Predicado para filtrar objetos
    ///   - propertiesToUpdate: Dicionário com propriedades para atualizar
    /// - Returns: Número de objetos atualizados
    func batchUpdate(
        entityName: String,
        predicate: NSPredicate,
        propertiesToUpdate: [String: Any]
    ) async throws -> Int {
        return try await performBackgroundTask { context in
            let batchUpdate = NSBatchUpdateRequest(entityName: entityName)
            batchUpdate.predicate = predicate
            batchUpdate.propertiesToUpdate = propertiesToUpdate
            batchUpdate.resultType = .updatedObjectsCountResultType
            
            let result = try context.execute(batchUpdate) as? NSBatchUpdateResult
            let updatedCount = result?.result as? Int ?? 0
            
            print("✅ CoreDataService: Batch update concluído - \(updatedCount) objetos atualizados")
            return updatedCount
        }
    }
    
    /// Executa operação de exclusão em lote
    /// - Parameters:
    ///   - entityName: Nome da entidade
    ///   - predicate: Predicado para filtrar objetos a serem excluídos
    /// - Returns: Número de objetos excluídos
    func batchDelete(
        entityName: String,
        predicate: NSPredicate
    ) async throws -> Int {
        return try await performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            fetchRequest.predicate = predicate
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeCount
            
            let result = try context.execute(batchDelete) as? NSBatchDeleteResult
            let deletedCount = result?.result as? Int ?? 0
            
            print("✅ CoreDataService: Batch delete concluído - \(deletedCount) objetos excluídos")
            return deletedCount
        }
    }
    
    /// Executa múltiplas operações em uma única transação
    /// - Parameter operations: Array de operações a serem executadas
    /// - Returns: Array de resultados das operações
    func performBatchTransaction<T>(
        _ operations: [(NSManagedObjectContext) throws -> T]
    ) async throws -> [T] {
        return try await performBackgroundTask { context in
            var results: [T] = []
            
            for operation in operations {
                let result = try operation(context)
                results.append(result)
            }
            
            // Salva todas as operações em uma única transação
            try context.save()
            print("✅ CoreDataService: Transação em lote concluída - \(operations.count) operações")
            
            return results
        }
    }
    
    /// Busca objeto por ID
    /// - Parameters:
    ///   - objectID: NSManagedObjectID do objeto
    ///   - context: Contexto a ser usado (opcional, usa viewContext por padrão)
    /// - Returns: Objeto encontrado ou nil
    func object<T: NSManagedObject>(with objectID: NSManagedObjectID, in context: NSManagedObjectContext? = nil) -> T? {
        let targetContext = context ?? viewContext
        
        do {
            return try targetContext.existingObject(with: objectID) as? T
        } catch {
            print("❌ CoreDataService: Erro ao buscar objeto por ID: \(error)")
            return nil
        }
    }
    
    // MARK: - Test Helpers
    // 🧪 Helpers para testes de integração e mocks
    
    /// Limpa todos os dados de uma entidade (uso em testes)
    /// - Parameter entityName: Nome da entidade a ser limpa
    func clearAllData(for entityName: String) async throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        try await performBackgroundTask { context in
            _ = try context.execute(deleteRequest)
            try context.save()
            print("🧪 CoreDataService: Dados limpos para entidade \(entityName)")
        }
    }
    
    /// Conta o número de objetos de uma entidade
    /// - Parameter entityName: Nome da entidade
    /// - Returns: Número de objetos
    func countObjects(for entityName: String) throws -> Int {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        return try viewContext.count(for: fetchRequest)
    }
    
    /// Verifica se o contexto tem mudanças pendentes
    /// - Returns: true se há mudanças não salvas
    func hasUnsavedChanges() -> Bool {
        return viewContext.hasChanges
    }
    
    /// Desfaz todas as mudanças não salvas no contexto principal
    func rollback() {
        viewContext.rollback()
        print("🔄 CoreDataService: Rollback executado no contexto principal")
    }
    
    /// Reseta o contexto principal (uso em testes)
    func reset() {
        viewContext.reset()
        print("🔄 CoreDataService: Contexto principal resetado")
    }
    
    /// Cria dados de teste para uma entidade
    /// - Parameters:
    ///   - entityName: Nome da entidade
    ///   - count: Número de objetos a criar
    ///   - configureObject: Closure para configurar cada objeto
    /// - Returns: Array de objetos criados
    func createTestData<T: NSManagedObject>(
        entityName: String,
        count: Int,
        configureObject: (T, Int) -> Void
    ) throws -> [T] {
        var objects: [T] = []
        
        for i in 0..<count {
            let object = T(context: viewContext)
            configureObject(object, i)
            objects.append(object)
        }
        
        try save()
        print("🧪 CoreDataService: \(count) objetos de teste criados para \(entityName)")
        return objects
    }
    
    /// Executa fetch com configuração personalizada para testes
    /// - Parameters:
    ///   - entityName: Nome da entidade
    ///   - predicate: Predicado opcional
    ///   - sortDescriptors: Ordenação opcional
    ///   - limit: Limite de resultados
    /// - Returns: Array de objetos
    func fetchForTesting<T: NSManagedObject>(
        entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) throws -> [T] {
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        if let limit = limit {
            fetchRequest.fetchLimit = limit
        }
        
        return try fetch(fetchRequest)
    }
}

// MARK: - Error Types
enum CoreDataError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case objectNotFound
    case contextNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Erro ao salvar dados: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Erro ao buscar dados: \(error.localizedDescription)"
        case .objectNotFound:
            return "Objeto não encontrado"
        case .contextNotAvailable:
            return "Contexto do Core Data não disponível"
        }
    }
} 