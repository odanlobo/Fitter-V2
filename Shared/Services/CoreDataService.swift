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
    
    func save() throws
    func saveBackground() async throws
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T]
    func create<T: NSManagedObject>(_ entityType: T.Type) -> T
    func delete(_ object: NSManagedObject)
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
            persistenceController.persistentContainer.performBackgroundTask { context in
                do {
                    let result = try operation(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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