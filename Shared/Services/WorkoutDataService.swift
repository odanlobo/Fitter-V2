/*
 * WorkoutDataService.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Serviço de dados especializado para operações CRUD de entidades relacionadas a treinos.
 *                   Implementa Clean Architecture com separação clara de responsabilidades.
 *
 * ARQUITETURA:
 * - NÃO faz sincronização (responsabilidade dos Use Cases)
 * - Delega serialização/deserialização ao CoreDataAdapter
 * - Usa CoreDataService para operações CRUD genéricas
 * - Trata erros específicos do domínio workout
 *
 * DEPENDÊNCIAS:
 * - CoreDataServiceProtocol: Operações CRUD genéricas
 * - CoreDataAdapter: Serialização de SensorData para Binary Data
 *
 * ENTIDADES GERENCIADAS (CONFORME CORE DATA MODEL):
 * - CDWorkoutPlan: Planos de treino personalizados
 * - CDCurrentSession: Sessão ativa de treino  
 * - CDCurrentExercise: Exercício ativo na sessão
 * - CDCurrentSet: Série ativa (treino em andamento)
 * - CDWorkoutHistory: Histórico de treinos completados
 * - CDHistoryExercise: Exercício no histórico
 * - CDHistorySet: Série completada (histórico de performance)
 * - CDExerciseTemplate: Templates de exercícios disponíveis
 * - CDPlanExercise: Exercícios dentro dos planos
 *
 * OTIMIZAÇÕES:
 * - External Storage para Binary Data (sensorData)
 * - 89% menos complexidade vs modelo anterior (18 → 2 campos)
 * - Logs informativos com emojis para debug
 * - Async/await nativo para performance
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Helper methods para operações complexas
 *
 * REFATORAÇÃO ITEM 16/47:
 * ✅ CRUD especializado sem sync
 * ✅ Delegação de serialização ao CoreDataAdapter
 * ✅ Entidades corretas do Core Data Model
 * ✅ Tratamento de erros com WorkoutDataError enum
 * ✅ Injeção de dependências CoreDataService + CoreDataAdapter
 */

import Foundation
import CoreData
import Combine

// MARK: - WorkoutDataError

enum WorkoutDataError: Error, LocalizedError {
    case entityNotFound(String)
    case serializationFailed(Error)
    case deserializationFailed(Error)
    case persistenceFailed(Error)
    case invalidData(String)
    case coreDataError(CoreDataError)
    
    var errorDescription: String? {
        switch self {
        case .entityNotFound(let id):
            return "Entidade não encontrada: \(id)"
        case .serializationFailed(let error):
            return "Falha na serialização: \(error.localizedDescription)"
        case .deserializationFailed(let error):
            return "Falha na deserialização: \(error.localizedDescription)"
        case .persistenceFailed(let error):
            return "Falha na persistência: \(error.localizedDescription)"
        case .invalidData(let message):
            return "Dados inválidos: \(message)"
        case .coreDataError(let coreDataError):
            return "Erro Core Data: \(coreDataError.localizedDescription)"
        }
    }
}

// MARK: - WorkoutDataServiceProtocol

protocol WorkoutDataServiceProtocol {
        // MARK: - Workout Plans  
    func createWorkoutPlan(autoTitle: String, customTitle: String?, muscleGroups: String?, user: CDAppUser) async throws -> CDWorkoutPlan
    func fetchWorkoutPlans(for user: CDAppUser) async throws -> [CDWorkoutPlan]
    func updateWorkoutPlan(_ plan: CDWorkoutPlan, customTitle: String?, muscleGroups: String?) async throws
    func deleteWorkoutPlan(_ plan: CDWorkoutPlan) async throws
    func reorderWorkoutPlans(_ plans: [CDWorkoutPlan]) async throws
    
    // MARK: - Plan Exercises
    func addExerciseTemplate(_ template: CDExerciseTemplate, to plan: CDWorkoutPlan, order: Int32) async throws -> CDPlanExercise
    func removePlanExercise(_ planExercise: CDPlanExercise, from plan: CDWorkoutPlan) async throws
    func reorderPlanExercises(_ planExercises: [CDPlanExercise], in plan: CDWorkoutPlan) async throws
    
