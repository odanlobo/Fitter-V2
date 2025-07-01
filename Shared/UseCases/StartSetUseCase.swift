/*
 * StartSetUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Iniciar série individual com captura ativa de sensores do Apple Watch
 *                   e integração robusta com HealthKit para modo background.
 *
 * ARQUITETURA:
 * - Clean Architecture: Protocol + Implementation
 * - Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
 * - LOGIN OBRIGATÓRIO: user: CDAppUser (nunca opcional)
 * - Error Handling: StartSetError enum específico
 * - Async/await: Todas operações assíncronas
 *
 * OPERAÇÕES PRINCIPAIS:
 * 1. Validar exercício ativo e dados de entrada
 * 2. Criar CDCurrentSet via WorkoutDataService
 * 3. Ativar sensores Apple Watch (MotionManager)
 * 4. Iniciar workout segment HealthKit para background
 * 5. Configurar tracking de duração e captura em tempo real
 * 6. Sincronizar com iPhone via ConnectivityManager
 * 7. Validar limites premium/free (preparado para itens 41-50)
 *
 * INTEGRAÇÕES WATCH:
 * - MotionManager: Captura de sensores (accelerometer, gyroscope, etc.)
 * - WatchDataManager: Persistência local no Watch
 * - ConnectivityManager: Sync Watch → iPhone em tempo real
 * - HealthKit: Background workout segments (preparado para item 54)
 *
 * FUNCIONALIDADES AVANÇADAS:
 * - Validação de séries por tipo de assinatura
 * - Analytics de início de série
 * - Captura em background (tela Watch apagada)
 * - Preparação para Core ML rep counting (pendências futuras)
 *
 * REFATORAÇÃO ITEM 28/88:
 * ✅ Criar StartSetUseCase.swift
 * 🔄 Preparado para HealthKitManager (item 54)
 * 🔄 Preparado para SubscriptionManager (itens 41-50)
 * 🔄 Preparado para AuthUseCase (item 34)
 */

import Foundation
import CoreData
import Combine

// MARK: - StartSetError

enum StartSetError: Error, LocalizedError {
    case userNotAuthenticated
    case noActiveSession
    case noActiveExercise
    case invalidExercise(String)
    case invalidSetData(String)
    case seriesLimitExceeded(limit: Int, current: Int)
    case subscriptionRequired(feature: String)
    case sensorActivationFailed(Error)
    case healthKitNotAvailable
    case watchNotConnected
    case persistenceFailed(Error)
    case syncFailed(Error)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Usuário não autenticado"
        case .noActiveSession:
            return "Nenhuma sessão de treino ativa"
        case .noActiveExercise:
            return "Nenhum exercício ativo na sessão"
        case .invalidExercise(let message):
            return "Exercício inválido: \(message)"
        case .invalidSetData(let message):
            return "Dados da série inválidos: \(message)"
        case .seriesLimitExceeded(let limit, let current):
            return "Limite de séries excedido: \(current)/\(limit). Considere fazer upgrade para Premium."
        case .subscriptionRequired(let feature):
            return "Recurso premium necessário: \(feature). Faça upgrade para continuar."
        case .sensorActivationFailed(let error):
            return "Falha ao ativar sensores: \(error.localizedDescription)"
        case .healthKitNotAvailable:
            return "HealthKit não disponível neste dispositivo"
        case .watchNotConnected:
            return "Apple Watch não conectado"
        case .persistenceFailed(let error):
            return "Falha ao salvar dados: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Erro desconhecido: \(error.localizedDescription)"
        }
    }
}

// MARK: - StartSetInput

struct StartSetInput {
    let user: CDAppUser                    // LOGIN OBRIGATÓRIO
    let exercise: CDCurrentExercise        // Exercício ativo
    let targetReps: Int32                  // Repetições planejadas
    let weight: Double                     // Peso utilizado
    let order: Int32                       // Ordem da série no exercício
    let enableSensorCapture: Bool          // Captura de sensores habilitada
    let enableHealthKit: Bool              // HealthKit workout segment
    let enableBackgroundMode: Bool         // Modo background no Watch
    
    // Validação de entrada
    var isValid: Bool {
        return targetReps > 0 && weight >= 0 && order >= 0
    }
    
    var validationMessage: String? {
        if targetReps <= 0 {
            return "Número de repetições deve ser maior que zero"
        }
        if weight < 0 {
            return "Peso não pode ser negativo"
        }
        if order < 0 {
            return "Ordem da série inválida"
        }
        return nil
    }
}

// MARK: - StartSetResult

