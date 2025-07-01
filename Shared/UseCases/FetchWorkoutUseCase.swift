/*
 * FetchWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para busca e filtragem de planos de treino existentes.
 *                   Implementa Clean Architecture com operações de consulta otimizadas.
 *
 * ARQUITETURA:
 * - Orquestra WorkoutDataService (busca local)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI
 * - NÃO contém lógica de sincronização (apenas leitura)
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: Busca de planos de treino
 *
 * OPERAÇÕES PRINCIPAIS:
 * 1. fetchAllWorkouts(for user:) - Todos os planos do usuário ordenados
 * 2. fetchWorkoutById(id:) - Busca específica por UUID
 * 3. fetchWorkoutsByMuscleGroup(groups:, user:) - Filtro por grupos musculares
 * 4. fetchWorkoutStatistics(for user:) - Estatísticas básicas
 *
 * COMPATIBILIDADE TÍTULOS DUAIS:
 * - Usa displayTitle e compactTitle das computed properties
 * - Suporte total ao sistema autoTitle + customTitle
 * - Ordenação inteligente por order (sistemática)
 *
 * FUNCIONALIDADES AVANÇADAS:
 * - Filtros por grupos musculares
 * - Ordenação configurável (order, createdAt, title)
 * - Estatísticas de treinos (contagem, grupos únicos)
 * - Busca otimizada com performance
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 * - Logs informativos em português
 *
 * REFATORAÇÃO ITEM 18/50:
 * ✅ Use Case de busca com Clean Architecture
 * ✅ Injeção de WorkoutDataService
 * ✅ Operações de consulta otimizadas
 * ✅ Compatibilidade com sistema dual de títulos
 * ✅ Filtros e estatísticas avançadas
 */

import Foundation

// MARK: - FetchWorkoutError

enum FetchWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case fetchFailed(Error)
    case workoutNotFound(UUID)
    case invalidMuscleGroups([String])
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Dados inválidos para busca: \(message)"
        case .fetchFailed(let error):
            return "Falha na busca de treinos: \(error.localizedDescription)"
        case .workoutNotFound(let id):
            return "Treino não encontrado com ID: \(id.uuidString)"
        case .invalidMuscleGroups(let groups):
            return "Grupos musculares inválidos: \(groups.joined(separator: ", "))"
        }
    }
}

// MARK: - FetchWorkoutSortOrder

enum FetchWorkoutSortOrder {
    case order          // Padrão: ordenação sistemática (A, B, C...)
    case createdAt      // Por data de criação (mais recente primeiro)
    case title          // Alfabética por displayTitle
    case muscleGroups   // Por grupos musculares
}

// MARK: - FetchWorkoutInput

struct FetchAllWorkoutsInput {
    let user: CDAppUser
    let sortOrder: FetchWorkoutSortOrder
    let muscleGroupFilter: [String]?
    
    init(
        user: CDAppUser,
        sortOrder: FetchWorkoutSortOrder = .order,
        muscleGroupFilter: [String]? = nil
    ) {
        self.user = user
        self.sortOrder = sortOrder
        self.muscleGroupFilter = muscleGroupFilter
    }
    
    /// Validação dos dados de entrada
    func validate() throws {
        // Validar filtro de grupos musculares se fornecido
        if let groups = muscleGroupFilter {
            let validGroups = groups.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !validGroups.isEmpty else {
                throw FetchWorkoutError.invalidInput("Filtro de grupos musculares não pode estar vazio")
            }
            
            guard validGroups.count <= 10 else {
                throw FetchWorkoutError.invalidInput("Máximo de 10 grupos musculares por filtro")
            }
        }
    }
}

struct FetchWorkoutByIdInput {
    let id: UUID
    
    /// Validação simples do UUID
    func validate() throws {
        // UUID já validado pelo tipo, nenhuma validação adicional necessária
    }
}

struct FetchWorkoutsByMuscleGroupInput {
    let muscleGroups: [String]
    let user: CDAppUser
    let exactMatch: Bool // true = todos os grupos devem estar presentes, false = pelo menos um
    
    init(muscleGroups: [String], user: CDAppUser, exactMatch: Bool = false) {
        self.muscleGroups = muscleGroups
        self.user = user
        self.exactMatch = exactMatch
    }
    
