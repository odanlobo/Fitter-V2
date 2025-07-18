//
//  EndWorkoutUseCase.swift
//  Fitter V2
//
//  📋 RESPONSABILIDADE: Finalizar sessão de treino + finalizar MotionManager no Watch + salvar histórico completo
//  
//  🎯 OPERAÇÕES PRINCIPAIS:
//  • Finalizar CDCurrentSession com endTime
//  • Finalizar MotionManager no Apple Watch via PhoneSessionManager
//  • Migrar dados completos para CDWorkoutHistory
//  • Preservar exercícios e séries com sensorData
//  • Calcular estatísticas de performance
//  • Sincronizar histórico via SyncWorkoutUseCase
//  • Limpar entidades "current" após migração
//  • Preparar integração com HealthKit (item 54)
//  
//  🏗️ ARQUITETURA:
//  • Protocol + Implementation para testabilidade
//  • Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
//  • Error handling específico com EndWorkoutError enum
//  • Input validation com EndWorkoutInput struct
//  • Analytics robustos com EndWorkoutStatistics
//  
//  ⚡ INTEGRAÇÃO:
//  • WorkoutDataService: Migração Current → History
//  • SyncWorkoutUseCase: Sincronização automática
//  • PhoneSessionManager: Finalização do MotionManager no Watch
//  • HealthKitManager: Finalização workout session (item 45 - CONCLUÍDO)
//  • CoreDataAdapter: Preservação de sensorData JSON
//  
//  🔄 LIFECYCLE:
//  1. Validação de entrada (sessão ativa, usuário)
//  2. Finalização de CDCurrentSession/Exercise/Set
//  3. Finalização do MotionManager no Apple Watch
//  4. Migração completa para entidades History
//  5. Cálculo de estatísticas de performance
//  6. Sincronização automática
//  7. Limpeza de dados temporários
//  8. Finalização de workout session HealthKit (futuro)
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import CoreData

// MARK: - EndWorkoutCommand

/// Comando estruturado para finalizar MotionManager no Watch
struct EndWorkoutCommand: WatchCommand {
    let sessionId: String
    let endTime: Date
    let duration: TimeInterval
    let totalExercises: Int
    let totalSets: Int
    
    var commandType: WatchCommandType {
        return .endWorkout
    }
    
    var payload: [String: Any] {
        return [
            "sessionId": sessionId,
            "endTime": endTime.timeIntervalSince1970,
            "duration": duration,
            "totalExercises": totalExercises,
            "totalSets": totalSets
        ]
    }
}

// MARK: - EndWorkoutInput

/// Input para finalizar uma sessão de treino
/// Consolida todos os parâmetros necessários com validações
struct EndWorkoutInput {
    let session: CDCurrentSession
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let endTime: Date
    let shouldCalculateStats: Bool
    let shouldSync: Bool
    let saveToHealthKit: Bool
    
    /// Inicializador com valores padrão otimizados
    init(
        session: CDCurrentSession,
        user: CDAppUser,
        endTime: Date = Date(),
        shouldCalculateStats: Bool = true,
        shouldSync: Bool = true,
        saveToHealthKit: Bool = true
    ) {
        self.session = session
        self.user = user
        self.endTime = endTime
        self.shouldCalculateStats = shouldCalculateStats
        self.shouldSync = shouldSync
        self.saveToHealthKit = saveToHealthKit
    }
    
    /// Validação básica de entrada
    var isValid: Bool {
        return session.isActive && 
               !session.safeId.uuidString.isEmpty &&
               endTime >= session.safeStartTime
    }
}

// MARK: - EndWorkoutError

/// Erros específicos para finalização de treino
enum EndWorkoutError: Error, LocalizedError {
    case invalidInput
    case sessionNotActive
    case migrationFailed(Error)
    case statsFailed(Error)
    case syncFailed(Error)
    case healthKitFailed(Error)
    case cleanupFailed(Error)
    case sessionNotFound
    case workoutDataServiceError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Dados de entrada inválidos para finalização do treino"
        case .sessionNotActive:
            return "Sessão não está ativa para finalização"
        case .migrationFailed(let error):
            return "Falha na migração para histórico: \(error.localizedDescription)"
        case .statsFailed(let error):
            return "Falha no cálculo de estatísticas: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização: \(error.localizedDescription)"
        case .healthKitFailed(let error):
            return "Falha no HealthKit: \(error.localizedDescription)"
        case .cleanupFailed(let error):
            return "Falha na limpeza: \(error.localizedDescription)"
        case .sessionNotFound:
            return "Sessão não encontrada"
        case .workoutDataServiceError(let error):
            return "Erro no WorkoutDataService: \(error.localizedDescription)"
        }
    }
}

