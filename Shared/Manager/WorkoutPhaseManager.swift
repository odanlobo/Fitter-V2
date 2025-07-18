//
//  WorkoutPhaseManager.swift
//  Fitter V2 (Shared)
//
//  REFATORADO em 04/01/25 - Apenas controle de estado
//  RESPONSABILIDADE: Controle simples de estados execução/descanso
//  ARQUITETURA: StateManager puro - sem lógicas complexas
//  COMPATIBILIDADE: iOS + watchOS compartilhado
//

import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// MARK: - Types

/// Fase do workout (compartilhada entre iOS e watchOS)
public enum WorkoutPhase: String, CaseIterable, Codable {
    case execution = "execution"
    case rest = "rest"
    
    public var samplingRate: Double {
        switch self {
        case .execution: return 50.0  // 0.02s - Alta frequência para captura precisa
        case .rest: return 20.0       // 0.05s - Frequência reduzida para economia
        }
    }
    
    public var description: String {
        switch self {
        case .execution: return "Execução"
        case .rest: return "Descanso"
        }
    }
}

/// Gatilho para mudança de fase
public enum PhaseTrigger: String, CaseIterable, Codable {
    case automatic = "automatic"      // Detecção automática via sensores
    case manual = "manual"           // Ação manual do usuário
    case timer = "timer"             // Timer de descanso finalizado
    case system = "system"           // Sistema (start/end workout)
    
    public var description: String {
        switch self {
        case .automatic: return "Detecção automática"
        case .manual: return "Manual do usuário"
        case .timer: return "Timer finalizado"
        case .system: return "Sistema"
        }
    }
}

/// Event de mudança de fase
public struct PhaseChangeEvent {
    public let fromPhase: WorkoutPhase
    public let toPhase: WorkoutPhase
    public let trigger: PhaseTrigger
    public let timestamp: Date
    
    public init(fromPhase: WorkoutPhase, toPhase: WorkoutPhase, trigger: PhaseTrigger, timestamp: Date = Date()) {
        self.fromPhase = fromPhase
        self.toPhase = toPhase
        self.trigger = trigger
        self.timestamp = timestamp
    }
}

// MARK: - Protocol

/// Protocolo para WorkoutPhaseManager (testabilidade)
public protocol WorkoutPhaseManagerProtocol: ObservableObject {
    var currentPhase: WorkoutPhase { get }
    var isWorkoutActive: Bool { get }
    
    /// Publisher para observar mudanças de fase
    var phaseChangePublisher: AnyPublisher<PhaseChangeEvent, Never> { get }
    
    /// Atualiza a fase do workout
    func updatePhase(_ phase: WorkoutPhase, trigger: PhaseTrigger) async
    
    /// Inicia controle de sessão
    func startSession() async
    
    /// Finaliza controle de sessão
    func endSession() async
    
    /// Reseta o estado para inicial
    func reset() async
}

// MARK: - WorkoutPhaseManager

/// Gerenciador simples de fases de workout (Compartilhado iOS + watchOS)
/// 
/// **RESPONSABILIDADES REDUZIDAS:**
/// - ✅ Controlar fase atual (execution/rest)
/// - ✅ Notificar mudanças de fase via Combine
/// - ✅ Validar transições de estado
/// - ✅ Sincronizar estado entre dispositivos
/// 
/// **❌ NÃO GERENCIA MAIS:**
/// - ❌ Timers de descanso (delegado para TimerService)
/// - ❌ Ações automáticas (delegado para Use Cases)
/// - ❌ Lógica de negócio (delegado para Use Cases)
/// - ❌ Comunicação complexa (delegado para SessionManagers)
/// 
/// **🎯 FOCO:** Apenas estado reativo e simples
@MainActor
public final class WorkoutPhaseManager: ObservableObject, WorkoutPhaseManagerProtocol {
    
    // MARK: - Singleton (compatibilidade temporária)
    public static let shared = WorkoutPhaseManager()
    
    // MARK: - Published Properties
    
    /// Fase atual do workout
    @Published public private(set) var currentPhase: WorkoutPhase = .execution
    
    /// Indica se há uma sessão de workout ativa
    @Published public private(set) var isWorkoutActive: Bool = false
    
    // MARK: - Private Properties
    
