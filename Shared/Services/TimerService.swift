import Foundation
import Combine
import WatchConnectivity

// MARK: - Protocols

/// Protocolo para facilitar testes e mocks do TimerService
protocol TimerServiceProtocol {
    /// Publisher para mudanças de estado do timer
    var timerStatePublisher: AnyPublisher<TimerState, Never> { get }
    
    /// Publisher para mudanças de tempo restante
    var timeRemainingPublisher: AnyPublisher<TimeInterval, Never> { get }
    
    /// Publisher para notificações de timer
    var timerNotificationPublisher: AnyPublisher<TimerNotification, Never> { get }
    
    /// Inicia um timer específico
    func startTimer(type: TimerType, duration: TimeInterval, autoAction: TimerAutoAction?) async throws
    
    /// Pausa o timer ativo
    func pauseTimer() async throws
    
    /// Retoma o timer pausado
    func resumeTimer() async throws
    
    /// Cancela o timer ativo
    func cancelTimer() async throws
    
    /// Obtém o estado atual do timer
    func getCurrentState() -> TimerState
    
    /// Obtém o tempo restante do timer ativo
    func getTimeRemaining() -> TimeInterval
    
    /// Configura notificações para o timer
    func configureNotifications(enabled: Bool, sound: Bool, haptic: Bool) async throws
    
    /// Sincroniza timer com Apple Watch
    func syncWithWatch(command: WatchTimerCommand) async throws
    
    /// Recebe comando de timer do Apple Watch
    func receiveWatchCommand(_ command: WatchTimerCommand) async throws
}

// MARK: - Enums

/// Tipos de timer suportados pelo app
enum TimerType: String, CaseIterable {
    case setDuration = "set_duration"           // Duração de série
    case restTimer = "rest_timer"               // Descanso entre séries
    case exerciseRest = "exercise_rest"         // Descanso entre exercícios
    case workoutTotal = "workout_total"         // Tempo total do treino
    case inactivity = "inactivity"              // Inatividade do usuário
    case timeout = "timeout"                    // Timeout por inatividade
    
    /// Nome de exibição do timer
    var displayName: String {
        switch self {
        case .setDuration: return "Duração da Série"
        case .restTimer: return "Descanso"
        case .exerciseRest: return "Descanso entre Exercícios"
        case .workoutTotal: return "Tempo Total"
        case .inactivity: return "Inatividade"
        case .timeout: return "Timeout"
        }
    }
    
    /// Duração padrão em segundos
    var defaultDuration: TimeInterval {
        switch self {
        case .setDuration: return 0 // Sem limite
        case .restTimer: return 90 // 1:30
        case .exerciseRest: return 180 // 3:00
        case .workoutTotal: return 0 // Sem limite
        case .inactivity: return 604800 // 7 dias
        case .timeout: return 300 // 5 minutos
        }
    }
}

/// Estado atual do timer
enum TimerState: Equatable {
    case idle
    case running(remaining: TimeInterval, type: TimerType)
    case paused(remaining: TimeInterval, type: TimerType)
    case completed(type: TimerType, autoAction: TimerAutoAction?)
    
    /// Verifica se o timer está ativo
    var isActive: Bool {
        switch self {
        case .running, .paused: return true
        case .idle, .completed: return false
        }
    }
    
    /// Obtém o tempo restante
    var timeRemaining: TimeInterval {
        switch self {
        case .running(let remaining, _), .paused(let remaining, _):
            return remaining
        case .idle, .completed:
            return 0
        }
    }
    
    /// Obtém o tipo do timer
    var timerType: TimerType? {
        switch self {
        case .running(_, let type), .paused(_, let type), .completed(let type, _):
            return type
        case .idle:
            return nil
        }
    }
}

/// Ação automática após conclusão do timer
enum TimerAutoAction: String, CaseIterable {
    case nextSet = "next_set"
    case nextExercise = "next_exercise"
    case endWorkout = "end_workout"
    case waitForUser = "wait_for_user"
    case addSeries = "add_series"           // 🆕 Propor adicionar série
    case completeExercise = "complete_exercise" // 🆕 Propor completar exercício
    case none = "none"
    
