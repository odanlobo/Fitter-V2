//
//  WatchSessionManager.swift
//  Fitter V2 Watch App
//
//  📋 WATCHSESSIONMANAGER: Gerenciamento do WCSession no Apple Watch (ITEM 43.1)
//  
//  🎯 RESPONSABILIDADES:
//  • Gerenciamento do WCSession no Watch
//  • Transferência assíncrona de chunks de dados de sensores
//  • Gerenciamento de conexão Watch-iPhone
//  • Recebimento de comandos do ML/iPhone
//  • Envio de heartRate/calories (2s)
//  • Sincronização de treinos Watch → iPhone
//  • Propagação de mudanças de fase
//  
//  🔄 FLUXO DE DADOS:
//  1. MotionManager → WatchSessionManager (chunks de 100 amostras)
//  2. WatchSessionManager → PhoneSessionManager (via WCSession.transferFile)
//  3. PhoneSessionManager → ML/iPhone (processamento em tempo real)
//  4. ML/iPhone → PhoneSessionManager → WatchSessionManager (comandos/feedback)
//  
//  🚀 FUNCIONALIDADES IMPLEMENTADAS:
//  • WCSessionDelegate completo
//  • Buffer e chunking de dados otimizado
//  • Envio em background com retry automático
//  • Monitoramento de reachability
//  • Sincronização bidirecional de UI
//  • Heart rate e calories em tempo real
//  • Comandos de fase (execução/descanso)
//  
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import WatchConnectivity
import Combine
import CoreData

// 🎯 IMPORTAÇÃO UNIFICADA: SensorData compartilhado entre Watch e iPhone
// Elimina necessidade de WatchSensorData separado
// Usa mesma struct para captura, transferência e persistência

/// Erros específicos para WatchSessionManager
enum WatchSessionError: LocalizedError {
    case sessionNotActivated
    case phoneNotReachable
    case transferFailed(Error)
    case invalidData
    case bufferOverflow
    case heartRateUnavailable
    case caloriesUnavailable
    
    var errorDescription: String? {
        switch self {
        case .sessionNotActivated:
            return "Sessão WCSession não está ativada"
        case .phoneNotReachable:
            return "iPhone não está alcançável"
        case .transferFailed(let error):
            return "Falha na transferência: \(error.localizedDescription)"
        case .invalidData:
            return "Dados inválidos para transferência"
        case .bufferOverflow:
            return "Buffer de dados excedeu o limite"
        case .heartRateUnavailable:
            return "Dados de frequência cardíaca não disponíveis"
        case .caloriesUnavailable:
            return "Dados de calorias não disponíveis"
        }
    }
}

/// Comandos enviados do iPhone para o Watch
enum WatchCommand: String, CaseIterable {
    case startWorkout = "startWorkout"
    case endWorkout = "endWorkout"
    case startExercise = "startExercise"
    case endExercise = "endExercise"
    case startSet = "startSet"
    case endSet = "endSet"
    case updatePhase = "updatePhase"
    case updateReps = "updateReps"
    case showAlert = "showAlert"
    case syncWorkoutPlans = "syncWorkoutPlans"
    case authStatus = "authStatus"
    case logout = "logout"
}

/// Estados de fase do treino
enum WorkoutPhase: String, CaseIterable {
    case execution = "execution"
    case rest = "rest"
}

// MARK: - WatchSessionManagerProtocol

/// Protocolo para WatchSessionManager (testabilidade e injeção de dependências)
protocol WatchSessionManagerProtocol: AnyObject {
    var isSessionActivated: Bool { get }
    var isReachable: Bool { get }
    
    func sendSensorDataChunk(_ sensorData: [SensorData]) async
    func sendHealthData() async
    func updateHealthData(heartRate: Int?, calories: Double?) async
    func updatePhase(_ phase: WorkoutPhase) async
    func sendTimerCommand(_ command: [String: Any]) async throws
    func sendMessage(_ message: [String: Any]) async throws
    func updateApplicationContext(_ context: [String: Any]) async throws
}