    /// Validação dos grupos musculares
    func validate() throws {
        guard !muscleGroups.isEmpty else {
            throw FetchWorkoutError.invalidInput("Deve especificar pelo menos um grupo muscular")
        }
        
        let validGroups = muscleGroups.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard validGroups.count == muscleGroups.count else {
            let invalidGroups = muscleGroups.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            throw FetchWorkoutError.invalidMuscleGroups(invalidGroups)
        }
        
        guard muscleGroups.count <= 5 else {
            throw FetchWorkoutError.invalidInput("Máximo de 5 grupos musculares por busca")
        }
    }
}

// MARK: - FetchWorkoutOutput

struct FetchAllWorkoutsOutput {
    let workouts: [CDWorkoutPlan]
    let totalCount: Int
    let uniqueMuscleGroups: Set<String>
    let sortOrder: FetchWorkoutSortOrder
}

struct FetchWorkoutByIdOutput {
    let workout: CDWorkoutPlan
    let exerciseCount: Int
    let muscleGroups: [String]
}

struct FetchWorkoutsByMuscleGroupOutput {
    let workouts: [CDWorkoutPlan]
    let matchingGroups: Set<String>
    let totalMatches: Int
}

struct FetchWorkoutStatisticsOutput {
    let totalWorkouts: Int
    let uniqueMuscleGroups: Set<String>
    let averageExercisesPerWorkout: Double
    let workoutsWithCustomTitle: Int
    let workoutsWithAutoTitleOnly: Int
    let mostCommonMuscleGroups: [(group: String, count: Int)]
}

// MARK: - FetchWorkoutUseCaseProtocol

protocol FetchWorkoutUseCaseProtocol {
    func fetchAllWorkouts(_ input: FetchAllWorkoutsInput) async throws -> FetchAllWorkoutsOutput
    func fetchWorkoutById(_ input: FetchWorkoutByIdInput) async throws -> FetchWorkoutByIdOutput
    func fetchWorkoutsByMuscleGroup(_ input: FetchWorkoutsByMuscleGroupInput) async throws -> FetchWorkoutsByMuscleGroupOutput
    func fetchWorkoutStatistics(for user: CDAppUser) async throws -> FetchWorkoutStatisticsOutput
}

// MARK: - FetchWorkoutUseCase

final class FetchWorkoutUseCase: FetchWorkoutUseCaseProtocol {
    
    // MARK: - Properties
    
    private let workoutDataService: WorkoutDataServiceProtocol
    
    // MARK: - Initialization
    
