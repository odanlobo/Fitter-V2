//
//  MotionManager.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import CoreMotion
import WatchConnectivity
import HealthKit

class MotionManager: NSObject, ObservableObject {
    static let shared = MotionManager()
    
    // MARK: - Properties
    private let motionManager = CMMotionManager()
    private let healthStore = HKHealthStore()
    
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    
    @Published var isRecording = false
    @Published var currentHeartRate: Int = 0
    @Published var currentCalories: Double = 0
    @Published var motionData: [CMDeviceMotion] = []
    
    private var sessionStartTime: Date?
    private var currentSetId: UUID?
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupHealthKit()
    }
    
    // MARK: - HealthKit Setup
    private func setupHealthKit() {
        let workoutConfiguration = HKWorkoutConfiguration()
        workoutConfiguration.activityType = .functionalStrengthTraining
        workoutConfiguration.locationType = .indoor
        
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
            self.workoutSession = session
            self.workoutBuilder = HKWorkoutBuilder(healthStore: healthStore, configuration: workoutConfiguration, device: .local())
            session.delegate = self
        } catch {
            print("❌ Erro ao criar sessão de treino: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recording Control
    
    /// Inicia gravação completa
    func startRecording() {
        guard !isRecording else { return }
        
        // 1. Iniciar a sessão do HealthKit
        startWorkoutSession()
        
        // 2. Configurar o CoreMotion
        setupMotionTracking()
        
        // 3. Marcar como gravando
        isRecording = true
        sessionStartTime = Date()
        
        // 4. Notificar início do treino
        addSensorData(WatchSensorData(type: .workoutStarted, duration: 0))
        
        print("🎬 Gravação de treino iniciada")
    }
    
    /// Para gravação completa
    func stopRecording() {
        guard isRecording else { return }
        
        // 1. Parar o CoreMotion
        motionManager.stopDeviceMotionUpdates()
        
        // 2. Finalizar a sessão do HealthKit
        stopWorkoutSession()
        
        // 3. Processar e salvar dados finais
        saveAndSendData()
        
        // 4. Marcar como parado
        isRecording = false
        currentSetId = nil
        
        print("⏹️ Gravação de treino finalizada")
    }
    
    /// Inicia captura específica para uma série
    func startSetRecording(setId: UUID) {
        guard isRecording else {
            print("⚠️ Treino não está sendo gravado")
            return
        }
        
        currentSetId = setId
        print("📊 Iniciando captura para série: \(setId)")
    }
    
    /// Finaliza captura de uma série específica
    func completeSet(setId: UUID) {
        guard currentSetId == setId else {
            print("⚠️ ID da série não confere")
            return
        }
        
        let setData = WatchSensorData(
            type: .setCompleted,
            heartRate: currentHeartRate > 0 ? currentHeartRate : nil,
            calories: currentCalories > 0 ? currentCalories : nil,
            setId: setId
        )
        
        addSensorData(setData)
        currentSetId = nil
        print("✅ Série \(setId) completada - dados de sensores enviados")
    }
    
    // MARK: - Motion Tracking
    private func setupMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion não está disponível")
            return
        }
        
        // Limpar dados anteriores
        motionData.removeAll()
        
        // Configurar a frequência de atualização
        motionManager.deviceMotionUpdateInterval = 0.033
        
        // Iniciar a captura de dados
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, self.isRecording else { return }
            
            if let error = error {
                print("❌ Erro na captura de movimento: \(error.localizedDescription)")
                return
            }
            
            // Armazenar os dados
            self.motionData.append(motion)
            
            // Processar dados em tempo real se há uma série ativa
            if self.currentSetId != nil {
                self.processCurrentSetMotion(motion)
            }
        }
    }
    
    private func processCurrentSetMotion(_ motion: CMDeviceMotion) {
        guard let setId = currentSetId else { return }
        
        // Processar a cada 0.5 segundo
        if motionData.count % 15 == 0 {
            let movementData = WatchSensorData(
                type: .movement,
                heartRate: currentHeartRate > 0 ? currentHeartRate : nil,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                rotationX: motion.rotationRate.x,
                rotationY: motion.rotationRate.y,
                rotationZ: motion.rotationRate.z,
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z,
                attitudeRoll: motion.attitude.roll,
                attitudePitch: motion.attitude.pitch,
                attitudeYaw: motion.attitude.yaw,
                setId: setId
            )
            
            addSensorData(movementData)
        }
    }
    
    // MARK: - Rest Period Tracking
    func startRestPeriod() {
        let restData = WatchSensorData(
            type: .restStarted,
            heartRate: currentHeartRate > 0 ? currentHeartRate : nil
        )
        addSensorData(restData)
    }
    
    func endRestPeriod(duration: TimeInterval) {
        let restData = WatchSensorData(
            type: .restCompleted,
            heartRate: currentHeartRate > 0 ? currentHeartRate : nil,
            duration: duration
        )
        addSensorData(restData)
        print("⏱️ Descanso registrado: \(duration)s")
    }
    
    // MARK: - Data Management
    private func addSensorData(_ data: WatchSensorData) {
        // Adicionar aos dados pendentes do WatchDataManager
        DispatchQueue.main.async {
            WatchDataManager.shared.addSensorData(data)
        }
    }
    
    private func saveAndSendData() {
        guard let startTime = sessionStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Converter os dados para formato serializável
        var dataToSend: [[String: Double]] = []
        
        for motion in motionData {
            let motionDict: [String: Double] = [
                "timestamp": motion.timestamp,
                "rotationX": motion.rotationRate.x,
                "rotationY": motion.rotationRate.y,
                "rotationZ": motion.rotationRate.z,
                "accelerationX": motion.userAcceleration.x,
                "accelerationY": motion.userAcceleration.y,
                "accelerationZ": motion.userAcceleration.z,
                "gravityX": motion.gravity.x,
                "gravityY": motion.gravity.y,
                "gravityZ": motion.gravity.z,
                "attitudeRoll": motion.attitude.roll,
                "attitudePitch": motion.attitude.pitch,
                "attitudeYaw": motion.attitude.yaw
            ]
            dataToSend.append(motionDict)
        }
        
        // Salvar dados de fim de treino
        let endData = WatchSensorData(
            type: .workoutCompleted,
            heartRate: currentHeartRate > 0 ? currentHeartRate : nil,
            calories: currentCalories > 0 ? currentCalories : nil,
            duration: duration
        )
        
        addSensorData(endData)
        
        // Enviar para o iPhone
        sendDataToiPhone(data: dataToSend)
        
        // Limpar dados temporários
        motionData.removeAll()
        sessionStartTime = nil
    }
    
    private func sendDataToiPhone(data: [[String: Double]]) {
        let message: [String: Any] = [
            "type": "motionData",
            "data": data,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Usar a versão síncrona do ConnectivityManager como no Fit2
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("WCSession não está ativado")
            return
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Erro ao enviar dados para o iPhone: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Workout Session Management
    private func startWorkoutSession() {
        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder else { return }
        
        do {
            try workoutSession.startActivity(with: Date())
            
            workoutBuilder.beginCollection(withStart: Date()) { (success, error) in
                if let error = error {
                    print("❌ Erro ao iniciar coleta: \(error.localizedDescription)")
                }
            }
        } catch {
            print("❌ Erro ao iniciar sessão: \(error.localizedDescription)")
        }
    }
    
    private func stopWorkoutSession() {
        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder else { return }
        
        workoutSession.end()
        
        workoutBuilder.endCollection(withEnd: Date()) { (success, error) in
            if let error = error {
                print("❌ Erro ao finalizar coleta: \(error.localizedDescription)")
                return
            }
            
            workoutBuilder.finishWorkout { (workout, error) in
                if let error = error {
                    print("❌ Erro ao finalizar treino: \(error.localizedDescription)")
                } else {
                    print("✅ Treino salvo no HealthKit")
                }
            }
        }
    }
    
    // MARK: - Command Processing
    func processCommand(_ command: String) {
        DispatchQueue.main.async {
            switch command {
            case "startRecording":
                if !self.isRecording {
                    self.startRecording()
                }
            case "stopRecording":
                if self.isRecording {
                    self.stopRecording()
                }
            default:
                print("Comando desconhecido: \(command)")
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension MotionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("🏃‍♂️ Sessão de treino mudou de \(fromState.rawValue) para \(toState.rawValue)")
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("❌ Sessão de treino falhou: \(error.localizedDescription)")
    }
} 