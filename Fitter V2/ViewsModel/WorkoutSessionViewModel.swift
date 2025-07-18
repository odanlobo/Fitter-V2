//
//  WorkoutSessionViewModel.swift
//  Fitter V2
//
//  📋 RESPONSABILIDADE: ViewModel para gerenciar estado de treino ativo
//  
//  🎯 FUNCIONALIDADES PRINCIPAIS:
//  • Controle de fluxo de treino (Start/End Workout/Exercise/Set)
//  • Estado dinâmico de exercícios e séries (1-N séries por exercício)
//  • Timer de descanso automático com ações inteligentes
//  • Dados em tempo real do Apple Watch (sensores, heart rate, calories)
//  • Navegação entre exercícios com drag-and-drop
//  • Validação de limites premium/free
//  • Sincronização bidirecional Watch ↔ iPhone
//  
//  🏗️ ARQUITETURA:
//  • Herda de BaseViewModel (estados UI, currentUser, executeUseCase)
//  • Clean Architecture: apenas Use Cases, sem acesso direto a serviços
//  • Dependency Injection: todos Use Cases via inicializador
//  • Publishers para UI reativa (@Published properties)
//  • Async/await para todas operações
//  
//  ⚡ INTEGRAÇÃO:
//  • Use Cases: Start/End Workout/Exercise/Set via DI
//  • TimerService: Rest timer e cronômetro global
//  • PhoneSessionManager: Dados em tempo real do Watch
//  • HealthKitManager: Heart rate e calories
//  • SubscriptionManager: Validação de limites premium
//  
//  🔄 FLUXO GRANULAR:
//  StartWorkout → StartExercise → StartSet → EndSet → (loop séries) → EndExercise → (loop exercícios) → EndWorkout
//
//  Created by Daniel Lobo on 15/01/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - WorkoutSessionState

/// Estados possíveis da sessão de treino
enum WorkoutSessionState {
    case idle
    case starting
    case active
    case paused
    case ending
    case completed
    case error(Error)
    
    var isActive: Bool {
        switch self {
        case .active, .paused:
            return true
        default:
            return false
        }
    }
    
    var canPause: Bool {
        return self == .active
    }
    
    var canResume: Bool {
        return self == .paused
    }
    
    var canEnd: Bool {
        switch self {
        case .active, .paused:
            return true
        default:
            return false
        }
    }
}

// MARK: - WorkoutPhase

/// Fases do treino (execução/descanso) - alinhado com WorkoutPhaseManager e MotionManager
/// 
/// 🎯 LÓGICA IMPLEMENTADA:
/// • Treino inicia → Primeira série automaticamente ativa (execution)
/// • Usuário clica timer → Finaliza série atual → Inicia timer de descanso (rest)
/// • Timer termina → Verifica séries restantes → Decisão automática
/// • Durante REST: Usuário pode adicionar séries sem problemas
/// • Pausa manual: WorkoutSessionState.paused (não afeta WorkoutPhase)
/// 
/// 🔄 DECISÃO APÓS TIMER:
/// • Há séries planejadas? → Continuar execução
/// • Mínimo 2 séries + nenhuma planejada? → Modal de decisão
/// • Menos de 2 séries? → Adicionar automaticamente e volta para execução
enum WorkoutPhase {
    case execution  // Série sendo executada, dados capturados (50Hz)
    case rest       // Timer de descanso ativo (20Hz)
    
    var displayName: String {
        switch self {
        case .execution: return "Executando"
        case .rest: return "Descansando"
        }
    }
    
    var isCapturingData: Bool {
        return self == .execution
    }
    
    var samplingRate: Double {
        switch self {
        case .execution: return 50.0  // 0.02s
        case .rest: return 20.0       // 0.05s
        }
    }
}

// MARK: - ExerciseSessionState

/// Estado de um exercício específico na sessão
struct ExerciseSessionState {
    let template: CDExerciseTemplate
    let order: Int32
    let isActive: Bool
    let isCompleted: Bool
    let currentSets: [SetSessionState]
    let totalSets: Int
    let estimatedDuration: TimeInterval
    let actualDuration: TimeInterval?
    
    var progress: Double {
        guard totalSets > 0 else { return 0 }
        return Double(currentSets.count) / Double(totalSets)
    }
    
    var displayName: String {
        return template.displayName
    }
    
    var muscleGroup: String {
        return template.muscleGroup
    }
    
    var equipment: String {
        return template.equipment
    }
}

// MARK: - SetSessionState

/// Estado de uma série específica (DTO para UI)
/// 
/// 🏗️ ARQUITETURA CLEAN:
/// • Este é um DTO (Data Transfer Object) apenas para a UI
/// • NÃO deve ser convertido para CDCurrentSet (violação de arquitetura)
/// • Use Cases gerenciam entidades Core Data diretamente
/// • ViewModel apenas observa e exibe dados
struct SetSessionState {
    let order: Int32
    let targetReps: Int32
    let actualReps: Int32?
    let weight: Double
    let duration: TimeInterval?
    let isActive: Bool
    let isCompleted: Bool
    let intensityScore: Double?
    let formGrade: String?
    

    
    var displayText: String {
        // Formato das imagens: "25.0kg × 12" (peso primeiro, depois repetições)
        let weightText = String(format: "%.1f", weight)
        let repsText = targetReps > 0 ? "\(targetReps)" : "_"
        
        if let actualReps = actualReps, actualReps > 0 && actualReps != targetReps {
            // Mostrar diferença do ML: "25.0kg × 12 (ML: 11)"
            return "\(weightText)kg × \(repsText) (ML: \(actualReps))"
        } else {
            // Formato padrão: "25.0kg × 12"
            return "\(weightText)kg × \(repsText)"
        }
    }
    