    // MARK: - Current Sessions (Active Workouts)
    func createCurrentSession(for plan: CDWorkoutPlan, user: CDAppUser, startTime: Date) async throws -> CDCurrentSession
    func fetchCurrentSessions(for user: CDAppUser) async throws -> [CDCurrentSession]
    func updateCurrentSession(_ session: CDCurrentSession, endTime: Date?) async throws
    func deleteCurrentSession(_ session: CDCurrentSession) async throws
    
    // MARK: - Current Exercises (Active in Session)
    func createCurrentExercise(for template: CDExerciseTemplate, in session: CDCurrentSession, startTime: Date) async throws -> CDCurrentExercise
    func updateCurrentExercise(_ exercise: CDCurrentExercise, endTime: Date?) async throws
    
    // MARK: - Current Sets (Live Workout)
    func createCurrentSet(for exercise: CDCurrentExercise, targetReps: Int32, weight: Double, order: Int32, sensorData: SensorData?) async throws -> CDCurrentSet
    func fetchCurrentSets(for exercise: CDCurrentExercise?) async throws -> [CDCurrentSet]
    func updateCurrentSet(_ set: CDCurrentSet, actualReps: Int32?, restTime: Double?, endTime: Date?, sensorData: SensorData?) async throws
    func deleteCurrentSet(_ set: CDCurrentSet) async throws
    func deleteAllCurrentSets() async throws
    
    // MARK: - Workout History (Completed Workouts)
    func createWorkoutHistory(from session: CDCurrentSession, user: CDAppUser, date: Date) async throws -> CDWorkoutHistory
    func fetchWorkoutHistory(for user: CDAppUser) async throws -> [CDWorkoutHistory]
    func deleteWorkoutHistory(_ history: CDWorkoutHistory) async throws
    
    // MARK: - History Exercises (Completed Exercises)
    func createHistoryExercise(name: String, order: Int32, workoutHistory: CDWorkoutHistory) async throws -> CDHistoryExercise
    
    // MARK: - History Sets (Completed Sets)
    func createHistorySet(from currentSet: CDCurrentSet, exercise: CDHistoryExercise, order: Int32) async throws -> CDHistorySet
    func fetchHistorySets(for exercise: CDHistoryExercise?) async throws -> [CDHistorySet]
    func fetchHistorySets(for template: CDExerciseTemplate?) async throws -> [CDHistorySet]
    func deleteHistorySet(_ set: CDHistorySet) async throws
}

// MARK: - WorkoutDataService

final class WorkoutDataService: WorkoutDataServiceProtocol {
    
    // MARK: - Properties
    
    private let coreDataService: CoreDataServiceProtocol
    private let adapter: CoreDataAdapter
    
    // MARK: - Initialization
    
    init(coreDataService: CoreDataServiceProtocol, adapter: CoreDataAdapter = CoreDataAdapter()) {
        self.coreDataService = coreDataService
        self.adapter = adapter
        
        print("🏋️‍♂️ WorkoutDataService inicializado")
    }
    
    // MARK: - Private Helper Methods
    
