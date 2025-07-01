//
//  StartWorkoutUseCase.swift
//  Fitter V2
//
//  📋 RESPONSABILIDADE: Iniciar sessão completa de treino
//  
//  🎯 OPERAÇÕES PRINCIPAIS:
//  • Validar usuário autenticado e plano válido
//  • Verificar se não há sessão ativa conflitante
//  • Criar CDCurrentSession via WorkoutDataService
//  • Configurar primeiro exercício automaticamente
//  • Sincronizar dados via SyncWorkoutUseCase
//  • Preparar integração com HealthKit (quando disponível)
//  • Notificar Apple Watch sobre nova sessão
//  
//  🏗️ ARQUITETURA:
//  • Protocol + Implementation para testabilidade
//  • Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
//  • Error handling específico com StartWorkoutError enum
//  • Input validation com StartWorkoutInput struct
//  • Async/await nativo para performance
//  
//  ⚡ INTEGRAÇÃO:
//  • WorkoutDataService: Operações CRUD de sessão
//  • SyncWorkoutUseCase: Sincronização automática
//  • AuthService: Validação de usuário (será AuthUseCase no item 34)
//  • HealthKitManager: Workout sessions (será implementado no item 54)
//  
//  🔄 LIFECYCLE:
//  1. Validação de entrada (usuário, plano, sessão ativa)
//  2. Criação de CDCurrentSession
//  3. Configuração do primeiro exercício (se existir)
//  4. Sincronização automática
//  5. Notificação para Apple Watch
//  6. Início de workout session HealthKit (futuro)
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import CoreData

// MARK: - StartWorkoutInput

/// Input para iniciar uma sessão de treino
/// Consolida todos os parâmetros necessários com validações
struct StartWorkoutInput {
    let plan: CDWorkoutPlan
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let startTime: Date
    let autoStartFirstExercise: Bool
    let enableHealthKit: Bool
    let backgroundPermissions: Bool
    
    /// Inicializador com valores padrão otimizados
    init(
        plan: CDWorkoutPlan,
        user: CDAppUser, // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
        startTime: Date = Date(),
        autoStartFirstExercise: Bool = true,
        enableHealthKit: Bool = true,
        backgroundPermissions: Bool = true
    ) {
        self.plan = plan
        self.user = user
        self.startTime = startTime
        self.autoStartFirstExercise = autoStartFirstExercise
        self.enableHealthKit = enableHealthKit
        self.backgroundPermissions = backgroundPermissions
    }
    
    /// Validação básica de entrada
    var isValid: Bool {
        return !plan.safeId.uuidString.isEmpty && 
               plan.exercisesArray.count > 0
    }
}

// MARK: - StartWorkoutError

/// Erros específicos para início de treino
enum StartWorkoutError: LocalizedError {
    case planNotFound
    case planEmpty
    case sessionAlreadyActive
    case workoutDataServiceError(Error)
    case syncError(Error)
    case healthKitPermissionDenied
    case healthKitNotAvailable
    case watchConnectivityError
    case invalidInput
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .planNotFound:
            return "Plano de treino não encontrado."
        case .planEmpty:
            return "Plano de treino não possui exercícios. Adicione exercícios antes de iniciar."
        case .sessionAlreadyActive:
            return "Já existe uma sessão de treino ativa. Finalize o treino atual antes de iniciar um novo."
        case .workoutDataServiceError(let error):
            return "Erro ao salvar dados do treino: \(error.localizedDescription)"
        case .syncError(let error):
            return "Erro na sincronização: \(error.localizedDescription)"
        case .healthKitPermissionDenied:
            return "Permissão negada para acessar dados de saúde."
        case .healthKitNotAvailable:
            return "HealthKit não está disponível neste dispositivo."
        case .watchConnectivityError:
            return "Erro na comunicação com Apple Watch."
        case .invalidInput:
            return "Dados de entrada inválidos para iniciar treino."
        case .unknownError(let error):
            return "Erro inesperado: \(error.localizedDescription)"
        }
    }
}

// MARK: - StartWorkoutResult

/// Resultado do início de treino
struct StartWorkoutResult {
    let session: CDCurrentSession
    let firstExercise: CDCurrentExercise?
    let syncStatus: SyncStatus
    let healthKitStarted: Bool
    let watchNotified: Bool
    
    enum SyncStatus {
        case synced
        case pending
        case failed(Error)
        case disabled
        
        var isSuccessful: Bool {
            switch self {
            case .synced, .pending, .disabled:
                return true
            case .failed:
                return false
            }
        }
    }
}

// MARK: - StartWorkoutUseCaseProtocol

/// Protocolo para início de treino (testabilidade)
protocol StartWorkoutUseCaseProtocol {
    func execute(_ input: StartWorkoutInput) async throws -> StartWorkoutResult
    func executeQuickStart(plan: CDWorkoutPlan, user: CDAppUser) async throws -> StartWorkoutResult
    func canStartWorkout(for user: CDAppUser) async throws -> Bool
    func validateWorkoutPlan(_ plan: CDWorkoutPlan) -> Bool
}

