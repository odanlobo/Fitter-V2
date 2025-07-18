//
//  EndExerciseUseCase.swift
//  Fitter V2
//
//  📋 RESPONSABILIDADE: Finalizar exercício individual e decidir próximo passo
//  
//  🎯 OPERAÇÕES PRINCIPAIS:
//  • Finalizar CDCurrentExercise ativo com endTime
//  • Calcular estatísticas do exercício (volume, tempo, séries)
//  • Decidir próximo passo: próximo exercício OU finalizar treino
//  • Atualizar índices de navegação na sessão
//  • Sincronizar dados via SyncWorkoutUseCase (opcional)
//  • Preparar integração com HealthKit (item 54)
//  • Notificar Apple Watch sobre status
//  
//  🏗️ ARQUITETURA:
//  • Protocol + Implementation para testabilidade
//  • Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
//  • Error handling específico com EndExerciseError enum
//  • Input validation com EndExerciseInput struct
//  • Async/await nativo para performance
//  
//  ⚡ INTEGRAÇÃO:
//  • WorkoutDataService: Operações CRUD de exercícios
//  • SyncWorkoutUseCase: Sincronização automática (opcional)
//  • ConnectivityManager: Notificação Apple Watch
//  • HealthKitManager: Sessão HealthKit é iniciada/finalizada apenas em Start/EndWorkoutUseCase.
// Aqui, apenas leitura de dados em tempo real se necessário (ex: feedback, análise).
//  
//  🔄 LIFECYCLE:
//  1. Validação de entrada (exercício ativo, sessão válida)
//  2. Finalização do CDCurrentExercise com endTime
//  3. Cálculo de estatísticas do exercício
//  4. Decisão de navegação (próximo exercício vs fim de treino)
//  5. Atualização de índices na sessão
//  6. Sincronização automática (opcional)
//  7. Notificação para Apple Watch
//  8. Finalização de workout segment HealthKit (futuro)
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import CoreData

// MARK: - EndExerciseInput

/// Input para finalizar um exercício individual
/// Consolida todos os parâmetros necessários com validações
struct EndExerciseInput {
    let exercise: CDCurrentExercise
    let session: CDCurrentSession
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let endTime: Date
    let shouldCalculateStats: Bool
    let shouldSync: Bool
    let enableHealthKit: Bool
    let autoAdvanceToNext: Bool
    
    /// Inicializador com valores padrão otimizados
    init(
        exercise: CDCurrentExercise,
        session: CDCurrentSession,
        user: CDAppUser,
        endTime: Date = Date(),
        shouldCalculateStats: Bool = true,
        shouldSync: Bool = true,
        enableHealthKit: Bool = true,
        autoAdvanceToNext: Bool = true
    ) {
        self.exercise = exercise
        self.session = session
        self.user = user
        self.endTime = endTime
        self.shouldCalculateStats = shouldCalculateStats
        self.shouldSync = shouldSync
        self.enableHealthKit = enableHealthKit
        self.autoAdvanceToNext = autoAdvanceToNext
    }
    
    /// Validação básica de entrada
    var isValid: Bool {
        return exercise.isActive && 
               session.isActive &&
               !exercise.safeId.uuidString.isEmpty &&
               endTime >= exercise.safeStartTime &&
               exercise.session == session &&
               session.user == user
    }
}

// MARK: - EndExerciseError

/// Erros específicos para finalização de exercício
enum EndExerciseError: LocalizedError {
    case exerciseNotActive
    case sessionNotActive
    case exerciseNotFound
    case sessionMismatch
    case workoutDataServiceError(Error)
    case syncError(Error)
    case healthKitError(Error)
    case watchConnectivityError
    case invalidInput
    case statisticsCalculationFailed(Error)
    case navigationError(Error)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .exerciseNotActive:
            return "Exercício não está ativo para finalização."
        case .sessionNotActive:
            return "Sessão de treino não está ativa."
        case .exerciseNotFound:
            return "Exercício não encontrado."
        case .sessionMismatch:
            return "Exercício não pertence à sessão informada."
        case .workoutDataServiceError(let error):
            return "Erro ao salvar dados do exercício: \(error.localizedDescription)"
        case .syncError(let error):
            return "Erro na sincronização: \(error.localizedDescription)"
        case .healthKitError(let error):
            return "Erro no HealthKit: \(error.localizedDescription)"
        case .watchConnectivityError:
            return "Erro na comunicação com Apple Watch."
        case .invalidInput:
            return "Dados de entrada inválidos para finalizar exercício."
        case .statisticsCalculationFailed(let error):
            return "Falha no cálculo de estatísticas: \(error.localizedDescription)"
        case .navigationError(let error):
            return "Erro na navegação: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Erro inesperado: \(error.localizedDescription)"
        }
    }
}

