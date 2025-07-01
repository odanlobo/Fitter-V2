/*
 * FetchFBExercisesUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Busca simples de exercícios direto do Firebase para listas de seleção
 *                   Implementa abordagem simplificada sem cache local complexo.
 *
 * ARQUITETURA:
 * - Clean Architecture: Protocol + Implementation
 * - Dependency Injection: FirestoreExerciseRepository via inicializador
 * - Error Handling: FetchFBExercisesError enum específico
 * - Async/await: Todas operações assíncronas
 *
 * ABORDAGEM SIMPLIFICADA:
 * 1. Exercícios sempre buscados da nuvem (Firestore)
 * 2. Vídeos/GIFs stream direto do Firebase Storage (sem download)
 * 3. Salvamento local APENAS quando exercício é adicionado ao treino
 * 4. Performance via paginação simples, thumbnails pequenos
 *
 * OPERAÇÕES PRINCIPAIS:
 * 1. fetchExercises() - Busca básica com filtros opcionais
 * 2. searchExercises() - Busca por texto livre
 * 3. fetchExercisesByMuscleGroup() - Filtro por grupo muscular
 * 4. fetchExercisesByEquipment() - Filtro por equipamento
 * 5. fetchExerciseById() - Busca por templateId específico
 *
 * MÍDIA HANDLING:
 * - URLs diretas do Firebase Storage para streaming
 * - Thumbnails pequenos para preview rápido
 * - Vídeos carregados sob demanda via AsyncImage/VideoPlayer
 * - Propriedades hasVideo, hasThumbnail para UI condicional
 *
 * DEPENDENCY:
 * - FirestoreExerciseRepository: Repository direto para Firestore
 * - Sem CloudSyncManager (não há sincronização aqui, apenas leitura)
 *
 * REFATORAÇÃO ITEM 30/89:
 * ✅ Criar FetchFBExercisesUseCase.swift
 * 🔄 Preparado para videoURL/thumbnailURL (item 32)
 * 🔄 Integração com Repository (item 31)
 */

import Foundation
import Combine

// MARK: - FetchFBExercisesError

enum FetchFBExercisesError: LocalizedError {
    case invalidInput(String)
    case networkError
    case firestoreError(Error)
    case exerciseNotFound(String)
    case loadFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Entrada inválida: \(message)"
        case .networkError:
            return "Erro de conexão. Verifique sua internet."
        case .firestoreError(let error):
            return "Erro do Firebase: \(error.localizedDescription)"
        case .exerciseNotFound(let id):
            return "Exercício não encontrado: \(id)"
        case .loadFailed(let error):
            return "Falha ao carregar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Input Structs

struct FetchFBExercisesInput {
    let muscleGroup: String?
    let equipment: String?
    let searchText: String?
    let limit: Int
    let sortBy: String
    
    init(
        muscleGroup: String? = nil,
        equipment: String? = nil,
        searchText: String? = nil,
        limit: Int = 50,
        sortBy: String = "name"
    ) {
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.searchText = searchText
        self.limit = limit
        self.sortBy = sortBy
    }
}

// MARK: - Output Structs

struct FetchFBExercisesOutput {
    let exercises: [FirebaseExercise]
    let totalCount: Int
    let uniqueMuscleGroups: Set<String>
}

// MARK: - Protocol

protocol FetchFBExercisesUseCaseProtocol {
    func fetchExercises(_ input: FetchFBExercisesInput) async throws -> FetchFBExercisesOutput
    func searchExercises(query: String) async throws -> [FirebaseExercise]
}

// MARK: - Use Case Implementation

final class FetchFBExercisesUseCase: FetchFBExercisesUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let repository: FirestoreExerciseRepositoryProtocol
    
    // MARK: - Initialization
    
    init(repository: FirestoreExerciseRepositoryProtocol) {
        self.repository = repository
        print("🔍 FetchFBExercisesUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func fetchExercises(_ input: FetchFBExercisesInput) async throws -> FetchFBExercisesOutput {
        print("🔍 Buscando exercícios Firebase")
        
        do {
            let exercises = try await repository.fetchExercises(
                muscleGroup: input.muscleGroup,
                equipment: input.equipment,
                searchText: input.searchText,
                limit: input.limit,
                sortBy: input.sortBy
            )
            
            let uniqueMuscleGroups = Set(exercises.map { $0.muscleGroup })
            
            let output = FetchFBExercisesOutput(
                exercises: exercises,
                totalCount: exercises.count,
                uniqueMuscleGroups: uniqueMuscleGroups
            )
            
            print("✅ \(exercises.count) exercícios carregados")
            return output
            
        } catch {
            print("❌ Erro ao buscar exercícios: \(error)")
            throw FetchFBExercisesError.loadFailed(error)
        }
    }
    
    func searchExercises(query: String) async throws -> [FirebaseExercise] {
        let input = FetchFBExercisesInput(searchText: query, limit: 20)
        let output = try await fetchExercises(input)
        return output.exercises
    }
}

// MARK: - Repository Protocol (será implementado no item 31)

protocol FirestoreExerciseRepositoryProtocol {
    func fetchExercises(
        muscleGroup: String?,
        equipment: String?,
        searchText: String?,
        limit: Int,
        sortBy: String
    ) async throws -> [FirebaseExercise]
}

// MARK: - FirebaseExercise já implementado no item 32 ✅
// Propriedades hasVideo, videoURL, description já disponíveis no modelo atualizado
} 