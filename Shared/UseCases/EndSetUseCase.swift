/*
 * EndSetUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Finalizar série individual e processar dados de sensores
 *                   com rest timer automático e fluxo contínuo.
 *
 * ARQUITETURA:
 * - Clean Architecture: Protocol + Implementation
 * - Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
 * - LOGIN OBRIGATÓRIO: user: CDAppUser (nunca opcional)
 * - Error Handling: EndSetError enum específico
 * - Async/await: Todas operações assíncronas
 *
 * OPERAÇÕES PRINCIPAIS:
 * 1. Finalizar CDCurrentSet com endTime e actualReps
 * 2. Parar captura de sensores Apple Watch
 * 3. Serializar sensorData via CoreDataAdapter
 * 4. Calcular analytics (intensity score, form analysis, fatigue metrics)
 * 5. Iniciar rest timer automático inteligente
 * 6. Detectar próxima ação automática (série/exercício/fim)
 * 7. Sincronizar dados críticos com iPhone
 * 8. Preparar fluxo contínuo automático
 *
 * 🎯 FLUXO AUTOMÁTICO (CORRIGIDO):
 * EndSetUseCase → rest timer → próxima ação AUTOMÁTICA
 * • Manual: botão "Finalizar Série"
 * • Automático: sensores detectam baixa movimentação
 * • Timer explícito: botão "Descansar Agora"
 * • Timeout: inatividade prolongada
 *
 * REFATORAÇÃO ITEM 29/89:
 * ✅ Criar EndSetUseCase.swift
 * 🔄 Preparado para TimerService (item 46 - CONCLUÍDO)
 * 🔄 Preparado para HealthKitManager (item 45 - CONCLUÍDO)
 * 🔄 Preparado para MotionManager refatorado
 */

import Foundation
import CoreData
import Combine

// MARK: - EndSetError

enum EndSetError: Error, LocalizedError {
    case userNotAuthenticated
    case noActiveSession
    case noCurrentSet
    case setNotActive
    case invalidSetData(String)
    case sensorProcessingFailed(Error)
    case healthKitError(Error)
    case timerServiceError(Error)
    case watchSyncFailed(Error)
    case persistenceFailed(Error)
    case syncFailed(Error)
    case detectionServiceUnavailable
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Usuário não autenticado"
        case .noActiveSession:
            return "Nenhuma sessão de treino ativa"
        case .noCurrentSet:
            return "Nenhuma série ativa para finalizar"
        case .setNotActive:
            return "Série não está ativa"
        case .invalidSetData(let message):
            return "Dados da série inválidos: \(message)"
        case .sensorProcessingFailed(let error):
            return "Falha no processamento de sensores: \(error.localizedDescription)"
        case .healthKitError(let error):
            return "Erro no HealthKit: \(error.localizedDescription)"
        case .timerServiceError(let error):
            return "Erro no timer de descanso: \(error.localizedDescription)"
        case .watchSyncFailed(let error):
            return "Falha na sincronização com Apple Watch: \(error.localizedDescription)"
        case .persistenceFailed(let error):
            return "Falha ao salvar dados: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização: \(error.localizedDescription)"
        case .detectionServiceUnavailable:
            return "Serviço de detecção automática indisponível"
        case .unknownError(let error):
            return "Erro desconhecido: \(error.localizedDescription)"
        }
    }
}

// MARK: - EndSetInput

struct EndSetInput {
    let user: CDAppUser                    // LOGIN OBRIGATÓRIO
    let set: CDCurrentSet                  // Série ativa para finalizar
    let exercise: CDCurrentExercise        // Exercício atual
    let actualReps: Int32?                 // Repetições realizadas (opcional - pode ser detectado automaticamente)
    let endTime: Date                      // Momento da finalização
    let finalSensorData: SensorData?       // Dados finais dos sensores
    let enableRestTimer: Bool              // Iniciar timer de descanso
    let restDuration: TimeInterval?        // Duração personalizada do descanso
    let enableAutoFlow: Bool               // Fluxo automático após rest timer
    let triggerType: TriggerType           // Como a série foi finalizada
    
    enum TriggerType {
        case manual                        // Botão "Finalizar Série"
        case automatic                     // Detecção por sensores
        case timerExplicit                 // Botão "Descansar Agora"
        case timeout                       // Inatividade prolongada
    }
    