    var statusIcon: String {
        if isCompleted {
            return "checkmark.circle.fill"
        } else if isActive {
            return "circle.fill"
        } else {
            return "circle"
        }
    }
    
    var statusColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .blue
        } else {
            return .gray
        }
    }
}

// MARK: - RestTimerState

/// Estado do timer de descanso
struct RestTimerState {
    let duration: TimeInterval
    let remaining: TimeInterval
    let type: RestType
    let nextAction: String?
    let isActive: Bool
    
    enum RestType {
        case betweenSets
        case betweenExercises
        case custom
        case intelligent
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return (duration - remaining) / duration
    }
    
    var displayTime: String {
        let minutes = Int(remaining / 60)
        let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var isCompleted: Bool {
        return remaining <= 0
    }
}

// MARK: - DecisionModalState

/// Estado do modal de decisão após timer
struct DecisionModalState {
    let isVisible: Bool
    let title: String
    let message: String
    let completedSets: Int
    let exerciseName: String
    
    static let hidden = DecisionModalState(
        isVisible: false,
        title: "",
        message: "",
        completedSets: 0,
        exerciseName: ""
    )
    
    static func show(completedSets: Int, exerciseName: String) -> DecisionModalState {
        return DecisionModalState(
            isVisible: true,
            title: "Timer de descanso encerrou",
            message: "O que você quer fazer?",
            completedSets: completedSets,
            exerciseName: exerciseName
        )
    }
}

// MARK: - MissingFieldsModalState

/// Estado do modal de lembrete para campos obrigatórios
struct MissingFieldsModalState {
    let isVisible: Bool
    let title: String
    let message: String
    let missingFields: [String]
    let currentSetOrder: Int32
    let exerciseName: String
    
    static let hidden = MissingFieldsModalState(
        isVisible: false,
        title: "",
        message: "",
        missingFields: [],
        currentSetOrder: 0,
        exerciseName: ""
    )
    
    static func show(missingFields: [String], setOrder: Int32, exerciseName: String) -> MissingFieldsModalState {
        let fieldsText = missingFields.joined(separator: " e ")
        return MissingFieldsModalState(
            isVisible: true,
            title: "Dados obrigatórios não inseridos",
            message: "Insira \(fieldsText) para finalizar a série.",
            missingFields: missingFields,
            currentSetOrder: setOrder,
            exerciseName: exerciseName
        )
    }
}

// MARK: - 🆕 NOVOS ESTADOS: Modal de detecção automática e sheet de timer

/// Estado do modal de detecção automática de fim de série
struct AutoDetectionModalState {
    let isVisible: Bool
    let title: String
    let message: String
    let exerciseName: String
    let setOrder: Int32
    let timeElapsed: TimeInterval
    let detectedAt: Date
    
    static let hidden = AutoDetectionModalState(
        isVisible: false,
        title: "",
        message: "",
        exerciseName: "",
        setOrder: 0,
        timeElapsed: 0,
        detectedAt: Date()
    )
    
    static func show(exerciseName: String, setOrder: Int32, timeElapsed: TimeInterval, detectedAt: Date) -> AutoDetectionModalState {
        return AutoDetectionModalState(
            isVisible: true,
            title: "Finalizou a série?",
            message: "Inicie o timer de descanso.",
            exerciseName: exerciseName,
            setOrder: setOrder,
            timeElapsed: timeElapsed,
            detectedAt: detectedAt
        )
    }
}

/// Estado do sheet de seleção de timer
struct TimerSelectionSheetState {
    let isVisible: Bool
    let selectedDuration: TimeInterval
    let timeElapsed: TimeInterval
    let availableTimers: [TimerOption]
    
    static let hidden = TimerSelectionSheetState(
        isVisible: false,
        selectedDuration: 90, // 1:30 padrão
        timeElapsed: 0,
        availableTimers: TimerOption.defaultOptions
    )
    
    static func show(timeElapsed: TimeInterval) -> TimerSelectionSheetState {
        return TimerSelectionSheetState(
            isVisible: true,
            selectedDuration: 90,
            timeElapsed: timeElapsed,
            availableTimers: TimerOption.defaultOptions
        )
    }
}

/// Opção de timer pré-definida
struct TimerOption {
    let duration: TimeInterval
    let displayName: String
    let emoji: String
    
    static let defaultOptions: [TimerOption] = [
        TimerOption(duration: 60, displayName: "1:00", emoji: "⚡"),
        TimerOption(duration: 90, displayName: "1:30", emoji: "🏃‍♂️"),
        TimerOption(duration: 120, displayName: "2:00", emoji: "💪"),
        TimerOption(duration: 150, displayName: "2:30", emoji: "🔥"),
        TimerOption(duration: 180, displayName: "3:00", emoji: "🏋️‍♂️"),
        TimerOption(duration: 240, displayName: "4:00", emoji: "🚀"),
        TimerOption(duration: 300, displayName: "5:00", emoji: "⏰")
    ]
}

// MARK: - WorkoutSessionViewModel

/// ViewModel para gerenciar sessão de treino ativa
@MainActor
final class WorkoutSessionViewModel: BaseViewModel {
    
    // MARK: - Dependencies
    
    private let startWorkoutUseCase: StartWorkoutUseCaseProtocol
    private let endWorkoutUseCase: EndWorkoutUseCaseProtocol
    private let startExerciseUseCase: StartExerciseUseCaseProtocol
    private let endExerciseUseCase: EndExerciseUseCaseProtocol
    private let startSetUseCase: StartSetUseCaseProtocol
    private let endSetUseCase: EndSetUseCaseProtocol
    private let timerService: TimerServiceProtocol
    private let phoneSessionManager: PhoneSessionManagerProtocol
    private let healthKitManager: HealthKitManagerProtocol
    private let subscriptionManager: SubscriptionManagerProtocol
    
    // MARK: - Published Properties
    
