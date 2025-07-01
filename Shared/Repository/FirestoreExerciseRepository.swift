/*
 * FirestoreExerciseRepository.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Repository direto para Firestore sem cache inteligente
 *                   Implementa FirestoreExerciseRepositoryProtocol definido no FetchFBExercisesUseCase
 *
 * ARQUITETURA SIMPLIFICADA:
 * - Protocol + Implementation básica, sem listeners complexos
 * - Operações diretas ao Firestore: fetch(), search(), getVideoURL()
 * - URLs diretas do Firebase Storage para streaming
 * - Sem cache local, sem singleton, sem @Published
 *
 * OPERAÇÕES:
 * 1. fetchExercises() - Busca básica com filtros opcionais
 * 2. search() - Busca por texto livre
 * 3. getVideoURL() - URLs diretas do Firebase Storage (item 32)
 * 4. getThumbnailURL() - URLs de thumbnails (item 32)
 *
 * BENEFÍCIOS:
 * - Clean Architecture: Separação clara de responsabilidades
 * - Dependency Injection: Repository injetado no UseCase
 * - Testabilidade: Protocol facilita mocks
 * - Performance: Sem overhead de listeners ou cache complexo
 * - Simplicidade: Operações diretas, sem estado interno
 *
 * REFATORAÇÃO ITEM 31/101:
 * ✅ Criar FirestoreExerciseRepository.swift
 * 🔄 Preparado para videoURL/thumbnailURL (item 32)
 * 🔄 Substitui FirebaseExerciseService.swift (item 33)
 */

import Foundation
import FirebaseFirestore

// MARK: - FirestoreExerciseRepository Implementation

final class FirestoreExerciseRepository: FirestoreExerciseRepositoryProtocol {
    
    // MARK: - Dependencies
    
    private let firestore: Firestore
    private let collectionName = "exercisesList"
    