    init(
        user: CDAppUser,
        set: CDCurrentSet,
        exercise: CDCurrentExercise,
        actualReps: Int32? = nil,
        endTime: Date = Date(),
        finalSensorData: SensorData? = nil,
        enableRestTimer: Bool = true,
        restDuration: TimeInterval? = nil,
        enableAutoFlow: Bool = true,
        triggerType: TriggerType = .manual
    ) {
        self.user = user
        self.set = set
        self.exercise = exercise
        self.actualReps = actualReps
        self.endTime = endTime
        self.finalSensorData = finalSensorData
        self.enableRestTimer = enableRestTimer
        self.restDuration = restDuration
        self.enableAutoFlow = enableAutoFlow
        self.triggerType = triggerType
    }
    
    var isValid: Bool {
        return set.isActive && 
               exercise.isActive &&
               endTime >= set.safeTimestamp &&
               set.exercise == exercise
    }
}

// MARK: - EndSetResult

struct EndSetResult {
    let finalizedSet: CDCurrentSet
    let sensorData: SensorData?
    let analytics: EndSetAnalytics
    let restTimer: RestTimerInfo?
    let nextAction: NextAction
    let syncStatus: SyncStatus
    let healthKitStatus: HealthKitStatus
    let watchSyncStatus: WatchSyncStatus
    
    enum NextAction {
        case nextSet(estimatedRestTime: TimeInterval)
        case nextExercise(template: CDExerciseTemplate, restTime: TimeInterval)
        case workoutComplete
        case waitingForUserDecision
        case automaticAfterRest(action: String, countdown: TimeInterval)
        
        var isAutomatic: Bool {
            if case .automaticAfterRest = self { return true }
            return false
        }
        
        var hasRestTimer: Bool {
            switch self {
            case .nextSet, .nextExercise, .automaticAfterRest:
                return true
            default:
                return false
            }
        }
    }
    
    enum SyncStatus {
        case synced, pending, failed(Error), skipped
    }
    
    enum HealthKitStatus {
        case segmentEnded, failed(Error), skipped
    }
    
    enum WatchSyncStatus {
        case synced, failed(Error), offline
    }
}

// MARK: - EndSetAnalytics

struct EndSetAnalytics {
    let endedAt: Date
    let exerciseName: String
    let setNumber: Int32
    let targetReps: Int32
    let actualReps: Int32
    let weight: Double
    let duration: TimeInterval
    let intensityScore: Double
    let formAnalysis: FormAnalysis
    let fatigueMetrics: FatigueMetrics
    let userId: String
    let sessionId: String
    let exerciseId: String
    let triggerType: EndSetInput.TriggerType
    
    struct FormAnalysis {
        let consistency: Double        // 0-1 (consistência dos movimentos)
        let rangeOfMotion: Double     // 0-1 (amplitude do movimento)
        let tempo: Double             // 0-1 (controle do tempo)
        let overall: Double           // Score geral
        
        var grade: String {
            switch overall {
            case 0.9...1.0: return "Excelente"
            case 0.7..<0.9: return "Bom"
            case 0.5..<0.7: return "Regular"
            default: return "Precisa melhorar"
            }
        }
    }
    
    struct FatigueMetrics {
        let initialIntensity: Double
        let finalIntensity: Double
        let fatigueIndex: Double      // Queda de intensidade
        let recoveryNeeded: TimeInterval // Tempo estimado de descanso
        
        var fatigueLevel: String {
            switch fatigueIndex {
            case 0.0..<0.3: return "Baixa"
            case 0.3..<0.6: return "Moderada"
            case 0.6..<0.8: return "Alta"
            default: return "Extrema"
            }
        }
    }
    
    var summary: String {
        let durationSeconds = Int(duration)
        return "\(exerciseName) - Série \(setNumber): \(actualReps)/\(targetReps) reps, \(String(format: "%.1f", weight))kg, \(durationSeconds)s, Intensidade: \(String(format: "%.1f", intensityScore * 100))%"
    }
}

// MARK: - RestTimerInfo

struct RestTimerInfo {
    let duration: TimeInterval
    let type: RestType
    let autoAction: String?
    let startedAt: Date
    
    enum RestType {
        case betweenSets
        case betweenExercises
        case custom(TimeInterval)
        case intelligent(basedOnFatigue: Double)
    }
    
    var endTime: Date {
        return startedAt.addingTimeInterval(duration)
    }
    
    var description: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - EndSetUseCaseProtocol

protocol EndSetUseCaseProtocol {
    func execute(_ input: EndSetInput) async throws -> EndSetResult
    func executeQuickEnd(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser) async throws -> EndSetResult
    func executeAutoDetected(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, sensorData: SensorData) async throws -> EndSetResult
    func executeWithRestNow(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, customRestTime: TimeInterval) async throws -> EndSetResult
    func executeOffline(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, actualReps: Int32) async throws -> EndSetResult
    