// MARK: - StartWorkoutUseCase

/// Use Case para iniciar sessão completa de treino
/// Orquestra todas as operações necessárias para começar um treino
final class StartWorkoutUseCase: StartWorkoutUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let syncWorkoutUseCase: SyncWorkoutUseCaseProtocol
    // TODO: Adicionar AuthUseCase quando item 34 for implementado
    // private let authUseCase: AuthUseCaseProtocol
    // TODO: Adicionar HealthKitManager quando item 54 for implementado
    // private let healthKitManager: HealthKitManagerProtocol
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        syncWorkoutUseCase: SyncWorkoutUseCaseProtocol
    ) {
        self.workoutDataService = workoutDataService
        self.syncWorkoutUseCase = syncWorkoutUseCase
    }
    
    // MARK: - Public Methods
    
    /// Executa início completo de treino com validações robustas
    func execute(_ input: StartWorkoutInput) async throws -> StartWorkoutResult {
        print("🚀 [START WORKOUT] Iniciando treino: \(input.plan.displayTitle)")
        
        // 1. Validação de entrada
        try await validateInput(input)
        
        // 2. Verificar se usuário pode iniciar treino
        let canStart = try await canStartWorkout(for: input.user)
        
        guard canStart else {
            throw StartWorkoutError.sessionAlreadyActive
        }
        
        // 3. Criar sessão de treino
        print("📝 [START WORKOUT] Criando sessão para usuário: \(input.user.safeName)")
        let session: CDCurrentSession
        do {
            session = try await workoutDataService.createCurrentSession(
                for: input.plan,
                user: input.user,
                startTime: input.startTime
            )
        } catch {
            throw StartWorkoutError.workoutDataServiceError(error)
        }
        
        // 4. Configurar primeiro exercício (se solicitado)
        var firstExercise: CDCurrentExercise? = nil
        if input.autoStartFirstExercise && !input.plan.exercisesArray.isEmpty {
            firstExercise = try await startFirstExercise(in: session)
        }
        
        // 5. Sincronização automática
        let syncStatus = await performSync(session: session)
        
        // 6. Integração com HealthKit (futuro)
        let healthKitStarted = await startHealthKitSession(input: input, session: session)
        
        // 7. Notificar Apple Watch
        let watchNotified = await notifyAppleWatch(session: session)
        
        let result = StartWorkoutResult(
            session: session,
            firstExercise: firstExercise,
            syncStatus: syncStatus,
            healthKitStarted: healthKitStarted,
            watchNotified: watchNotified
        )
        
        print("✅ [START WORKOUT] Treino iniciado com sucesso")
        print("📊 [START WORKOUT] Health: \(healthKitStarted), Watch: \(watchNotified), Sync: \(syncStatus.isSuccessful)")
        
        return result
    }
    
    /// Método de conveniência para início rápido
    func executeQuickStart(plan: CDWorkoutPlan, user: CDAppUser) async throws -> StartWorkoutResult {
        let input = StartWorkoutInput(plan: plan, user: user)
        return try await execute(input)
    }
    
    /// Verifica se usuário pode iniciar treino (sem sessão ativa)
    func canStartWorkout(for user: CDAppUser) async throws -> Bool {
        do {
            let activeSessions = try await workoutDataService.fetchCurrentSessions(for: user)
            let hasActiveSession = activeSessions.contains { $0.isActive }
            return !hasActiveSession
        } catch {
            throw StartWorkoutError.workoutDataServiceError(error)
        }
    }
    
    /// Valida se plano de treino é adequado para iniciar
    func validateWorkoutPlan(_ plan: CDWorkoutPlan) -> Bool {
        guard !plan.safeId.uuidString.isEmpty else { return false }
        guard !plan.exercisesArray.isEmpty else { return false }
        
        // Verifica se todos os exercícios têm templates válidos
        for planExercise in plan.exercisesArray {
            guard let template = planExercise.template,
                  !template.safeName.isEmpty else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Private Methods
    
    /// Validação robusta de entrada
    private func validateInput(_ input: StartWorkoutInput) async throws {
        guard input.isValid else {
            throw StartWorkoutError.invalidInput
        }
        
        guard validateWorkoutPlan(input.plan) else {
            if input.plan.exercisesArray.isEmpty {
                throw StartWorkoutError.planEmpty
            } else {
                throw StartWorkoutError.planNotFound
            }
        }
    }
    
    /// Inicia primeiro exercício automaticamente
    private func startFirstExercise(in session: CDCurrentSession) async throws -> CDCurrentExercise? {
        guard let firstPlanExercise = session.plan?.exercisesArray.first,
              let template = firstPlanExercise.template else {
            print("⚠️ [START WORKOUT] Primeiro exercício não encontrado")
            return nil
        }
        
        print("🏃‍♂️ [START WORKOUT] Iniciando primeiro exercício: \(template.safeName)")
        
        do {
            let exercise = try await workoutDataService.createCurrentExercise(
                for: template,
                in: session,
                startTime: Date()
            )
            return exercise
        } catch {
            print("❌ [START WORKOUT] Erro ao iniciar primeiro exercício: \(error)")
            // Não falha o treino por causa do exercício
            return nil
        }
    }
    
    /// Sincronização com tratamento de erro
    private func performSync(session: CDCurrentSession) async -> StartWorkoutResult.SyncStatus {
        do {
            let result = try await syncWorkoutUseCase.execute(.upload)
            
            switch result {
            case .success:
                print("✅ [START WORKOUT] Sessão sincronizada")
                return .synced
            case .failure(let error):
                print("⚠️ [START WORKOUT] Falha na sincronização: \(error.localizedDescription)")
                return .failed(error)
            }
        } catch {
            print("❌ [START WORKOUT] Erro na sincronização: \(error)")
            return .failed(error)
        }
    }
    
    /// Integração com HealthKit (preparação para item 54)
    private func startHealthKitSession(input: StartWorkoutInput, session: CDCurrentSession) async -> Bool {
        guard input.enableHealthKit else {
            print("ℹ️ [START WORKOUT] HealthKit desabilitado pelo usuário")
            return false
        }
        
        print("🏥 [START WORKOUT] HealthKit será integrado no item 54")
        // TODO: Implementar quando HealthKitManager estiver disponível
        // guard let healthKitManager = self.healthKitManager else { return false }
        // 
        // do {
        //     let workoutType = HKWorkoutActivityType.traditionalStrengthTraining
        //     try await healthKitManager.startWorkoutSession(
        //         type: workoutType,
        //         session: session,
        //         backgroundPermissions: input.backgroundPermissions
        //     )
        //     return true
        // } catch {
        //     print("❌ [START WORKOUT] HealthKit error: \(error)")
        //     return false
        // }
        
        return false // Temporário até item 54
    }
    
    /// Notificação para Apple Watch
    private func notifyAppleWatch(session: CDCurrentSession) async -> Bool {
        #if os(iOS)
        print("⌚ [START WORKOUT] Notificando Apple Watch sobre nova sessão")
        
        // Integração com ConnectivityManager existente
        guard let connectivityManager = getConnectivityManager() else {
            print("⚠️ [START WORKOUT] ConnectivityManager não disponível")
            return false
        }
        
        let sessionContext: [String: Any] = [
            "type": "sessionStarted",
            "sessionId": session.safeId.uuidString,
            "planId": session.plan?.safeId.uuidString ?? "",
            "planTitle": session.plan?.displayTitle ?? "",
            "startTime": session.startTime.timeIntervalSince1970,
            "exerciseCount": session.plan?.exercisesArray.count ?? 0,
            "firstExerciseName": session.plan?.exercisesArray.first?.template?.safeName ?? ""
        ]
        
        await connectivityManager.sendMessage(sessionContext, replyHandler: nil)
        return true
        #else
        print("ℹ️ [START WORKOUT] Watch notification skipped (watchOS)")
        return false
        #endif
    }
    
    /// Helper para obter ConnectivityManager
    private func getConnectivityManager() -> ConnectivityManager? {
        #if os(iOS)
        return ConnectivityManager.shared
        #else
        return nil
        #endif
    }
}

// MARK: - Convenience Extensions

extension StartWorkoutUseCase {
    
    /// Inicia treino com configurações padrão
    func startDefaultWorkout(plan: CDWorkoutPlan, user: CDAppUser) async throws -> StartWorkoutResult {
        return try await executeQuickStart(plan: plan, user: user)
    }
    
    /// Inicia treino sem iniciar primeiro exercício automaticamente
    func startWorkoutPlanOnly(plan: CDWorkoutPlan, user: CDAppUser) async throws -> StartWorkoutResult {
        let input = StartWorkoutInput(
            plan: plan,
            user: user,
            autoStartFirstExercise: false
        )
        return try await execute(input)
    }
    
    /// Inicia treino sem HealthKit
    func startWorkoutWithoutHealthKit(plan: CDWorkoutPlan, user: CDAppUser) async throws -> StartWorkoutResult {
        let input = StartWorkoutInput(
            plan: plan,
            user: user,
            enableHealthKit: false
        )
        return try await execute(input)
    }
}

// MARK: - Error Recovery

extension StartWorkoutUseCase {
    
    /// Recupera de sessão ativa órfã
    /// - Parameter user: Usuário autenticado (deve vir do ViewModel via BaseViewModel.currentUser)
    func recoverFromOrphanSession(for user: CDAppUser) async throws -> Bool {
        do {
            let activeSessions = try await workoutDataService.fetchCurrentSessions(for: user)
            
            for session in activeSessions where session.isActive {
                // Finaliza sessões órfãs
                try await workoutDataService.updateCurrentSession(session, endTime: Date())
                print("🔧 [START WORKOUT] Sessão órfã finalizada: \(session.safeId)")
            }
            
            return true
        } catch {
            print("❌ [START WORKOUT] Erro ao recuperar sessões órfãs: \(error)")
            return false
        }
    }
} 