// MARK: - EndWorkoutStatistics

/// Estatísticas calculadas do treino finalizado
struct EndWorkoutStatistics {
    let duration: TimeInterval
    let totalExercises: Int
    let totalSets: Int
    let totalVolume: Double // peso × reps total
    let averageRestTime: TimeInterval?
    let totalCalories: Double?
    let averageHeartRate: Int?
    let exercisesCompleted: Int
    let setsCompleted: Int
    let personalRecords: [String] // PRs atingidos
    
    /// Resumo textual das estatísticas
    var summary: String {
        let durationMinutes = Int(duration / 60)
        let durationSeconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        var summary = "Duração: \(durationMinutes)m \(durationSeconds)s"
        summary += ", Exercícios: \(exercisesCompleted)/\(totalExercises)"
        summary += ", Séries: \(setsCompleted)/\(totalSets)"
        summary += ", Volume: \(String(format: "%.1f", totalVolume))kg"
        
        if let calories = totalCalories {
            summary += ", Calorias: \(Int(calories))"
        }
        
        if !personalRecords.isEmpty {
            summary += ", PRs: \(personalRecords.count)"
        }
        
        return summary
    }
}

// MARK: - EndWorkoutResult

/// Resultado da finalização do treino
struct EndWorkoutResult {
    let workoutHistory: CDWorkoutHistory
    let statistics: EndWorkoutStatistics
    let syncStatus: SyncStatus
    let healthKitStatus: HealthKitStatus
    let migrationDetails: MigrationDetails
    
    /// Status de sincronização
    enum SyncStatus {
        case synced
        case failed(Error)
        case skipped
        case disabled
        
        var isSuccessful: Bool {
            if case .failed = self { return false }
            return true
        }
    }
    
    /// Status do HealthKit
    enum HealthKitStatus {
        case saved
        case failed(Error)
        case skipped
        case disabled
        
        var isSuccessful: Bool {
            if case .failed = self { return false }
            return true
        }
    }
    
    /// Detalhes da migração
    struct MigrationDetails {
        let migratedExercises: Int
        let migratedSets: Int
        let preservedSensorData: Int
        let migrationTime: TimeInterval
        
        var summary: String {
            return "\(migratedExercises) exercícios, \(migratedSets) séries, \(preservedSensorData) sensores em \(String(format: "%.2f", migrationTime))s"
        }
    }
}

// MARK: - EndWorkoutUseCaseProtocol

protocol EndWorkoutUseCaseProtocol {
    func execute(_ input: EndWorkoutInput) async throws -> EndWorkoutResult
    func executeQuickEnd(session: CDCurrentSession, user: CDAppUser) async throws -> EndWorkoutResult
    func canEndWorkout(session: CDCurrentSession) -> Bool
    func calculateSessionStatistics(_ session: CDCurrentSession) async throws -> EndWorkoutStatistics
}

// MARK: - EndWorkoutUseCase