    /// Estado geral da sessão
    @Published private(set) var sessionState: WorkoutSessionState = .idle
    
    /// Fase atual do treino (execução/descanso)
    @Published private(set) var currentPhase: WorkoutPhase = .execution
    
    /// Sessão ativa atual
    @Published private(set) var currentSession: CDCurrentSession?
    
    /// Plano de treino sendo executado
    @Published private(set) var workoutPlan: CDWorkoutPlan?
    
    /// Lista de exercícios com estado
    @Published private(set) var exercises: [ExerciseSessionState] = []
    
    /// Exercício atualmente ativo
    @Published private(set) var currentExercise: ExerciseSessionState?
    
    /// Índice do exercício atual
    @Published private(set) var currentExerciseIndex: Int = 0
    
    /// Série atualmente ativa
    @Published private(set) var currentSet: SetSessionState?
    
    /// Timer de descanso
    @Published private(set) var restTimer: RestTimerState?
    
    /// Modal de decisão após timer
    @Published private(set) var decisionModal: DecisionModalState = .hidden
    
    /// Modal de lembrete para campos obrigatórios
    @Published private(set) var missingFieldsModal: MissingFieldsModalState = .hidden
    
    /// 🆕 NOVOS MODAIS: Detecção automática e seleção de timer
    
    /// Modal de detecção automática de fim de série
    @Published private(set) var autoDetectionModal: AutoDetectionModalState = .hidden
    
    /// Sheet de seleção de timer
    @Published private(set) var timerSelectionSheet: TimerSelectionSheetState = .hidden
    
    /// Dados da última detecção automática (para controle de 10 segundos)
    @Published private(set) var lastPhaseDetection: PhaseChangeDetectionData?
    
    /// Cronômetro global do treino (HH:MM)
    @Published private(set) var workoutDuration: TimeInterval = 0
    
    /// Dados em tempo real do Apple Watch
    @Published private(set) var currentHeartRate: Double = 0
    @Published private(set) var currentCalories: Double = 0
    
    /// Localização do treino
    @Published private(set) var workoutLocation: CLLocation?
    
    /// Status de conectividade
    @Published private(set) var isWatchConnected: Bool = false
    @Published private(set) var isHealthKitActive: Bool = false
    
    /// Controle de UI
    @Published private(set) var showPauseButton: Bool = false
    @Published private(set) var showEndWorkoutButton: Bool = false
    @Published private(set) var canAddSet: Bool = false
    @Published private(set) var showRestTimerButton: Bool = false
    
    /// Limites de assinatura
    @Published private(set) var maxSetsPerExercise: Int32 = 3
    @Published private(set) var isPremium: Bool = false
    @Published private(set) var showUpgradePrompt: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var sensorDataBuffer: [SensorData] = []
    private var timerCancellable: AnyCancellable?
    private var watchDataCancellable: AnyCancellable?
    private var healthKitCancellable: AnyCancellable?
    
    /// 🆕 NOVA: Timer para controle de 10 segundos após detecção automática
    private var autoDetectionTimer: Timer?
    
    // MARK: - Initialization
    
