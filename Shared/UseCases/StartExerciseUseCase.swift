//
//  StartExerciseUseCase.swift
//  Fitter V2
//
//  📋 RESPONSABILIDADE: Iniciar exercício individual dentro de uma sessão ativa
//  
//  🎯 OPERAÇÕES PRINCIPAIS:
//  • Finalizar exercício atual (se existir)
//  • Navegar para próximo exercício no plano
//  • Criar CDCurrentExercise para template específico
//  • Atualizar currentExerciseIndex na sessão
//  • Sincronizar dados via SyncWorkoutUseCase (opcional)
//  • Preparar integração com HealthKit (item 54)
//  • Notificar Apple Watch sobre novo exercício
//  
//  🏗️ ARQUITETURA:
//  • Protocol + Implementation para testabilidade
//  • Dependency Injection: WorkoutDataService + SyncWorkoutUseCase
//  • Error handling específico com StartExerciseError enum
//  • Input validation com StartExerciseInput struct
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
//  1. Validação de entrada (sessão ativa, template válido)
//  2. Finalização do exercício atual (se existir)
//  3. Navegação para próximo exercício do plano
//  4. Criação de CDCurrentExercise
//  5. Atualização do índice na sessão
//  6. Sincronização automática (opcional)
//  7. Notificação para Apple Watch
//  8. Preparação de workout segment HealthKit (futuro)
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation
import CoreData

// MARK: - StartExerciseInput

/// Input para iniciar um exercício individual
/// Consolida todos os parâmetros necessários com validações
struct StartExerciseInput {
    let session: CDCurrentSession
    let template: CDExerciseTemplate  // Template específico OU
    let exerciseIndex: Int32?         // Índice no plano (mutuamente exclusivos)
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let startTime: Date
    let autoStartFirstSet: Bool
    let shouldSync: Bool
    let enableHealthKit: Bool
    
    /// Inicializador com template específico
    init(
        session: CDCurrentSession,
        template: CDExerciseTemplate,
        user: CDAppUser,
        startTime: Date = Date(),
        autoStartFirstSet: Bool = false,
        shouldSync: Bool = true,
        enableHealthKit: Bool = true
    ) {
        self.session = session
        self.template = template
        self.exerciseIndex = nil
        self.user = user
        self.startTime = startTime
        self.autoStartFirstSet = autoStartFirstSet
        self.shouldSync = shouldSync
        self.enableHealthKit = enableHealthKit
    }
    
    /// Inicializador com navegação por índice
    init(
        session: CDCurrentSession,
        exerciseIndex: Int32,
        user: CDAppUser,
        startTime: Date = Date(),
        autoStartFirstSet: Bool = false,
        shouldSync: Bool = true,
        enableHealthKit: Bool = true
    ) throws {
        self.session = session
        self.exerciseIndex = exerciseIndex
        self.user = user
        self.startTime = startTime
        self.autoStartFirstSet = autoStartFirstSet
        self.shouldSync = shouldSync
        self.enableHealthKit = enableHealthKit
        
        // Buscar template pelo índice
        guard let plan = session.plan,
              exerciseIndex >= 0,
              exerciseIndex < plan.exercisesArray.count else {
            throw StartExerciseError.exerciseIndexOutOfRange
        }
        
        guard let template = plan.exercisesArray[Int(exerciseIndex)].template else {
            throw StartExerciseError.templateNotFound
        }
        
        self.template = template
    }
    
    /// Validação básica de entrada
    var isValid: Bool {
        return session.isActive && 
               !session.safeId.uuidString.isEmpty &&
               !template.safeName.isEmpty &&
               session.user == user
    }
}

// MARK: - StartExerciseError

/// Erros específicos para início de exercício
enum StartExerciseError: LocalizedError {
    case sessionNotActive
    case sessionNotFound
    case templateNotFound
    case exerciseIndexOutOfRange
    case planNotFound
    case exerciseAlreadyActive
    case workoutDataServiceError(Error)
    case syncError(Error)
    case healthKitError(Error)
    case watchConnectivityError
    case invalidInput
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            return "Sessão de treino não está ativa."
        case .sessionNotFound:
            return "Sessão de treino não encontrada."
        case .templateNotFound:
            return "Template de exercício não encontrado."
        case .exerciseIndexOutOfRange:
            return "Índice de exercício fora do intervalo do plano."
        case .planNotFound:
            return "Plano de treino não encontrado na sessão."
        case .exerciseAlreadyActive:
            return "Já existe um exercício ativo. Finalize o atual primeiro."
        case .workoutDataServiceError(let error):
            return "Erro ao salvar dados do exercício: \(error.localizedDescription)"
        case .syncError(let error):
            return "Erro na sincronização: \(error.localizedDescription)"
        case .healthKitError(let error):
            return "Erro no HealthKit: \(error.localizedDescription)"
        case .watchConnectivityError:
            return "Erro na comunicação com Apple Watch."
        case .invalidInput:
            return "Dados de entrada inválidos para iniciar exercício."
        case .unknownError(let error):
            return "Erro inesperado: \(error.localizedDescription)"
        }
    }
}