// MARK: - EndExerciseStatistics

/// Estatísticas calculadas do exercício finalizado
struct EndExerciseStatistics {
    let exerciseName: String
    let duration: TimeInterval
    let totalSets: Int
    let completedSets: Int
    let totalVolume: Double // peso × reps total
    let averageWeight: Double
    let averageReps: Double
    let averageRestTime: TimeInterval?
    let totalRestTime: TimeInterval
    let caloriesBurned: Double?
    let averageHeartRate: Int?
    let peakHeartRate: Int?
    let isPersonalRecord: Bool
    
    /// Resumo textual das estatísticas
    var summary: String {
        let durationMinutes = Int(duration / 60)
        let durationSeconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        var summary = "\(exerciseName): \(durationMinutes)m \(durationSeconds)s"
        summary += ", Séries: \(completedSets)/\(totalSets)"
        summary += ", Volume: \(String(format: "%.1f", totalVolume))kg"
        summary += ", Peso médio: \(String(format: "%.1f", averageWeight))kg"
        summary += ", Reps médias: \(String(format: "%.1f", averageReps))"
        
        if let calories = caloriesBurned {
            summary += ", Calorias: \(Int(calories))"
        }
        
        if isPersonalRecord {
            summary += " 🏆 PR!"
        }
        
        return summary
    }
}

// MARK: - EndExerciseResult

/// Resultado da finalização do exercício
struct EndExerciseResult {
    let finalizedExercise: CDCurrentExercise
    let statistics: EndExerciseStatistics
    let nextStep: NextStep
    let syncStatus: SyncStatus
    let healthKitStatus: HealthKitStatus
    let watchNotified: Bool
    
    /// Próximo passo na navegação
    enum NextStep {
        case nextExercise(CDExerciseTemplate, index: Int32)
        case workoutComplete
        case waitingForUserDecision
        
        var hasNextExercise: Bool {
            if case .nextExercise = self { return true }
            return false
        }
        
        var isWorkoutComplete: Bool {
            if case .workoutComplete = self { return true }
            return false
        }
    }
    
    /// Status de sincronização
    enum SyncStatus {
        case synced
        case pending
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
        case segmentEnded
        case failed(Error)
        case skipped
        case disabled
        
        var isSuccessful: Bool {
            if case .failed = self { return false }
            return true
        }
    }
}

// MARK: - EndExerciseUseCaseProtocol