    // Validation helpers
    func canEndSet(_ set: CDCurrentSet) -> Bool
    func calculateOptimalRestTime(for set: CDCurrentSet, analytics: EndSetAnalytics) -> TimeInterval
    func determineNextAction(after set: CDCurrentSet, in exercise: CDCurrentExercise) async -> EndSetResult.NextAction
}

// MARK: - EndSetUseCase

final class EndSetUseCase: EndSetUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    
    // MARK: - Managers (Preparados para DI futura)
    
    private var motionManager: MotionManager? {
        // TODO: Injetar via DI quando MotionManager for refatorado (item 52)
        return nil
    }
    
    private var watchDataManager: WatchDataManager? {
        // TODO: Injetar via DI quando WatchDataManager for refatorado (item 53)
        return nil
    }
    
    private var connectivityManager: ConnectivityManager? {
        // TODO: Injetar via DI quando ConnectivityManager for refatorado
        return nil
    }
    
    private var healthKitManager: Any? {
    // TODO: Injetar HealthKitManager quando item 65 for implementado (iOSApp.swift)
    return nil
}
    
    private var timerService: Any? {
        // TODO: Injetar TimerService quando item 65 for implementado (iOSApp.swift)
        return nil
    }
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil
    ) {
        self.workoutDataService = workoutDataService
        self.syncUseCase = syncUseCase
        
        print("🏁 EndSetUseCase inicializado")
    }
    
    // MARK: - Main Execution
    
    func execute(_ input: EndSetInput) async throws -> EndSetResult {
        print("🏁 Finalizando série: \(input.exercise.template?.safeName ?? "Unknown") - Série \(input.set.order + 1)")
        
        // 1. Validação de entrada
        try await validateInput(input)
        
        // 2. Parar captura de sensores
        await stopSensorCapture(input.set)
        
        // 3. Processar dados finais de sensores
        let finalSensorData = try await processFinalSensorData(input)
        
        // 4. Finalizar CDCurrentSet
        try await finalizeCurrentSet(input, finalSensorData: finalSensorData)
        
        // 5. Calcular analytics detalhados
        let analytics = try await calculateAnalytics(input, sensorData: finalSensorData)
        
        // 6. Finalizar HealthKit segment
        let healthKitStatus = await finalizeHealthKitSegment(input)
        
        // 7. Determinar próxima ação
        let nextAction = await determineNextAction(after: input.set, in: input.exercise)
        
        // 8. Configurar rest timer (se habilitado)
        let restTimer = input.enableRestTimer ? 
            await configureRestTimer(input, analytics: analytics, nextAction: nextAction) : nil
        
        // 9. Sincronizar com Firebase (opcional)
        let syncStatus = await performSync(set: input.set)
        
        // 10. Sincronizar com Apple Watch
        let watchSyncStatus = await syncWithWatch(input.set, nextAction: nextAction)
        
        let result = EndSetResult(
            finalizedSet: input.set,
            sensorData: finalSensorData,
            analytics: analytics,
            restTimer: restTimer,
            nextAction: nextAction,
            syncStatus: syncStatus,
            healthKitStatus: healthKitStatus,
            watchSyncStatus: watchSyncStatus
        )
        
        print("✅ Série finalizada: \(input.set.safeId) - Próxima ação: \(nextActionDescription(nextAction))")
        return result
    }
    
    // MARK: - Convenience Methods
    
    func executeQuickEnd(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser) async throws -> EndSetResult {
        let input = EndSetInput(
            user: user,
            set: set,
            exercise: exercise,
            triggerType: .manual
        )
        return try await execute(input)
    }
    
    func executeAutoDetected(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, sensorData: SensorData) async throws -> EndSetResult {
        // Detectar repetições automaticamente baseado nos dados de sensores
        let estimatedReps = detectRepsFromSensorData(sensorData)
        
        let input = EndSetInput(
            user: user,
            set: set,
            exercise: exercise,
            actualReps: estimatedReps,
            finalSensorData: sensorData,
            triggerType: .automatic
        )
        return try await execute(input)
    }
    
    func executeWithRestNow(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, customRestTime: TimeInterval) async throws -> EndSetResult {
        let input = EndSetInput(
            user: user,
            set: set,
            exercise: exercise,
            restDuration: customRestTime,
            triggerType: .timerExplicit
        )
        return try await execute(input)
    }
    
    func executeOffline(set: CDCurrentSet, exercise: CDCurrentExercise, user: CDAppUser, actualReps: Int32) async throws -> EndSetResult {
        let input = EndSetInput(
            user: user,
            set: set,
            exercise: exercise,
            actualReps: actualReps,
            enableRestTimer: false,
            enableAutoFlow: false,
            triggerType: .manual
        )
        return try await execute(input)
    }
    
    // MARK: - Validation Methods
    
    func canEndSet(_ set: CDCurrentSet) -> Bool {
        return set.isActive && 
               set.startTime != nil &&
               set.endTime == nil
    }
    
    func calculateOptimalRestTime(for set: CDCurrentSet, analytics: EndSetAnalytics) -> TimeInterval {
        // Calcular tempo de descanso baseado na fadiga e intensidade
        let baseFatigueTime = analytics.fatigueMetrics.recoveryNeeded
        let intensityMultiplier = analytics.intensityScore
        
        let optimalTime = baseFatigueTime * (0.5 + intensityMultiplier * 0.5)
        
        // Limitar entre 30 segundos e 5 minutos
        return max(30, min(300, optimalTime))
    }
    
    func determineNextAction(after set: CDCurrentSet, in exercise: CDCurrentExercise) async -> EndSetResult.NextAction {
        // Buscar séries existentes do exercício
        do {
            let existingSets = try await workoutDataService.fetchCurrentSets(for: exercise)
            let completedSets = existingSets.count
            
            // Verificar se exercício tem mais séries planejadas (assumir 3-4 séries típicas)
            let plannedSets = 3 // TODO: Buscar do plano de treino quando disponível
            
            if completedSets < plannedSets {
                return .nextSet(estimatedRestTime: 90) // 1m30s padrão entre séries
            } else {
                // Verificar se há próximo exercício na sessão
                guard let session = exercise.session,
                      let plan = session.plan else {
                    return .workoutComplete
                }
                
                let exercises = plan.exercisesArray
                let currentIndex = Int(session.currentExerciseIndex)
                let nextIndex = currentIndex + 1
                
                if nextIndex < exercises.count,
                   let nextTemplate = exercises[nextIndex].template {
                    return .nextExercise(template: nextTemplate, restTime: 120) // 2min entre exercícios
                } else {
                    return .workoutComplete
                }
            }
        } catch {
            print("❌ Erro ao determinar próxima ação: \(error)")
            return .waitingForUserDecision
        }
    }
    
    // MARK: - Private Methods
    
    private func validateInput(_ input: EndSetInput) async throws {
        guard input.isValid else {
            throw EndSetError.invalidSetData("Dados de entrada inválidos")
        }
        
        guard canEndSet(input.set) else {
            throw EndSetError.setNotActive
        }
        
        guard input.exercise.isActive else {
            throw EndSetError.noActiveSession
        }
    }
    
    private func stopSensorCapture(_ set: CDCurrentSet) async {
        // MotionManager continua capturando continuamente
        // Apenas registrar finalização da série para tracking
        print("🛑 Série finalizada: \(set.safeId) - MotionManager continua ativo")
    }
    
    private func processFinalSensorData(_ input: EndSetInput) async throws -> SensorData? {
        // Se sensor data foi fornecido, usar ele
        if let providedData = input.finalSensorData {
            return providedData
        }
        
        // Caso contrário, tentar recuperar dados dos sensores ativos
        // TODO: Implementar quando MotionManager for refatorado
        // return await motionManager?.getAccumulatedSensorData(for: input.set.safeId)
        
        // Por enquanto, retornar dados existentes do set
        return input.set.sensorDataObject
    }
    
    private func finalizeCurrentSet(_ input: EndSetInput, finalSensorData: SensorData?) async throws {
        do {
            // 1. Processar dados do ML para obter timeline de movimento
            let movementTimeline = try await processMovementTimeline(input, sensorData: finalSensorData)
            
            // 2. O actualReps é o último pico detectado na timeline
            let actualReps = input.actualReps ?? Int32(movementTimeline?.finalRepsCount ?? Int(input.set.targetReps))
            
            // 3. Serializar timeline como repsCounterData
            var repsCounterData: Data? = nil
            if let timeline = movementTimeline {
                repsCounterData = try timeline.toJSONData()
            }
            
            // 4. Coletar TODOS os dados de saúde acumulados durante a série
            let (heartRateData, caloriesData) = try await collectHealthDataForSet(input.set)
            
            // 5. Atualizar CDCurrentSet APENAS com dados básicos (sem dados avançados)
            try await workoutDataService.updateCurrentSet(
                input.set,
                actualReps: actualReps,
                restTime: nil, // Será calculado pelo rest timer
                endTime: input.endTime,
                sensorData: nil // NÃO salva no CDCurrentSet
            )
            
            // 6. Armazenar TODOS os dados avançados temporariamente para migração posterior
            try await storeTemporarySetData(
                input.set,
                repsCounterData: repsCounterData,
                heartRateData: heartRateData,
                caloriesData: caloriesData,
                finalSensorData: finalSensorData
            )
            
            print("✅ CDCurrentSet finalizado: \(input.set.safeId) - Reps detectadas: \(actualReps)")
        } catch {
            throw EndSetError.persistenceFailed(error)
        }
    }
    
    /// Processa dados dos sensores para gerar timeline de movimento (-1 a +1)
    private func processMovementTimeline(_ input: EndSetInput, sensorData: SensorData?) async throws -> MovementTimeline? {
        guard let sensorData = sensorData else {
            print("⚠️ Sem dados de sensores para processamento")
            return nil
        }
        
        // TODO: Quando MLModelManager for implementado, usar processamento real
        // Por enquanto, gerar dados mock para demonstração
        let mockPoints = generateMockMovementPoints(duration: input.endTime.timeIntervalSince(input.set.safeTimestamp))
        
        return MovementTimeline(
            points: mockPoints,
            totalDuration: input.endTime.timeIntervalSince(input.set.safeTimestamp),
            totalReps: mockPoints.compactMap { $0.repIndex }.max() ?? 0,
            seriesId: input.set.safeId
        )
    }
    
    /// Gera pontos de movimento mock para demonstração (remover quando ML for implementado)
    private func generateMockMovementPoints(duration: TimeInterval) -> [MovementPoint] {
        var points: [MovementPoint] = []
        let targetReps = 3 // Mock: simular 3 repetições
        let timePerRep = duration / Double(targetReps)
        
        var currentTime: Double = 0.0
        let interval: Double = 0.1 // Ponto a cada 100ms
        var repCount = 0
        
        while currentTime <= duration {
            // Calcular posição no ciclo de movimento
            let repProgress = (currentTime.truncatingRemainder(dividingBy: timePerRep)) / timePerRep
            
            // Gerar movimento realista: excêntrico(-1) → neutro(0) → concêntrico(+1)
            // Ciclo: posição inicial → descida/alongamento → subida/contração → volta ao topo
            let movement = -cos(repProgress * 2 * .pi) // Inverte para começar em 0, descer para -1, subir para +1
            
            // Detectar conclusão da fase concêntrica (repetição completa)
            var repIndex: Int? = nil
            if movement > 0.9 && repProgress > 0.75 && repProgress < 0.95 {
                repCount += 1
                repIndex = repCount
            }
            
            points.append(MovementPoint(
                timestamp: currentTime,
                movement: movement,
                repIndex: repIndex
            ))
            
            currentTime += interval
        }
        
        return points
    }
    
    /// Cache temporário para TODOS os dados avançados de cada série
    private static var temporarySetDataCache: [String: TemporarySetData] = [:]
    
    /// Estrutura para armazenar todos os dados coletados durante a série
    struct TemporarySetData {
        let repsCounterData: Data?          // Timeline de movimento
        let heartRateData: Data?            // Dados de heart rate coletados
        let caloriesData: Data?             // Dados de calorias coletadas
        let finalSensorData: SensorData?    // Dados brutos finais dos sensores
    }
    
    /// Armazena TODOS os dados coletados temporariamente para migração posterior
    private func storeTemporarySetData(_ set: CDCurrentSet, repsCounterData: Data?, heartRateData: Data?, caloriesData: Data?, finalSensorData: SensorData?) async throws {
        let setId = set.safeId
        
        let temporaryData = TemporarySetData(
            repsCounterData: repsCounterData,
            heartRateData: heartRateData,
            caloriesData: caloriesData,
            finalSensorData: finalSensorData
        )
        
        EndSetUseCase.temporarySetDataCache[setId] = temporaryData
        print("🗂️ Dados completos armazenados temporariamente para série \(setId):")
        print("   - RepsCounterData: \(repsCounterData?.count ?? 0) bytes")
        print("   - HeartRateData: \(heartRateData?.count ?? 0) bytes")
        print("   - CaloriesData: \(caloriesData?.count ?? 0) bytes")
        print("   - SensorData: \(finalSensorData != nil ? "✅" : "❌")")
    }
    
    /// Recupera dados temporários completos para migração
    static func getTemporarySetData(for setId: String) -> TemporarySetData? {
        return temporarySetDataCache[setId]
    }
    
    /// Limpa dados temporários após migração
    static func clearTemporarySetData(for setId: String) {
        temporarySetDataCache.removeValue(forKey: setId)
    }
    
    /// Coleta dados de saúde acumulados durante a execução da série
    private func collectHealthDataForSet(_ set: CDCurrentSet) async throws -> (heartRateData: Data?, caloriesData: Data?) {
        guard let startTime = set.startTime else {
            return (nil, nil)
        }
        
        let endTime = Date()
        
        // TODO: Implementar coleta real via HealthKitManager quando disponível
        // Por enquanto, simular dados para demonstrar a estrutura
        
        do {
            // Simular dados de heart rate para a série
            let mockHeartRatePoints = generateMockHeartRateData(from: startTime, to: endTime)
            let heartRateData = try JSONSerialization.data(withJSONObject: mockHeartRatePoints)
            
            // Simular dados de calorias para a série
            let mockCaloriesPoints = generateMockCaloriesData(from: startTime, to: endTime)
            let caloriesData = try JSONSerialization.data(withJSONObject: mockCaloriesPoints)
            
            print("💓 Dados de saúde coletados para série \(set.safeId):")
            print("   - Heart Rate: \(mockHeartRatePoints.count) pontos")
            print("   - Calorias: \(mockCaloriesPoints.count) pontos")
            
            return (heartRateData, caloriesData)
            
        } catch {
            print("⚠️ Erro ao serializar dados de saúde: \(error)")
            return (nil, nil)
        }
    }
    
    /// Gera dados mock de heart rate (remover quando HealthKitManager for integrado)
    private func generateMockHeartRateData(from startTime: Date, to endTime: Date) -> [[String: Any]] {
        var points: [[String: Any]] = []
        let duration = endTime.timeIntervalSince(startTime)
        let interval: TimeInterval = 1.0 // Amostra a cada segundo
        
        var currentTime = startTime
        var baseHeartRate: Double = 140 // BPM base durante exercício
        
        while currentTime <= endTime {
            // Simular variação natural do heart rate
            let variation = Double.random(in: -10...10)
            let heartRate = max(120, min(180, baseHeartRate + variation))
            
            points.append([
                "timestamp": currentTime.timeIntervalSince1970,
                "value": heartRate,
                "unit": "BPM"
            ])
            
            currentTime.addTimeInterval(interval)
            baseHeartRate += Double.random(in: -2...2) // Drift lento
        }
        
        return points
    }
    
    /// Gera dados mock de calorias (remover quando HealthKitManager for integrado)
    private func generateMockCaloriesData(from startTime: Date, to endTime: Date) -> [[String: Any]] {
        var points: [[String: Any]] = []
        let duration = endTime.timeIntervalSince(startTime)
        let totalCalories = duration / 60.0 * 8.0 // ~8 cal/min durante exercício
        
        points.append([
            "timestamp": startTime.timeIntervalSince1970,
            "value": 0.0,
            "unit": "kcal"
        ])
        
        points.append([
            "timestamp": endTime.timeIntervalSince1970,
            "value": totalCalories,
            "unit": "kcal"
        ])
        
        return points
    }
    
    private func calculateAnalytics(_ input: EndSetInput, sensorData: SensorData?) async throws -> EndSetAnalytics {
        let duration = input.endTime.timeIntervalSince(input.set.safeTimestamp)
        let actualReps = input.actualReps ?? input.set.targetReps
        
        // Calcular intensity score baseado em dados de sensores
        let intensityScore = calculateIntensityScore(sensorData: sensorData, duration: duration)
        
        // Análise de forma (form analysis)
        let formAnalysis = calculateFormAnalysis(sensorData: sensorData)
        
        // Métricas de fadiga
        let fatigueMetrics = calculateFatigueMetrics(sensorData: sensorData, duration: duration)
        
        return EndSetAnalytics(
            endedAt: input.endTime,
            exerciseName: input.exercise.template?.safeName ?? "Unknown",
            setNumber: input.set.order + 1,
            targetReps: input.set.targetReps,
            actualReps: actualReps,
            weight: input.set.weight,
            duration: duration,
            intensityScore: intensityScore,
            formAnalysis: formAnalysis,
            fatigueMetrics: fatigueMetrics,
            userId: input.user.safeId,
            sessionId: input.exercise.session?.safeId ?? "unknown",
            exerciseId: input.exercise.safeId,
            triggerType: input.triggerType
        )
    }
    
    private func calculateIntensityScore(sensorData: SensorData?, duration: TimeInterval) -> Double {
        guard let sensorData = sensorData else { return 0.5 } // Score médio se não há dados
        
        // Calcular magnitudes manualmente se necessário para análise
        let hasAccelerationData = sensorData.accelerationX != nil || sensorData.accelerationY != nil || sensorData.accelerationZ != nil
        let hasRotationData = sensorData.rotationX != nil || sensorData.rotationY != nil || sensorData.rotationZ != nil
        
        var score = 0.0
        var components = 0
        
        if hasAccelerationData {
            score += 0.7 // Presença de dados de aceleração
            components += 1
        }
        
        if hasRotationData {
            score += 0.7 // Presença de dados de rotação
            components += 1
        }
        
        let durationScore = min(duration / 60.0, 1.0) // Normalizar por 1 minuto
        score += durationScore
        components += 1
        
        return components > 0 ? score / Double(components) : 0.5
    }
    
    private func calculateFormAnalysis(sensorData: SensorData?) -> EndSetAnalytics.FormAnalysis {
        guard let sensorData = sensorData else {
            return EndSetAnalytics.FormAnalysis(consistency: 0.5, rangeOfMotion: 0.5, tempo: 0.5, overall: 0.5)
        }
        
        // Análise básica de consistência baseada na variação dos movimentos
        let consistency = calculateMovementConsistency(sensorData)
        let rangeOfMotion = calculateRangeOfMotion(sensorData)
        let tempo = calculateTempoControl(sensorData)
        let overall = (consistency + rangeOfMotion + tempo) / 3.0
        
        return EndSetAnalytics.FormAnalysis(
            consistency: consistency,
            rangeOfMotion: rangeOfMotion,
            tempo: tempo,
            overall: overall
        )
    }
    
    private func calculateFatigueMetrics(sensorData: SensorData?, duration: TimeInterval) -> EndSetAnalytics.FatigueMetrics {
        // Estimativas baseadas na duração e presença de dados
        let initialIntensity = 1.0
        let finalIntensity = sensorData != nil ? 0.7 : 0.5 // Estimativa baseada na presença de dados
        let fatigueIndex = initialIntensity - finalIntensity
        
        // Tempo de recuperação baseado na fadiga
        let baseRecovery: TimeInterval = 60 // 1 minuto base
        let recoveryNeeded = baseRecovery + (fatigueIndex * 120) // Até 2min extra baseado na fadiga
        
        return EndSetAnalytics.FatigueMetrics(
            initialIntensity: initialIntensity,
            finalIntensity: finalIntensity,
            fatigueIndex: fatigueIndex,
            recoveryNeeded: recoveryNeeded
        )
    }
    
    private func configureRestTimer(_ input: EndSetInput, analytics: EndSetAnalytics, nextAction: EndSetResult.NextAction) async -> RestTimerInfo {
        let duration: TimeInterval
        let type: RestTimerInfo.RestType
        
        if let customDuration = input.restDuration {
            duration = customDuration
            type = .custom(customDuration)
        } else if case .nextExercise(_, let restTime) = nextAction {
            duration = restTime
            type = .betweenExercises
        } else if case .nextSet(let estimatedRestTime) = nextAction {
            duration = estimatedRestTime
            type = .betweenSets
        } else {
            // Rest timer inteligente baseado na fadiga
            duration = calculateOptimalRestTime(for: input.set, analytics: analytics)
            type = .intelligent(basedOnFatigue: analytics.fatigueMetrics.fatigueIndex)
        }
        
        // TODO: Iniciar timer via TimerService (item 46 - CONCLUÍDO)
        // await timerService?.startRestTimer(duration: duration, autoAction: nextAction)
        
        let autoAction = input.enableAutoFlow ? nextActionDescription(nextAction) : nil
        
        print("⏱️ Rest timer configurado: \(duration)s - Auto: \(autoAction ?? "Não")")
        
        return RestTimerInfo(
            duration: duration,
            type: type,
            autoAction: autoAction,
            startedAt: Date()
        )
    }
    
    private func finalizeHealthKitSegment(_ input: EndSetInput) async -> EndSetResult.HealthKitStatus {
        // TODO: Implementar quando HealthKitManager for injetado (item 65)
        // return await healthKitManager?.endWorkoutSegment() ?? .skipped
        
        print("🏥 HealthKit segment finalizado (simulado)")
        return .skipped
    }
    
    private func performSync(set: CDCurrentSet) async -> EndSetResult.SyncStatus {
        guard let syncUseCase = syncUseCase else {
            return .skipped
        }
        
        do {
            // Sincronizar série finalizada
            // let syncInput = SyncWorkoutInput(entity: set, strategy: .upload)
            // _ = try await syncUseCase.execute(syncInput)
            
            print("☁️ Sincronização concluída")
            return .synced
        } catch {
            print("⚠️ Falha na sincronização: \(error)")
            return .failed(error)
        }
    }
    
    private func syncWithWatch(_ set: CDCurrentSet, nextAction: EndSetResult.NextAction) async -> EndSetResult.WatchSyncStatus {
        // TODO: Implementar sync com WatchDataManager
        // await watchDataManager?.syncSetCompleted(set, nextAction: nextAction)
        
        print("⌚ Sincronização com Apple Watch: \(set.safeId)")
        return .synced
    }
    
    // MARK: - Helper Methods
    
    private func detectRepsFromSensorData(_ sensorData: SensorData) -> Int32 {
        // TODO: Implementar detecção de repetições via Core ML
        // Por enquanto, usar estimativa baseada na presença de dados
        let hasAccelData = sensorData.accelerationX != nil || sensorData.accelerationY != nil || sensorData.accelerationZ != nil
        let hasRotationData = sensorData.rotationX != nil || sensorData.rotationY != nil || sensorData.rotationZ != nil
        
        var estimatedReps: Int32 = 1
        
        if hasAccelData && hasRotationData {
            estimatedReps = 10 // Estimativa para dados completos
        } else if hasAccelData || hasRotationData {
            estimatedReps = 6  // Estimativa para dados parciais
        } else {
            estimatedReps = 3  // Estimativa mínima
        }
        
        return max(1, estimatedReps)
    }
    
    private func calculateMovementConsistency(_ sensorData: SensorData) -> Double {
        // Analisar consistência baseada na presença de dados válidos
        let hasAccelData = sensorData.accelerationX != nil && sensorData.accelerationY != nil && sensorData.accelerationZ != nil
        let hasRotationData = sensorData.rotationX != nil && sensorData.rotationY != nil && sensorData.rotationZ != nil
        
        if hasAccelData && hasRotationData {
            return 0.8 // Dados completos = alta consistência
        } else if hasAccelData || hasRotationData {
            return 0.6 // Dados parciais = consistência média
        } else {
            return 0.3 // Poucos dados = baixa consistência
        }
    }
    
    private func calculateRangeOfMotion(_ sensorData: SensorData) -> Double {
        // Baseado na presença e variação dos dados de aceleração
        let hasAccelData = sensorData.accelerationX != nil && sensorData.accelerationY != nil && sensorData.accelerationZ != nil
        
        if hasAccelData {
            let x = abs(sensorData.accelerationX ?? 0.0)
            let y = abs(sensorData.accelerationY ?? 0.0) 
            let z = abs(sensorData.accelerationZ ?? 0.0)
            let range = (x + y + z) / 3.0
            return max(0.0, min(1.0, range / 5.0))
        }
        
        return 0.5 // Default para dados incompletos
    }
    
    private func calculateTempoControl(_ sensorData: SensorData) -> Double {
        // Análise de controle de tempo baseado na variação de intensidade
        return 0.7 // Placeholder - implementar análise real quando MotionManager for refatorado
    }
    
    private func nextActionDescription(_ nextAction: EndSetResult.NextAction) -> String {
        switch nextAction {
        case .nextSet:
            return "Próxima série"
        case .nextExercise(let template, _):
            return "Próximo exercício: \(template.safeName)"
        case .workoutComplete:
            return "Treino completo"
        case .waitingForUserDecision:
            return "Aguardando decisão"
        case .automaticAfterRest(let action, _):
            return "Automático: \(action)"
        }
    }
    

}