// MARK: - StartExerciseResult

/// Resultado do início de exercício
struct StartExerciseResult {
    let exercise: CDCurrentExercise
    let previousExercise: CDCurrentExercise?
    let exerciseIndex: Int32
    let isFirstSet: CDCurrentSet?
    let syncStatus: SyncStatus
    let healthKitStatus: HealthKitStatus
    let watchNotified: Bool
    
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
        case segmentStarted
        case failed(Error)
        case skipped
        case disabled
        
        var isSuccessful: Bool {
            if case .failed = self { return false }
            return true
        }
    }
}

// MARK: - StartExerciseUseCaseProtocol

/// Protocolo para início de exercício (testabilidade)
protocol StartExerciseUseCaseProtocol {
    func execute(_ input: StartExerciseInput) async throws -> StartExerciseResult
    func executeNextExercise(in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult?
    func executeSpecificExercise(template: CDExerciseTemplate, in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult
    func canStartExercise(in session: CDCurrentSession) -> Bool
    func getNextExerciseTemplate(in session: CDCurrentSession) -> CDExerciseTemplate?
}

// MARK: - StartExerciseUseCase

/// Use Case para iniciar exercício individual dentro de uma sessão ativa
/// Substitui o WorkoutDataService.nextExercise() que estava quebrado
final class StartExerciseUseCase: StartExerciseUseCaseProtocol {
    
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
    
    /// Executa início de exercício com validações robustas
    func execute(_ input: StartExerciseInput) async throws -> StartExerciseResult {
        print("🏃‍♂️ [START EXERCISE] Iniciando exercício: \(input.template.safeName)")
        
        // 1. Validação de entrada
        try await validateInput(input)
        
        // 2. Verificar se pode iniciar exercício
        guard canStartExercise(in: input.session) else {
            throw StartExerciseError.exerciseAlreadyActive
        }
        
        // 3. Finalizar exercício atual (se existir)
        let previousExercise = try await finalizePreviousExercise(input.session)
        
        // 4. Criar novo exercício
        print("📝 [START EXERCISE] Criando exercício para usuário: \(input.user.safeName)")
        let exercise: CDCurrentExercise
        do {
            exercise = try await workoutDataService.createCurrentExercise(
                for: input.template,
                in: input.session,
                startTime: input.startTime
            )
        } catch {
            throw StartExerciseError.workoutDataServiceError(error)
        }
        
        // 5. Atualizar índice da sessão
        let exerciseIndex = try await updateSessionIndex(input.session, for: input.template)
        
        // 6. Criar primeira série (se solicitado)
        var firstSet: CDCurrentSet? = nil
        if input.autoStartFirstSet {
            firstSet = try await createFirstSet(for: exercise)
        }
        
        // 7. Sincronização automática (opcional)
        let syncStatus = await performSync(exercise: exercise, shouldSync: input.shouldSync)
        
        // 8. Integração com HealthKit (futuro)
        let healthKitStatus = await startHealthKitSegment(input: input, exercise: exercise)
        
        // 9. Notificar Apple Watch
        let watchNotified = await notifyAppleWatch(exercise: exercise, session: input.session)
        
        let result = StartExerciseResult(
            exercise: exercise,
            previousExercise: previousExercise,
            exerciseIndex: exerciseIndex,
            isFirstSet: firstSet,
            syncStatus: syncStatus,
            healthKitStatus: healthKitStatus,
            watchNotified: watchNotified
        )
        
        print("✅ [START EXERCISE] Exercício iniciado com sucesso")
        print("📊 [START EXERCISE] Índice: \(exerciseIndex), Health: \(healthKitStatus.isSuccessful), Watch: \(watchNotified)")
        
        return result
    }
    
    /// Método de conveniência para próximo exercício na sequência
    func executeNextExercise(in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult? {
        guard let nextTemplate = getNextExerciseTemplate(in: session) else {
            print("ℹ️ [START EXERCISE] Não há próximo exercício no plano")
            return nil
        }
        
        let input = StartExerciseInput(
            session: session,
            template: nextTemplate,
            user: user
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para exercício específico
    func executeSpecificExercise(template: CDExerciseTemplate, in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult {
        let input = StartExerciseInput(
            session: session,
            template: template,
            user: user
        )
        
        return try await execute(input)
    }
    
    /// Verifica se pode iniciar exercício (sem exercício ativo conflitante)
    func canStartExercise(in session: CDCurrentSession) -> Bool {
        guard session.isActive else { return false }
        
        // Permite se não há exercício atual OU se o atual já foi finalizado
        guard let currentExercise = session.currentExercise else { return true }
        return !currentExercise.isActive || currentExercise.endTime != nil
    }
    
    /// Obtém template do próximo exercício na sequência do plano
    func getNextExerciseTemplate(in session: CDCurrentSession) -> CDExerciseTemplate? {
        guard let plan = session.plan else { return nil }
        
        let exercises = plan.exercisesArray
        let nextIndex = Int(session.currentExerciseIndex + 1)
        
        guard nextIndex < exercises.count else { return nil }
        
        return exercises[nextIndex].template
    }
    
    // MARK: - Private Methods
    
    /// Validação robusta de entrada
    private func validateInput(_ input: StartExerciseInput) async throws {
        guard input.isValid else {
            throw StartExerciseError.invalidInput
        }
        
        guard input.session.isActive else {
            throw StartExerciseError.sessionNotActive
        }
        
        guard input.session.plan != nil else {
            throw StartExerciseError.planNotFound
        }
    }
    
    /// Finaliza exercício anterior se existir e estiver ativo
    private func finalizePreviousExercise(_ session: CDCurrentSession) async throws -> CDCurrentExercise? {
        guard let currentExercise = session.currentExercise,
              currentExercise.isActive else {
            return nil
        }
        
        print("🏁 [START EXERCISE] Finalizando exercício anterior: \(currentExercise.template?.safeName ?? "Unknown")")
        
        do {
            try await workoutDataService.updateCurrentExercise(currentExercise, endTime: Date())
            return currentExercise
        } catch {
            print("⚠️ [START EXERCISE] Erro ao finalizar exercício anterior: \(error)")
            // Não falha o processo por causa do exercício anterior
            return currentExercise
        }
    }
    
    /// Atualiza índice da sessão baseado no template
    private func updateSessionIndex(_ session: CDCurrentSession, for template: CDExerciseTemplate) async throws -> Int32 {
        guard let plan = session.plan else {
            throw StartExerciseError.planNotFound
        }
        
        let exercises = plan.exercisesArray
        
        // Buscar índice do template no plano
        for (index, planExercise) in exercises.enumerated() {
            if planExercise.template?.safeId == template.safeId {
                session.currentExerciseIndex = Int32(index)
                
                do {
                    try await workoutDataService.coreDataService.save()
                    print("📍 [START EXERCISE] Índice atualizado para: \(index)")
                    return Int32(index)
                } catch {
                    throw StartExerciseError.workoutDataServiceError(error)
                }
            }
        }
        
        // Se não encontrou no plano, mantém índice atual + 1
        session.currentExerciseIndex += 1
        
        do {
            try await workoutDataService.coreDataService.save()
            print("📍 [START EXERCISE] Índice incrementado para: \(session.currentExerciseIndex)")
            return session.currentExerciseIndex
        } catch {
            throw StartExerciseError.workoutDataServiceError(error)
        }
    }
    
    /// Cria primeira série automaticamente (preparação para item 28)
    private func createFirstSet(for exercise: CDCurrentExercise) async throws -> CDCurrentSet? {
        print("📊 [START EXERCISE] Preparação para primeira série será implementada no item 28")
        // TODO: Implementar quando StartSetUseCase estiver disponível (item 28)
        // guard let startSetUseCase = self.startSetUseCase else { return nil }
        // 
        // let input = StartSetInput(
        //     exercise: exercise,
        //     targetReps: 12, // Valor padrão
        //     weight: 0.0,    // Usuário define
        //     order: 0
        // )
        // 
        // do {
        //     let result = try await startSetUseCase.execute(input)
        //     return result.set
        // } catch {
        //     print("⚠️ [START EXERCISE] Erro ao criar primeira série: \(error)")
        //     return nil
        // }
        
        return nil // Temporário até item 28
    }
    
    /// Sincronização com tratamento de erro
    private func performSync(exercise: CDCurrentExercise, shouldSync: Bool) async -> StartExerciseResult.SyncStatus {
        guard shouldSync, let syncUseCase = syncWorkoutUseCase else {
            print("⏭️ [START EXERCISE] Sincronização desabilitada")
            return .disabled
        }
        
        do {
            try await syncUseCase.execute(exercise)
            print("☁️ [START EXERCISE] Exercício sincronizado")
            return .synced
        } catch {
            print("⚠️ [START EXERCISE] Falha na sincronização: \(error)")
            return .failed(error)
        }
    }
    
    /// Integração com HealthKit (item 45 - CONCLUÍDO)
    private func startHealthKitSegment(input: StartExerciseInput, exercise: CDCurrentExercise) async -> StartExerciseResult.HealthKitStatus {
        guard input.enableHealthKit else {
            print("ℹ️ [START EXERCISE] HealthKit desabilitado pelo usuário")
            return .skipped
        }
        
        print("🏥 [START EXERCISE] HealthKit será integrado no item 65 (iOSApp.swift)")
        // TODO: Implementar quando HealthKitManager for injetado no item 65
        // guard let healthKitManager = self.healthKitManager else { return .disabled }
        // 
        // do {
        //     // HealthKit não tem segments, apenas workout sessions
        //     // A integração será feita via workout session ativa
        //     return .segmentStarted
        // } catch {
        //     print("❌ [START EXERCISE] HealthKit error: \(error)")
        //     return .failed(error)
        // }
        
        return .disabled // Temporário até item 65
    }
    
    /// Notificação para Apple Watch
    private func notifyAppleWatch(exercise: CDCurrentExercise, session: CDCurrentSession) async -> Bool {
        #if os(iOS)
        do {
            let connectivityManager = ConnectivityManager.shared
            
            let exerciseContext: [String: Any] = [
                "type": "exerciseStarted",
                "sessionId": session.safeId.uuidString,
                "exerciseId": exercise.safeId.uuidString,
                "exerciseName": exercise.template?.safeName ?? "",
                "muscleGroup": exercise.template?.muscleGroup ?? "",
                "equipment": exercise.template?.equipment ?? "",
                "exerciseIndex": session.currentExerciseIndex,
                "startTime": exercise.safeStartTime.timeIntervalSince1970
            ]
            
            await connectivityManager.sendMessage(exerciseContext, replyHandler: nil)
            print("📱➡️⌚ Exercício notificado ao Watch")
            return true
            
        } catch {
            print("❌ [START EXERCISE] Erro ao notificar Watch: \(error)")
            return false
        }
        #else
        print("ℹ️ [START EXERCISE] Notificação Watch apenas disponível no iOS")
        return false
        #endif
    }
}

// MARK: - Convenience Extensions

extension StartExerciseUseCase {
    
    /// Inicia exercício com configurações padrão
    func startDefaultExercise(template: CDExerciseTemplate, in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult {
        return try await executeSpecificExercise(template: template, in: session, user: user)
    }
    
    /// Inicia exercício sem sincronização
    func startExerciseOffline(template: CDExerciseTemplate, in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult {
        let input = StartExerciseInput(
            session: session,
            template: template,
            user: user,
            shouldSync: false
        )
        return try await execute(input)
    }
    
    /// Inicia exercício sem HealthKit
    func startExerciseWithoutHealthKit(template: CDExerciseTemplate, in session: CDCurrentSession, user: CDAppUser) async throws -> StartExerciseResult {
        let input = StartExerciseInput(
            session: session,
            template: template,
            user: user,
            enableHealthKit: false
        )
        return try await execute(input)
    }
}

// MARK: - Navigation Helper

extension StartExerciseUseCase {
    
    /// Verifica se há próximo exercício no plano
    func hasNextExercise(in session: CDCurrentSession) -> Bool {
        return getNextExerciseTemplate(in: session) != nil
    }
    
    /// Conta exercícios restantes no plano
    func remainingExercisesCount(in session: CDCurrentSession) -> Int {
        guard let plan = session.plan else { return 0 }
        
        let totalExercises = plan.exercisesArray.count
        let currentIndex = Int(session.currentExerciseIndex)
        
        return max(0, totalExercises - currentIndex - 1)
    }
    
    /// Obtém lista de exercícios restantes
    func getRemainingExercises(in session: CDCurrentSession) -> [CDExerciseTemplate] {
        guard let plan = session.plan else { return [] }
        
        let exercises = plan.exercisesArray
        let currentIndex = Int(session.currentExerciseIndex + 1)
        
        guard currentIndex < exercises.count else { return [] }
        
        return Array(exercises[currentIndex...]).compactMap { $0.template }
    }
} 