    /// Nome de exibição da ação
    var displayName: String {
        switch self {
        case .nextSet: return "Próxima Série"
        case .nextExercise: return "Próximo Exercício"
        case .endWorkout: return "Finalizar Treino"
        case .waitForUser: return "Aguardar Usuário"
        case .addSeries: return "Adicionar Série"        // 🆕
        case .completeExercise: return "Completar Exercício" // 🆕
        case .none: return "Nenhuma Ação"
        }
    }
}

/// Notificação de timer
enum TimerNotification: Equatable {
    case started(type: TimerType, duration: TimeInterval)
    case paused(type: TimerType, remaining: TimeInterval)
    case resumed(type: TimerType, remaining: TimeInterval)
    case cancelled(type: TimerType)
    case completed(type: TimerType, autoAction: TimerAutoAction?)
    case warning(type: TimerType, remaining: TimeInterval) // 10s restantes
    case error(TimerServiceError)
}

/// Comandos de timer para Apple Watch
enum WatchTimerCommand: String, CaseIterable {
    case start = "start"
    case pause = "pause"
    case resume = "resume"
    case cancel = "cancel"
    case sync = "sync"
    
    /// Converte para dicionário para envio via WCSession
    func toDictionary(type: TimerType, duration: TimeInterval? = nil, autoAction: TimerAutoAction? = nil) -> [String: Any] {
        var dict: [String: Any] = ["command": rawValue, "type": type.rawValue]
        if let duration = duration {
            dict["duration"] = duration
        }
        if let autoAction = autoAction {
            dict["autoAction"] = autoAction.rawValue
        }
        return dict
    }
    
    /// Cria comando a partir de dicionário recebido
    static func fromDictionary(_ dict: [String: Any]) -> WatchTimerCommand? {
        guard let commandString = dict["command"] as? String,
              let command = WatchTimerCommand(rawValue: commandString) else {
            return nil
        }
        return command
    }
}

// MARK: - Error Handling

/// Erros específicos do TimerService
enum TimerServiceError: LocalizedError {
    case timerAlreadyRunning
    case timerNotRunning
    case invalidDuration
    case invalidTimerType
    case watchNotReachable
    case watchSyncFailed
    case notificationError
    case internalError
    
    var errorDescription: String? {
        switch self {
        case .timerAlreadyRunning:
            return "Timer já está em execução"
        case .timerNotRunning:
            return "Nenhum timer está em execução"
        case .invalidDuration:
            return "Duração inválida para o timer"
        case .invalidTimerType:
            return "Tipo de timer inválido"
        case .watchNotReachable:
            return "Apple Watch não está conectado"
        case .watchSyncFailed:
            return "Falha na sincronização com Apple Watch"
        case .notificationError:
            return "Erro ao configurar notificações"
        case .internalError:
            return "Erro interno do TimerService"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .timerAlreadyRunning:
            return "Cancele o timer atual antes de iniciar um novo"
        case .timerNotRunning:
            return "Inicie um timer antes de tentar pausá-lo"
        case .invalidDuration:
            return "Use uma duração maior que zero"
        case .invalidTimerType:
            return "Use um tipo de timer válido"
        case .watchNotReachable:
            return "Verifique a conexão com o Apple Watch"
        case .watchSyncFailed:
            return "Tente novamente em alguns segundos"
        case .notificationError:
            return "Verifique as permissões de notificação"
        case .internalError:
            return "Reinicie o app e tente novamente"
        }
    }
}

// MARK: - Timer Controller

/// Controlador individual para cada timer
private class TimerController {
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var timerType: TimerType
    private var autoAction: TimerAutoAction?
    private var isPaused: Bool = false
    
    // Publishers
    private let stateSubject = CurrentValueSubject<TimerState, Never>(.idle)
    private let timeRemainingSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let notificationSubject = PassthroughSubject<TimerNotification, Never>()
    
