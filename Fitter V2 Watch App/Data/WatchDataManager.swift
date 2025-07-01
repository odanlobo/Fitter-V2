//
//  WatchDataManager.swift
//  Fitter V2 Watch App
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import WatchKit
import HealthKit
import Combine

/// Gerenciador de dados simplificado para o Apple Watch
/// Responsável por:
/// 1. Receber dados do iPhone via WatchConnectivity
/// 2. Armazenar temporariamente dados de sensores
/// 3. Sincronizar dados de volta para o iPhone
@MainActor
final class WatchDataManager: ObservableObject {
    static let shared = WatchDataManager()
    
    // MARK: - Published Properties
    @Published var workoutPlans: [WatchWorkoutPlan] = []
    @Published var pendingSensorData: [WatchSensorData] = []
    @Published var isConnectedToPhone = false
    @Published var currentSessionContext: WatchSessionContext?
    
    // MARK: - Private Properties
    private let connectivity = ConnectivityManager.shared
    private let userDefaults = UserDefaults.standard
    private let sensorDataKey = "pendingSensorData"
    private let sessionContextKey = "currentSessionContext"
    
    private init() {
        loadPendingSensorData()
        loadSessionContext()
        setupConnectivityObserver()
    }
    
    // MARK: - Workout Plans Management
    
    func updateWorkoutPlans(_ plans: [WatchWorkoutPlan]) {
        self.workoutPlans = plans
        print("📱➡️⌚ Recebidos \(plans.count) planos do iPhone")
    }
    
    // MARK: - Session Context Management
    
    func updateSessionContext(_ context: WatchSessionContext) {
        self.currentSessionContext = context
        saveSessionContext()
        print("📱➡️⌚ Contexto de sessão atualizado: \(context.currentExerciseName)")
    }
    
    func clearSessionContext() {
        self.currentSessionContext = nil
        saveSessionContext()
        print("📱➡️⌚ Contexto de sessão limpo")
    }
    
    // MARK: - Sensor Data Management (with Session Context)
    
    func addSensorData(_ data: WatchSensorData) {
        // Se há contexto de sessão ativo, usa os IDs corretos
        var updatedData = data
        if let context = currentSessionContext {
            updatedData = WatchSensorData(
                type: data.type,
                heartRate: data.heartRate,
                calories: data.calories,
                duration: data.duration,
                reps: data.reps,
                weight: data.weight,
                accelerationX: data.accelerationX,
                accelerationY: data.accelerationY,
                accelerationZ: data.accelerationZ,
                rotationX: data.rotationX,
                rotationY: data.rotationY,
                rotationZ: data.rotationZ,
                gravityX: data.gravityX,
                gravityY: data.gravityY,
                gravityZ: data.gravityZ,
                attitudeRoll: data.attitudeRoll,
                attitudePitch: data.attitudePitch,
                attitudeYaw: data.attitudeYaw,
                setId: UUID(uuidString: context.currentSetId), // USA O ID DO CONTEXTO
                sessionId: UUID(uuidString: context.sessionId),
                exerciseId: UUID(uuidString: context.currentExerciseId),
                planId: UUID(uuidString: context.planId)
            )
        }
        
        pendingSensorData.append(updatedData)
        savePendingSensorData()
        
        // Tenta enviar imediatamente se conectado
        if isConnectedToPhone {
            Task {
                await syncSensorDataToPhone()
            }
        }
        
        print("⌚📊 Dados de sensor adicionados com contexto: \(updatedData.type)")
    }
    
    func syncSensorDataToPhone() async {
        guard !pendingSensorData.isEmpty, isConnectedToPhone else { return }
        
        let dataToSync = pendingSensorData
        
        // Converte para formato de mensagem
        let message: [String: Any] = [
            "type": "sensorData",
            "data": dataToSync.map { $0.toDictionary() }
        ]
        
        // Envia via WatchConnectivity
        await connectivity.sendMessage(message) { [weak self] response in
            Task { @MainActor in
                if response["success"] as? Bool == true {
                    // Remove dados confirmados
                    self?.removeSyncedData(dataToSync)
                    print("✅ Dados de sensor sincronizados com iPhone")
                } else {
                    print("❌ Falha na sincronização de dados de sensor")
                }
            }
        }
    }
    
    private func removeSyncedData(_ syncedData: [WatchSensorData]) {
        let syncedIds = Set(syncedData.map(\.id))
        pendingSensorData.removeAll { syncedIds.contains($0.id) }
        savePendingSensorData()
    }
    
    // MARK: - Persistence
    