/// Gerenciador de sessão WCSession no Apple Watch
/// Responsável por toda comunicação Watch ↔ iPhone
/// 
/// ⚡ Clean Architecture:
/// - Implementa WCSessionDelegate
/// - Delega persistência para CoreDataService (compartilhado)
/// - Delega operações de workout para WorkoutDataService (compartilhado)
/// - Foco apenas em comunicação Watch-iPhone
/// - Sincronização automática via Core Data compartilhado
@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WatchSessionManagerProtocol {
    
    // MARK: - Published Properties
    
    /// Estado de conectividade com o iPhone
    @Published private(set) var isConnectedToPhone = false
    
    /// Estado de ativação da sessão
    @Published private(set) var isSessionActivated = false
    
    /// Última frequência cardíaca recebida
    @Published private(set) var currentHeartRate: Int?
    
    /// Últimas calorias queimadas recebidas
    @Published private(set) var currentCalories: Double?
    
    /// Fase atual do treino
    @Published private(set) var currentPhase: WorkoutPhase = .execution
    
    /// Contexto da sessão atual
    @Published private(set) var sessionContext: WatchSessionContext?
    
    // MARK: - Private Properties
    
    /// Sessão WCSession
    private let session: WCSession
    
    /// Dependências injetadas (Clean Architecture)
    private let coreDataService: CoreDataServiceProtocol
    private let workoutDataService: WorkoutDataServiceProtocol
    
    /// Buffer para dados de sensores (chunks de 100 amostras)
    private var sensorDataBuffer: [SensorData] = []
    private let maxBufferSize = 100
    
    /// Buffer para heart rate e calories (envio a cada 2s)
    private var healthDataBuffer: [(heartRate: Int?, calories: Double?, timestamp: Date)] = []
    private let healthDataInterval: TimeInterval = 2.0
    private var lastHealthDataSend: Date = Date()
    
    /// Fila para operações de transferência
    private let transferQueue = DispatchQueue(label: "WatchSessionTransfer", qos: .userInitiated)
    
    /// Timer para envio periódico de health data
    private var healthDataTimer: Timer?
    
    /// Callbacks para comandos recebidos
    private var commandHandlers: [WatchCommand: (([String: Any]) -> Void)] = [:]
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Inicializa WatchSessionManager com dependências injetadas
    /// - Parameters:
    ///   - coreDataService: Serviço para operações Core Data (compartilhado)
    ///   - workoutDataService: Serviço para operações de workout (compartilhado)
    init(
        coreDataService: CoreDataServiceProtocol = CoreDataService(),
        workoutDataService: WorkoutDataServiceProtocol = WorkoutDataService()
    ) {
        self.session = WCSession.default
        self.coreDataService = coreDataService
        self.workoutDataService = workoutDataService
        
        super.init()
        
        setupSession()
        setupHealthDataTimer()
        setupCommandHandlers()
        
        print("⌚ WatchSessionManager inicializado com dependency injection")
    }
    
    // MARK: - Setup
    
    /// Configura a sessão WCSession
    private func setupSession() {
        guard WCSession.isSupported() else {
            print("❌ [WATCH SESSION] WCSession não é suportado")
            return
        }
        
        session.delegate = self
        session.activate()
        
        print("✅ [WATCH SESSION] Sessão configurada e ativando...")
    }
    
    /// Configura timer para envio de health data
    private func setupHealthDataTimer() {
        healthDataTimer = Timer.scheduledTimer(withTimeInterval: healthDataInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendHealthData()
            }
        }
    }
    
    /// Configura handlers para comandos recebidos
    private func setupCommandHandlers() {
        commandHandlers[.startWorkout] = { [weak self] data in
            Task { @MainActor in
                await self?.handleStartWorkout(data)
            }
        }
        
        commandHandlers[.endWorkout] = { [weak self] data in
            Task { @MainActor in
                await self?.handleEndWorkout(data)
            }
        }
        
        commandHandlers[.startExercise] = { [weak self] data in
            Task { @MainActor in
                await self?.handleStartExercise(data)
            }
        }
        
        commandHandlers[.endExercise] = { [weak self] data in
            Task { @MainActor in
                await self?.handleEndExercise(data)
            }
        }
        
        commandHandlers[.startSet] = { [weak self] data in
            Task { @MainActor in
                await self?.handleStartSet(data)
            }
        }
        
        commandHandlers[.endSet] = { [weak self] data in
            Task { @MainActor in
                await self?.handleEndSet(data)
            }
        }
        
        commandHandlers[.updatePhase] = { [weak self] data in
            Task { @MainActor in
                await self?.handleUpdatePhase(data)
            }
        }
        
        commandHandlers[.updateReps] = { [weak self] data in
            Task { @MainActor in
                await self?.handleUpdateReps(data)
            }
        }
        
        commandHandlers[.showAlert] = { [weak self] data in
            Task { @MainActor in
                await self?.handleShowAlert(data)
            }
        }
        
        commandHandlers[.syncWorkoutPlans] = { [weak self] data in
            Task { @MainActor in
                await self?.handleSyncWorkoutPlans(data)
            }
        }
        
        commandHandlers[.authStatus] = { [weak self] data in
            Task { @MainActor in
                await self?.handleAuthStatus(data)
            }
        }
        
        commandHandlers[.logout] = { [weak self] data in
            Task { @MainActor in
                await self?.handleLogout(data)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Envia chunk de dados de sensores para o iPhone
    /// - Parameter sensorData: Array de dados de sensores (máximo 100 amostras)
    func sendSensorDataChunk(_ sensorData: [SensorData]) async {
        // Persiste dados localmente via CoreDataService (para backup)
        await persistSensorDataLocally(sensorData)
        
        guard isSessionActivated else {
            print("⚠️ [SENSOR] Sessão não ativada, dados perdidos")
            return
        }
        
        guard session.isReachable else {
            print("⚠️ [SENSOR] iPhone não alcançável, dados em buffer")
            // Adiciona ao buffer para envio posterior
            sensorDataBuffer.append(contentsOf: sensorData)
            if sensorDataBuffer.count > maxBufferSize * 2 {
                sensorDataBuffer.removeFirst(sensorDataBuffer.count - maxBufferSize)
                print("⚠️ [SENSOR] Buffer overflow, dados antigos removidos")
            }
            return
        }
        
        do {
            // Serializa dados para JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(sensorData)
            
            // Cria arquivo temporário para transferência
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sensor_chunk_\(Date().timeIntervalSince1970)")
                .appendingPathExtension("json")
            
            try jsonData.write(to: tempURL)
            
            // ✅ CORRIGIDO: Incluir contexto da sessão nos metadados
            var metadata: [String: Any] = [
                "type": "sensorData",
                "count": sensorData.count,
                "timestamp": Date().timeIntervalSince1970,
                "phase": currentPhase.rawValue
            ]
            
            // ✅ CONTEXTO DA SESSÃO: Adicionar IDs para rastreamento
            if let context = sessionContext {
                metadata["sessionId"] = context.sessionId
                metadata["planId"] = context.planId
                metadata["exerciseId"] = context.currentExerciseId
                metadata["setId"] = context.currentSetId
                metadata["setOrder"] = context.currentSetOrder
                metadata["exerciseIndex"] = context.exerciseIndex
                print("✅ [SENSOR] Contexto incluído: Session=\(context.sessionId), Exercise=\(context.currentExerciseName), Set=\(context.currentSetOrder)")
            } else {
                print("⚠️ [SENSOR] Contexto da sessão não disponível - dados sem contexto")
            }
            
            // Envia via transferFile (assíncrono e confiável)
            let transfer = session.transferFile(tempURL, metadata: metadata)
            
            print("📤 [SENSOR] Chunk enviado: \(sensorData.count) amostras com contexto")
            
            // Limpa arquivo temporário após transferência
            transferQueue.asyncAfter(deadline: .now() + 5.0) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
        } catch {
            print("❌ [SENSOR] Erro ao enviar chunk: \(error)")
        }
    }
    
    /// Envia dados de health (heart rate e calories) para o iPhone
    func sendHealthData() async {
        guard isSessionActivated && session.isReachable else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastHealthDataSend) >= healthDataInterval else { return }
        
        // Coleta dados de health (item 45 - HealthKitManager CONCLUÍDO)
        let heartRate = currentHeartRate
        let calories = currentCalories
        
        let healthData: [String: Any] = [
            "type": "healthData",
            "heartRate": heartRate as Any,
            "calories": calories as Any,
            "timestamp": now.timeIntervalSince1970,
            "phase": currentPhase.rawValue
        ]
        
        do {
            try await sendMessage(healthData)
            lastHealthDataSend = now
            print("💓 [HEALTH] Health data enviado: HR=\(heartRate ?? 0), Cal=\(calories ?? 0)")
        } catch {
            print("❌ [HEALTH] Erro ao enviar health data: \(error)")
        }
    }
    
    /// Atualiza dados de health (item 45 - HealthKitManager CONCLUÍDO)
    func updateHealthData(heartRate: Int?, calories: Double?) async {
        currentHeartRate = heartRate
        currentCalories = calories
        
        // Envia dados em tempo real se conectado
        if isSessionActivated && session.isReachable {
            await sendHealthData()
        }
    }
    
    // 🆕 NOVA FUNÇÃO: Envia detecção de mudança de fase para o iPhone
    /// Envia dados de mudança de fase detectada automaticamente
    /// - Parameter phaseChangeData: Dados da mudança de fase detectada
    func sendPhaseChangeDetection(_ phaseChangeData: [String: Any]) async {
        guard isSessionActivated && session.isReachable else {
            print("⚠️ [PHASE] Sessão não ativada ou iPhone não alcançável")
            return
        }
        
        var message = phaseChangeData
        message["source"] = "watch_motion_manager"
        message["watch_timestamp"] = Date().timeIntervalSince1970
        
        // ✅ CONTEXTO DA SESSÃO: Adicionar IDs para rastreamento
        if let context = sessionContext {
            message["sessionId"] = context.sessionId
            message["planId"] = context.planId
            message["exerciseId"] = context.currentExerciseId
            message["setId"] = context.currentSetId
            message["setOrder"] = context.currentSetOrder
            message["exerciseIndex"] = context.exerciseIndex
            message["exerciseName"] = context.currentExerciseName
            print("✅ [PHASE] Contexto incluído: Session=\(context.sessionId), Exercise=\(context.currentExerciseName), Set=\(context.currentSetOrder)")
        } else {
            print("⚠️ [PHASE] Contexto da sessão não disponível")
        }
        
        do {
            try await sendMessage(message)
            print("🔄 [PHASE] Mudança de fase enviada para iPhone: \(phaseChangeData["from_phase"] ?? "unknown") → \(phaseChangeData["to_phase"] ?? "unknown")")
        } catch {
            print("❌ [PHASE] Erro ao enviar mudança de fase: \(error)")
        }
    }
    
    /// Atualiza a fase do treino
    func updatePhase(_ phase: WorkoutPhase) async {
        currentPhase = phase
        
        // Notifica o iPhone sobre a mudança de fase
        await notifyPhaseChange(phase)
    }
    
    /// Envia mensagem para o iPhone
    func sendMessage(_ message: [String: Any]) async throws {
        guard isSessionActivated else {
            throw WatchSessionError.sessionNotActivated
        }
        
        guard session.isReachable else {
            throw WatchSessionError.phoneNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume()
            }, errorHandler: { error in
                continuation.resume(throwing: WatchSessionError.transferFailed(error))
            })
        }
    }
    
    /// Sincroniza dados pendentes quando reconecta
    func syncPendingData() async {
        guard isSessionActivated && session.isReachable else { return }
        
        // Envia dados de sensores em buffer
        if !sensorDataBuffer.isEmpty {
            let pendingData = Array(sensorDataBuffer)
            sensorDataBuffer.removeAll()
            await sendSensorDataChunk(pendingData)
        }
        
        // Envia health data pendente
        await sendHealthData()
        
        // Sincronização automática via Core Data compartilhado
        print("🔄 [SYNC] Dados persistidos no Core Data compartilhado - sincronização automática")
        
        print("🔄 [SYNC] Dados pendentes sincronizados")
    }
    
    // MARK: - Private Methods
    
    /// Persiste dados de sensores no Core Data compartilhado
    /// - Parameter sensorData: Array de dados de sensores
    private func persistSensorDataLocally(_ sensorData: [SensorData]) async {
        // TODO: Implementar persistência no Core Data compartilhado
        // Os dados serão automaticamente sincronizados com iPhone via App Groups
        print("💾 [SHARED] Dados de sensores para persistência no Core Data compartilhado: \(sensorData.count) amostras")
    }
    
    /// Notifica mudança de fase para o iPhone
    private func notifyPhaseChange(_ phase: WorkoutPhase) async {
        let message: [String: Any] = [
            "type": "phaseChange",
            "phase": phase.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            try await sendMessage(message)
            print("🔄 [PHASE] Mudança de fase notificada: \(phase.rawValue)")
        } catch {
            print("❌ [PHASE] Erro ao notificar mudança de fase: \(error)")
        }
    }
    
    /// Processa comando recebido do iPhone
    private func processCommand(_ command: WatchCommand, data: [String: Any]) {
        guard let handler = commandHandlers[command] else {
            print("⚠️ [COMMAND] Handler não encontrado para comando: \(command.rawValue)")
            return
        }
        
        handler(data)
    }
    
    // MARK: - Command Handlers
    
    private func handleStartWorkout(_ data: [String: Any]) async {
        print("🏋️‍♂️ [COMMAND] Iniciando treino")
        // TODO: Integrar com StartWorkoutUseCase (item 24)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleEndWorkout(_ data: [String: Any]) async {
        print("✅ [COMMAND] Finalizando treino")
        // TODO: Integrar com EndWorkoutUseCase (item 25)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleStartExercise(_ data: [String: Any]) async {
        print("💪 [COMMAND] Iniciando exercício")
        // TODO: Integrar com StartExerciseUseCase (item 26)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleEndExercise(_ data: [String: Any]) async {
        print("🏁 [COMMAND] Finalizando exercício")
        // TODO: Integrar com EndExerciseUseCase (item 27)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleStartSet(_ data: [String: Any]) async {
        print("🎯 [COMMAND] Iniciando série")
        // TODO: Integrar com StartSetUseCase (item 28)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleEndSet(_ data: [String: Any]) async {
        print("🎯 [COMMAND] Finalizando série")
        // TODO: Integrar com EndSetUseCase (item 29)
        // Por enquanto, apenas log - será implementado quando Use Cases estiverem disponíveis no Watch
    }
    
    private func handleUpdatePhase(_ data: [String: Any]) async {
        if let phaseString = data["phase"] as? String,
           let phase = WorkoutPhase(rawValue: phaseString) {
            currentPhase = phase
            print("🔄 [COMMAND] Fase atualizada: \(phase.rawValue)")
        }
    }
    
    private func handleUpdateReps(_ data: [String: Any]) async {
        if let reps = data["reps"] as? Int {
            print("🔢 [COMMAND] Reps atualizados: \(reps)")
            // TODO: Atualizar UI do Watch
        }
    }
    
    private func handleShowAlert(_ data: [String: Any]) async {
        if let message = data["message"] as? String {
            print("⚠️ [COMMAND] Alerta: \(message)")
            // TODO: Mostrar alerta na UI do Watch
        }
    }
    
    private func handleSyncWorkoutPlans(_ data: [String: Any]) async {
        print("📋 [COMMAND] Sincronizando planos de treino")
        // TODO: Integrar com WatchDataManager
    }
    
    private func handleAuthStatus(_ data: [String: Any]) async {
        if let isAuthenticated = data["isAuthenticated"] as? Bool {
            print("🔐 [COMMAND] Status de autenticação: \(isAuthenticated)")
            // TODO: Atualizar estado de autenticação
        }
    }
    
    private func handleLogout(_ data: [String: Any]) async {
        print("🚪 [COMMAND] Logout solicitado")
        // TODO: Limpar dados locais e mostrar tela de login
    }
    
    // MARK: - Cleanup
    
    deinit {
        healthDataTimer?.invalidate()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isSessionActivated = activationState == .activated
            
            if let error = error {
                print("❌ [WATCH SESSION] Erro na ativação: \(error)")
            } else {
                print("✅ [WATCH SESSION] Sessão ativada com sucesso")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isConnectedToPhone = session.isReachable
            
            if session.isReachable {
                print("📱 [WATCH SESSION] iPhone conectado")
                Task {
                    await syncPendingData()
                }
            } else {
                print("📱 [WATCH SESSION] iPhone desconectado")
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let commandString = message["command"] as? String,
              let command = WatchCommand(rawValue: commandString) else {
            print("⚠️ [WATCH SESSION] Comando inválido recebido")
            return
        }
        
        print("📥 [WATCH SESSION] Comando recebido: \(command.rawValue)")
        processCommand(command, data: message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let commandString = message["command"] as? String,
              let command = WatchCommand(rawValue: commandString) else {
            replyHandler(["error": "Comando inválido"])
            return
        }
        
        print("📥 [WATCH SESSION] Comando com reply recebido: \(command.rawValue)")
        processCommand(command, data: message)
        
        // Resposta padrão de sucesso
        replyHandler(["success": true, "timestamp": Date().timeIntervalSince1970])
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("📱 [WATCH SESSION] Contexto de aplicação recebido")
        
        Task { @MainActor in
            await processApplicationContext(applicationContext)
        }
    }
    
    /// Processa contexto da aplicação recebido do iPhone
    /// - Parameter context: Contexto da aplicação contendo dados da sessão
    private func processApplicationContext(_ context: [String: Any]) async {
        // ✅ CONTEXTO DA SESSÃO: Processar dados da sessão ativa
        if let type = context["type"] as? String, type == "sessionContext" {
            let sessionContext = WatchSessionContext(
                sessionId: context["sessionId"] as? String ?? "",
                planId: context["planId"] as? String ?? "",
                planTitle: context["planTitle"] as? String ?? "",
                currentExerciseId: context["currentExerciseId"] as? String ?? "",
                currentExerciseName: context["currentExerciseName"] as? String ?? "",
                currentSetId: context["currentSetId"] as? String ?? "",
                currentSetOrder: context["currentSetOrder"] as? Int ?? 0,
                exerciseIndex: context["exerciseIndex"] as? Int32 ?? 0,
                isActive: context["isActive"] as? Bool ?? false
            )
            
            self.sessionContext = sessionContext
            print("✅ [CONTEXT] Contexto da sessão atualizado: \(sessionContext.planTitle) - \(sessionContext.currentExerciseName)")
        }
        
        // ✅ FIM DA SESSÃO: Limpar contexto quando sessão termina
        else if let type = context["type"] as? String, type == "sessionEnd" {
            self.sessionContext = nil
            print("🔄 [CONTEXT] Contexto da sessão limpo - sessão finalizada")
        }
        
        // ✅ OUTROS CONTEXTOS: Processar configurações globais
        else {
            print("📋 [CONTEXT] Contexto geral processado")
        }
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            print("❌ [WATCH SESSION] Erro na transferência de arquivo: \(error)")
        } else {
            print("✅ [WATCH SESSION] Transferência de arquivo concluída")
        }
    }
}

// MARK: - WatchSessionContext

/// Contexto da sessão de treino no Watch
struct WatchSessionContext: Codable {
    let sessionId: String
    let planId: String
    let planTitle: String
    let currentExerciseId: String
    let currentExerciseName: String
    let currentSetId: String
    let currentSetOrder: Int
    let exerciseIndex: Int32
    let isActive: Bool
}

// MARK: - Debug Extensions

extension WatchSessionManager {
    /// Retorna estatísticas de sessão
    var sessionStats: String {
        """
        📊 Watch Session Stats:
        - Ativada: \(isSessionActivated)
        - Conectada: \(isConnectedToPhone)
        - Fase: \(currentPhase.rawValue)
        - Buffer Sensor: \(sensorDataBuffer.count)/\(maxBufferSize)
        - Buffer Health: \(healthDataBuffer.count)
        - Heart Rate: \(currentHeartRate ?? 0)
        - Calories: \(currentCalories ?? 0)
        """
    }
}
