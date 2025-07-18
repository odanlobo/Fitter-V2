//
//  PhoneSessionManager.swift
//  Fitter V2
//
//  REFATORADO em 15/12/25 - ITEM 43.2 ✅
//  RESPONSABILIDADE: Gerenciamento do WCSession no iPhone
//  ARQUITETURA: Clean Architecture com dependency injection
//  INTEGRAÇÃO: WatchSessionManager (Watch) + Use Cases (iPhone)
//

import Foundation
import WatchConnectivity
import Combine
import CoreData

// MARK: - Protocols

/// Protocolo para comandos enviados do iPhone para o Apple Watch
protocol WatchCommand {
    var commandType: WatchCommandType { get }
    var payload: [String: Any] { get }
}

/// Tipos de comandos suportados
enum WatchCommandType: String, CaseIterable {
    case startWorkout = "start_workout"
    case endWorkout = "end_workout"
    case startExercise = "start_exercise"
    case endExercise = "end_exercise"
    case startSet = "start_set"
    case endSet = "end_set"
    case updatePhase = "update_phase"
    case updateTimer = "update_timer"
    case updateReps = "update_reps"
    case syncUI = "sync_ui"

    case error = "error"
}

/// Protocolo para dados recebidos do Apple Watch
protocol WatchData {
    var dataType: WatchDataType { get }
    var timestamp: Date { get }
    var payload: [String: Any] { get }
}

/// Tipos de dados suportados
enum WatchDataType: String, CaseIterable {
    case sensorChunk = "sensor_chunk"
    case heartRate = "heart_rate"
    case calories = "calories"
    case phaseChange = "phase_change"
    case phaseChangeDetected = "phase_change_detected"  // 🆕 NOVA: Detecção automática de mudança de fase
    case repCount = "rep_count"
    case timerUpdate = "timer_update"
    case workoutStatus = "workout_status"
    case error = "error"
}

/// Protocolo para PhoneSessionManager
protocol PhoneSessionManagerProtocol: AnyObject {
    var isReachable: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    
    func startSession()
    func stopSession()
    func sendCommand(_ command: WatchCommand) async throws
    func sendMessage(_ message: [String: Any]) async throws
    func updateApplicationContext(_ context: [String: Any]) async throws
    func transferFile(_ fileURL: URL, metadata: [String: Any]?) async throws
}

// MARK: - Supporting Types

/// Dados de detecção automática de mudança de fase
struct PhaseChangeDetectionData {
    let fromPhase: String
    let toPhase: String
    let detectedAt: Date
    let sessionId: String
    let exerciseId: String
    let setId: String
    let setOrder: Int32
    let exerciseName: String
    let threshold: Double
    let detectionDuration: TimeInterval
    
    /// Verifica se a detecção é de execução para descanso (fim de série)
    var isExecutionToRest: Bool {
        return fromPhase == "execution" && toPhase == "rest"
    }
    
    /// Tempo decorrido desde a detecção
    func timeElapsed() -> TimeInterval {
        return Date().timeIntervalSince(detectedAt)
    }
}

// MARK: - PhoneSessionManager

/// Gerenciador do WCSession no iPhone
/// 
/// Responsabilidades:
/// - Gerenciamento do WCSession no iPhone
/// - Recepção e processamento de chunks de sensores
/// - Despacho para Use Cases e persistência
/// - Envio de comandos para o Apple Watch
/// - Sincronização bidirecional de UI
/// 
/// ⚡ Clean Architecture:
/// - Implementa WCSessionDelegate
/// - Delega processamento para Use Cases
/// - Usa dependency injection
/// - Foco apenas em comunicação Watch-iPhone
@MainActor
final class PhoneSessionManager: NSObject, PhoneSessionManagerProtocol {
    
    // MARK: - Published Properties
    
    /// Indica se o Apple Watch está reachable
    @Published private(set) var isReachable: Bool = false
    
    /// Indica se o Apple Watch está paired
    @Published private(set) var isPaired: Bool = false
    
    /// Indica se o app do Apple Watch está instalado
    @Published private(set) var isWatchAppInstalled: Bool = false
    
    // MARK: - Publishers para dados em tempo real

