/*
 * CreateWorkoutUseCase.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Use Case para criação de novos planos de treino.
 *                   Implementa Clean Architecture com orquestração de operações de persistência e sincronização.
 *
 * ARQUITETURA:
 * - Orquestra WorkoutDataService (persistência local)
 * - Orquestra SyncWorkoutUseCase (sincronização remota)
 * - NÃO acessa Core Data diretamente
 * - NÃO contém lógica de UI
 *
 * DEPENDÊNCIAS:
 * - WorkoutDataServiceProtocol: CRUD de planos de treino
 * - SyncWorkoutUseCaseProtocol: Sincronização remota (item 23)
 *
 * FLUXO DE EXECUÇÃO:
 * 1. Validação de entrada
 * 2. Geração do título automático (sempre)
 * 3. Criação via WorkoutDataService (autoTitle + customTitle opcional)
 * 4. Sincronização via SyncWorkoutUseCase
 * 5. Retorno do resultado
 *
 * SISTEMA DUAL DE TÍTULOS:
 * - autoTitle: Sempre "Treino A", "Treino B", "Treino A1"... (sistemático, não editável)
 * - customTitle: Totalmente livre - "Peitoral Heavy", "Push Day"... (sem palavra "Treino")
 * - Exibição: "Peitoral Heavy (Treino A)" ou apenas "Treino A"
 *
 * EXEMPLOS PRÁTICOS:
 * - 1º treino sem customização → autoTitle: "Treino A" → displayTitle: "Treino A"
 * - 2º treino com "Peitoral Heavy" → autoTitle: "Treino B" → displayTitle: "Peitoral Heavy (Treino B)"
 * - 27º treino com "Leg Killer" → autoTitle: "Treino A1" → displayTitle: "Leg Killer (Treino A1)"
 * 
 * GERAÇÃO AUTOMÁTICA DE TÍTULOS:
 * - Lógica melhorada baseada no CreateWorkoutView
 * - Treino A, B, C... até Z (26 primeiros)
 * - Treino A1, B1, C1... Z1 (27º ao 52º)
 * - Treino A2, B2, C2... Z2 (53º ao 78º)
 * - Padrão infinito: Letter + Cycle Number
 * - Fallback com timestamp em caso de erro
 *
 * PADRÕES:
 * - Protocol + Implementation para testabilidade
 * - Dependency Injection via inicializador
 * - Error handling específico do domínio
 * - Async/await para operações assíncronas
 *
 * REFATORAÇÃO ITEM 17/47:
 * ✅ Use Case de criação com orquestração
 * ✅ Injeção de WorkoutDataService
 * ✅ Preparado para SyncWorkoutUseCase (item 23)
 * ✅ Clean Architecture - sem acesso direto ao Core Data
 * ✅ Tratamento de erros específicos do domínio
 * ✅ ITEM 66: Bloqueio de funcionalidades premium - limite de 4 treinos para usuários free
 */

import Foundation

// MARK: - CreateWorkoutError

enum CreateWorkoutError: Error, LocalizedError {
    case invalidInput(String)
    case workoutLimitExceeded(limit: Int, current: Int)
    case subscriptionRequired(feature: String)
    case creationFailed(Error)
    case syncFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Dados inválidos para criação do treino: \(message)"
        case .workoutLimitExceeded(let limit, let current):
            return "Limite de treinos excedido: \(current)/\(limit). Faça upgrade para Premium para treinos ilimitados."
        case .subscriptionRequired(let feature):
            return "Recurso premium necessário: \(feature). Faça upgrade para continuar."
        case .creationFailed(let error):
            return "Falha na criação do treino: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Falha na sincronização do treino: \(error.localizedDescription)"
        }
    }
}

// MARK: - CreateWorkoutInput

struct CreateWorkoutInput {
    let title: String?  // Título TOTALMENTE LIVRE - "Peitoral Heavy", "Push Day"... (opcional)
    let muscleGroups: String?
    let user: CDAppUser  // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    let exerciseTemplates: [CDExerciseTemplate]
    