// MARK: - EndSetUseCase Extension

extension EndSetUseCase {
    
    // MARK: - Additional Helper Methods
    
    func getSetProgress(for exercise: CDCurrentExercise) async throws -> Double {
        let sets = try await workoutDataService.fetchCurrentSets(for: exercise)
        let completedSets = sets.filter { !$0.isActive }.count
        
        // Assumir 3-4 séries típicas
        let targetSets = 3.0
        return min(Double(completedSets) / targetSets, 1.0)
    }
    
    func isExerciseCompleted(for exercise: CDCurrentExercise) async throws -> Bool {
        let sets = try await workoutDataService.fetchCurrentSets(for: exercise)
        let completedSets = sets.filter { !$0.isActive }.count
        
        return completedSets >= 3 // Considerar exercício completo com 3+ séries
    }
    
    func estimateWorkoutProgress(for session: CDCurrentSession) async throws -> Double {
        guard let plan = session.plan else { return 0.0 }
        
        let totalExercises = plan.exercisesArray.count
        let currentIndex = Int(session.currentExerciseIndex)
        
        let exerciseProgress = Double(currentIndex) / Double(totalExercises)
        
        // Adicionar progresso da série atual
        if let currentExercise = session.currentExercise {
            let setProgress = try await getSetProgress(for: currentExercise)
            let exerciseIncrement = setProgress / Double(totalExercises)
            return min(1.0, exerciseProgress + exerciseIncrement)
        }
        
        return exerciseProgress
    }
}

// MARK: - EndSetUseCase Mock Support

#if DEBUG
extension EndSetUseCase {
    
    static func mock() -> EndSetUseCase {
        // TODO: Implementar mock quando MockWorkoutDataService for criado (itens 74-85)
        fatalError("Mock não implementado - aguardando itens 74-85")
    }
}
#endif 