    init(
        startWorkoutUseCase: StartWorkoutUseCaseProtocol,
        endWorkoutUseCase: EndWorkoutUseCaseProtocol,
        startExerciseUseCase: StartExerciseUseCaseProtocol,
        endExerciseUseCase: EndExerciseUseCaseProtocol,
        startSetUseCase: StartSetUseCaseProtocol,
        endSetUseCase: EndSetUseCaseProtocol,
        timerService: TimerServiceProtocol,
        phoneSessionManager: PhoneSessionManagerProtocol,
        healthKitManager: HealthKitManagerProtocol,
        subscriptionManager: SubscriptionManagerProtocol,
        coreDataService: CoreDataServiceProtocol,
        authUseCase: AuthUseCaseProtocol
    ) {
        self.startWorkoutUseCase = startWorkoutUseCase
        self.endWorkoutUseCase = endWorkoutUseCase
        self.startExerciseUseCase = startExerciseUseCase
        self.endExerciseUseCase = endExerciseUseCase
        self.startSetUseCase = startSetUseCase
        self.endSetUseCase = endSetUseCase
        self.timerService = timerService
        self.phoneSessionManager = phoneSessionManager
        self.healthKitManager = healthKitManager
        self.subscriptionManager = subscriptionManager
        
        super.init(coreDataService: coreDataService, authUseCase: authUseCase)
        
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Inicia treino com plano específico
    func startWorkout(with plan: CDWorkoutPlan) async {
        await executeUseCase {
            self.sessionState = .starting
            
            let input = StartWorkoutInput(
                plan: plan,
                user: self.currentUser,
                autoStartFirstExercise: true
            )
            
            let result = try await self.startWorkoutUseCase.execute(input)
            
            self.currentSession = result.session
            self.workoutPlan = plan
            self.sessionState = .active
            
            // Inicializar exercícios
            await self.initializeExercises(from: plan)
            
            // Iniciar cronômetro global
            self.startWorkoutTimer()
            
            // Configurar primeiro exercício
            if let firstExercise = result.firstExercise {
                await self.updateCurrentExercise(firstExercise)
            }
            
            // Iniciar primeira série automaticamente (fase execução)
            await self.startFirstSetAutomatically()
            
            // Atualizar controles de UI
            self.updateUIControls()
            
            print("✅ Treino iniciado: \(plan.displayTitle)")
        }
    }
    
    /// Finaliza treino atual
    func endWorkout() async {
        guard let session = currentSession else { return }
        
        await executeUseCase {
            self.sessionState = .ending
            
            let input = EndWorkoutInput(
                session: session,
                user: self.currentUser
            )
            
            let result = try await self.endWorkoutUseCase.execute(input)
            
            // Parar timers
            self.stopAllTimers()
            
            // Limpar estado
            self.currentSession = nil
            self.workoutPlan = nil
            self.exercises = []
            self.currentExercise = nil
            self.currentSet = nil
            self.restTimer = nil
            self.workoutDuration = 0
            
            self.sessionState = .completed
            
            print("✅ Treino finalizado - Duração: \(result.statistics.totalDuration)")
        }
    }
    
    /// Inicia próximo exercício
    func startNextExercise() async {
        guard let session = currentSession else { return }
        
        await executeUseCase {
            let result = try await self.startExerciseUseCase.executeNextExercise(
                in: session,
                user: self.currentUser
            )
            
            if let nextResult = result {
                await self.updateCurrentExercise(nextResult.exercise)
                self.currentExerciseIndex = Int(nextResult.exerciseIndex)
                self.updateUIControls()
                
                print("✅ Próximo exercício iniciado: \(nextResult.exercise.template?.displayName ?? "Unknown")")
            } else {
                // Não há mais exercícios - finalizar treino
                await self.endWorkout()
            }
        }
    }
    
    /// Adiciona nova série planejada (não executa ainda)
    func addNewSet(targetReps: Int32 = 12, weight: Double = 20.0) {
        guard let currentExercise = currentExercise else { return }
        
        // Verificar limites de assinatura
        let currentSetsCount = currentExercise.currentSets.count
        if currentSetsCount >= maxSetsPerExercise && !isPremium {
            showUpgradePrompt = true
            return
        }
        
        // Criar nova série planejada (não ativa ainda)
        let newSet = SetSessionState(
            order: Int32(currentSetsCount + 1),
            targetReps: targetReps,
            actualReps: nil,
            weight: weight,
            duration: nil,
            isActive: false,
            isCompleted: false,
            intensityScore: nil,
            formGrade: nil
        )
        
        // Adicionar à lista de séries do exercício atual
        if var updatedExercise = currentExercise {
            updatedExercise.currentSets.append(newSet)
            self.currentExercise = updatedExercise
            
            // Atualizar exercício na lista geral
            if let exerciseIndex = exercises.firstIndex(where: { $0.order == updatedExercise.order }) {
                exercises[exerciseIndex] = updatedExercise
            }
        }
        
        updateUIControls()
        
        print("✅ Nova série adicionada: \(newSet.order) - \(targetReps) × \(String(format: "%.1f", weight))kg")
    }
    
    /// Inicia série específica (executa via StartSetUseCase)
    /// - Parameter setOrder: Ordem da série a ser iniciada (1, 2, 3...)
    /// - Note: Série deve ter sido previamente planejada via addNewSet()
    func startSet(setOrder: Int32) async {
        guard let currentExercise = currentSession?.currentExercise,
              let currentSession = currentSession else { return }
        
        await executeUseCase {
            let input = StartSetInput(
                user: self.currentUser,
                exercise: currentExercise,
                session: currentSession,
                setOrder: setOrder
            )
            
            let result = try await self.startSetUseCase.execute(input)
            
            // Atualizar estado da série atual
            await self.updateCurrentSet(result.startedSet)
            
            // Entrar em fase de execução
            self.currentPhase = .execution
            
            self.updateUIControls()
            
            print("🏃‍♂️ Série iniciada: \(setOrder) - \(result.analytics.summary)")
        }
    }
    
    /// Finaliza série ativa atual (executa via EndSetUseCase)
    /// - Note: Valida weight e targetReps obrigatórios antes de finalizar
    func endCurrentSet() async {
        guard let currentSet = currentSet,
              let currentExercise = currentSession?.currentExercise else { return }
        
        // Validar campos obrigatórios
        let missingFields = validateRequiredFields(currentSet)
        if !missingFields.isEmpty {
            await showMissingFieldsModal(missingFields: missingFields)
            return
        }
        
        await executeUseCase {
            // ✅ ARQUITETURA CORRETA: Use Case busca a entidade Core Data
            let input = EndSetInput(
                user: self.currentUser,
                setOrder: currentSet.order,
                exercise: currentExercise,
                weight: currentSet.weight,
                targetReps: currentSet.targetReps,
                actualReps: currentSet.actualReps ?? 0, // ML sempre 0 se não processado
                triggerType: .manual
            )
            
            let result = try await self.endSetUseCase.execute(input)
            
            // Atualizar estado da série
            await self.updateSetState(result.finalizedSet)
            
            // Entrar em fase de descanso
            self.currentPhase = .rest
            
            // Iniciar timer de descanso
            self.startRestTimer()
            
            self.updateUIControls()
            
            print("✅ Série finalizada: \(currentSet.weight)kg × \(currentSet.targetReps) (ML: \(currentSet.actualReps ?? 0))")
        }
    }
    
    /// Usuário clicou no timer - indica que terminou a série atual
    func onRestTimerTapped() async {
        guard currentPhase == .execution else { return }
        
        // 🆕 CANCELAR DETECÇÃO AUTOMÁTICA: Usuário iniciou timer manualmente
        if autoDetectionTimer != nil {
            autoDetectionTimer?.invalidate()
            autoDetectionTimer = nil
            lastPhaseDetection = nil
            autoDetectionModal = .hidden
            print("❌ Detecção automática cancelada - usuário iniciou timer manualmente")
        }
        
        // Finalizar série atual usando a função pública
        await endCurrentSet()
        
        print("⏱️ Timer de descanso iniciado - Série finalizada")
    }
    
    /// Ação do modal: Adicionar nova série
    func onDecisionModalAddSet() async {
        decisionModal = .hidden
        
        // Adicionar nova série com valores padrão
        addNewSet()
        
        // Iniciar nova série automaticamente
        if let currentExercise = currentExercise {
            let nextSetOrder = Int32(currentExercise.currentSets.count)
            await startSet(setOrder: nextSetOrder)
        }
        
        print("➕ Nova série adicionada via modal e iniciada")
    }
    
    /// Ação do modal: Finalizar exercício e ir para próximo
    func onDecisionModalFinishExercise() async {
        decisionModal = .hidden
        
        // Finalizar exercício atual
        await finishCurrentExercise()
        
        // Ir para próximo exercício ou finalizar treino
        await startNextExercise()
        
        updateUIControls()
        print("✅ Exercício finalizado via modal")
    }
    
    /// Fechar modal sem ação
    func onDecisionModalDismiss() {
        decisionModal = .hidden
        updateUIControls()
    }
    
    /// Valida campos obrigatórios da série
    private func validateRequiredFields(_ set: SetSessionState) -> [String] {
        var missingFields: [String] = []
        
        if set.weight <= 0 {
            missingFields.append("peso")
        }
        
        if set.targetReps <= 0 {
            missingFields.append("repetições")
        }
        
        return missingFields
    }
    
    /// Mostrar modal de lembrete para campos obrigatórios
    private func showMissingFieldsModal(missingFields: [String]) async {
        guard let currentSet = currentSet,
              let currentExercise = currentExercise else { return }
        
        missingFieldsModal = MissingFieldsModalState.show(
            missingFields: missingFields,
            setOrder: currentSet.order,
            exerciseName: currentExercise.displayName
        )
        
        print("⚠️ Modal de campos obrigatórios exibido: \(missingFields.joined(separator: ", "))")
    }
    
    /// Ação do modal: Confirmar dados e finalizar série
    func onMissingFieldsConfirm() async {
        missingFieldsModal = .hidden
        
        // Tentar finalizar série novamente (usuário deve ter preenchido os campos)
        await endCurrentSet()
        
        print("✅ Tentando finalizar série após preenchimento")
    }
    
    /// Fechar modal sem ação
    func onMissingFieldsDismiss() {
        missingFieldsModal = .hidden
        updateUIControls()
    }
    
    // MARK: - 🆕 NOVAS FUNÇÕES: Detecção automática de mudança de fase
    
    /// Processa detecção automática de mudança de fase do Apple Watch
    /// - Parameter detectionData: Dados da detecção recebidos do Watch
    private func handlePhaseChangeDetection(_ detectionData: PhaseChangeDetectionData) {
        // Apenas processar se for transição execution → rest (fim de série)
        guard detectionData.isExecutionToRest else {
            print("🔄 Detecção ignorada: não é fim de série (\(detectionData.fromPhase) → \(detectionData.toPhase))")
            return
        }
        
        // Verificar se há uma série ativa (usuário não iniciou timer manualmente)
        guard let currentSet = currentSet, currentSet.isActive else {
            print("🔄 Detecção ignorada: não há série ativa")
            return
        }
        
        // Verificar se é da série atual
        guard detectionData.setOrder == currentSet.order else {
            print("🔄 Detecção ignorada: série diferente (detectada: \(detectionData.setOrder), atual: \(currentSet.order))")
            return
        }
        
        // Armazenar dados da detecção
        lastPhaseDetection = detectionData
        
        // Iniciar timer de 10 segundos
        startAutoDetectionTimer(for: detectionData)
        
        print("🔄 Detecção processada: \(detectionData.exerciseName) Set \(detectionData.setOrder) - Timer de 10s iniciado")
    }
    
    /// Inicia timer de 10 segundos após detecção automática
    /// - Parameter detectionData: Dados da detecção
    private func startAutoDetectionTimer(for detectionData: PhaseChangeDetectionData) {
        // Cancelar timer anterior se existir
        autoDetectionTimer?.invalidate()
        
        // Criar novo timer de 10 segundos
        autoDetectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                await self?.showAutoDetectionModal(for: detectionData)
            }
        }
        