    private func savePendingSensorData() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(pendingSensorData) {
            userDefaults.set(encoded, forKey: sensorDataKey)
        }
    }
    
    private func loadPendingSensorData() {
        guard let data = userDefaults.data(forKey: sensorDataKey) else { return }
        
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([WatchSensorData].self, from: data) {
            pendingSensorData = decoded
        }
    }
    
    private func loadSessionContext() {
        guard let data = userDefaults.data(forKey: sessionContextKey) else { return }
        
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(WatchSessionContext.self, from: data) {
            currentSessionContext = decoded
        }
    }
    
    private func saveSessionContext() {
        let encoder = JSONEncoder()
        if let context = currentSessionContext,
           let encoded = try? encoder.encode(context) {
            userDefaults.set(encoded, forKey: sessionContextKey)
        } else {
            userDefaults.removeObject(forKey: sessionContextKey)
        }
    }
    
    // MARK: - Connectivity
    
    private func setupConnectivityObserver() {
        // Observa mudanças na conectividade
        connectivity.$isReachable
            .assign(to: &$isConnectedToPhone)
        
        // Tenta sincronizar quando reconectar
        connectivity.$isReachable
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncSensorDataToPhone()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Watch Models

/// Versão simplificada do WorkoutPlan para o Watch
struct WatchWorkoutPlan: Identifiable, Codable {
    let id: UUID
    let title: String
    let exercises: [WatchExercise]
    let muscleGroups: String
    
    init(from dict: [String: Any]) {
        self.id = UUID(uuidString: dict["id"] as? String ?? "") ?? UUID()
        self.title = dict["title"] as? String ?? ""
        self.muscleGroups = dict["muscleGroups"] as? String ?? ""
        
        if let exercisesData = dict["exercises"] as? [[String: Any]] {
            self.exercises = exercisesData.compactMap { WatchExercise(from: $0) }
        } else {
            self.exercises = []
        }
    }
}

/// Versão simplificada do Exercise para o Watch
struct WatchExercise: Identifiable, Codable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let equipment: String
    
    init(from dict: [String: Any]) {
        self.id = UUID(uuidString: dict["id"] as? String ?? "") ?? UUID()
        self.name = dict["name"] as? String ?? ""
        self.muscleGroup = dict["muscleGroup"] as? String ?? ""
        self.equipment = dict["equipment"] as? String ?? ""
    }
}

/// Contexto da sessão ativa sincronizado com o iPhone
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

/// Dados de sensores captados pelo Watch
struct WatchSensorData: Identifiable, Codable {
    let id: UUID
    let type: SensorType
    let timestamp: Date
    let heartRate: Int?
    let calories: Double?
    let duration: TimeInterval?
    let reps: Int?
    let weight: Double?
    
    // Dados de movimento - todos os sensores do diagrama
    let accelerationX: Double?
    let accelerationY: Double?
    let accelerationZ: Double?
    let rotationX: Double?
    let rotationY: Double?
    let rotationZ: Double?
    let gravityX: Double?
    let gravityY: Double?
    let gravityZ: Double?
    let attitudeRoll: Double?
    let attitudePitch: Double?
    let attitudeYaw: Double?
    
    // Identificação da série (para mapear com CurrentSet)
    let setId: UUID?
    
    // Identificação da sessão
    let sessionId: UUID?
    let exerciseId: UUID?
    let planId: UUID?
    
    init(
        type: SensorType,
        heartRate: Int? = nil,
        calories: Double? = nil,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        accelerationX: Double? = nil,
        accelerationY: Double? = nil,
        accelerationZ: Double? = nil,
        rotationX: Double? = nil,
        rotationY: Double? = nil,
        rotationZ: Double? = nil,
        gravityX: Double? = nil,
        gravityY: Double? = nil,
        gravityZ: Double? = nil,
        attitudeRoll: Double? = nil,
        attitudePitch: Double? = nil,
        attitudeYaw: Double? = nil,
        setId: UUID? = nil,
        sessionId: UUID? = nil,
        exerciseId: UUID? = nil,
        planId: UUID? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.heartRate = heartRate
        self.calories = calories
        self.duration = duration
        self.reps = reps
        self.weight = weight
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
        self.attitudeRoll = attitudeRoll
        self.attitudePitch = attitudePitch
        self.attitudeYaw = attitudeYaw
        self.setId = setId
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.planId = planId
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "type": type.rawValue,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        
        if let heartRate = heartRate { dict["heartRate"] = heartRate }
        if let calories = calories { dict["calories"] = calories }
        if let duration = duration { dict["duration"] = duration }
        if let reps = reps { dict["reps"] = reps }
        if let weight = weight { dict["weight"] = weight }
        if let accelerationX = accelerationX { dict["accelerationX"] = accelerationX }
        if let accelerationY = accelerationY { dict["accelerationY"] = accelerationY }
        if let accelerationZ = accelerationZ { dict["accelerationZ"] = accelerationZ }
        if let rotationX = rotationX { dict["rotationX"] = rotationX }
        if let rotationY = rotationY { dict["rotationY"] = rotationY }
        if let rotationZ = rotationZ { dict["rotationZ"] = rotationZ }
        if let gravityX = gravityX { dict["gravityX"] = gravityX }
        if let gravityY = gravityY { dict["gravityY"] = gravityY }
        if let gravityZ = gravityZ { dict["gravityZ"] = gravityZ }
        if let attitudeRoll = attitudeRoll { dict["attitudeRoll"] = attitudeRoll }
        if let attitudePitch = attitudePitch { dict["attitudePitch"] = attitudePitch }
        if let attitudeYaw = attitudeYaw { dict["attitudeYaw"] = attitudeYaw }
        if let setId = setId { dict["setId"] = setId.uuidString }
        if let sessionId = sessionId { dict["sessionId"] = sessionId.uuidString }
        if let exerciseId = exerciseId { dict["exerciseId"] = exerciseId.uuidString }
        if let planId = planId { dict["planId"] = planId.uuidString }
        
        return dict
    }
}

/// Tipos de dados de sensor coletados pelo Watch
enum SensorType: String, CaseIterable, Codable {
    case workoutStarted = "workoutStarted"
    case workoutCompleted = "workoutCompleted"
    case setCompleted = "setCompleted"
    case movement = "movement"
    case restStarted = "restStarted"
    case restCompleted = "restCompleted"
    case heartRate = "heartRate"
    case calories = "calories"
} 