    init(workoutDataService: WorkoutDataServiceProtocol) {
        self.workoutDataService = workoutDataService
        print("🔍 FetchWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func fetchAllWorkouts(_ input: FetchAllWorkoutsInput) async throws -> FetchAllWorkoutsOutput {
        print("📋 Buscando todos os treinos do usuário: \(input.user.safeName)")
        
        do {
            // 1. Validar entrada
            try input.validate()
            
            // 2. Buscar treinos via WorkoutDataService
            let workouts = try await workoutDataService.fetchWorkoutPlans(for: input.user)
            print("✅ \(workouts.count) treinos encontrados")
            
            // 3. Aplicar filtro de grupos musculares se especificado
            let filteredWorkouts = try applyMuscleGroupFilter(workouts, filter: input.muscleGroupFilter)
            print("🎯 \(filteredWorkouts.count) treinos após filtro de grupos musculares")
            
            // 4. Aplicar ordenação
            let sortedWorkouts = applySortOrder(filteredWorkouts, sortOrder: input.sortOrder)
            
            // 5. Coletar estatísticas
            let uniqueMuscleGroups = extractUniqueMuscleGroups(from: sortedWorkouts)
            
            let output = FetchAllWorkoutsOutput(
                workouts: sortedWorkouts,
                totalCount: sortedWorkouts.count,
                uniqueMuscleGroups: uniqueMuscleGroups,
                sortOrder: input.sortOrder
            )
            
            print("🎉 Busca concluída: \(output.totalCount) treinos, \(output.uniqueMuscleGroups.count) grupos únicos")
            return output
            
        } catch let error as FetchWorkoutError {
            print("❌ Erro na busca de treinos: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na busca: \(error)")
            throw FetchWorkoutError.fetchFailed(error)
        }
    }
    
    func fetchWorkoutById(_ input: FetchWorkoutByIdInput) async throws -> FetchWorkoutByIdOutput {
        print("🔎 Buscando treino por ID: \(input.id.uuidString)")
        
        do {
            try input.validate()
            
            // Buscar todos os treinos e encontrar o específico
            let allWorkouts = try await workoutDataService.fetchWorkoutPlans(for: nil)
            
            guard let workout = allWorkouts.first(where: { $0.safeId == input.id }) else {
                print("❌ Treino não encontrado com ID: \(input.id.uuidString)")
                throw FetchWorkoutError.workoutNotFound(input.id)
            }
            
            // Coletar informações detalhadas
            let exerciseCount = workout.exercisesArray.count
            let muscleGroups = workout.muscleGroupsList
            
            let output = FetchWorkoutByIdOutput(
                workout: workout,
                exerciseCount: exerciseCount,
                muscleGroups: muscleGroups
            )
            
            print("✅ Treino encontrado: \(workout.displayTitle) (\(exerciseCount) exercícios)")
            return output
            
        } catch let error as FetchWorkoutError {
            throw error
        } catch {
            print("❌ Erro inesperado na busca por ID: \(error)")
            throw FetchWorkoutError.fetchFailed(error)
        }
    }
    
    func fetchWorkoutsByMuscleGroup(_ input: FetchWorkoutsByMuscleGroupInput) async throws -> FetchWorkoutsByMuscleGroupOutput {
        let groupsStr = input.muscleGroups.joined(separator: ", ")
        print("💪 Buscando treinos por grupos musculares: \(groupsStr)")
        
        do {
            try input.validate()
            
            // Buscar todos os treinos do usuário
            let allWorkouts = try await workoutDataService.fetchWorkoutPlans(for: input.user)
            
            // Filtrar por grupos musculares
            let matchingWorkouts = allWorkouts.filter { workout in
                let workoutGroups = Set(workout.muscleGroupsList.map { $0.lowercased() })
                let searchGroups = Set(input.muscleGroups.map { $0.lowercased() })
                
                if input.exactMatch {
                    // Todos os grupos devem estar presentes
                    return searchGroups.isSubset(of: workoutGroups)
                } else {
                    // Pelo menos um grupo deve estar presente
                    return !searchGroups.intersection(workoutGroups).isEmpty
                }
            }
            
            // Coletar grupos musculares únicos dos resultados
            let matchingGroups = extractUniqueMuscleGroups(from: matchingWorkouts)
            
            let output = FetchWorkoutsByMuscleGroupOutput(
                workouts: matchingWorkouts,
                matchingGroups: matchingGroups,
                totalMatches: matchingWorkouts.count
            )
            
            let matchType = input.exactMatch ? "exata" : "parcial"
            print("🎯 Busca \(matchType) concluída: \(output.totalMatches) treinos encontrados")
            return output
            
        } catch let error as FetchWorkoutError {
            throw error
        } catch {
            print("❌ Erro inesperado na busca por grupos musculares: \(error)")
            throw FetchWorkoutError.fetchFailed(error)
        }
    }
    
    func fetchWorkoutStatistics(for user: CDAppUser) async throws -> FetchWorkoutStatisticsOutput {
        print("📊 Coletando estatísticas de treinos para: \(user.safeName)")
        
        do {
            let workouts = try await workoutDataService.fetchWorkoutPlans(for: user)
            
            // Coletar estatísticas básicas
            let totalWorkouts = workouts.count
            let uniqueMuscleGroups = extractUniqueMuscleGroups(from: workouts)
            
            // Calcular média de exercícios por treino
            let totalExercises = workouts.reduce(0) { $0 + $1.exercisesArray.count }
            let averageExercisesPerWorkout = totalWorkouts > 0 ? Double(totalExercises) / Double(totalWorkouts) : 0.0
            
            // Contar treinos com títulos personalizados
            let workoutsWithCustomTitle = workouts.filter { $0.hasCustomTitle }.count
            let workoutsWithAutoTitleOnly = totalWorkouts - workoutsWithCustomTitle
            
            // Encontrar grupos musculares mais comuns
            let muscleGroupCounts = countMuscleGroupOccurrences(in: workouts)
            let mostCommonMuscleGroups = muscleGroupCounts.sorted { $0.count > $1.count }.prefix(5).map { $0 }
            
            let output = FetchWorkoutStatisticsOutput(
                totalWorkouts: totalWorkouts,
                uniqueMuscleGroups: uniqueMuscleGroups,
                averageExercisesPerWorkout: averageExercisesPerWorkout,
                workoutsWithCustomTitle: workoutsWithCustomTitle,
                workoutsWithAutoTitleOnly: workoutsWithAutoTitleOnly,
                mostCommonMuscleGroups: Array(mostCommonMuscleGroups)
            )
            
            print("📈 Estatísticas coletadas: \(totalWorkouts) treinos, \(uniqueMuscleGroups.count) grupos únicos")
            return output
            
        } catch {
            print("❌ Erro ao coletar estatísticas: \(error)")
            throw FetchWorkoutError.fetchFailed(error)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func applyMuscleGroupFilter(_ workouts: [CDWorkoutPlan], filter: [String]?) throws -> [CDWorkoutPlan] {
        guard let filter = filter, !filter.isEmpty else {
            return workouts // Sem filtro, retorna todos
        }
        
        let filterGroups = Set(filter.map { $0.lowercased() })
        
        return workouts.filter { workout in
            let workoutGroups = Set(workout.muscleGroupsList.map { $0.lowercased() })
            return !filterGroups.intersection(workoutGroups).isEmpty
        }
    }
    
    private func applySortOrder(_ workouts: [CDWorkoutPlan], sortOrder: FetchWorkoutSortOrder) -> [CDWorkoutPlan] {
        switch sortOrder {
        case .order:
            return workouts.sorted { $0.order < $1.order }
            
        case .createdAt:
            return workouts.sorted { $0.createdAt > $1.createdAt } // Mais recente primeiro
            
        case .title:
            return workouts.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            
        case .muscleGroups:
            return workouts.sorted { $0.muscleGroupsString.localizedCaseInsensitiveCompare($1.muscleGroupsString) == .orderedAscending }
        }
    }
    
    private func extractUniqueMuscleGroups(from workouts: [CDWorkoutPlan]) -> Set<String> {
        var allGroups = Set<String>()
        
        for workout in workouts {
            for group in workout.muscleGroupsList {
                allGroups.insert(group.capitalized)
            }
        }
        
        return allGroups
    }
    
    private func countMuscleGroupOccurrences(in workouts: [CDWorkoutPlan]) -> [(group: String, count: Int)] {
        var groupCounts: [String: Int] = [:]
        
        for workout in workouts {
            for group in workout.muscleGroupsList {
                let normalizedGroup = group.capitalized
                groupCounts[normalizedGroup, default: 0] += 1
            }
        }
        
        return groupCounts.map { (group: $0.key, count: $0.value) }
    }
}

// MARK: - Convenience Extensions

extension FetchWorkoutUseCase {
    
    /// Método de conveniência para buscar todos os treinos com ordenação padrão
    func fetchAllWorkouts(for user: CDAppUser) async throws -> [CDWorkoutPlan] {
        let input = FetchAllWorkoutsInput(user: user)
        let output = try await fetchAllWorkouts(input)
        return output.workouts
    }
    
    /// Método de conveniência para buscar treino por ID sem output estruturado
    func fetchWorkout(id: UUID) async throws -> CDWorkoutPlan {
        let input = FetchWorkoutByIdInput(id: id)
        let output = try await fetchWorkoutById(input)
        return output.workout
    }
    
    /// Método de conveniência para buscar por um único grupo muscular
    func fetchWorkouts(withMuscleGroup group: String, for user: CDAppUser) async throws -> [CDWorkoutPlan] {
        let input = FetchWorkoutsByMuscleGroupInput(muscleGroups: [group], user: user)
        let output = try await fetchWorkoutsByMuscleGroup(input)
        return output.workouts
    }
} 