        print("⏰ Timer de 10 segundos iniciado para detecção automática")
    }
    
    /// Exibe modal de detecção automática após 10 segundos
    /// - Parameter detectionData: Dados da detecção
    private func showAutoDetectionModal(for detectionData: PhaseChangeDetectionData) async {
        // Verificar se ainda há série ativa (usuário não iniciou timer manualmente)
        guard let currentSet = currentSet, currentSet.isActive else {
            print("🔄 Modal cancelado: série não está mais ativa")
            return
        }
        
        // Verificar se é ainda da mesma série
        guard detectionData.setOrder == currentSet.order else {
            print("🔄 Modal cancelado: série diferente")
            return
        }
        
        // Calcular tempo decorrido desde a detecção
        let timeElapsed = detectionData.timeElapsed()
        
        // Exibir modal
        autoDetectionModal = AutoDetectionModalState.show(
            exerciseName: detectionData.exerciseName,
            setOrder: detectionData.setOrder,
            timeElapsed: timeElapsed,
            detectedAt: detectionData.detectedAt
        )
        
        print("🤖 Modal de detecção automática exibido após 10 segundos")
    }
    
    /// Usuário confirmou que finalizou a série - iniciar timer padrão
    func onAutoDetectionStartDefaultTimer() async {
        guard let detectionData = lastPhaseDetection else { return }
        
        autoDetectionModal = .hidden
        
        // Finalizar série atual
        await endCurrentSet()
        
        // Iniciar timer de descanso com duração padrão, descontando tempo decorrido
        let timeElapsed = detectionData.timeElapsed()
        await startRestTimerWithElapsedTime(timeElapsed)
        
        print("✅ Timer padrão iniciado com tempo decorrido: \(timeElapsed)s")
    }
    
    /// Usuário quer escolher outro timer
    func onAutoDetectionChooseTimer() {
        guard let detectionData = lastPhaseDetection else { return }
        
        autoDetectionModal = .hidden
        
        // Exibir sheet de seleção de timer
        let timeElapsed = detectionData.timeElapsed()
        timerSelectionSheet = TimerSelectionSheetState.show(timeElapsed: timeElapsed)
        
        print("🎯 Sheet de seleção de timer exibido")
    }
    