    /// Validação dos dados de entrada
    func validate() throws {
        // Se título personalizado fornecido, validar (pode ser qualquer coisa)
        if let title = title {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CreateWorkoutError.invalidInput("Título personalizado não pode estar vazio")
            }
            
            guard title.count <= 50 else {
                throw CreateWorkoutError.invalidInput("Título personalizado não pode ter mais de 50 caracteres")
            }
        }
        
        guard !exerciseTemplates.isEmpty else {
            throw CreateWorkoutError.invalidInput("Treino deve conter pelo menos um exercício")
        }
        
        guard exerciseTemplates.count <= 20 else {
            throw CreateWorkoutError.invalidInput("Treino não pode ter mais de 20 exercícios")
        }
    }
}

// MARK: - CreateWorkoutOutput

struct CreateWorkoutOutput {
    let workoutPlan: CDWorkoutPlan
    let planExercises: [CDPlanExercise]
    let syncStatus: CreateWorkoutSyncStatus
}

enum CreateWorkoutSyncStatus {
    case synced
    case pending
    case failed(Error)
    case disabled // Quando SyncWorkoutUseCase não está disponível
}

// MARK: - CreateWorkoutUseCaseProtocol

protocol CreateWorkoutUseCaseProtocol {
    func execute(_ input: CreateWorkoutInput) async throws -> CreateWorkoutOutput
}

// SyncWorkoutUseCaseProtocol removed - now using real implementation from item 23

// MARK: - CreateWorkoutUseCase

final class CreateWorkoutUseCase: CreateWorkoutUseCaseProtocol {
    
    // MARK: - Properties
    
    private let workoutDataService: WorkoutDataServiceProtocol
    private let subscriptionManager: SubscriptionManagerProtocol
    private let syncUseCase: SyncWorkoutUseCaseProtocol?
    
    // MARK: - Initialization
    
    init(
        workoutDataService: WorkoutDataServiceProtocol,
        subscriptionManager: SubscriptionManagerProtocol,
        syncUseCase: SyncWorkoutUseCaseProtocol? = nil // Optional for testing - should be provided in production
    ) {
        self.workoutDataService = workoutDataService
        self.subscriptionManager = subscriptionManager
        self.syncUseCase = syncUseCase
        
        print("🏋️‍♂️ CreateWorkoutUseCase inicializado")
    }
    
    // MARK: - Public Methods
    
