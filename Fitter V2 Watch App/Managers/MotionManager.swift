//
//  MotionManager.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import CoreMotion
import Combine

/// MotionManager: Responsável pela captura de dados brutos dos sensores do Apple Watch
///
/// Responsabilidades:
/// - Captura de dados brutos dos sensores com frequência variável (50Hz/20Hz)
/// - Bufferização de 100 amostras por chunk
/// - Empacotamento dos dados em SensorData
/// - Delegação do envio para WatchSessionManager
/// - Detecção automática de fase (Execução/Descanso) "Apple Style"
///
/// Arquitetura:
/// - Separação clara de responsabilidades (apenas captura, bufferização e detecção de fase)
/// - Sem processamento ou análise de dados (exceto detecção de fase)
/// - Sem comunicação direta com iPhone
/// - Integração via injeção de dependências

@MainActor
final class MotionManager: NSObject, ObservableObject {
    // MARK: - Types

    enum WorkoutPhase {
        case execution  // 50Hz
        case rest      // 20Hz

        var samplingRate: Double {
            switch self {
            case .execution: return 50.0  // 0.02s
            case .rest: return 20.0       // 0.05s
            }
        }
    }

    // MARK: - Dependencies

    private let sessionManager: WatchSessionManager
    private let phaseManager: WorkoutPhaseManager
    
    // MARK: - Properties

    /// Core Motion manager
    private let motionManager = CMMotionManager()

    /// Fila de operação para processamento de dados
    private let motionQueue = OperationQueue()

    /// Buffer circular para otimização de memória (envio)
    private var sensorBuffer: [SensorData] = []
    private let bufferSize = 100

    /// Buffer curto para detecção automática de fase
    private var activityBuffer: [SensorData] = []
    private let activityWindowSize = 50 // ~1s em 50Hz

    // Thresholds para detecção automática de descanso/execução
    private let thresholdRest: Double = 0.015
    private let thresholdExec: Double = 0.025
    private let detectRestDuration: TimeInterval = 1.0
    private let detectExecDuration: TimeInterval = 0.5
    private var lastRestDetect: Date?
    private var lastExecDetect: Date?

    /// Fase atual do treino
    @Published private(set) var currentPhase: WorkoutPhase = .execution {
        didSet {
            updateSamplingRate()
        }
    }

    /// Estado de gravação
    @Published private(set) var isRecording = false

    // MARK: - Lifecycle

    init(sessionManager: WatchSessionManager, phaseManager: WorkoutPhaseManager) {
        self.sessionManager = sessionManager
        self.phaseManager = phaseManager
        super.init()
        setupMotionManager()
    }

    // MARK: - Setup

    private func setupMotionManager() {
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated
        updateSamplingRate()
    }

    private func updateSamplingRate() {
        let interval = 1.0 / currentPhase.samplingRate
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.accelerometerUpdateInterval = interval
        motionManager.gyroUpdateInterval = interval
        motionManager.magnetometerUpdateInterval = interval
    }

    // MARK: - Public Methods

    /// Inicia a captura de dados de movimento
    func startMotionUpdates() async {
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion não disponível")
            return
        }
        
        // Iniciar captura de dados com todos os sensores
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, error in
            guard let self = self,
                  let motion = motion else {
            if let error = error {
                print("❌ Erro na captura de movimento: \(error.localizedDescription)")
                }
                return
            }
            
            // Criar SensorData com dados brutos
            let newData = SensorData(
                // Acelerômetro
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,

                // Giroscópio
                rotationX: motion.rotationRate.x,
                rotationY: motion.rotationRate.y,
                rotationZ: motion.rotationRate.z,

                // Gravidade
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z,

                // Orientação
                attitudeRoll: motion.attitude.roll,
                attitudePitch: motion.attitude.pitch,
                attitudeYaw: motion.attitude.yaw,

                // Campo magnético (se disponível)
                magneticFieldX: motion.magneticField?.field.x,
                magneticFieldY: motion.magneticField?.field.y,
                magneticFieldZ: motion.magneticField?.field.z,

                // Metadados
                captureFrequency: self.currentPhase.samplingRate,
                sampleCount: 1,
                capturedAt: Date()
            )