    /// Usuário cancelou modal de detecção automática
    func onAutoDetectionDismiss() {
        autoDetectionModal = .hidden
        autoDetectionTimer?.invalidate()
        autoDetectionTimer = nil
        lastPhaseDetection = nil
        
        print("❌ Modal de detecção automática cancelado")
    }
    
    /// Usuário selecionou timer personalizado
    func onTimerSelectionConfirm(_ selectedDuration: TimeInterval) async {
        guard let detectionData = lastPhaseDetection else { return }
        
        timerSelectionSheet = .hidden
        
        // Finalizar série atual
        await endCurrentSet()
        
        // Iniciar timer de descanso com duração selecionada, descontando tempo decorrido
        let timeElapsed = detectionData.timeElapsed()
        await startRestTimerWithCustomDuration(selectedDuration, timeElapsed: timeElapsed)
        
        print("✅ Timer personalizado iniciado: \(selectedDuration)s com tempo decorrido: \(timeElapsed)s")
    }
    
    /// Usuário cancelou seleção de timer
    func onTimerSelectionDismiss() {
        timerSelectionSheet = .hidden
        
        print("❌ Seleção de timer cancelada")
    }
    

    
    /// Pausa treino atual
    func pauseWorkout() {
        guard sessionState == .active else { return }
        
        sessionState = .paused
        currentPhase = .execution // Pausa a fase de execução, não a fase de descanso
        
        timerService.pauseTimer(.workoutTotal)
        
        if let restTimer = restTimer, restTimer.isActive {
            timerService.pauseTimer(.restBetweenSets)
        }
        
        updateUIControls()
        print("⏸️ Treino pausado")
    }
    
    /// Retoma treino pausado
    func resumeWorkout() {
        guard sessionState == .paused else { return }
        
        sessionState = .active
        
        // Voltar para fase anterior (execução ou descanso)
        if restTimer?.isActive == true {
            currentPhase = .rest
        } else {
            currentPhase = .execution
        }
        
        timerService.resumeTimer(.workoutTotal)
        
        if let restTimer = restTimer, restTimer.isActive {
            timerService.resumeTimer(.restBetweenSets)
        }
        
        updateUIControls()
        print("▶️ Treino retomado")
    }
    
    /// Reordena exercícios (drag and drop)
    func reorderExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
        