    func execute(_ input: CreateWorkoutInput) async throws -> CreateWorkoutOutput {
        let titleDisplay = input.title ?? "automático"
        print("🆕 Iniciando criação de treino: \(titleDisplay)")
        
        do {
            // 1. Validar entrada
            try input.validate()
            print("✅ Validação de entrada concluída")
            
            // 2. Validar limite de treinos
            try await validateWorkoutLimit(for: input.user)
            print("✅ Validação de limite de treinos concluída")
            
            // 3. Criar plano de treino via WorkoutDataService
            let workoutPlan = try await createWorkoutPlan(input)
            print("✅ Plano de treino criado: \(workoutPlan.displayTitle)")
            
            // 4. Adicionar exercícios ao plano
            let planExercises = try await addExercisesToPlan(workoutPlan, exercises: input.exerciseTemplates)
            print("✅ \(planExercises.count) exercícios adicionados ao plano")
            
            // 5. Tentar sincronização (se disponível)
            let syncStatus = await attemptSync(workoutPlan)
            
            let output = CreateWorkoutOutput(
                workoutPlan: workoutPlan,
                planExercises: planExercises,
                syncStatus: syncStatus
            )
            
            print("🎉 Treino criado com sucesso: \(workoutPlan.displayTitle)")
            return output
            
        } catch let error as CreateWorkoutError {
            print("❌ Erro na criação do treino: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Erro inesperado na criação do treino: \(error)")
            throw CreateWorkoutError.creationFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createWorkoutPlan(_ input: CreateWorkoutInput) async throws -> CDWorkoutPlan {
        do {
            // Gerar título automático baseado na quantidade de planos
            let autoTitle = try await generateAutoTitleForUser(input.user)
            
            return try await workoutDataService.createWorkoutPlan(
                autoTitle: autoTitle,
                customTitle: input.title,
                muscleGroups: input.muscleGroups,
                user: input.user
            )
        } catch {
            throw CreateWorkoutError.creationFailed(error)
        }
    }
    
    /// Gera título automático para o usuário baseado na quantidade de planos existentes
    /// Mantém a lógica robusta: Treino A, B, C... A1, B1, C1...
    private func generateAutoTitleForUser(_ user: CDAppUser) async throws -> String {
        do {
            let existingPlans = try await workoutDataService.fetchWorkoutPlans(for: user)
            return generateAutomaticTitle(basedOnCount: existingPlans.count)
        } catch {
            print("⚠️ Erro ao buscar planos existentes para geração de título automático: \(error)")
            // Fallback: usar timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM HH:mm"
            return "Treino \(formatter.string(from: Date()))"
        }
    }
    
    /// Gera título automático seguindo a lógica melhorada
    /// Treino A, B, C... até Z, depois Treino A1, B1, C1... Z1, A2, B2...
    private func generateAutomaticTitle(basedOnCount count: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        
        if count < letters.count {
            // Primeiros 26: A, B, C... Z
            return "Treino \(letters[count])"
        } else {
            // A partir do 27º: A1, B1, C1... Z1, A2, B2...
            let cycle = (count - letters.count) / letters.count + 1  // 1, 2, 3...
            let letterIndex = (count - letters.count) % letters.count // 0, 1, 2... 25, 0, 1...
            return "Treino \(letters[letterIndex])\(cycle)"
        }
    }
    
    private func addExercisesToPlan(_ plan: CDWorkoutPlan, exercises: [CDExerciseTemplate]) async throws -> [CDPlanExercise] {
        var planExercises: [CDPlanExercise] = []
        
        for (index, exercise) in exercises.enumerated() {
            do {
                let planExercise = try await workoutDataService.addExerciseTemplate(
                    exercise,
                    to: plan,
                    order: Int32(index)
                )
                planExercises.append(planExercise)
            } catch {
                // Se falhar, tentar limpar exercícios já adicionados
                await cleanupPartialCreation(planExercises)
                throw CreateWorkoutError.creationFailed(error)
            }
        }
        
        return planExercises
    }
    
    private func attemptSync(_ workoutPlan: CDWorkoutPlan) async -> CreateWorkoutSyncStatus {
        guard let syncUseCase = syncUseCase else {
            print("⚠️ SyncWorkoutUseCase não disponível - sincronização desabilitada")
            return .disabled
        }
        
        do {
            try await syncUseCase.execute(workoutPlan)
            print("☁️ Treino sincronizado com sucesso")
            return .synced
        } catch {
            print("⚠️ Falha na sincronização do treino: \(error)")
            return .failed(error)
        }
    }
    
    /// Valida limite de treinos para usuários free
    /// ✅ Implementação do item 66 - bloqueio de funcionalidades premium
    private func validateWorkoutLimit(for user: CDAppUser) async throws {
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin para desenvolvimento
        // Verificar se é usuário admin primeiro
        if await subscriptionManager.isAdminUser(user) {
            print("👑 [CREATE] Usuário admin detectado: treinos ilimitados")
            return
        }
        
        // ✅ Verificar status premium via SubscriptionManager
        let status = await subscriptionManager.getSubscriptionStatus(for: user)
        
        switch status {
        case .active(let type, _):
            if type != .none {
                print("💎 [CREATE] Usuário premium: treinos ilimitados")
                return  // Premium: ilimitado
            }
        case .gracePeriod(let type, _):
            if type != .none {
                print("⏰ [CREATE] Usuário em grace period: treinos ilimitados")
                return  // Grace period: manter benefícios
            }
        case .expired, .none:
            // Continuar para verificar limite
            break
        }
        
        // ✅ Usuário free: verificar limite de 4 treinos
        do {
            let existingPlans = try await workoutDataService.fetchWorkoutPlans(for: user)
            let currentCount = existingPlans.count
            let maxWorkouts = 4
            
            if currentCount >= maxWorkouts {
                print("🚫 [CREATE] Limite de treinos atingido: \(currentCount)/\(maxWorkouts)")
                throw CreateWorkoutError.workoutLimitExceeded(limit: maxWorkouts, current: currentCount)
            }
            
            print("✅ [CREATE] Limite de treinos OK: \(currentCount)/\(maxWorkouts)")
        } catch let error as CreateWorkoutError {
            throw error
        } catch {
            print("⚠️ [CREATE] Erro ao verificar limite de treinos: \(error)")
            throw CreateWorkoutError.creationFailed(error)
        }
    }
    
    /// Sistema de admin movido para SubscriptionManager.isAdminUser() para evitar duplicação
    /// ✅ Para desenvolvimento e testes sem limitações
    /// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
    
    private func cleanupPartialCreation(_ planExercises: [CDPlanExercise]) async {
        print("🧹 Limpando criação parcial de exercícios...")
        
        for planExercise in planExercises {
            do {
                try await workoutDataService.removePlanExercise(planExercise, from: planExercise.plan!)
            } catch {
                print("⚠️ Erro na limpeza do exercício: \(error)")
            }
        }
    }
}

// MARK: - Extension for Convenience

extension CreateWorkoutUseCase {
    
    /// Método de conveniência para criação rápida de treino
    /// ✅ Inclui validação automática de limite de treinos (item 66)
    /// - Parameter title: Título do treino (opcional - se nil, gera automaticamente)
    func createQuickWorkout(
        title: String? = nil,
        exercises: [CDExerciseTemplate],
        user: CDAppUser // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    ) async throws -> CreateWorkoutOutput {
        let input = CreateWorkoutInput(
            title: title,
            muscleGroups: generateMuscleGroups(from: exercises),
            user: user,
            exerciseTemplates: exercises
        )
        
        return try await execute(input)
    }
    
    /// Método de conveniência para criação automática de treino (título gerado automaticamente)
    /// ✅ Inclui validação automática de limite de treinos (item 66)
    func createAutoWorkout(
        exercises: [CDExerciseTemplate],
        user: CDAppUser // ✅ LOGIN OBRIGATÓRIO - BaseViewModel.currentUser nunca nil
    ) async throws -> CreateWorkoutOutput {
        return try await createQuickWorkout(
            title: nil, // Força geração automática
            exercises: exercises,
            user: user
        )
    }
    
    private func generateMuscleGroups(from exercises: [CDExerciseTemplate]) -> String {
        let muscleGroups = Set(exercises.compactMap { $0.muscleGroup })
        return muscleGroups.sorted().joined(separator: ", ")
    }
}

// MARK: - Exemplos de Uso

/*
 EXEMPLOS PRÁTICOS DE USO:

 // 1. Treino automático (sem personalização)
 let auto = try await createWorkoutUseCase.execute(CreateWorkoutInput(
     title: nil,  // ← Sem customização
     muscleGroups: nil,
     user: currentUser,  // ← LOGIN OBRIGATÓRIO: BaseViewModel.currentUser nunca nil
     exerciseTemplates: chestExercises
 ))
 // Resultado: autoTitle = "Treino A", displayTitle = "Treino A"

 // 2. Treino personalizado  
 let custom = try await createWorkoutUseCase.execute(CreateWorkoutInput(
     title: "Peitoral Heavy",  // ← Título livre, sem "Treino"
     muscleGroups: nil,
     user: currentUser,  // ← LOGIN OBRIGATÓRIO: BaseViewModel.currentUser nunca nil
     exerciseTemplates: chestExercises
 ))
 // Resultado: autoTitle = "Treino B", customTitle = "Peitoral Heavy", displayTitle = "Peitoral Heavy (Treino B)"

 // 3. Método de conveniência
 let quick = try await createWorkoutUseCase.createQuickWorkout(
     title: "Leg Killer",
     exercises: legExercises,
     user: currentUser  // ← LOGIN OBRIGATÓRIO: BaseViewModel.currentUser nunca nil
 )
 // Resultado: autoTitle = "Treino C", customTitle = "Leg Killer", displayTitle = "Leg Killer (Treino C)"

 // 4. Exibição nas Views
 Text(workoutPlan.displayTitle)    // "Peitoral Heavy (Treino B)" ou "Treino A"
 Text(workoutPlan.compactTitle)    // "Peitoral Heavy" ou "Treino A"
 Text(workoutPlan.safeAutoTitle)   // Sempre "Treino X" (para organização)
 
 if workoutPlan.hasCustomTitle {
     // Mostrar ícone de personalização
 }
 */ 