    /// Subject para mudanças de fase
    private let phaseChangeSubject = PassthroughSubject<PhaseChangeEvent, Never>()
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Publishers
    
    /// Publisher para observar mudanças de fase
    public var phaseChangePublisher: AnyPublisher<PhaseChangeEvent, Never> {
        phaseChangeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        print("🔄 WorkoutPhaseManager inicializado (estado puro)")
    }
    
    // MARK: - Public Methods
    
    /// Atualiza a fase do workout
    /// - Parameters:
    ///   - phase: Nova fase
    ///   - trigger: Gatilho da mudança
    public func updatePhase(_ phase: WorkoutPhase, trigger: PhaseTrigger) async {
        guard phase != currentPhase else {
            print("🔄 [PHASE] Fase já está em \(phase.description)")
            return
        }
        
        guard isWorkoutActive else {
            print("⚠️ [PHASE] Tentativa de mudar fase sem sessão ativa")
            return
        }
        
        print("🔄 [PHASE] Mudando de \(currentPhase.description) para \(phase.description) (\(trigger.description))")
        
        // Validar transição
        guard isValidPhaseTransition(from: currentPhase, to: phase) else {
            print("❌ [PHASE] Transição inválida: \(currentPhase.description) → \(phase.description)")
            return
        }
        
        // Criar event de mudança
        let event = PhaseChangeEvent(
            fromPhase: currentPhase,
            toPhase: phase,
            trigger: trigger
        )
        
        // Atualizar estado
        currentPhase = phase
        
        // Notificar observadores
        phaseChangeSubject.send(event)
        
        print("✅ [PHASE] Fase atualizada: \(phase.description)")
    }
    
    /// Inicia controle de sessão
    public func startSession() async {
        print("🏋️‍♂️ [PHASE] Iniciando controle de sessão")
        
        // Resetar estado
        currentPhase = .execution
        isWorkoutActive = true
        
        print("✅ [PHASE] Controle de sessão iniciado")
    }
    
    /// Finaliza controle de sessão
    public func endSession() async {
        print("🏁 [PHASE] Finalizando controle de sessão")
        
        // Resetar estado
        isWorkoutActive = false
        currentPhase = .execution
        
        print("✅ [PHASE] Controle de sessão finalizado")
    }
    
    /// Reseta o estado para inicial
    public func reset() async {
        print("🔄 [PHASE] Resetando estado")
        
        currentPhase = .execution
        isWorkoutActive = false
        
        print("✅ [PHASE] Estado resetado")
    }
    
    // MARK: - Private Methods
    
    /// Valida transição de fase
    /// - Parameters:
    ///   - from: Fase atual
    ///   - to: Nova fase
    /// - Returns: True se transição é válida
    private func isValidPhaseTransition(from: WorkoutPhase, to: WorkoutPhase) -> Bool {
        // Todas as transições execution ↔ rest são válidas
        // Lógica de validação mais complexa pode ser adicionada aqui no futuro
        return true
    }
}

// MARK: - Convenience Extensions

public extension WorkoutPhaseManager {
    
    /// Indica se está em fase de execução
    var isInExecution: Bool {
        return currentPhase == .execution && isWorkoutActive
    }
    
    /// Indica se está em fase de descanso
    var isInRest: Bool {
        return currentPhase == .rest && isWorkoutActive
    }
    
    /// Frequência de captura atual
    var currentSamplingRate: Double {
        return currentPhase.samplingRate
    }
    
    /// Atualiza para execução (convenience method)
    func switchToExecution(trigger: PhaseTrigger = .manual) async {
        await updatePhase(.execution, trigger: trigger)
    }
    
    /// Atualiza para descanso (convenience method)
    func switchToRest(trigger: PhaseTrigger = .manual) async {
        await updatePhase(.rest, trigger: trigger)
    }
}

// MARK: - Debug Extensions

public extension WorkoutPhaseManager {
    
    /// Retorna estatísticas de debug
    var debugInfo: String {
        """
        🔄 WorkoutPhaseManager (Simples):
        - Fase atual: \(currentPhase.description)
        - Frequência: \(currentPhase.samplingRate)Hz
        - Sessão ativa: \(isWorkoutActive ? "Sim" : "Não")
        - Em execução: \(isInExecution ? "Sim" : "Não")
        - Em descanso: \(isInRest ? "Sim" : "Não")
        """
    }
}