        // TODO: Implementar reordenação no Core Data
        // Usar ReorderExerciseUseCase quando disponível
        print("🔄 Exercícios reordenados")
    }
    
    /// Pula timer de descanso
    func skipRestTimer() {
        guard let restTimer = restTimer, restTimer.isActive else { return }
        
        timerService.cancelTimer(.restBetweenSets)
        self.restTimer = nil
        
        // Processar fim do timer automaticamente
        Task {
            await processRestTimerEnd()
        }
        
        updateUIControls()
        print("⏭️ Timer de descanso pulado")
    }
    
    /// Processa dados do modelo ML para série atual
    /// - Parameter mlReps: Repetições detectadas pelo modelo ML
    func processMLData(mlReps: Int32) async {
        guard let currentSet = currentSet else { return }
        
        // Atualizar estado da série com dados do ML
        var updatedSet = currentSet
        updatedSet.actualReps = mlReps
        self.currentSet = updatedSet
        
        // Atualizar exercício na lista
        if let currentExercise = currentExercise {
            var updatedExercise = currentExercise
            if let setIndex = updatedExercise.currentSets.firstIndex(where: { $0.order == currentSet.order }) {
                updatedExercise.currentSets[setIndex] = updatedSet
                self.currentExercise = updatedExercise
            }
        }
        
        print("🤖 ML processou: \(mlReps) repetições detectadas")
    }
    
    /// Atualiza peso da série atual (editável mesmo após finalizada)
    func updateSetWeight(_ weight: Double, setOrder: Int32) {
        guard let currentExercise = currentExercise else { return }
        
        var updatedExercise = currentExercise
        if let setIndex = updatedExercise.currentSets.firstIndex(where: { $0.order == setOrder }) {
            var updatedSet = updatedExercise.currentSets[setIndex]
            updatedSet.weight = weight
            updatedExercise.currentSets[setIndex] = updatedSet
            
            // Atualizar série atual se for a mesma
            if currentSet?.order == setOrder {
                self.currentSet = updatedSet
            }
        }
        
        self.currentExercise = updatedExercise
        print("⚖️ Peso atualizado: \(weight)kg para série \(setOrder)")
    }
    
    /// Atualiza repetições da série atual (editável mesmo após finalizada)
    func updateSetTargetReps(_ reps: Int32, setOrder: Int32) {
        guard let currentExercise = currentExercise else { return }
        
        var updatedExercise = currentExercise
        if let setIndex = updatedExercise.currentSets.firstIndex(where: { $0.order == setOrder }) {
            var updatedSet = updatedExercise.currentSets[setIndex]
            updatedSet.targetReps = reps
            updatedExercise.currentSets[setIndex] = updatedSet
            
            // Atualizar série atual se for a mesma
            if currentSet?.order == setOrder {
                self.currentSet = updatedSet
            }
        }
        
        self.currentExercise = updatedExercise
        print("🔢 Repetições atualizadas: \(reps) para série \(setOrder)")
    }
    
    // MARK: - Private Methods
    
    /// Verifica se pode adicionar mais séries baseado na assinatura
    private func checkSubscriptionLimit() async -> Bool {
        guard let currentExercise = currentExercise else { return false }
        
        let currentSetsCount = currentExercise.currentSets.count
        let canAddMore = currentSetsCount < maxSetsPerExercise || isPremium
        
        if !canAddMore {
            print("⚠️ Limite de séries atingido: \(currentSetsCount)/\(maxSetsPerExercise) - Premium: \(isPremium)")
        }
        
        return canAddMore
    }
    
    /// Limpa mensagem de upgrade premium
    func clearSubscriptionLimitMessage() {
        showUpgradePrompt = false
    }
    
    private func setupSubscriptions() {
        // Subscription status
        subscriptionManager.isPremiumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPremium in
                self?.isPremium = isPremium
                self?.maxSetsPerExercise = isPremium ? Int32.max : 3
            }
            .store(in: &cancellables)
        
        // Watch connectivity
        phoneSessionManager.isReachablePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReachable in
                self?.isWatchConnected = isReachable
            }
            .store(in: &cancellables)
        
        // Real-time data from Watch
        phoneSessionManager.heartRatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heartRate in
                self?.currentHeartRate = heartRate
            }
            .store(in: &cancellables)
        
        phoneSessionManager.caloriesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] calories in
                self?.currentCalories = calories
            }
            .store(in: &cancellables)
        
        // HealthKit status
        healthKitManager.isAuthorizedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthorized in
                self?.isHealthKitActive = isAuthorized
            }
            .store(in: &cancellables)
        
        // 🆕 NOVA: Detecção automática de mudança de fase
        phoneSessionManager.phaseChangeDetectionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detectionData in
                self?.handlePhaseChangeDetection(detectionData)
            }
            .store(in: &cancellables)
    }
    
    private func initializeExercises(from plan: CDWorkoutPlan) async {
        let planExercises = plan.exercisesArray
        
        exercises = planExercises.enumerated().map { index, planExercise in
            ExerciseSessionState(
                template: planExercise.template!,
                order: Int32(index),
                isActive: index == 0,
                isCompleted: false,
                currentSets: [],
                totalSets: 3, // Estimativa padrão
                estimatedDuration: 600, // 10 minutos estimados
                actualDuration: nil
            )
        }
    }
    
    private func updateCurrentExercise(_ exercise: CDCurrentExercise) async {
        guard let template = exercise.template else { return }
        
        let sets = exercise.setsArray.map { set in
            SetSessionState(
                order: set.order,
                targetReps: set.targetReps,
                actualReps: set.actualReps > 0 ? set.actualReps : nil,
                weight: set.weight,
                duration: set.duration,
                isActive: set.isActive,
                isCompleted: set.endTime != nil,
                intensityScore: nil, // TODO: Calcular via ML
                formGrade: nil // TODO: Calcular via ML
            )
        }
        
        currentExercise = ExerciseSessionState(
            template: template,
            order: Int32(currentExerciseIndex),
            isActive: true,
            isCompleted: false,
            currentSets: sets,
            totalSets: max(sets.count, 3),
            estimatedDuration: 600,
            actualDuration: exercise.duration
        )
    }
    
    private func updateCurrentSet(_ set: CDCurrentSet) async {
        currentSet = SetSessionState(
            order: set.order,
            targetReps: set.targetReps,
            actualReps: nil,
            weight: set.weight,
            duration: nil,
            isActive: true,
            isCompleted: false,
            intensityScore: nil,
            formGrade: nil
        )
    }
    
    private func updateSetState(_ set: CDCurrentSet) async {
        currentSet = SetSessionState(
            order: set.order,
            targetReps: set.targetReps,
            actualReps: set.actualReps > 0 ? set.actualReps : nil,
            weight: set.weight,
            duration: set.duration,
            isActive: false,
            isCompleted: true,
            intensityScore: nil, // TODO: Calcular via analytics
            formGrade: nil // TODO: Calcular via analytics
        )
    }
    
    private func startWorkoutTimer() {
        timerCancellable = timerService.startTimer(.workoutTotal, duration: .infinity)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsed in
                self?.workoutDuration = elapsed
            }
    }
    
    /// Inicia primeira série automaticamente ao começar treino
    private func startFirstSetAutomatically() async {
        guard let currentExercise = currentExercise else { return }
        
        // Adicionar primeira série automaticamente
        addNewSet()
        
        // Iniciar primeira série (ordem 1)
        await startSet(setOrder: 1)
        
        print("🏃‍♂️ Primeira série iniciada automaticamente")
    }
    

    
    /// Finaliza exercício atual via Use Case
    private func finishCurrentExercise() async {
        guard let currentExercise = currentSession?.currentExercise,
              let currentSession = currentSession else { return }
        
        await executeUseCase {
            let input = EndExerciseInput(
                exercise: currentExercise,
                session: currentSession,
                user: self.currentUser
            )
            
            let result = try await self.endExerciseUseCase.execute(input)
            
            print("✅ Exercício finalizado: \(result.finalizedExercise.template?.displayName ?? "Unknown")")
        }
    }
    
    /// Inicia timer de descanso com duração padrão
    private func startRestTimer() {
        let defaultRestDuration: TimeInterval = 90 // 1:30
        
        restTimer = RestTimerState(
            duration: defaultRestDuration,
            remaining: defaultRestDuration,
            type: .betweenSets,
            nextAction: nil,
            isActive: true
        )
        
        timerCancellable = timerService.startTimer(.restBetweenSets, duration: defaultRestDuration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.restTimer?.remaining = remaining
                
                if remaining <= 0 {
                    self?.restTimer = nil
                    
                    // Processar fim do timer
                    Task {
                        await self?.processRestTimerEnd()
                    }
                }
            }
    }
    
    /// 🆕 NOVA: Inicia timer de descanso com duração padrão, descontando tempo decorrido
    /// - Parameter timeElapsed: Tempo já decorrido desde a detecção
    private func startRestTimerWithElapsedTime(_ timeElapsed: TimeInterval) async {
        let defaultRestDuration: TimeInterval = 90 // 1:30
        let adjustedDuration = max(10, defaultRestDuration - timeElapsed) // Mínimo 10s
        
        restTimer = RestTimerState(
            duration: defaultRestDuration,
            remaining: adjustedDuration,
            type: .betweenSets,
            nextAction: nil,
            isActive: true
        )
        
        timerCancellable = timerService.startTimer(.restBetweenSets, duration: adjustedDuration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.restTimer?.remaining = remaining
                
                if remaining <= 0 {
                    self?.restTimer = nil
                    
                    // Processar fim do timer
                    Task {
                        await self?.processRestTimerEnd()
                    }
                }
            }
        
        print("⏱️ Timer de descanso iniciado: \(adjustedDuration)s (padrão: \(defaultRestDuration)s - decorrido: \(timeElapsed)s)")
    }
    
    /// 🆕 NOVA: Inicia timer de descanso com duração personalizada, descontando tempo decorrido
    /// - Parameters:
    ///   - duration: Duração total selecionada pelo usuário
    ///   - timeElapsed: Tempo já decorrido desde a detecção
    private func startRestTimerWithCustomDuration(_ duration: TimeInterval, timeElapsed: TimeInterval) async {
        let adjustedDuration = max(10, duration - timeElapsed) // Mínimo 10s
        
        restTimer = RestTimerState(
            duration: duration,
            remaining: adjustedDuration,
            type: .betweenSets,
            nextAction: nil,
            isActive: true
        )
        
        timerCancellable = timerService.startTimer(.restBetweenSets, duration: adjustedDuration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.restTimer?.remaining = remaining
                
                if remaining <= 0 {
                    self?.restTimer = nil
                    
                    // Processar fim do timer
                    Task {
                        await self?.processRestTimerEnd()
                    }
                }
            }
        
        print("⏱️ Timer personalizado iniciado: \(adjustedDuration)s (selecionado: \(duration)s - decorrido: \(timeElapsed)s)")
    }
    
    /// Processa fim do timer de descanso
    private func processRestTimerEnd() async {
        guard let currentExercise = currentExercise else { return }
        
        let completedSets = currentExercise.currentSets.filter { $0.isCompleted }.count
        let plannedSets = currentExercise.currentSets.count
        let hasPlannedSets = plannedSets > completedSets
        
        if hasPlannedSets {
            // Há séries planejadas - iniciar próxima série
            let nextSetOrder = Int32(completedSets + 1)
            await startSet(setOrder: nextSetOrder)
            print("▶️ Iniciando próxima série planejada: \(nextSetOrder)")
        } else if completedSets >= 1 {
            // Mínimo 1 série feita e nenhuma planejada - mostrar modal
            decisionModal = DecisionModalState.show(
                completedSets: completedSets,
                exerciseName: currentExercise.displayName
            )
            print("🤔 Modal de decisão exibido")
        } else {
            // Menos de 1 série - adicionar automaticamente e iniciar execução
            addNewSet()
            let nextSetOrder = Int32(currentExercise.currentSets.count)
            await startSet(setOrder: nextSetOrder)
            print("➕ Série adicionada automaticamente (mínimo 2) - iniciando execução")
        }
        
        updateUIControls()
    }
    
    private func stopAllTimers() {
        timerService.cancelTimer(.workoutTotal)
        timerService.cancelTimer(.restBetweenSets)
        timerCancellable?.cancel()
        timerCancellable = nil
        
        // 🆕 LIMPEZA: Cancelar timer de detecção automática
        autoDetectionTimer?.invalidate()
        autoDetectionTimer = nil
        lastPhaseDetection = nil
        autoDetectionModal = .hidden
        timerSelectionSheet = .hidden
    }
    

    

    
    private func updateUIControls() {
        showPauseButton = sessionState.canPause
        showEndWorkoutButton = sessionState.canEnd
        
        // Controles baseados na fase atual
        switch currentPhase {
        case .execution:
            showRestTimerButton = true
            canAddSet = true
            
        case .rest:
            showRestTimerButton = false
            canAddSet = true // ✅ PERMITE adicionar séries durante o timer de descanso
        }
        
        // Validar limites de assinatura para adicionar séries
        if let currentExercise = currentExercise {
            let currentSetsCount = currentExercise.currentSets.count
            canAddSet = canAddSet && (currentSetsCount < maxSetsPerExercise || isPremium)
        }
    }
}