/// Protocolo para finalização de exercício (testabilidade)
protocol EndExerciseUseCaseProtocol {
    func execute(_ input: EndExerciseInput) async throws -> EndExerciseResult
    func executeQuickEnd(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult
    func canEndExercise(_ exercise: CDCurrentExercise) -> Bool
    func calculateExerciseStatistics(_ exercise: CDCurrentExercise) async throws -> EndExerciseStatistics
    func determineNextStep(after exercise: CDCurrentExercise, in session: CDCurrentSession) async -> EndExerciseResult.NextStep
}

// MARK: - EndExerciseUseCase

/// Use Case para finalizar exercício individual e decidir próximo passo
/// Orquestra finalização, estatísticas e navegação dentro do fluxo granular
final class EndExerciseUseCase: EndExerciseUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncWorkoutUseCase: SyncWorkoutUseCaseProtocol?
    // TODO: Adicionar HealthKitManager quando item 65 for implementado (iOSApp.swift)
    // private let healthKitManager: HealthKitManagerProtocol
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncWorkoutUseCase: SyncWorkoutUseCaseProtocol? = nil
    ) {
        self.workoutDataService = workoutDataService
        self.syncWorkoutUseCase = syncWorkoutUseCase
    }
    
    // MARK: - Public Methods
    
    /// Executa finalização completa de exercício com navegação inteligente
    func execute(_ input: EndExerciseInput) async throws -> EndExerciseResult {
        print("🏁 [END EXERCISE] Finalizando exercício: \(input.exercise.template?.safeName ?? "Unknown")")
        
        // 1. Validação de entrada
        try await validateInput(input)
        
        // 2. Verificar se pode finalizar exercício
        guard canEndExercise(input.exercise) else {
            throw EndExerciseError.exerciseNotActive
        }
        
        // 3. Finalizar exercício
        try await finalizeExercise(input.exercise, endTime: input.endTime)
        
        // 4. Calcular estatísticas
        let statistics = input.shouldCalculateStats ? 
            try await calculateDetailedStatistics(input.exercise) :
            try await calculateBasicStatistics(input.exercise)
        
        // 5. Determinar próximo passo
        let nextStep = await determineNextStep(after: input.exercise, in: input.session)
        
        // 6. Atualizar navegação da sessão
        try await updateSessionNavigation(input.session, nextStep: nextStep)
        
        // 7. Finalizar HealthKit segment
        let healthKitStatus = await finalizeHealthKitSegment(input)
        
        // 8. Sincronização automática (opcional)
        let syncStatus = await performSync(exercise: input.exercise, shouldSync: input.shouldSync)
        
        // 9. Notificar Apple Watch
        let watchNotified = await notifyAppleWatch(exercise: input.exercise, nextStep: nextStep)
        
        let result = EndExerciseResult(
            finalizedExercise: input.exercise,
            statistics: statistics,
            nextStep: nextStep,
            syncStatus: syncStatus,
            healthKitStatus: healthKitStatus,
            watchNotified: watchNotified
        )
        
        print("✅ [END EXERCISE] Exercício finalizado com sucesso")
        print("📊 [END EXERCISE] Estatísticas: \(statistics.summary)")
        print("🧭 [END EXERCISE] Próximo passo: \(nextStepDescription(nextStep))")
        
        return result
    }
    
    /// Método de conveniência para finalização rápida
    func executeQuickEnd(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult {
        let input = EndExerciseInput(exercise: exercise, session: session, user: user)
        return try await execute(input)
    }
    
    /// Verifica se exercício pode ser finalizado
    func canEndExercise(_ exercise: CDCurrentExercise) -> Bool {
        return exercise.isActive && 
               !exercise.safeId.uuidString.isEmpty &&
               exercise.endTime == nil &&
               exercise.safeStartTime.timeIntervalSinceNow < 0 // Iniciado no passado
    }
    
    /// Calcula estatísticas do exercício (sem finalizar)
    func calculateExerciseStatistics(_ exercise: CDCurrentExercise) async throws -> EndExerciseStatistics {
        return try await calculateBasicStatistics(exercise)
    }
    
    /// Determina próximo passo na navegação
    func determineNextStep(after exercise: CDCurrentExercise, in session: CDCurrentSession) async -> EndExerciseResult.NextStep {
        guard let plan = session.plan else {
            return .workoutComplete
        }
        
        let exercises = plan.exercisesArray
        let currentIndex = Int(session.currentExerciseIndex)
        let nextIndex = currentIndex + 1
        
        // Verificar se há próximo exercício
        if nextIndex < exercises.count,
           let nextTemplate = exercises[nextIndex].template {
            return .nextExercise(nextTemplate, index: Int32(nextIndex))
        }
        
        // Último exercício - treino completo
        return .workoutComplete
    }
    
    // MARK: - Private Methods
    
    /// Validação robusta de entrada
    private func validateInput(_ input: EndExerciseInput) async throws {
        guard input.isValid else {
            throw EndExerciseError.invalidInput
        }
        
        guard input.exercise.isActive else {
            throw EndExerciseError.exerciseNotActive
        }
        
        guard input.session.isActive else {
            throw EndExerciseError.sessionNotActive
        }
        
        guard input.exercise.session == input.session else {
            throw EndExerciseError.sessionMismatch
        }
    }
    
    /// Finaliza exercício com endTime
    private func finalizeExercise(_ exercise: CDCurrentExercise, endTime: Date) async throws {
        do {
            try await workoutDataService.updateCurrentExercise(exercise, endTime: endTime)
            print("✅ [END EXERCISE] Exercício finalizado: \(exercise.template?.safeName ?? "Unknown")")
        } catch {
            throw EndExerciseError.workoutDataServiceError(error)
        }
    }
    
    /// Calcula estatísticas básicas do exercício
    private func calculateBasicStatistics(_ exercise: CDCurrentExercise) async throws -> EndExerciseStatistics {
        do {
            let exerciseName = exercise.template?.safeName ?? "Exercício Desconhecido"
            let duration = exercise.duration
            
            // Buscar current sets do exercício
            let allCurrentSets = try await workoutDataService.fetchCurrentSets(for: exercise)
            let totalSets = allCurrentSets.count
            let completedSets = allCurrentSets.filter { $0.endTime != nil }.count
            
            // Calcular métricas básicas
            let totalVolume = allCurrentSets.reduce(0.0) { sum, set in
                let reps = Double(set.actualReps ?? set.targetReps)
                return sum + (set.weight * reps)
            }
            
            let weights = allCurrentSets.map { $0.weight }
            let averageWeight = weights.isEmpty ? 0.0 : weights.reduce(0, +) / Double(weights.count)
            
            let reps = allCurrentSets.map { Double($0.actualReps ?? $0.targetReps) }
            let averageReps = reps.isEmpty ? 0.0 : reps.reduce(0, +) / Double(reps.count)
            
            // Tempo de descanso
            let restTimes = allCurrentSets.compactMap { $0.restTime }
            let totalRestTime = restTimes.reduce(0, +)
            let averageRestTime = restTimes.isEmpty ? nil : totalRestTime / Double(restTimes.count)
            
            // Métricas de saúde
            let calories = allCurrentSets.compactMap { $0.caloriesBurned }
            let totalCalories = calories.isEmpty ? nil : calories.reduce(0, +)
            
            let heartRates = allCurrentSets.compactMap { $0.heartRate }
            let averageHeartRate = heartRates.isEmpty ? nil : Int(Double(heartRates.reduce(0, +)) / Double(heartRates.count))
            let peakHeartRate = heartRates.isEmpty ? nil : heartRates.max()
            
            // TODO: Implementar detecção de PR comparando com histórico
            let isPersonalRecord = false
            
            return EndExerciseStatistics(
                exerciseName: exerciseName,
                duration: duration,
                totalSets: totalSets,
                completedSets: completedSets,
                totalVolume: totalVolume,
                averageWeight: averageWeight,
                averageReps: averageReps,
                averageRestTime: averageRestTime,
                totalRestTime: totalRestTime,
                caloriesBurned: totalCalories,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate,
                isPersonalRecord: isPersonalRecord
            )
            
        } catch {
            throw EndExerciseError.statisticsCalculationFailed(error)
        }
    }
    
    /// Calcula estatísticas detalhadas com análise de sensor data
    private func calculateDetailedStatistics(_ exercise: CDCurrentExercise) async throws -> EndExerciseStatistics {
        // Por agora, usar estatísticas básicas
        // TODO: Adicionar análise avançada de sensorData quando disponível
        return try await calculateBasicStatistics(exercise)
    }
    
    /// Atualiza navegação da sessão baseada no próximo passo
    private func updateSessionNavigation(_ session: CDCurrentSession, nextStep: EndExerciseResult.NextStep) async throws {
        do {
            switch nextStep {
            case .nextExercise(_, let index):
                session.currentExerciseIndex = index
                print("📍 [END EXERCISE] Índice atualizado para: \(index)")
                
            case .workoutComplete:
                // Manter índice atual - EndWorkoutUseCase decidirá o que fazer
                print("🏁 [END EXERCISE] Treino pronto para finalização")
                
            case .waitingForUserDecision:
                // Não alterar índice - usuário decidirá
                print("⏸️ [END EXERCISE] Aguardando decisão do usuário")
            }
            
            try await workoutDataService.coreDataService.save()
            
        } catch {
            throw EndExerciseError.navigationError(error)
        }
    }
    
    /// Finaliza segment HealthKit (preparação para item 54)
    private func finalizeHealthKitSegment(_ input: EndExerciseInput) async -> EndExerciseResult.HealthKitStatus {
        guard input.enableHealthKit else {
            print("ℹ️ [END EXERCISE] HealthKit desabilitado pelo usuário")
            return .skipped
        }
        
        print("🏥 [END EXERCISE] HealthKit será integrado no item 65 (iOSApp.swift)")
        // TODO: Implementar quando HealthKitManager for injetado no item 65
        
        return .disabled // Temporário até item 65
    }
    
    /// Sincronização com tratamento de erro
    private func performSync(exercise: CDCurrentExercise, shouldSync: Bool) async -> EndExerciseResult.SyncStatus {
        guard shouldSync, let syncUseCase = syncWorkoutUseCase else {
            print("⏭️ [END EXERCISE] Sincronização desabilitada")
            return .disabled
        }
        
        do {
            try await syncUseCase.execute(exercise)
            print("☁️ [END EXERCISE] Exercício sincronizado")
            return .synced
        } catch {
            print("⚠️ [END EXERCISE] Falha na sincronização: \(error)")
            return .failed(error)
        }
    }
    
    /// Notificação para Apple Watch
    private func notifyAppleWatch(exercise: CDCurrentExercise, nextStep: EndExerciseResult.NextStep) async -> Bool {
        #if os(iOS)
        do {
            let connectivityManager = ConnectivityManager.shared
            
            var exerciseContext: [String: Any] = [
                "type": "exerciseEnded",
                "exerciseId": exercise.safeId.uuidString,
                "exerciseName": exercise.template?.safeName ?? "",
                "endTime": exercise.endTime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                "duration": exercise.duration
            ]
            
            // Adicionar informação do próximo passo
            switch nextStep {
            case .nextExercise(let template, let index):
                exerciseContext["hasNext"] = true
                exerciseContext["nextExerciseName"] = template.safeName
                exerciseContext["nextExerciseIndex"] = index
                
            case .workoutComplete:
                exerciseContext["hasNext"] = false
                exerciseContext["workoutComplete"] = true
                
            case .waitingForUserDecision:
                exerciseContext["hasNext"] = false
                exerciseContext["waitingDecision"] = true
            }
            
            await connectivityManager.sendMessage(exerciseContext, replyHandler: nil)
            print("📱➡️⌚ Finalização de exercício notificada ao Watch")
            return true
            
        } catch {
            print("❌ [END EXERCISE] Erro ao notificar Watch: \(error)")
            return false
        }
        #else
        print("ℹ️ [END EXERCISE] Notificação Watch apenas disponível no iOS")
        return false
        #endif
    }
    
    /// Descrição textual do próximo passo
    private func nextStepDescription(_ nextStep: EndExerciseResult.NextStep) -> String {
        switch nextStep {
        case .nextExercise(let template, let index):
            return "Próximo exercício: \(template.safeName) (índice \(index))"
        case .workoutComplete:
            return "Treino completo - pronto para finalização"
        case .waitingForUserDecision:
            return "Aguardando decisão do usuário"
        }
    }
}