            // Adicionar ao buffer e ao buffer de atividade
            Task { @MainActor in
                await self.addToBuffer(newData)
            }
        }

        isRecording = true
    }

    /// Para a captura de dados de movimento
    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        isRecording = false

        // Enviar dados remanescentes
        Task {
            await flushBuffer()
        }
        activityBuffer.removeAll()
        lastRestDetect = nil
        lastExecDetect = nil
    }

    /// Atualiza a fase do treino manualmente
    func updatePhase(_ newPhase: WorkoutPhase) {
        currentPhase = newPhase
    }

    // MARK: - Buffer Management

    private func addToBuffer(_ data: SensorData) async {
        sensorBuffer.append(data)

        // Buffer de atividade para detecção de fase
        activityBuffer.append(data)
        if activityBuffer.count > activityWindowSize {
            activityBuffer.removeFirst(activityBuffer.count - activityWindowSize)
        }
        await detectPhaseAutomatically()

        // Flush do buffer de envio
        if sensorBuffer.count >= bufferSize {
            await flushBuffer()
        }
    }

    private func flushBuffer() async {
        guard !sensorBuffer.isEmpty else { return }

        // Criar chunk com dados atuais
        let chunk = Array(sensorBuffer)
        sensorBuffer.removeAll(keepingCapacity: true)

        // Delegar envio para WatchSessionManager
        await sessionManager.sendSensorDataChunk(chunk)
    }

    // MARK: - Detecção automática de fase (Apple Style)

    private func detectPhaseAutomatically() async {
        guard !activityBuffer.isEmpty else { return }
        let avgMagnitude = activityBuffer
            .map { sqrt($0.accelerationX * $0.accelerationX +
                        $0.accelerationY * $0.accelerationY +
                        $0.accelerationZ * $0.accelerationZ) }
            .reduce(0, +) / Double(activityBuffer.count)
        let now = Date()

        switch currentPhase {
        case .execution:
            if avgMagnitude < thresholdRest {
                if let last = lastRestDetect, now.timeIntervalSince(last) > detectRestDuration {
                    await MainActor.run { self.updatePhase(.rest) }
                    
                    // 🆕 NOTIFICAR IPHONE: Detectou mudança de padrão (parou de fazer exercício)
                    await notifyPhoneOfPhaseChange(from: .execution, to: .rest, detectedAt: now)
                    
                    lastRestDetect = nil
                } else if lastRestDetect == nil {
                    lastRestDetect = now
                }
            } else {
                lastRestDetect = nil
            }
        case .rest:
            if avgMagnitude > thresholdExec {
                if let last = lastExecDetect, now.timeIntervalSince(last) > detectExecDuration {
                    await MainActor.run { self.updatePhase(.execution) }
                    lastExecDetect = nil
                } else if lastExecDetect == nil {
                    lastExecDetect = now
                }
            } else {
                lastExecDetect = nil
            }
        }
    }
    
    // 🆕 NOVA FUNÇÃO: Notifica iPhone sobre mudança de fase
    private func notifyPhoneOfPhaseChange(from oldPhase: WorkoutPhase, to newPhase: WorkoutPhase, detectedAt: Date) async {
        let phaseChangeData: [String: Any] = [
            "type": "phase_change_detected",
            "from_phase": oldPhase == .execution ? "execution" : "rest",
            "to_phase": newPhase == .execution ? "execution" : "rest",
            "detected_at": detectedAt.timeIntervalSince1970,
            "threshold_used": newPhase == .rest ? thresholdRest : thresholdExec,
            "detection_duration": newPhase == .rest ? detectRestDuration : detectExecDuration
        ]
        
        // Enviar para iPhone via WatchSessionManager
        await sessionManager.sendPhaseChangeDetection(phaseChangeData)
        
        print("🔄 Mudança de fase detectada e notificada: \(oldPhase) → \(newPhase)")
    }
}

// MARK: - Debug Extensions

extension MotionManager {
    /// Retorna estatísticas de captura
    var captureStats: String {
        """
        📊 Captura Stats:
        - Fase: \(currentPhase)
        - Taxa: \(currentPhase.samplingRate)Hz
        - Intervalo: \(1.0 / currentPhase.samplingRate * 1000)ms
        - Buffer: \(sensorBuffer.count)/\(bufferSize)
        - Sensores: Acelerômetro, Giroscópio, Gravidade, Atitude, Magnetômetro
        - QoS: \(motionQueue.qualityOfService.rawValue)
        """
    }
}