    private func handleCoreDataError<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as CoreDataError {
            throw WorkoutDataError.coreDataError(error)
        } catch {
            throw WorkoutDataError.persistenceFailed(error)
        }
    }
    
    private func serializeSensorData(_ sensorData: SensorData?) throws -> Data? {
        guard let sensorData = sensorData else { return nil }
        
        do {
            return try adapter.serializeSensorData(sensorData)
        } catch {
            throw WorkoutDataError.serializationFailed(error)
        }
    }
    
    private func deserializeSensorData(_ data: Data?) throws -> SensorData? {
        guard let data = data else { return nil }
        
        do {
            return try adapter.deserializeSensorData(data)
        } catch {
            throw WorkoutDataError.deserializationFailed(error)
        }
    }
    
    // MARK: - Workout Plans
    
    func createWorkoutPlan(autoTitle: String, customTitle: String?, muscleGroups: String?, user: CDAppUser) async throws -> CDWorkoutPlan {
        return try await handleCoreDataError {
            let plan: CDWorkoutPlan = try await coreDataService.create()
            plan.id = UUID()
            plan.autoTitle = autoTitle
            plan.title = customTitle
            plan.muscleGroups = muscleGroups ?? ""
            plan.createdAt = Date()
            plan.order = 0 // Will be updated when reordering
            plan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            plan.user = user
            
            try await coreDataService.save()
            
            print("✅ Plano de treino criado: \(plan.displayTitle)")
            return plan
        }
    }
    
    func fetchWorkoutPlans(for user: CDAppUser) async throws -> [CDWorkoutPlan] {
        return try await handleCoreDataError {
            let request = CDWorkoutPlan.fetchRequest()
            
            request.predicate = NSPredicate(format: "user == %@", user)
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkoutPlan.order, ascending: true)]
            
            let plans = try await coreDataService.fetch(request)
            print("📋 Buscados \(plans.count) planos de treino")
            return plans
        }
    }
    
    func updateWorkoutPlan(_ plan: CDWorkoutPlan, customTitle: String?, muscleGroups: String?) async throws {
        try await handleCoreDataError {
            if let customTitle = customTitle {
                plan.title = customTitle
            }
            if let muscleGroups = muscleGroups {
                plan.muscleGroups = muscleGroups
            }
            plan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            print("✏️ Plano de treino atualizado: \(plan.displayTitle)")
        }
    }
    
    func deleteWorkoutPlan(_ plan: CDWorkoutPlan) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(plan)
            print("🗑️ Plano de treino excluído: \(plan.displayTitle)")
        }
    }
    
    func reorderWorkoutPlans(_ plans: [CDWorkoutPlan]) async throws {
        try await handleCoreDataError {
            for (index, plan) in plans.enumerated() {
                plan.order = Int32(index)
                plan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            }
            
            try await coreDataService.save()
            print("🔄 Reordenados \(plans.count) planos de treino")
        }
    }
    
    // MARK: - Plan Exercises
    
    func addExerciseTemplate(_ template: CDExerciseTemplate, to plan: CDWorkoutPlan, order: Int32) async throws -> CDPlanExercise {
        return try await handleCoreDataError {
            let planExercise: CDPlanExercise = try await coreDataService.create()
            planExercise.id = UUID()
            planExercise.order = order
            planExercise.template = template
            planExercise.plan = plan
            planExercise.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            print("➕ Exercício \(template.safeName) adicionado ao plano \(plan.displayTitle)")
            return planExercise
        }
    }
    
    func removePlanExercise(_ planExercise: CDPlanExercise, from plan: CDWorkoutPlan) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(planExercise)
            plan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            print("➖ Exercício removido do plano \(plan.displayTitle)")
        }
    }
    
    func reorderPlanExercises(_ planExercises: [CDPlanExercise], in plan: CDWorkoutPlan) async throws {
        try await handleCoreDataError {
            for (index, planExercise) in planExercises.enumerated() {
                planExercise.order = Int32(index)
                planExercise.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            }
            
            plan.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            print("🔄 Exercícios reordenados no plano: \(plan.displayTitle)")
        }
    }
    
    // MARK: - Current Sessions (Active Workouts)
    
    func createCurrentSession(for plan: CDWorkoutPlan, user: CDAppUser, startTime: Date) async throws -> CDCurrentSession {
        return try await handleCoreDataError {
            let session: CDCurrentSession = try await coreDataService.create()
            session.id = UUID()
            session.startTime = startTime
            session.isActive = true
            session.currentExerciseIndex = 0
            session.plan = plan
            session.user = user
            
            try await coreDataService.save()
            
            print("▶️ Sessão de treino iniciada para: \(plan.displayTitle)")
            return session
        }
    }
    
    func fetchCurrentSessions(for user: CDAppUser) async throws -> [CDCurrentSession] {
        return try await handleCoreDataError {
            let request = CDCurrentSession.fetchRequest()
            
            request.predicate = NSPredicate(format: "user == %@", user)
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDCurrentSession.startTime, ascending: false)]
            
            let sessions = try await coreDataService.fetch(request)
            print("📅 Buscadas \(sessions.count) sessões ativas")
            return sessions
        }
    }
    
    func updateCurrentSession(_ session: CDCurrentSession, endTime: Date?) async throws {
        try await handleCoreDataError {
            if let endTime = endTime {
                session.endTime = endTime
                session.isActive = false
            }
            
            try await coreDataService.save()
            print("✏️ Sessão de treino atualizada")
        }
    }
    
    func deleteCurrentSession(_ session: CDCurrentSession) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(session)
            print("🗑️ Sessão de treino excluída")
        }
    }
    
    // MARK: - Current Exercises (Active in Session)
    
    func createCurrentExercise(for template: CDExerciseTemplate, in session: CDCurrentSession, startTime: Date) async throws -> CDCurrentExercise {
        return try await handleCoreDataError {
            let exercise: CDCurrentExercise = try await coreDataService.create()
            exercise.id = UUID()
            exercise.startTime = startTime
            exercise.isActive = true
            exercise.currentSetIndex = 0
            exercise.template = template
            exercise.session = session
            
            // Atualizar sessão
            session.currentExercise = exercise
            
            try await coreDataService.save()
            
            print("🏃‍♂️ Exercício iniciado: \(template.safeName)")
            return exercise
        }
    }
    
    func updateCurrentExercise(_ exercise: CDCurrentExercise, endTime: Date?) async throws {
        try await handleCoreDataError {
            if let endTime = endTime {
                exercise.endTime = endTime
                exercise.isActive = false
            }
            
            try await coreDataService.save()
            print("✏️ Exercício atualizado: \(exercise.template?.safeName ?? "Unknown")")
        }
    }
    
    // MARK: - Current Sets (Live Workout)
    
    func createCurrentSet(for exercise: CDCurrentExercise, targetReps: Int32, weight: Double, order: Int32, sensorData: SensorData?) async throws -> CDCurrentSet {
        return try await handleCoreDataError {
            let set: CDCurrentSet = try await coreDataService.create()
            set.id = UUID()
            set.order = order
            set.targetReps = targetReps
            set.weight = weight
            set.timestamp = Date()
            set.isActive = true
            set.exercise = exercise
            
            // Serializar sensor data via CoreDataAdapter
            if let sensorData = sensorData {
                set.sensorData = try serializeSensorData(sensorData)
            }
            
            // Atualizar exercício
            exercise.currentSet = set
            
            try await coreDataService.save()
            
            print("🏃‍♂️ Current set criado para: \(exercise.template?.safeName ?? "Unknown")")
            return set
        }
    }
    
    func fetchCurrentSets(for exercise: CDCurrentExercise?) async throws -> [CDCurrentSet] {
        return try await handleCoreDataError {
            let request = CDCurrentSet.fetchRequest()
            
            if let exercise = exercise {
                request.predicate = NSPredicate(format: "exercise == %@", exercise)
            }
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDCurrentSet.order, ascending: true)]
            
            let sets = try await coreDataService.fetch(request)
            print("💪 Buscados \(sets.count) current sets")
            return sets
        }
    }
    
    func updateCurrentSet(_ set: CDCurrentSet, actualReps: Int32?, restTime: Double?, endTime: Date?, sensorData: SensorData?) async throws {
        try await handleCoreDataError {
            if let actualReps = actualReps {
                set.actualReps = actualReps
            }
            if let restTime = restTime {
                set.restTime = restTime
            }
            if let endTime = endTime {
                set.endTime = endTime
                set.isActive = false
            }
            
            // Atualizar sensor data via CoreDataAdapter
            if let sensorData = sensorData {
                set.sensorData = try serializeSensorData(sensorData)
            }
            
            try await coreDataService.save()
            print("✏️ Current set atualizado")
        }
    }
    
    func deleteCurrentSet(_ set: CDCurrentSet) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(set)
            print("🗑️ Current set excluído")
        }
    }
    
    func deleteAllCurrentSets() async throws {
        try await handleCoreDataError {
            let request = CDCurrentSet.fetchRequest()
            let sets = try await coreDataService.fetch(request)
            
            for set in sets {
                try await coreDataService.delete(set)
            }
            
            print("🧹 Todos os current sets foram excluídos (\(sets.count) itens)")
        }
    }
    
    // MARK: - Workout History (Completed Workouts)
    
    func createWorkoutHistory(from session: CDCurrentSession, user: CDAppUser, date: Date) async throws -> CDWorkoutHistory {
        return try await handleCoreDataError {
            let history: CDWorkoutHistory = try await coreDataService.create()
            history.id = UUID()
            history.date = date
            history.user = user
            history.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            
            print("📜 Histórico de treino criado da sessão")
            return history
        }
    }
    
    func fetchWorkoutHistory(for user: CDAppUser) async throws -> [CDWorkoutHistory] {
        return try await handleCoreDataError {
            let request = CDWorkoutHistory.fetchRequest()
            
            request.predicate = NSPredicate(format: "user == %@", user)
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkoutHistory.date, ascending: false)]
            
            let histories = try await coreDataService.fetch(request)
            print("📊 Buscados \(histories.count) históricos de treino")
            return histories
        }
    }
    
    func deleteWorkoutHistory(_ history: CDWorkoutHistory) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(history)
            print("🗑️ Histórico de treino excluído")
        }
    }
    
    // MARK: - History Exercises (Completed Exercises)
    
    func createHistoryExercise(name: String, order: Int32, workoutHistory: CDWorkoutHistory) async throws -> CDHistoryExercise {
        return try await handleCoreDataError {
            let historyExercise: CDHistoryExercise = try await coreDataService.create()
            historyExercise.id = UUID()
            historyExercise.name = name
            historyExercise.order = order
            historyExercise.history = workoutHistory
            historyExercise.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            
            print("📜 History exercise criado: \(name)")
            return historyExercise
        }
    }
    
    // MARK: - History Sets (Completed Sets)
    
    func createHistorySet(from currentSet: CDCurrentSet, exercise: CDHistoryExercise, order: Int32) async throws -> CDHistorySet {
        return try await handleCoreDataError {
            let historySet: CDHistorySet = try await coreDataService.create()
            historySet.id = UUID()
            historySet.order = order
            historySet.reps = currentSet.actualReps ?? currentSet.targetReps
            historySet.weight = currentSet.weight
            historySet.startTime = currentSet.startTime
            historySet.endTime = currentSet.endTime
            historySet.timestamp = currentSet.timestamp
            historySet.restTime = currentSet.restTime
            historySet.heartRate = currentSet.heartRate
            historySet.caloriesBurned = currentSet.caloriesBurned
            historySet.sensorData = currentSet.sensorData // Já serializado
            historySet.exercise = exercise
            historySet.cloudSyncStatus = CloudSyncStatus.pending.rawValue
            
            try await coreDataService.save()
            
            print("📜 History set criado do current set")
            return historySet
        }
    }
    
    func fetchHistorySets(for exercise: CDHistoryExercise?) async throws -> [CDHistorySet] {
        return try await handleCoreDataError {
            let request = CDHistorySet.fetchRequest()
            
            if let exercise = exercise {
                request.predicate = NSPredicate(format: "exercise == %@", exercise)
            }
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDHistorySet.timestamp, ascending: false)]
            
            let sets = try await coreDataService.fetch(request)
            print("📊 Buscados \(sets.count) history sets")
            return sets
        }
    }
    
    func fetchHistorySets(for template: CDExerciseTemplate?) async throws -> [CDHistorySet] {
        return try await handleCoreDataError {
            guard let template = template else {
                let request = CDHistorySet.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \CDHistorySet.timestamp, ascending: false)]
                let sets = try await coreDataService.fetch(request)
                print("📈 Buscados \(sets.count) history sets (todos)")
                return sets
            }
            
            // Buscar por exercícios com o mesmo nome do template
            let request = CDHistorySet.fetchRequest()
            request.predicate = NSPredicate(format: "exercise.name == %@", template.safeName)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDHistorySet.timestamp, ascending: false)]
            
            let sets = try await coreDataService.fetch(request)
            print("📈 Buscados \(sets.count) history sets para template: \(template.safeName)")
            return sets
        }
    }
    
    func deleteHistorySet(_ set: CDHistorySet) async throws {
        try await handleCoreDataError {
            try await coreDataService.delete(set)
            print("🗑️ History set excluído")
        }
    }
}

// MARK: - Extension for SensorData Access

extension WorkoutDataService {
    
    /// Busca sensor data deserializado de um CDCurrentSet
    func getSensorData(from currentSet: CDCurrentSet) throws -> SensorData? {
        return try deserializeSensorData(currentSet.sensorData)
    }
    
    /// Busca sensor data deserializado de um CDHistorySet
    func getSensorData(from historySet: CDHistorySet) throws -> SensorData? {
        return try deserializeSensorData(historySet.sensorData)
    }
} 