// MARK: - Convenience Extensions

extension EndExerciseUseCase {
    
    /// Finaliza exercício com configurações padrão
    func endDefaultExercise(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult {
        return try await executeQuickEnd(exercise: exercise, session: session, user: user)
    }
    
    /// Finaliza exercício sem sincronização
    func endExerciseOffline(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult {
        let input = EndExerciseInput(
            exercise: exercise,
            session: session,
            user: user,
            shouldSync: false
        )
        return try await execute(input)
    }
    
    /// Finaliza exercício sem HealthKit
    func endExerciseWithoutHealthKit(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult {
        let input = EndExerciseInput(
            exercise: exercise,
            session: session,
            user: user,
            enableHealthKit: false
        )
        return try await execute(input)
    }
    
    /// Finaliza exercício sem avançar automaticamente
    func endExerciseManual(exercise: CDCurrentExercise, session: CDCurrentSession, user: CDAppUser) async throws -> EndExerciseResult {
        let input = EndExerciseInput(
            exercise: exercise,
            session: session,
            user: user,
            autoAdvanceToNext: false
        )
        return try await execute(input)
    }
}

// MARK: - Navigation Helpers

extension EndExerciseUseCase {
    
    /// Verifica se há próximo exercício após o atual
    func hasNextExercise(after exercise: CDCurrentExercise, in session: CDCurrentSession) async -> Bool {
        let nextStep = await determineNextStep(after: exercise, in: session)
        return nextStep.hasNextExercise
    }
    
    /// Conta exercícios restantes após o atual
    func remainingExercisesCount(after exercise: CDCurrentExercise, in session: CDCurrentSession) -> Int {
        guard let plan = session.plan else { return 0 }
        
        let totalExercises = plan.exercisesArray.count
        let currentIndex = Int(session.currentExerciseIndex)
        
        return max(0, totalExercises - currentIndex - 1)
    }
    
    /// Obtém lista de exercícios restantes após o atual
    func getRemainingExercises(after exercise: CDCurrentExercise, in session: CDCurrentSession) -> [CDExerciseTemplate] {
        guard let plan = session.plan else { return [] }
        
        let exercises = plan.exercisesArray
        let currentIndex = Int(session.currentExerciseIndex + 1)
        
        guard currentIndex < exercises.count else { return [] }
        
        return Array(exercises[currentIndex...]).compactMap { $0.template }
    }
} 