    /// Publisher para dados de heart rate em tempo real
    @Published private(set) var currentHeartRate: Double = 0
    var heartRatePublisher: AnyPublisher<Double, Never> {
        $currentHeartRate.eraseToAnyPublisher()
    }

    /// Publisher para dados de calorias em tempo real
    @Published private(set) var currentCalories: Double = 0
    var caloriesPublisher: AnyPublisher<Double, Never> {
        $currentCalories.eraseToAnyPublisher()
    }

    /// Publisher para dados de sensor chunks
    @Published private(set) var latestSensorChunk: [SensorData] = []
    var sensorChunkPublisher: AnyPublisher<[SensorData], Never> {
        $latestSensorChunk.eraseToAnyPublisher()
    }

    /// Publisher para fase do workout
    @Published private(set) var currentPhase: WorkoutPhase = .execution
    var phasePublisher: AnyPublisher<WorkoutPhase, Never> {
        $currentPhase.eraseToAnyPublisher()
    }

    /// Publisher para contador de repetições
    @Published private(set) var currentReps: Int = 0
    var repsPublisher: AnyPublisher<Int, Never> {
        $currentReps.eraseToAnyPublisher()
    }
    
    /// Status do timer de descanso
    @Published private(set) var restTimerStatus: RestTimerStatus = .inactive
    