    var statePublisher: AnyPublisher<TimerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    var timeRemainingPublisher: AnyPublisher<TimeInterval, Never> {
        timeRemainingSubject.eraseToAnyPublisher()
    }
    
    var notificationPublisher: AnyPublisher<TimerNotification, Never> {
        notificationSubject.eraseToAnyPublisher()
    }
    
    init(type: TimerType) {
        self.timerType = type
    }
    
    func start(duration: TimeInterval, autoAction: TimerAutoAction?) async throws {
        guard !isActive else {
            throw TimerServiceError.timerAlreadyRunning
        }
        
        guard duration > 0 else {
            throw TimerServiceError.invalidDuration
        }
        
        self.duration = duration
        self.autoAction = autoAction
        self.startTime = Date()
        self.pausedTime = 0
        self.isPaused = false
        
        // Atualizar estado
        let state = TimerState.running(remaining: duration, type: timerType)
        stateSubject.send(state)
        timeRemainingSubject.send(duration)
        
        // Enviar notificação
        notificationSubject.send(.started(type: timerType, duration: duration))
        
        // Iniciar timer
        startTimer()
        
        print("⏱️ [TIMER] Iniciado \(timerType.displayName) - \(duration)s")
    }
    
    func pause() async throws {
        guard isActive else {
            throw TimerServiceError.timerNotRunning
        }
        
        timer?.invalidate()
        timer = nil
        
        if let startTime = startTime {
            let elapsed = Date().timeIntervalSince(startTime) - pausedTime
            let remaining = max(0, duration - elapsed)
            
            self.pausedTime = elapsed
            self.isPaused = true
            
            let state = TimerState.paused(remaining: remaining, type: timerType)
            stateSubject.send(state)
            timeRemainingSubject.send(remaining)
            
            notificationSubject.send(.paused(type: timerType, remaining: remaining))
            
            print("⏸️ [TIMER] Pausado \(timerType.displayName) - \(remaining)s restantes")
        }
    }
    
    func resume() async throws {
        guard isPaused else {
            throw TimerServiceError.timerNotRunning
        }
        
        self.isPaused = false
        
        if let startTime = startTime {
            let elapsed = Date().timeIntervalSince(startTime) - pausedTime
            let remaining = max(0, duration - elapsed)
            
            let state = TimerState.running(remaining: remaining, type: timerType)
            stateSubject.send(state)
            timeRemainingSubject.send(remaining)
            
            notificationSubject.send(.resumed(type: timerType, remaining: remaining))
            
            startTimer()
            
            print("▶️ [TIMER] Retomado \(timerType.displayName) - \(remaining)s restantes")
        }
    }
    
    func cancel() async throws {
        guard isActive else {
            throw TimerServiceError.timerNotRunning
        }
        
        timer?.invalidate()
        timer = nil
        
        let state = TimerState.idle
        stateSubject.send(state)
        timeRemainingSubject.send(0)
        
        notificationSubject.send(.cancelled(type: timerType))
        
        // Resetar estado
        self.startTime = nil
        self.pausedTime = 0
        self.isPaused = false
        
        print("❌ [TIMER] Cancelado \(timerType.displayName)")
    }
    
    func getCurrentState() -> TimerState {
        return stateSubject.value
    }
    
    func getTimeRemaining() -> TimeInterval {
        return timeRemainingSubject.value
    }
    
    private var isActive: Bool {
        return stateSubject.value.isActive
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    private func updateTimer() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime) - pausedTime
        let remaining = max(0, duration - elapsed)
        
        timeRemainingSubject.send(remaining)
        
        // Verificar se timer completou
        if remaining <= 0 {
            completeTimer()
        } else if remaining <= 10 {
            // Aviso de 10 segundos restantes
            notificationSubject.send(.warning(type: timerType, remaining: remaining))
        }
    }
    
    private func completeTimer() {
        timer?.invalidate()
        timer = nil
        
        let state = TimerState.completed(type: timerType, autoAction: autoAction)
        stateSubject.send(state)
        timeRemainingSubject.send(0)
        
        notificationSubject.send(.completed(type: timerType, autoAction: autoAction))
        
        // Resetar estado
        self.startTime = nil
        self.pausedTime = 0
        self.isPaused = false
        
        print("✅ [TIMER] Concluído \(timerType.displayName) - Ação: \(autoAction?.displayName ?? "Nenhuma")")
    }
}