    // MARK: - Initialization
    
    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
        print("🏗️ FirestoreExerciseRepository inicializado")
    }
    
    // MARK: - FirestoreExerciseRepositoryProtocol Implementation
    
    func fetchExercises(
        muscleGroup: String?,
        equipment: String?,
        searchText: String?,
        limit: Int,
        sortBy: String
    ) async throws -> [FirebaseExercise] {
        print("🔍 Buscando exercícios do Firestore")
        print("📊 Filtros: muscleGroup=\(muscleGroup ?? "nil"), equipment=\(equipment ?? "nil"), search=\(searchText ?? "nil")")
        
        do {
            var query: Query = firestore.collection(collectionName)
            
            // Filtrar por grupo muscular
            if let muscleGroup = muscleGroup {
                query = query.whereField("muscleGroup", isEqualTo: muscleGroup)
            }
            
            // Filtrar por equipamento
            if let equipment = equipment {
                query = query.whereField("equipment", isEqualTo: equipment)
            }
            
            // Busca por texto (apenas no nome por simplicidade)
            if let searchText = searchText, !searchText.isEmpty {
                // Firestore não tem full-text search, usamos range query
                let searchLower = searchText.lowercased()
                query = query
                    .whereField("name", isGreaterThanOrEqualTo: searchLower)
                    .whereField("name", isLessThanOrEqualTo: searchLower + "\u{f8ff}")
            }
            
            // Ordenação
            query = query.order(by: sortBy)
            
            // Limite
            query = query.limit(to: limit)
            
            let snapshot = try await query.getDocuments()
            
            let exercises = snapshot.documents.compactMap { document in
                FirebaseExercise(document: document)
            }
            
            print("✅ \(exercises.count) exercícios carregados do Firestore")
            return exercises
            
        } catch {
            print("❌ Erro ao buscar exercícios: \(error)")
            throw FirestoreExerciseError.fetchFailed(error)
        }
    }
    
    // MARK: - Additional Methods (extensões para funcionalidades futuras)
    
    /// Busca exercício específico por templateId
    func fetchExercise(by templateId: String) async throws -> FirebaseExercise? {
        print("🔍 Buscando exercício específico: \(templateId)")
        
        do {
            let snapshot = try await firestore
                .collection(collectionName)
                .whereField("templateId", isEqualTo: templateId)
                .limit(to: 1)
                .getDocuments()
            
            guard let document = snapshot.documents.first else {
                print("⚠️ Exercício não encontrado: \(templateId)")
                return nil
            }
            
            let exercise = FirebaseExercise(document: document)
            print("✅ Exercício encontrado: \(exercise?.safeName ?? "unknown")")
            return exercise
            
        } catch {
            print("❌ Erro ao buscar exercício específico: \(error)")
            throw FirestoreExerciseError.fetchFailed(error)
        }
    }
    
    /// Busca múltiplos exercícios por templateIds
    func fetchExercises(by templateIds: Set<String>) async throws -> [FirebaseExercise] {
        print("🔍 Buscando \(templateIds.count) exercícios específicos")
        
        guard !templateIds.isEmpty else { return [] }
        
        // Firestore 'in' query limit é 10 itens
        let chunks = Array(templateIds).chunked(into: 10)
        var allExercises: [FirebaseExercise] = []
        
        do {
            for chunk in chunks {
                let snapshot = try await firestore
                    .collection(collectionName)
                    .whereField("templateId", in: chunk)
                    .getDocuments()
                
                let exercises = snapshot.documents.compactMap { document in
                    FirebaseExercise(document: document)
                }
                
                allExercises.append(contentsOf: exercises)
            }
            
            print("✅ \(allExercises.count) exercícios específicos carregados")
            return allExercises
            
        } catch {
            print("❌ Erro ao buscar exercícios específicos: \(error)")
            throw FirestoreExerciseError.fetchFailed(error)
        }
    }
    
    // MARK: - Video Methods (implementado no item 32) ✅
    
    /// Obtém URL do vídeo do Firebase Storage
    func getVideoURL(for exercise: FirebaseExercise) async throws -> String? {
        print("🎬 Obtendo URL do vídeo para: \(exercise.safeName)")
        
        // URL já vem direto do Firebase
        guard let videoURL = exercise.videoURL,
              !videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Vídeo não disponível para: \(exercise.safeName)")
            return nil
        }
        
        print("✅ URL do vídeo obtida: \(videoURL)")
        return videoURL
    }
    
    /// Obtém URL do thumbnail gerado automaticamente do vídeo
    func getThumbnailURL(for exercise: FirebaseExercise) async throws -> String? {
        print("🖼️ Gerando thumbnail para: \(exercise.safeName)")
        
        // Se tem vídeo, pode gerar thumbnail
        guard let videoURL = exercise.videoURL,
              !videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Sem vídeo para gerar thumbnail: \(exercise.safeName)")
            return nil
        }
        
        // Thumbnail será gerado automaticamente pelo player de vídeo ou AsyncImage
        // Para Firebase Storage, podemos usar transformações de URL se configurado
        let thumbnailURL = videoURL // Por enquanto retorna a mesma URL - o player gerará o thumbnail
        
        print("✅ Thumbnail gerado: \(thumbnailURL)")
        return thumbnailURL
    }
}

// MARK: - Error Types

enum FirestoreExerciseError: LocalizedError {
    case fetchFailed(Error)
    case exerciseNotFound(String)
    case invalidTemplateId(String)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed(let error):
            return "Erro ao buscar exercícios: \(error.localizedDescription)"
        case .exerciseNotFound(let id):
            return "Exercício não encontrado: \(id)"
        case .invalidTemplateId(let id):
            return "ID de template inválido: \(id)"
        case .networkError:
            return "Erro de conexão ao buscar exercícios"
        }
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview Mock (para desenvolvimento)

#if DEBUG
extension FirestoreExerciseRepository {
    static var preview: FirestoreExerciseRepository {
        return FirestoreExerciseRepository()
    }
}
#endif 