    /// 🆕 NOVA: Publisher para detecção automática de mudança de fase
    private let phaseChangeDetectionSubject = PassthroughSubject<PhaseChangeDetectionData, Never>()
    var phaseChangeDetectionPublisher: AnyPublisher<PhaseChangeDetectionData, Never> {
        phaseChangeDetectionSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    /// Sessão WCSession
    private var session: WCSession?
    
    // MARK: - Dependencies

    /// Core Data Service para persistência
    private let coreDataService: CoreDataServiceProtocol

    /// Workout Data Service para persistência específica
    private let workoutDataService: WorkoutDataServiceProtocol

    /// Sync Workout Use Case para sincronização
    private let syncWorkoutUseCase: SyncWorkoutUseCaseProtocol

    /// Update Data to ML Use Case para processamento
    private let updateDataToMLUseCase: UpdateDataToMLUseCaseProtocol
    
    /// Buffer para chunks de sensores
    private var sensorChunkBuffer: [SensorData] = []
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Logger para debug
    private let logger = Logger(subsystem: "com.fitter.app", category: "PhoneSessionManager")
    
    // MARK: - Initialization
    
    /// Inicializa PhoneSessionManager com dependências injetadas
    /// - Parameters:
    ///   - coreDataService: Serviço para operações Core Data
    ///   - workoutDataService: Serviço para operações de workout
    ///   - syncWorkoutUseCase: Use Case para sincronização
    ///   - updateDataToMLUseCase: Use Case para processamento ML
    init(
        coreDataService: CoreDataServiceProtocol = CoreDataService(),
        workoutDataService: WorkoutDataServiceProtocol = WorkoutDataService(),
        syncWorkoutUseCase: SyncWorkoutUseCaseProtocol = SyncWorkoutUseCase(syncManager: CloudSyncManager.shared),
        updateDataToMLUseCase: UpdateDataToMLUseCaseProtocol = UpdateDataToMLUseCase(mlModelManager: MLModelManager(), subscriptionManager: SubscriptionManager())
    ) {
        self.coreDataService = coreDataService
        self.workoutDataService = workoutDataService
        self.syncWorkoutUseCase = syncWorkoutUseCase
        self.updateDataToMLUseCase = updateDataToMLUseCase
        
        super.init()
        
        setupSession()
        print("📱 PhoneSessionManager inicializado com dependency injection")
    }
    
    deinit {
        stopSession()
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    /// Inicia a sessão WCSession
    func startSession() {
        guard WCSession.isSupported() else {
            logger.error("❌ WCSession não é suportado neste dispositivo")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        
        if session?.activationState == .notActivated {
            session?.activate()
            logger.info("🔄 Ativando WCSession...")
        } else {
            updateSessionState()
            logger.info("✅ WCSession já ativo")
        }
    }
    
    /// Para a sessão WCSession
    func stopSession() {
        session?.delegate = nil
        session = nil
        logger.info("🛑 WCSession parado")
    }
    
    /// Envia comando para o Apple Watch
    /// - Parameter command: Comando a ser enviado
    func sendCommand(_ command: WatchCommand) async throws {
        guard let session = session, session.isReachable else {
            throw PhoneSessionError.watchNotReachable
        }
        
        let message: [String: Any] = [
            "type": "command",
            "command": command.commandType.rawValue,
            "payload": command.payload,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        try await sendMessage(message)
        logger.info("📤 Comando enviado: \(command.commandType.rawValue)")
    }
    
    /// Envia mensagem para o Apple Watch
    /// - Parameter message: Mensagem a ser enviada
    func sendMessage(_ message: [String: Any]) async throws {
        guard let session = session, session.isReachable else {
            throw PhoneSessionError.watchNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume()
                self.logger.info("✅ Mensagem enviada com sucesso")
            }, errorHandler: { error in
                continuation.resume(throwing: PhoneSessionError.messageSendFailed(error))
                self.logger.error("❌ Erro ao enviar mensagem: \(error.localizedDescription)")
            })
        }
    }
    
    /// Atualiza o contexto da aplicação (persistente)
    /// - Parameter context: Contexto da aplicação
    func updateApplicationContext(_ context: [String: Any]) async throws {
        guard let session = session else {
            throw PhoneSessionError.watchNotReachable
        }
        
        do {
            try session.updateApplicationContext(context)
            logger.info("📱 Contexto da aplicação atualizado com sucesso")
        } catch {
            logger.error("❌ Erro ao atualizar contexto da aplicação: \(error.localizedDescription)")
            throw PhoneSessionError.messageSendFailed(error)
        }
    }
    
    /// Transfere arquivo para o Apple Watch
    /// - Parameters:
    ///   - fileURL: URL do arquivo
    ///   - metadata: Metadados opcionais
    func transferFile(_ fileURL: URL, metadata: [String: Any]?) async throws {
        guard let session = session, session.isReachable else {
            throw PhoneSessionError.watchNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let transfer = session.transferFile(fileURL, metadata: metadata)
            
            // Monitora o progresso da transferência
            if transfer.isTransferring {
                self.logger.info("📤 Transferindo arquivo: \(fileURL.lastPathComponent)")
            }
            
            // Configura completion handler
            transfer.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: PhoneSessionError.fileTransferFailed(error))
                    self.logger.error("❌ Erro na transferência: \(error.localizedDescription)")
                } else {
                    continuation.resume()
                    self.logger.info("✅ Arquivo transferido com sucesso")
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Configura a sessão WCSession
    private func setupSession() {
        guard WCSession.isSupported() else {
            logger.error("❌ WCSession não é suportado")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
    }
    
    /// Atualiza o estado da sessão
    private func updateSessionState() {
        guard let session = session else { return }
        
        isReachable = session.isReachable
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        
        logger.info("📱 Estado da sessão - Reachable: \(isReachable), Paired: \(isPaired), Installed: \(isWatchAppInstalled)")
    }
    
    /// Processa dados recebidos do Apple Watch
    /// - Parameter data: Dados recebidos
    private func processWatchData(_ data: WatchData) async {
        logger.info("📥 Processando dados do Watch: \(data.dataType.rawValue)")
        
        switch data.dataType {
        case .sensorChunk:
            await processSensorChunk(data.payload)
        case .heartRate:
            await processHeartRate(data.payload)
        case .calories:
            await processCalories(data.payload)
        case .phaseChange:
            await processPhaseChange(data.payload)
        case .phaseChangeDetected:  // 🆕 NOVA: Processa detecção automática
            await processPhaseChangeDetected(data.payload)
        case .repCount:
            await processRepCount(data.payload)
        case .timerUpdate:
            await processTimerUpdate(data.payload)
        case .workoutStatus:
            await processWorkoutStatus(data.payload)
        case .error:
            await processError(data.payload)
        }
    }
    
    /// Processa chunk de sensores
    /// - Parameter payload: Payload do chunk
    private func processSensorChunk(_ payload: [String: Any]) async {
        guard let chunkData = payload["sensorData"] as? Data else {
            logger.error("❌ Dados de sensor inválidos")
            return
        }
        
        do {
            let sensorData = try SensorData.fromBinaryData(chunkData)
            
            // ✅ NOVO: Atualizar Publisher
            latestSensorChunk = [sensorData] // Simplificado para um item
            
            // ✅ NOVO: Adicionar ao buffer
            sensorChunkBuffer.append(sensorData)
            
            // ✅ NOVO: Processar quando buffer atinge 100 amostras
            if sensorChunkBuffer.count >= 100 {
                await processSensorBuffer()
            }
            
            logger.info("📊 Chunk de sensor processado: \(sensorData.sampleCount ?? 1) amostras")
        } catch {
            logger.error("❌ Erro ao processar chunk de sensor: \(error.localizedDescription)")
        }
    }
    
    /// Processa buffer de sensores
    private func processSensorBuffer() async {
        guard !sensorChunkBuffer.isEmpty else { return }
        
        let buffer = sensorChunkBuffer
        sensorChunkBuffer.removeAll()
        
        // ✅ NOVO: Despachar para ML
        do {
            let chunk = SensorDataChunk(
                samples: buffer,
                sessionId: "current-session", // TODO: Obter da sessão ativa
                exerciseId: "current-exercise", // TODO: Obter do exercício ativo
                timestamp: Date()
            )
            
            let result = try await updateDataToMLUseCase.processChunk(chunk)
            
            // ✅ NOVO: Atualizar contador de repetições
            currentReps = result.totalReps
            
            logger.info("🧠 Buffer processado pelo ML: \(result.repsDetected) reps detectadas")
        } catch {
            logger.error("❌ Erro no processamento ML: \(error.localizedDescription)")
        }
        
        // ✅ NOVO: Persistir dados de sensor se há sessão ativa
        await persistSensorData(buffer)
    }
    
    /// Processa dados de heart rate
    /// - Parameter payload: Payload do heart rate
    private func processHeartRate(_ payload: [String: Any]) async {
        guard let heartRate = payload["value"] as? Double else {
            logger.error("❌ Dados de heart rate inválidos")
            return
        }
        
        // ✅ NOVO: Atualizar Publisher
        currentHeartRate = heartRate
        
        // ✅ NOVO: Persistir em Core Data se há sessão ativa
        await persistHealthData(heartRate: heartRate, calories: nil)
        
        logger.info("❤️ Heart rate atualizado: \(heartRate) BPM")
    }
    
    /// Processa dados de calories
    /// - Parameter payload: Payload das calories
    private func processCalories(_ payload: [String: Any]) async {
        guard let calories = payload["value"] as? Double else {
            logger.error("❌ Dados de calories inválidos")
            return
        }
        
        // ✅ NOVO: Atualizar Publisher
        currentCalories = calories
        
        // ✅ NOVO: Persistir em Core Data se há sessão ativa
        await persistHealthData(heartRate: nil, calories: calories)
        
        logger.info("🔥 Calories atualizadas: \(calories) kcal")
    }
    
    /// Processa mudança de fase
    /// - Parameter payload: Payload da mudança de fase
    private func processPhaseChange(_ payload: [String: Any]) async {
        guard let phaseString = payload["phase"] as? String,
              let phase = WorkoutPhase(rawValue: phaseString) else {
            logger.error("❌ Dados de fase inválidos")
            return
        }
        
        currentPhase = phase
        logger.info("🔄 Fase alterada para: \(phase.rawValue)")
    }
    
    /// Processa detecção automática de mudança de fase
    /// - Parameter payload: Payload da detecção
    private func processPhaseChangeDetected(_ payload: [String: Any]) async {
        guard let fromPhase = payload["from_phase"] as? String,
              let toPhase = payload["to_phase"] as? String,
              let detectedAt = payload["detected_at"] as? TimeInterval else {
            logger.error("❌ Dados de detecção de fase inválidos")
            return
        }
        
        // Extrair contexto da sessão se disponível
        let sessionId = payload["sessionId"] as? String ?? "unknown"
        let exerciseId = payload["exerciseId"] as? String ?? "unknown"
        let setId = payload["setId"] as? String ?? "unknown"
        let setOrder = payload["setOrder"] as? Int32 ?? 0
        let exerciseName = payload["exerciseName"] as? String ?? "Exercício"
        
        // Criar dados de detecção para o ViewModel
        let phaseDetectionData = PhaseChangeDetectionData(
            fromPhase: fromPhase,
            toPhase: toPhase,
            detectedAt: Date(timeIntervalSince1970: detectedAt),
            sessionId: sessionId,
            exerciseId: exerciseId,
            setId: setId,
            setOrder: setOrder,
            exerciseName: exerciseName,
            threshold: payload["threshold_used"] as? Double ?? 0.0,
            detectionDuration: payload["detection_duration"] as? TimeInterval ?? 0.0
        )
        
        // Atualizar fase atual
        if let phase = WorkoutPhase(rawValue: toPhase) {
            currentPhase = phase
        }
        
        // 🎯 NOTIFICAR VIEWMODEL: Enviar dados de detecção via Publisher
        phaseChangeDetectionSubject.send(phaseDetectionData)
        
        logger.info("🔄 Detecção automática processada: \(fromPhase) → \(toPhase) em \(exerciseName) (Set \(setOrder))")
    }
    
    /// Processa contador de repetições
    /// - Parameter payload: Payload do contador
    private func processRepCount(_ payload: [String: Any]) async {
        guard let reps = payload["count"] as? Int else {
            logger.error("❌ Dados de repetições inválidos")
            return
        }
        
        currentReps = reps
        logger.info("🔢 Repetições atualizadas: \(reps)")
    }
    
    /// Processa atualização do timer
    /// - Parameter payload: Payload do timer
    private func processTimerUpdate(_ payload: [String: Any]) async {
        guard let statusString = payload["status"] as? String,
              let status = RestTimerStatus(rawValue: statusString) else {
            logger.error("❌ Dados de timer inválidos")
            return
        }
        
        restTimerStatus = status
        logger.info("⏱️ Status do timer atualizado: \(status.rawValue)")
    }
    
    /// Processa status do workout
    /// - Parameter payload: Payload do status
    private func processWorkoutStatus(_ payload: [String: Any]) async {
        logger.info("🏋️ Status do workout recebido")
        // TODO: Implementar processamento do status (item futuro)
    }
    
    /// Processa erro do Watch
    /// - Parameter payload: Payload do erro
    private func processError(_ payload: [String: Any]) async {
        guard let errorMessage = payload["message"] as? String else {
            logger.error("❌ Dados de erro inválidos")
            return
        }
        
        logger.error("❌ Erro do Watch: \(errorMessage)")
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ Erro na ativação do WCSession: \(error.localizedDescription)")
        } else {
            logger.info("✅ WCSession ativado com sucesso")
            updateSessionState()
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.warning("⚠️ WCSession tornou-se inativo")
        updateSessionState()
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        logger.warning("⚠️ WCSession desativado")
        updateSessionState()
        
        // Reativa a sessão
        WCSession.default.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("📱 Reachability alterada: \(session.isReachable)")
        updateSessionState()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task {
            await processReceivedMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task {
            await processReceivedMessage(message)
            replyHandler(["status": "received"])
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Task {
            await processReceivedFile(file)
        }
    }
    
    // MARK: - Private WCSession Methods
    
    /// Processa mensagem recebida do Watch
    /// - Parameter message: Mensagem recebida
    private func processReceivedMessage(_ message: [String: Any]) async {
        guard let typeString = message["type"] as? String else {
            logger.error("❌ Tipo de mensagem inválido")
            return
        }
        
        // 🆕 PROCESSAR DETECÇÃO DE MUDANÇA DE FASE
        if typeString == "phase_change_detected" {
            let watchData = WatchDataImpl(
                dataType: .phaseChangeDetected,
                timestamp: Date(),
                payload: message
            )
            await processWatchData(watchData)
            return
        }
        
        // Processar outros tipos de dados
        guard let dataType = WatchDataType(rawValue: typeString) else {
            logger.error("❌ Tipo de dados inválido: \(typeString)")
            return
        }
        
        let watchData = WatchDataImpl(
            dataType: dataType,
            timestamp: Date(),
            payload: message
        )
        
        await processWatchData(watchData)
    }
    
    /// Processa arquivo recebido do Watch
    /// - Parameter file: Arquivo recebido
    private func processReceivedFile(_ file: WCSessionFile) async {
        logger.info("📁 Arquivo recebido: \(file.fileURL.lastPathComponent)")
        
        // TODO: Processar arquivo de sensor data (item futuro)
        // TODO: Persistir em entidades history (item futuro)
    }
}

// MARK: - Supporting Types

/// Status do timer de descanso
enum RestTimerStatus: String, CaseIterable {
    case inactive = "inactive"
    case active = "active"
    case paused = "paused"
    case completed = "completed"
}

/// Fase do workout
enum WorkoutPhase: String, CaseIterable {
    case execution = "execution"
    case rest = "rest"
}

/// Erros do PhoneSessionManager
enum PhoneSessionError: LocalizedError {
    case watchNotReachable
    case messageSendFailed(Error)
    case fileTransferFailed(Error)
    case invalidData
    case processingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .watchNotReachable:
            return "Apple Watch não está reachable"
        case .messageSendFailed(let error):
            return "Falha ao enviar mensagem: \(error.localizedDescription)"
        case .fileTransferFailed(let error):
            return "Falha na transferência de arquivo: \(error.localizedDescription)"
        case .invalidData:
            return "Dados inválidos recebidos"
        case .processingFailed(let error):
            return "Falha no processamento: \(error.localizedDescription)"
        }
    }
}

/// Implementação de WatchData
private struct WatchDataImpl: WatchData {
    let dataType: WatchDataType
    let timestamp: Date
    let payload: [String: Any]
}

/// Implementação de WatchCommand
struct WatchCommandImpl: WatchCommand {
    let commandType: WatchCommandType
    let payload: [String: Any]
}

// MARK: - Logger

private struct Logger {
    private let subsystem: String
    private let category: String
    
    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
    
    func info(_ message: String) {
        print("📱 [\(category)] \(message)")
    }
    
    func warning(_ message: String) {
        print("⚠️ [\(category)] \(message)")
    }
    
    func error(_ message: String) {
        print("❌ [\(category)] \(message)")
    }
}

#if DEBUG
// MARK: - Preview Support
extension PhoneSessionManager {
    
    /// Cria instância para preview
    /// - Returns: PhoneSessionManager configurado para preview
    static func previewInstance() -> PhoneSessionManager {
        let manager = PhoneSessionManager()
        manager.isReachable = true
        manager.isPaired = true
        manager.isWatchAppInstalled = true
        return manager
    }
}
#endif 

// MARK: - Persistência de Dados

/// Persiste dados de health (heart rate/calories) em tempo real
private func persistHealthData(heartRate: Double?, calories: Double?) async {
    // TODO: Implementar persistência em CDCurrentSet ativo
    // Aguarda integração com Use Cases de Lifecycle
    
    do {
        // Buscar sessão ativa
        // let activeSession = try await workoutDataService.fetchActiveSession(user: currentUser)
        // let activeSet = try await workoutDataService.fetchActiveSet(session: activeSession)
        
        // Atualizar dados de health no set ativo
        // try await workoutDataService.updateSetHealthData(set: activeSet, heartRate: heartRate, calories: calories)
        
        logger.info("💾 Dados de health persistidos (placeholder)")
    } catch {
        logger.error("❌ Erro ao persistir dados de health: \(error.localizedDescription)")
    }
}

/// Persiste dados de sensor em tempo real
private func persistSensorData(_ sensorData: [SensorData]) async {
    // TODO: Implementar persistência em CDCurrentSet ativo
    // Aguarda integração com Use Cases de Lifecycle
    
    do {
        // Buscar sessão ativa
        // let activeSession = try await workoutDataService.fetchActiveSession(user: currentUser)
        // let activeSet = try await workoutDataService.fetchActiveSet(session: activeSession)
        
        // Serializar e salvar dados de sensor
        // let serializedData = try CoreDataAdapter.serializeSensorData(sensorData)
        // try await workoutDataService.updateSetSensorData(set: activeSet, sensorData: serializedData)
        
        logger.info("💾 Dados de sensor persistidos (placeholder): \(sensorData.count) amostras")
    } catch {
        logger.error("❌ Erro ao persistir dados de sensor: \(error.localizedDescription)")
    }
} 