// MARK: - TimerService Implementation

/// Serviço centralizado para gerenciamento de todos os timers do app
final class TimerService: TimerServiceProtocol {
    
    // MARK: - Properties
    
    private var controllers: [TimerType: TimerController] = [:]
    private var watchSessionManager: WatchSessionManagerProtocol?
    private var phoneSessionManager: PhoneSessionManagerProtocol?
    
    // Publishers
    private let stateSubject = CurrentValueSubject<TimerState, Never>(.idle)
    private let timeRemainingSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let notificationSubject = PassthroughSubject<TimerNotification, Never>()
    
    // Configurações
    private var notificationsEnabled: Bool = true
    private var soundEnabled: Bool = true
    private var hapticEnabled: Bool = true
    
    // MARK: - Publishers
    
    var timerStatePublisher: AnyPublisher<TimerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    var timeRemainingPublisher: AnyPublisher<TimeInterval, Never> {
        timeRemainingSubject.eraseToAnyPublisher()
    }
    
    var timerNotificationPublisher: AnyPublisher<TimerNotification, Never> {
        notificationSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(watchSessionManager: WatchSessionManagerProtocol? = nil,
         phoneSessionManager: PhoneSessionManagerProtocol? = nil) {
        self.watchSessionManager = watchSessionManager
        self.phoneSessionManager = phoneSessionManager
        
        setupControllers()
        setupNotificationHandling()
    }
    
    // MARK: - Public Methods
    
    func startTimer(type: TimerType, duration: TimeInterval, autoAction: TimerAutoAction?) async throws {
        let controller = getController(for: type)
        
        try await controller.start(duration: duration, autoAction: autoAction)
        
        // Sincronizar com Watch
        try await syncWithWatch(command: .start, type: type, duration: duration, autoAction: autoAction)
        
        // Atualizar estado global
        updateGlobalState()
    }
    
    func pauseTimer() async throws {
        guard let activeController = getActiveController() else {
            throw TimerServiceError.timerNotRunning
        }
        
        try await activeController.pause()
        
        // Sincronizar com Watch
        if let type = activeController.getCurrentState().timerType {
            try await syncWithWatch(command: .pause, type: type)
        }
        
        updateGlobalState()
    }
    
    func resumeTimer() async throws {
        guard let activeController = getActiveController() else {
            throw TimerServiceError.timerNotRunning
        }
        
        try await activeController.resume()
        
        // Sincronizar com Watch
        if let type = activeController.getCurrentState().timerType {
            try await syncWithWatch(command: .resume, type: type)
        }
        
        updateGlobalState()
    }
    
    func cancelTimer() async throws {
        guard let activeController = getActiveController() else {
            throw TimerServiceError.timerNotRunning
        }
        
        try await activeController.cancel()
        
        // Sincronizar com Watch
        if let type = activeController.getCurrentState().timerType {
            try await syncWithWatch(command: .cancel, type: type)
        }
        
        updateGlobalState()
    }
    
    func getCurrentState() -> TimerState {
        return stateSubject.value
    }
    
    func getTimeRemaining() -> TimeInterval {
        return timeRemainingSubject.value
    }
    
    func configureNotifications(enabled: Bool, sound: Bool, haptic: Bool) async throws {
        self.notificationsEnabled = enabled
        self.soundEnabled = sound
        self.hapticEnabled = haptic
        
        print("🔔 [TIMER] Notificações configuradas - enabled: \(enabled), sound: \(sound), haptic: \(haptic)")
    }
    
    func syncWithWatch(command: WatchTimerCommand) async throws {
        try await syncWithWatch(command: command, type: .restTimer, duration: nil, autoAction: nil)
    }
    
    func syncWithWatch(command: WatchTimerCommand, type: TimerType, duration: TimeInterval? = nil, autoAction: TimerAutoAction? = nil) async throws {
        guard let watchSessionManager = watchSessionManager else {
            throw TimerServiceError.watchNotReachable
        }
        
        let dict = command.toDictionary(type: type, duration: duration, autoAction: autoAction)
        
        do {
            try await watchSessionManager.sendTimerCommand(dict)
            print("📱 [TIMER] Comando enviado para Watch: \(command.rawValue) - \(type.displayName)")
        } catch {
            print("❌ [TIMER] Erro ao enviar comando para Watch: \(error)")
            throw TimerServiceError.watchSyncFailed
        }
    }
    
    func receiveWatchCommand(_ command: WatchTimerCommand) async throws {
        // Processar comando recebido do Watch
        switch command {
        case .start:
            // O Watch iniciou um timer - sincronizar estado
            print("⌚ [TIMER] Comando recebido do Watch: start")
        case .pause:
            // O Watch pausou um timer - sincronizar estado
            print("⌚ [TIMER] Comando recebido do Watch: pause")
        case .resume:
            // O Watch retomou um timer - sincronizar estado
            print("⌚ [TIMER] Comando recebido do Watch: resume")
        case .cancel:
            // O Watch cancelou um timer - sincronizar estado
            print("⌚ [TIMER] Comando recebido do Watch: cancel")
        case .sync:
            // O Watch solicitou sincronização - enviar estado atual
            print("⌚ [TIMER] Comando recebido do Watch: sync")
            try await syncCurrentStateWithWatch()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupControllers() {
        for type in TimerType.allCases {
            controllers[type] = TimerController(type: type)
        }
    }
    
    private func setupNotificationHandling() {
        // Observar notificações de todos os controllers
        for controller in controllers.values {
            controller.notificationPublisher
                .sink { [weak self] notification in
                    self?.handleNotification(notification)
                }
                .store(in: &cancellables)
        }
    }
    
    private func getController(for type: TimerType) -> TimerController {
        guard let controller = controllers[type] else {
            fatalError("Controller não encontrado para tipo: \(type)")
        }
        return controller
    }
    
    private func getActiveController() -> TimerController? {
        for controller in controllers.values {
            if controller.getCurrentState().isActive {
                return controller
            }
        }
        return nil
    }
    
    private func updateGlobalState() {
        // Atualizar estado global baseado no controller ativo
        if let activeController = getActiveController() {
            let state = activeController.getCurrentState()
            stateSubject.send(state)
            timeRemainingSubject.send(state.timeRemaining)
        } else {
            stateSubject.send(.idle)
            timeRemainingSubject.send(0)
        }
    }
    
    private func handleNotification(_ notification: TimerNotification) {
        // Processar notificação
        notificationSubject.send(notification)
        
        // Executar ações automáticas
        if case .completed(_, let autoAction) = notification {
            handleAutoAction(autoAction)
        }
        
        // Enviar notificações locais se habilitadas
        if notificationsEnabled {
            sendLocalNotification(for: notification)
        }
    }
    
    private func handleAutoAction(_ autoAction: TimerAutoAction?) {
        guard let autoAction = autoAction else { return }
        
        print("🤖 [TIMER] Executando ação automática: \(autoAction.displayName)")
        
        // Preparar integração com Use Cases
        switch autoAction {
        case .nextSet:
            // Integrar com StartSetUseCase
            notificationSubject.send(.completed(type: .restTimer, autoAction: .nextSet))
        case .nextExercise:
            // Integrar com EndExerciseUseCase → StartExerciseUseCase
            notificationSubject.send(.completed(type: .exerciseRest, autoAction: .nextExercise))
        case .endWorkout:
            // Integrar com EndWorkoutUseCase
            notificationSubject.send(.completed(type: .workoutTotal, autoAction: .endWorkout))
        case .addSeries:
            // 🆕 Propor adicionar nova série
            notificationSubject.send(.completed(type: .restTimer, autoAction: .addSeries))
        case .completeExercise:
            // 🆕 Propor completar exercício
            notificationSubject.send(.completed(type: .restTimer, autoAction: .completeExercise))
        case .waitForUser, .none:
            // Aguardar decisão do usuário
            break
        }
    }
    
    private func sendLocalNotification(for notification: TimerNotification) {
        // Implementar notificações locais
        // UNUserNotificationCenter, som, haptic feedback
        print("🔔 [TIMER] Notificação local: \(notification)")
    }
    
    private func syncCurrentStateWithWatch() async throws {
        guard let activeController = getActiveController() else { return }
        
        let state = activeController.getCurrentState()
        if let type = state.timerType {
            try await syncWithWatch(command: .sync, type: type)
        }
    }
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Mock Implementation

/// Implementação mock do TimerService para testes e previews
final class MockTimerService: TimerServiceProtocol {
    
    private let stateSubject = CurrentValueSubject<TimerState, Never>(.idle)
    private let timeRemainingSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let notificationSubject = PassthroughSubject<TimerNotification, Never>()
    
    var timerStatePublisher: AnyPublisher<TimerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    var timeRemainingPublisher: AnyPublisher<TimeInterval, Never> {
        timeRemainingSubject.eraseToAnyPublisher()
    }
    
    var timerNotificationPublisher: AnyPublisher<TimerNotification, Never> {
        notificationSubject.eraseToAnyPublisher()
    }
    
    func startTimer(type: TimerType, duration: TimeInterval, autoAction: TimerAutoAction?) async throws {
        let state = TimerState.running(remaining: duration, type: type)
        stateSubject.send(state)
        timeRemainingSubject.send(duration)
        notificationSubject.send(.started(type: type, duration: duration))
        
        print("🎭 [MOCK TIMER] Iniciado \(type.displayName) - \(duration)s")
    }
    
    func pauseTimer() async throws {
        let currentState = stateSubject.value
        if case .running(let remaining, let type) = currentState {
            let state = TimerState.paused(remaining: remaining, type: type)
            stateSubject.send(state)
            notificationSubject.send(.paused(type: type, remaining: remaining))
        }
    }
    
    func resumeTimer() async throws {
        let currentState = stateSubject.value
        if case .paused(let remaining, let type) = currentState {
            let state = TimerState.running(remaining: remaining, type: type)
            stateSubject.send(state)
            notificationSubject.send(.resumed(type: type, remaining: remaining))
        }
    }
    
    func cancelTimer() async throws {
        let currentState = stateSubject.value
        if let type = currentState.timerType {
            stateSubject.send(.idle)
            timeRemainingSubject.send(0)
            notificationSubject.send(.cancelled(type: type))
        }
    }
    
    func getCurrentState() -> TimerState {
        return stateSubject.value
    }
    
    func getTimeRemaining() -> TimeInterval {
        return timeRemainingSubject.value
    }
    
    func configureNotifications(enabled: Bool, sound: Bool, haptic: Bool) async throws {
        print("🎭 [MOCK TIMER] Notificações configuradas")
    }
    
    func syncWithWatch(command: WatchTimerCommand) async throws {
        print("🎭 [MOCK TIMER] Sincronização com Watch simulada")
    }
    
    func receiveWatchCommand(_ command: WatchTimerCommand) async throws {
        print("🎭 [MOCK TIMER] Comando do Watch recebido: \(command.rawValue)")
    }
    
    /// Simular timer de descanso inteligente
    func startRestTimerWithSmartAction(
        duration: TimeInterval = 90,
        seriesCompleted: Int,
        seriesPlanned: Int,
        isLastExercise: Bool
    ) async throws {
        
        let autoAction: TimerAutoAction = seriesCompleted >= seriesPlanned 
            ? (isLastExercise ? .endWorkout : .completeExercise)
            : .addSeries
        
        try await startTimer(type: .restTimer, duration: duration, autoAction: autoAction)
    }
    
    /// Formatar tempo total do treino (HH:MM) - Mock
    func formatWorkoutTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
    
    /// Formatar timer de descanso (MM:SS) - Mock
    func formatRestTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formatar timer manual para botão (M:SS) - Mock
    func formatManualTimer(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Verifica se deve exibir timer de descanso entre séries - Mock
    func shouldShowRestTimer(lastSetCompleted: Bool, restTimerActive: Bool) -> Bool {
        return lastSetCompleted && (restTimerActive || getCurrentState().timerType == .restTimer)
    }
    
    /// Obtém texto de exibição do timer baseado no estado - Mock
    func getTimerDisplayText() -> String? {
        let state = getCurrentState()
        
        switch state {
        case .running(let remaining, let type):
            switch type {
            case .restTimer:
                return "Descanso: \(formatRestTime(remaining)) restante"
            case .workoutTotal:
                return formatWorkoutTime(remaining)
            default:
                return nil
            }
        case .completed(let type, _):
            switch type {
            case .restTimer:
                return "Timer de \(formatManualTimer(type.defaultDuration))"
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - Extensions

extension TimerService {
    /// Método de conveniência para iniciar timer de descanso
    func startRestTimer(duration: TimeInterval = 90, autoAction: TimerAutoAction = .nextSet) async throws {
        try await startTimer(type: .restTimer, duration: duration, autoAction: autoAction)
    }
    
    /// Método de conveniência para iniciar timer de duração de série
    func startSetDurationTimer() async throws {
        try await startTimer(type: .setDuration, duration: 0, autoAction: nil)
    }
    
    /// Método de conveniência para iniciar timer de inatividade
    func startInactivityTimer() async throws {
        try await startTimer(type: .inactivity, duration: 604800, autoAction: .none)
    }
    
    /// Método de conveniência para cancelar todos os timers
    func cancelAllTimers() async throws {
        for controller in controllers.values {
            if controller.getCurrentState().isActive {
                try await controller.cancel()
            }
        }
        updateGlobalState()
    }
    
    /// Iniciar timer de descanso com ação automática inteligente
    func startRestTimerWithSmartAction(
        duration: TimeInterval = 90,
        seriesCompleted: Int,
        seriesPlanned: Int,
        isLastExercise: Bool
    ) async throws {
        
        let autoAction: TimerAutoAction
        
        if seriesCompleted >= seriesPlanned {
            // Todas as séries foram feitas
            autoAction = isLastExercise ? .endWorkout : .completeExercise
        } else {
            // Ainda há séries planejadas
            autoAction = .addSeries
        }
        
        try await startTimer(type: .restTimer, duration: duration, autoAction: autoAction)
    }
}

// MARK: - Formatting Extensions

extension TimerService {
    /// Formatar tempo total do treino (HH:MM)
    func formatWorkoutTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
    
    /// Formatar timer de descanso (MM:SS)
    func formatRestTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formatar timer manual para botão (M:SS)
    func formatManualTimer(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Verifica se deve exibir timer de descanso entre séries
    func shouldShowRestTimer(lastSetCompleted: Bool, restTimerActive: Bool) -> Bool {
        // Timer só aparece se:
        // 1. Última série foi completada
        // 2. Timer de descanso está ativo OU já finalizou
        return lastSetCompleted && (restTimerActive || getCurrentState().timerType == .restTimer)
    }
    
    /// Obtém texto de exibição do timer baseado no estado
    func getTimerDisplayText() -> String? {
        let state = getCurrentState()
        
        switch state {
        case .running(let remaining, let type):
            switch type {
            case .restTimer:
                return "Descanso: \(formatRestTime(remaining)) restante"
            case .workoutTotal:
                return formatWorkoutTime(remaining)
            default:
                return nil
            }
        case .completed(let type, _):
            switch type {
            case .restTimer:
                return "Timer de \(formatManualTimer(type.defaultDuration))"
            default:
                return nil
            }
        default:
            return nil
        }
    }
} 