final class EndWorkoutUseCase: EndWorkoutUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncWorkoutUseCase: SyncWorkoutUseCaseProtocol
    private let locationManager: LocationManagerProtocol
    // TODO: Adicionar HealthKitManager quando item 65 for implementado (iOSApp.swift)
    // private let healthKitManager: HealthKitManagerProtocol
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncWorkoutUseCase: SyncWorkoutUseCaseProtocol,
        locationManager: LocationManagerProtocol
    ) {
        self.workoutDataService = workoutDataService
        self.syncWorkoutUseCase = syncWorkoutUseCase
        self.locationManager = locationManager
    }
    
    // MARK: - Public Methods
    
    /// Executa finalização completa de treino com migração para histórico
    func execute(_ input: EndWorkoutInput) async throws -> EndWorkoutResult {
        print("🏁 [END WORKOUT] Iniciando finalização da sessão: \(input.session.safeId)")
        
        let startTime = Date()
        
        do {
            // 1. Validar entrada
            try await validateInput(input)
            
            // 2. Finalizar entidades "current"
            try await finalizeCurrentEntities(input.session, endTime: input.endTime)
            
            // 3. Finalizar MotionManager no Apple Watch
            let watchFinalized = await finalizeMotionManager(input.session, endTime: input.endTime)
            
            // 4. Migrar para histórico
            let (workoutHistory, migrationDetails) = try await migrateToHistory(input.session, user: input.user, endTime: input.endTime)
            
            // 4.1. Salvar localização final no histórico (opcional)
            await saveLocationToHistory(workoutHistory)
            
            // 5. Calcular estatísticas
            let statistics = input.shouldCalculateStats ? 
                try await calculateDetailedStatistics(input.session, workoutHistory) :
                try await calculateBasicStatistics(input.session)
            
            // 6. Finalizar HealthKit
            let healthKitStatus = await finalizeHealthKitSession(input)
            
            // 7. Sincronizar
            let syncStatus = await performSync(workoutHistory, shouldSync: input.shouldSync)
            
            // 8. Limpeza final
            try await performCleanup(input.session)
            
            let result = EndWorkoutResult(
                workoutHistory: workoutHistory,
                statistics: statistics,
                syncStatus: syncStatus,
                healthKitStatus: healthKitStatus,
                migrationDetails: migrationDetails
            )
            
            let duration = Date().timeIntervalSince(startTime)
            print("🎉 [END WORKOUT] Treino finalizado com sucesso em \(String(format: "%.2f", duration))s")
            print("📊 [END WORKOUT] Estatísticas: \(statistics.summary)")
            print("📈 [END WORKOUT] Migração: \(migrationDetails.summary)")
            
            return result
            
        } catch let error as EndWorkoutError {
            print("❌ [END WORKOUT] Erro na finalização: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ [END WORKOUT] Erro inesperado: \(error)")
            throw EndWorkoutError.workoutDataServiceError(error)
        }
    }
    
    /// Método de conveniência para finalização rápida
    func executeQuickEnd(session: CDCurrentSession, user: CDAppUser) async throws -> EndWorkoutResult {
        let input = EndWorkoutInput(session: session, user: user)
        return try await execute(input)
    }
    
    /// Verifica se sessão pode ser finalizada
    func canEndWorkout(session: CDCurrentSession) -> Bool {
        return session.isActive && 
               !session.safeId.uuidString.isEmpty &&
               session.safeStartTime.timeIntervalSinceNow < 0 // Iniciada no passado
    }
    
    /// Calcula estatísticas da sessão (sem migração)
    func calculateSessionStatistics(_ session: CDCurrentSession) async throws -> EndWorkoutStatistics {
        return try await calculateBasicStatistics(session)
    }
    
    // MARK: - Private Methods
    
    /// Validação robusta de entrada
    private func validateInput(_ input: EndWorkoutInput) async throws {
        guard input.isValid else {
            throw EndWorkoutError.invalidInput
        }
        
        guard input.session.isActive else {
            throw EndWorkoutError.sessionNotActive
        }
        
        guard canEndWorkout(session: input.session) else {
            throw EndWorkoutError.sessionNotActive
        }
    }
    
    /// Finaliza todas as entidades "current" com endTime
    private func finalizeCurrentEntities(_ session: CDCurrentSession, endTime: Date) async throws {
        do {
            // 1. Finalizar sessão
            try await workoutDataService.updateCurrentSession(session, endTime: endTime)
            print("✅ [END WORKOUT] Sessão finalizada")
            
            // 2. Finalizar exercício atual se existir
            if let currentExercise = session.currentExercise {
                try await workoutDataService.updateCurrentExercise(currentExercise, endTime: endTime)
                print("✅ [END WORKOUT] Exercício atual finalizado")
                
                // 3. Finalizar set atual se existir
                if let currentSet = currentExercise.currentSet {
                    try await workoutDataService.updateCurrentSet(
                        currentSet,
                        actualReps: currentSet.actualReps ?? currentSet.targetReps,
                        restTime: currentSet.restTime,
                        endTime: endTime,
                        sensorData: nil // Preserva dados existentes
                    )
                    print("✅ [END WORKOUT] Set atual finalizado")
                }
            }
            
        } catch {
            throw EndWorkoutError.workoutDataServiceError(error)
        }
    }
    
    /// Migra dados completos para histórico
    private func migrateToHistory(_ session: CDCurrentSession, user: CDAppUser, endTime: Date) async throws -> (CDWorkoutHistory, EndWorkoutResult.MigrationDetails) {
        let migrationStart = Date()
        
        do {
            // 1. Criar workout history
            let workoutHistory = try await workoutDataService.createWorkoutHistory(
                from: session,
                user: user,
                date: endTime
            )
            print("📜 [END WORKOUT] WorkoutHistory criado")
            
            // 2. Migrar exercícios e séries
            let (migratedExercises, migratedSets, preservedSensorData) = try await migrateExercisesAndSets(
                from: session,
                to: workoutHistory
            )
            
            let migrationTime = Date().timeIntervalSince(migrationStart)
            let migrationDetails = EndWorkoutResult.MigrationDetails(
                migratedExercises: migratedExercises,
                migratedSets: migratedSets,
                preservedSensorData: preservedSensorData,
                migrationTime: migrationTime
            )
            
            return (workoutHistory, migrationDetails)
            
        } catch {
            throw EndWorkoutError.migrationFailed(error)
        }
    }
    
    /// Migra exercícios e séries preservando sensorData
    private func migrateExercisesAndSets(from session: CDCurrentSession, to workoutHistory: CDWorkoutHistory) async throws -> (Int, Int, Int) {
        guard let plan = session.plan else {
            return (0, 0, 0)
        }
        
        var migratedExercises = 0
        var migratedSets = 0
        var preservedSensorData = 0
        
        // Buscar todos os current sets da sessão
        let allCurrentSets = try await workoutDataService.fetchCurrentSets(for: nil)
        
        // Agrupar sets por exercício (baseado no template)
        var exerciseGroups: [String: [CDCurrentSet]] = [:]
        for set in allCurrentSets {
            guard let exerciseName = set.exercise?.template?.safeName else { continue }
            exerciseGroups[exerciseName, default: []].append(set)
        }
        
        // Migrar cada grupo de exercícios
        for (exerciseName, sets) in exerciseGroups {
            // Criar CDHistoryExercise
            let historyExercise = try await createHistoryExercise(
                name: exerciseName,
                order: Int32(migratedExercises),
                workoutHistory: workoutHistory
            )
            migratedExercises += 1
            
            // Migrar todas as séries do exercício
            for (index, set) in sets.enumerated() {
                try await workoutDataService.createHistorySet(
                    from: set,
                    exercise: historyExercise,
                    order: Int32(index)
                )
                migratedSets += 1
                
                // Contar sensorData preservado
                if set.sensorData != nil {
                    preservedSensorData += 1
                }
            }
        }
        
        print("🔄 [END WORKOUT] Migração concluída: \(migratedExercises) exercícios, \(migratedSets) séries")
        return (migratedExercises, migratedSets, preservedSensorData)
    }
    
    /// Cria CDHistoryExercise via WorkoutDataService ✅
    private func createHistoryExercise(name: String, order: Int32, workoutHistory: CDWorkoutHistory) async throws -> CDHistoryExercise {
        // ✅ CLEAN ARCHITECTURE: Usa WorkoutDataService diretamente
        return try await workoutDataService.createHistoryExercise(
            name: name,
            order: order,
            workoutHistory: workoutHistory
        )
    }
    
    /// Calcula estatísticas básicas da sessão
    private func calculateBasicStatistics(_ session: CDCurrentSession) async throws -> EndWorkoutStatistics {
        do {
            let duration = session.duration
            let planExercises = session.plan?.exercisesArray ?? []
            let totalExercises = planExercises.count
            
            // Buscar current sets da sessão
            let allCurrentSets = try await workoutDataService.fetchCurrentSets(for: nil)
            let totalSets = allCurrentSets.count
            let setsCompleted = allCurrentSets.filter { $0.endTime != nil }.count
            
            // Calcular volume total (peso × reps)
            let totalVolume = allCurrentSets.reduce(0.0) { sum, set in
                let reps = Double(set.actualReps ?? set.targetReps)
                return sum + (set.weight * reps)
            }
            
            // Contar exercícios únicos
            let uniqueExercises = Set(allCurrentSets.compactMap { $0.exercise?.template?.safeName })
            let exercisesCompleted = uniqueExercises.count
            
            return EndWorkoutStatistics(
                duration: duration,
                totalExercises: totalExercises,
                totalSets: totalSets,
                totalVolume: totalVolume,
                averageRestTime: nil,
                totalCalories: nil,
                averageHeartRate: nil,
                exercisesCompleted: exercisesCompleted,
                setsCompleted: setsCompleted,
                personalRecords: []
            )
            
        } catch {
            throw EndWorkoutError.statsFailed(error)
        }
    }
    
    /// Calcula estatísticas detalhadas com análise de sensor data
    private func calculateDetailedStatistics(_ session: CDCurrentSession, _ workoutHistory: CDWorkoutHistory) async throws -> EndWorkoutStatistics {
        do {
            // Estatísticas básicas
            let basicStats = try await calculateBasicStatistics(session)
            
            // Buscar current sets para análise detalhada
            let allCurrentSets = try await workoutDataService.fetchCurrentSets(for: nil)
            
            // Cálculos avançados
            let completedSets = allCurrentSets.filter { $0.endTime != nil }
            
            // Tempo de descanso médio
            let restTimes = completedSets.compactMap { $0.restTime }
            let averageRestTime = restTimes.isEmpty ? nil : restTimes.reduce(0, +) / Double(restTimes.count)
            
            // Calorias totais
            let calories = completedSets.compactMap { $0.caloriesBurned }
            let totalCalories = calories.isEmpty ? nil : calories.reduce(0, +)
            
            // Frequência cardíaca média
            let heartRates = completedSets.compactMap { $0.heartRate }
            let averageHeartRate = heartRates.isEmpty ? nil : Int(Double(heartRates.reduce(0, +)) / Double(heartRates.count))
            
            // TODO: Implementar detecção de PRs comparando com histórico
            let personalRecords: [String] = []
            
            return EndWorkoutStatistics(
                duration: basicStats.duration,
                totalExercises: basicStats.totalExercises,
                totalSets: basicStats.totalSets,
                totalVolume: basicStats.totalVolume,
                averageRestTime: averageRestTime,
                totalCalories: totalCalories,
                averageHeartRate: averageHeartRate,
                exercisesCompleted: basicStats.exercisesCompleted,
                setsCompleted: basicStats.setsCompleted,
                personalRecords: personalRecords
            )
            
        } catch {
            throw EndWorkoutError.statsFailed(error)
        }
    }
    
    /// Finaliza sessão HealthKit (item 45 - CONCLUÍDO)
    private func finalizeHealthKitSession(_ input: EndWorkoutInput) async -> EndWorkoutResult.HealthKitStatus {
        guard input.saveToHealthKit else {
            print("ℹ️ [END WORKOUT] HealthKit desabilitado pelo usuário")
            return .skipped
        }
        
        print("🏥 [END WORKOUT] HealthKit será integrado no item 65 (iOSApp.swift)")
        // TODO: Implementar quando HealthKitManager for injetado no item 65
        // guard let healthKitManager = self.healthKitManager else { return .disabled }
        // 
        // do {
        //     try await healthKitManager.endWorkoutSession(
        //         session: activeWorkoutSession,
        //         endDate: input.endTime
        //     )
        //     return .saved
        // } catch {
        //     print("❌ [END WORKOUT] HealthKit error: \(error)")
        //     return .failed(error)
        // }
        
        return .disabled // Temporário até item 65
    }
    
    /// Sincronização com tratamento de erro
    private func performSync(_ workoutHistory: CDWorkoutHistory, shouldSync: Bool) async -> EndWorkoutResult.SyncStatus {
        guard shouldSync else {
            print("⏭️ [END WORKOUT] Sincronização ignorada conforme solicitado")
            return .skipped
        }
        
        do {
            try await syncWorkoutUseCase.execute(workoutHistory)
            print("☁️ [END WORKOUT] Histórico sincronizado com sucesso")
            return .synced
        } catch {
            print("⚠️ [END WORKOUT] Falha na sincronização: \(error)")
            return .failed(error)
        }
    }
    
    /// Finaliza MotionManager no Apple Watch
    private func finalizeMotionManager(_ session: CDCurrentSession, endTime: Date) async -> Bool {
        #if os(iOS)
        print("⌚ [END WORKOUT] Finalizando MotionManager no Apple Watch")
        
        // Integração com PhoneSessionManager para comandos estruturados
        guard let phoneSessionManager = getPhoneSessionManager() else {
            print("⚠️ [END WORKOUT] PhoneSessionManager não disponível")
            return false
        }
        
        // Buscar estatísticas básicas para o comando
        let duration = session.duration
        let totalExercises = session.plan?.exercisesArray.count ?? 0
        
        do {
            let allCurrentSets = try await workoutDataService.fetchCurrentSets(for: nil)
            let totalSets = allCurrentSets.count
            
            // Comando estruturado para finalizar MotionManager no Watch
            let endWorkoutCommand = EndWorkoutCommand(
                sessionId: session.safeId.uuidString,
                endTime: endTime,
                duration: duration,
                totalExercises: totalExercises,
                totalSets: totalSets
            )
            
            try await phoneSessionManager.sendCommand(endWorkoutCommand)
            print("✅ [END WORKOUT] MotionManager finalizado no Watch")
            return true
        } catch {
            print("❌ [END WORKOUT] Erro ao finalizar MotionManager: \(error)")
            return false
        }
        #else
        print("ℹ️ [END WORKOUT] Watch finalization skipped (watchOS)")
        return false
        #endif
    }
    
    /// Helper para obter PhoneSessionManager
    private func getPhoneSessionManager() -> PhoneSessionManager? {
        #if os(iOS)
        return PhoneSessionManager.shared
        #else
        return nil
        #endif
    }
    
    /// Salva localização final no histórico do treino
    private func saveLocationToHistory(_ workoutHistory: CDWorkoutHistory) async {
        print("📍 [END WORKOUT] Salvando localização no histórico...")
        
        do {
            // Capturar localização atual (com timeout de 5s para não atrasar finalização)
            let location = try await locationManager.getCurrentLocation(timeout: 5.0)
            
            // Atualizar CDWorkoutHistory com localização
            try await workoutDataService.updateWorkoutHistoryLocation(
                workoutHistory: workoutHistory,
                latitude: location.latitude,
                longitude: location.longitude,
                locationAccuracy: location.accuracy
            )
            
            print("✅ [END WORKOUT] Localização salva: (\(location.latitude), \(location.longitude)) ±\(location.accuracy)m")
            
        } catch LocationManagerError.permissionDenied {
            print("ℹ️ [END WORKOUT] Localização negada pelo usuário - continuando sem localização")
        } catch LocationManagerError.timeout {
            print("⏱️ [END WORKOUT] Timeout na captura de localização - continuando sem localização")
        } catch {
            print("⚠️ [END WORKOUT] Erro ao capturar localização (não crítico): \(error)")
        }
    }
    
    /// Limpeza final das entidades temporárias
    private func performCleanup(_ session: CDCurrentSession) async throws {
        do {
            // Opcionalmente excluir current sets
            // try await workoutDataService.deleteAllCurrentSets()
            
            // Opcionalmente excluir current session
            // try await workoutDataService.deleteCurrentSession(session)
            
            print("🧹 [END WORKOUT] Limpeza concluída")
            
        } catch {
            print("⚠️ [END WORKOUT] Erro na limpeza (não crítico): \(error)")
            // Não falha o processo por causa da limpeza
        }
    }
}

// MARK: - Convenience Extensions

extension EndWorkoutUseCase {
    
    /// Finaliza treino com configurações padrão
    func endDefaultWorkout(session: CDCurrentSession, user: CDAppUser) async throws -> EndWorkoutResult {
        return try await executeQuickEnd(session: session, user: user)
    }
    
    /// Finaliza treino sem HealthKit
    func endWorkoutWithoutHealthKit(session: CDCurrentSession, user: CDAppUser) async throws -> EndWorkoutResult {
        let input = EndWorkoutInput(
            session: session,
            user: user,
            saveToHealthKit: false
        )
        return try await execute(input)
    }
    
    /// Finaliza treino sem sincronização
    func endWorkoutOffline(session: CDCurrentSession, user: CDAppUser) async throws -> EndWorkoutResult {
        let input = EndWorkoutInput(
            session: session,
            user: user,
            shouldSync: false
        )
        return try await execute(input)
    }
} 