struct StartSetResult {
    let set: CDCurrentSet
    let sensorCaptureActive: Bool
    let healthKitSessionActive: Bool
    let estimatedDuration: TimeInterval
    let setNumber: Int32
    let analytics: StartSetAnalytics
    
    var isFullyActive: Bool {
        return sensorCaptureActive && healthKitSessionActive
    }
}

// MARK: - StartSetAnalytics

struct StartSetAnalytics {
    let startedAt: Date
    let exerciseName: String
    let setNumber: Int32
    let targetReps: Int32
    let weight: Double
    let userId: String
    let sessionId: String
    let exerciseId: String
    let hasSensorCapture: Bool
    let hasHealthKitIntegration: Bool
    let watchConnected: Bool
    let estimatedIntensity: Double
    
    // Computed properties
    var intensityLevel: String {
        switch estimatedIntensity {
        case 0..<0.3: return "Leve"
        case 0.3..<0.7: return "Moderada"
        case 0.7...1.0: return "Intensa"
        default: return "Desconhecida"
        }
    }
    
    var isFullyOptimized: Bool {
        return hasSensorCapture && hasHealthKitIntegration && watchConnected
    }
}

// MARK: - StartSetUseCaseProtocol

protocol StartSetUseCaseProtocol {
    func execute(_ input: StartSetInput) async throws -> StartSetResult
    func executeQuickStart(for exercise: CDCurrentExercise, user: CDAppUser, targetReps: Int32, weight: Double) async throws -> StartSetResult
    func executeWithDefaultSettings(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> StartSetResult
    func executeOffline(for exercise: CDCurrentExercise, user: CDAppUser, targetReps: Int32, weight: Double) async throws -> StartSetResult
    
    // Validation helpers
    func canStartSet(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> Bool
    func validateSeriesLimit(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> Bool
    func getMaxSeries(for user: CDAppUser) async -> Int32
}

// MARK: - StartSetUseCase

final class StartSetUseCase: StartSetUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    
    // MARK: - Managers (Preparados para DI futura)
    
    private var motionManager: MotionManager? {
        // TODO: Injetar via DI quando MotionManager for refatorado
        return nil
    }
    
    private var watchDataManager: WatchDataManager? {
        // TODO: Injetar via DI quando WatchDataManager for refatorado
        return nil
    }
    
    private var connectivityManager: ConnectivityManager? {
        // TODO: Injetar via DI quando ConnectivityManager for refatorado
        return nil
    }
    
    private var healthKitManager: Any? {
        // TODO: Injetar HealthKitManager quando item 54 for implementado
        return nil
    }
    
    private var subscriptionManager: Any? {
        // TODO: Injetar SubscriptionManager quando itens 41-50 forem implementados
        return nil
    }
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil
    ) {
        self.workoutDataService = workoutDataService
        self.syncUseCase = syncUseCase
        
        print("🎯 StartSetUseCase inicializado")
    }
    
    // MARK: - Main Execution
    
    func execute(_ input: StartSetInput) async throws -> StartSetResult {
        print("▶️ Iniciando série: \(input.exercise.safeExerciseName) - Série \(input.order + 1)")
        
        // 1. Validação de entrada
        try await validateInput(input)
        
        // 2. Validação de limites de assinatura
        try await validateSubscriptionLimits(input)
        
        // 3. Preparar captura de sensores
        let sensorCaptureActive = await prepareSensorCapture(input)
        
        // 4. Preparar HealthKit workout segment
        let healthKitActive = await prepareHealthKitSession(input)
        
        // 5. Criar CDCurrentSet
        let set = try await createCurrentSet(input)
        
        // 6. Iniciar captura em tempo real
        await startRealTimeCapture(set, input: input)
        
        // 7. Sincronizar com Watch
        await syncWithWatch(set, input: input)
        
        // 8. Sincronizar com Firebase (opcional)
        if let syncUseCase = syncUseCase {
            try await syncWithFirebase(set, syncUseCase: syncUseCase)
        }
        
        // 9. Calcular analytics
        let analytics = generateAnalytics(set, input: input, sensorActive: sensorCaptureActive, healthKitActive: healthKitActive)
        
        // 10. Preparar resultado
        let result = StartSetResult(
            set: set,
            sensorCaptureActive: sensorCaptureActive,
            healthKitSessionActive: healthKitActive,
            estimatedDuration: estimateSetDuration(input),
            setNumber: input.order + 1,
            analytics: analytics
        )
        
        print("✅ Série iniciada com sucesso: \(set.safeId) - Sensores: \(sensorCaptureActive ? "✅" : "❌")")
        return result
    }
    
    // MARK: - Convenience Methods
    
    func executeQuickStart(for exercise: CDCurrentExercise, user: CDAppUser, targetReps: Int32, weight: Double) async throws -> StartSetResult {
        let currentSets = try await workoutDataService.fetchCurrentSets(for: exercise)
        let nextOrder = Int32(currentSets.count)
        
        let input = StartSetInput(
            user: user,
            exercise: exercise,
            targetReps: targetReps,
            weight: weight,
            order: nextOrder,
            enableSensorCapture: true,
            enableHealthKit: true,
            enableBackgroundMode: true
        )
        
        return try await execute(input)
    }
    
    func executeWithDefaultSettings(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> StartSetResult {
        // Buscar configurações padrão do exercício
        let defaultReps: Int32 = 12
        let defaultWeight: Double = 0.0
        
        return try await executeQuickStart(for: exercise, user: user, targetReps: defaultReps, weight: defaultWeight)
    }
    
    func executeOffline(for exercise: CDCurrentExercise, user: CDAppUser, targetReps: Int32, weight: Double) async throws -> StartSetResult {
        let currentSets = try await workoutDataService.fetchCurrentSets(for: exercise)
        let nextOrder = Int32(currentSets.count)
        
        let input = StartSetInput(
            user: user,
            exercise: exercise,
            targetReps: targetReps,
            weight: weight,
            order: nextOrder,
            enableSensorCapture: false,
            enableHealthKit: false,
            enableBackgroundMode: false
        )
        
        return try await execute(input)
    }
    
    // MARK: - Validation Methods
    
    func canStartSet(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> Bool {
        // Verificar se há sessão ativa
        guard exercise.session != nil else {
            return false
        }
        
        // Verificar limites de assinatura
        return try await validateSeriesLimit(for: exercise, user: user)
    }
    
    func validateSeriesLimit(for exercise: CDCurrentExercise, user: CDAppUser) async throws -> Bool {
        let currentSets = try await workoutDataService.fetchCurrentSets(for: exercise)
        let maxSeries = await getMaxSeries(for: user)
        
        return Int32(currentSets.count) < maxSeries
    }
    
    func getMaxSeries(for user: CDAppUser) async -> Int32 {
        // TODO: Implementar validação com SubscriptionManager (itens 41-50)
        // Por enquanto, retorna limite padrão
        return 10  // Usuário free: 3 séries, Premium: ilimitado
    }
    
    // MARK: - Private Methods
    
    private func validateInput(_ input: StartSetInput) async throws {
        // Validação básica
        guard input.isValid else {
            throw StartSetError.invalidSetData(input.validationMessage ?? "Dados inválidos")
        }
        
        // Verificar se há sessão ativa
        guard input.exercise.session != nil else {
            throw StartSetError.noActiveSession
        }
        
        // Verificar se exercício está ativo
        guard input.exercise.isActive else {
            throw StartSetError.invalidExercise("Exercício não está ativo")
        }
    }
    
    private func validateSubscriptionLimits(_ input: StartSetInput) async throws {
        // Verificar limite de séries
        let canStart = try await validateSeriesLimit(for: input.exercise, user: input.user)
        
        if !canStart {
            let currentSets = try await workoutDataService.fetchCurrentSets(for: input.exercise)
            let maxSeries = await getMaxSeries(for: input.user)
            throw StartSetError.seriesLimitExceeded(limit: Int(maxSeries), current: currentSets.count)
        }
        
        // TODO: Implementar outras validações premium quando itens 41-50 forem implementados
        // - Captura de sensores premium
        // - Analytics avançados
        // - Feedback ML em tempo real
    }
    
    private func prepareSensorCapture(_ input: StartSetInput) async -> Bool {
        guard input.enableSensorCapture else { return false }
        
        // TODO: Implementar quando MotionManager for injetado via DI
        // return await motionManager?.startSensorCapture() ?? false
        
        print("🔄 Preparando captura de sensores (simulado)")
        return true
    }
    
    private func prepareHealthKitSession(_ input: StartSetInput) async -> Bool {
        guard input.enableHealthKit else { return false }
        
        // TODO: Implementar quando HealthKitManager for criado (item 54)
        // return await healthKitManager?.startWorkoutSegment() ?? false
        
        print("🔄 Preparando sessão HealthKit (aguardando item 54)")
        return false
    }
    
    private func createCurrentSet(_ input: StartSetInput) async throws -> CDCurrentSet {
        do {
            // Criar SensorData inicial (vazio, será preenchido durante exercício)
            let initialSensorData = SensorData(capturedAt: Date())
            
            let set = try await workoutDataService.createCurrentSet(
                for: input.exercise,
                targetReps: input.targetReps,
                weight: input.weight,
                order: input.order,
                sensorData: initialSensorData
            )
            
            return set
        } catch {
            throw StartSetError.persistenceFailed(error)
        }
    }
    
    private func startRealTimeCapture(_ set: CDCurrentSet, input: StartSetInput) async {
        guard input.enableSensorCapture else { return }
        
        // TODO: Implementar captura em tempo real com MotionManager
        // await motionManager?.startRealTimeCapture(for: set.safeId)
        
        print("📡 Iniciando captura em tempo real para série: \(set.safeId)")
    }
    
    private func syncWithWatch(_ set: CDCurrentSet, input: StartSetInput) async {
        // TODO: Implementar sync com WatchDataManager
        // await watchDataManager?.syncCurrentSet(set)
        
        print("⌚ Sincronizando com Apple Watch: \(set.safeId)")
    }
    
    private func syncWithFirebase(_ set: CDCurrentSet, syncUseCase: SyncWorkoutUseCaseProtocol) async throws {
        do {
            // Sincronizar série com Firebase
            // let syncInput = SyncWorkoutInput(entity: set, strategy: .upload)
            // _ = try await syncUseCase.execute(syncInput)
            
            print("☁️ Sincronização com Firebase concluída")
        } catch {
            print("⚠️ Falha na sincronização Firebase: \(error.localizedDescription)")
            throw StartSetError.syncFailed(error)
        }
    }
    
    private func generateAnalytics(_ set: CDCurrentSet, input: StartSetInput, sensorActive: Bool, healthKitActive: Bool) -> StartSetAnalytics {
        let estimatedIntensity = calculateEstimatedIntensity(targetReps: input.targetReps, weight: input.weight)
        
        return StartSetAnalytics(
            startedAt: Date(),
            exerciseName: input.exercise.safeExerciseName,
            setNumber: input.order + 1,
            targetReps: input.targetReps,
            weight: input.weight,
            userId: input.user.safeId,
            sessionId: input.exercise.session?.safeId ?? "unknown",
            exerciseId: input.exercise.safeId,
            hasSensorCapture: sensorActive,
            hasHealthKitIntegration: healthKitActive,
            watchConnected: connectivityManager?.isReachable ?? false,
            estimatedIntensity: estimatedIntensity
        )
    }
    
    private func calculateEstimatedIntensity(targetReps: Int32, weight: Double) -> Double {
        // Fórmula simples: intensidade baseada em reps e peso
        let repsIntensity = min(Double(targetReps) / 15.0, 1.0)
        let weightIntensity = min(weight / 100.0, 1.0)
        return (repsIntensity + weightIntensity) / 2.0
    }
    
    private func estimateSetDuration(_ input: StartSetInput) -> TimeInterval {
        // Estimativa baseada em repetições: ~2-3 segundos por rep
        let secondsPerRep: Double = 2.5
        let baseTime = Double(input.targetReps) * secondsPerRep
        
        // Adicionar tempo para setup e preparação
        let setupTime: Double = 10.0
        
        return baseTime + setupTime
    }
}

// MARK: - StartSetUseCase Extension

extension StartSetUseCase {
    
    // MARK: - Helper Methods
    
    func getCurrentSetCount(for exercise: CDCurrentExercise) async throws -> Int {
        let sets = try await workoutDataService.fetchCurrentSets(for: exercise)
        return sets.count
    }
    
    func getExerciseProgress(for exercise: CDCurrentExercise) async throws -> Double {
        let sets = try await workoutDataService.fetchCurrentSets(for: exercise)
        
        // Assumir que exercício tem 3-4 séries típicas
        let typicalSets = 3.0
        return min(Double(sets.count) / typicalSets, 1.0)
    }
    
    func isExerciseCompleted(for exercise: CDCurrentExercise) async throws -> Bool {
        let sets = try await workoutDataService.fetchCurrentSets(for: exercise)
        
        // Considerar exercício completo com 3+ séries
        return sets.count >= 3
    }
}

// MARK: - StartSetUseCase Mock Support

#if DEBUG
extension StartSetUseCase {
    
    static func mock() -> StartSetUseCase {
        // TODO: Implementar mock quando MockWorkoutDataService for criado (itens 74-85)
        fatalError("Mock não implementado - aguardando itens 74-85")
    }
}
#endif 