// MARK: - Computed Properties

extension WorkoutSessionViewModel {
    
    /// Progresso geral do treino (0-1)
    var workoutProgress: Double {
        guard !exercises.isEmpty else { return 0 }
        
        let completedExercises = exercises.filter { $0.isCompleted }.count
        let currentExerciseProgress = currentExercise?.progress ?? 0
        
        return (Double(completedExercises) + currentExerciseProgress) / Double(exercises.count)
    }
    
    /// Tempo total formatado (HH:MM)
    var formattedWorkoutDuration: String {
        let hours = Int(workoutDuration / 3600)
        let minutes = Int((workoutDuration.truncatingRemainder(dividingBy: 3600)) / 60)
        return String(format: "%02d:%02d", hours, minutes)
    }
    
    /// Exercícios restantes
    var remainingExercises: Int {
        return exercises.count - currentExerciseIndex - 1
    }
    
    /// Séries totais completadas
    var totalCompletedSets: Int {
        return exercises.reduce(0) { total, exercise in
            total + exercise.currentSets.filter { $0.isCompleted }.count
        }
    }
    
    /// Pode finalizar treino
    var canEndWorkout: Bool {
        return sessionState.canEnd && totalCompletedSets > 0
    }
}

// MARK: - Preview Support

#if DEBUG
extension WorkoutSessionViewModel {
    
    static func preview() -> WorkoutSessionViewModel {
        // TODO: Implementar quando MockUseCases estiverem disponíveis
        fatalError("Preview não implementado - aguardando MockUseCases")
    }
}
#endif 