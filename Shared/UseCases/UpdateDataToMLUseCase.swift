import Foundation
import Combine

// MARK: - UpdateDataToMLUseCase Protocol

/// Protocol básico para processamento de dados ML (futuro)
protocol UpdateDataToMLUseCaseProtocol {
    func processChunk(_ chunk: SensorDataChunk) async throws -> MLProcessingResult
    func getCurrentRepsCount() -> Int
    func getRepTimeline() -> [RepDetection]
    func resetSession()
}

// MARK: - Modelos Básicos

/// Chunk de dados de sensores
struct SensorDataChunk {
    let samples: [SensorData]
    let sessionId: String
    let exerciseId: String?
    let timestamp: Date
}

/// Resultado básico do processamento
struct MLProcessingResult {
    let repsDetected: Int
    let totalReps: Int
    let confidence: Double
    let processingTime: TimeInterval
}

/// Detecção de repetição
struct RepDetection {
    let repNumber: Int
    let timestamp: Date
    let confidence: Double
}

/// Ponto do movimento para timeline detalhada
struct MovementPoint {
    let timestamp: Double          // Segundos desde início da série
    let movement: Double          // Valor -1.0 a +1.0 (fase excêntrica a concêntrica)
    let repIndex: Int?           // Número da repetição quando movimento completo é detectado
    
    /// Interpretação do valor movement por tipo de exercício:
    /// -1.0 = Fase excêntrica (alongamento/descida):
    ///   • Agachamento: posição mais baixa
    ///   • Bíceps: braço totalmente estendido
    ///   • Supino: peso tocando o peito
    ///   • Flexão: peito próximo ao chão
    ///  0.0 = Posição neutra (transição entre fases)
    /// +1.0 = Fase concêntrica (contração/subida):
    ///   • Agachamento: totalmente em pé
    ///   • Bíceps: braço totalmente contraído
    ///   • Supino: braços totalmente estendidos
    ///   • Flexão: braços totalmente estendidos
    
    /// Para JSON serialization
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": timestamp,
            "movement": movement
        ]
        
        if let repIndex = repIndex {
            dict["repIndex"] = repIndex
        }
        
        return dict
    }
    
    /// From JSON deserialization
    static func fromDictionary(_ dict: [String: Any]) -> MovementPoint? {
        guard let timestamp = dict["timestamp"] as? Double,
              let movement = dict["movement"] as? Double else {
            return nil
        }
        
        let repIndex = dict["repIndex"] as? Int
        
        return MovementPoint(
            timestamp: timestamp,
            movement: movement,
            repIndex: repIndex
        )
    }
}

/// Timeline completa de movimento para uma série
struct MovementTimeline {
    let points: [MovementPoint]
    let totalDuration: Double
    let totalReps: Int
    let seriesId: String
    
    /// Último pico detectado (valor final de actualReps)
    var finalRepsCount: Int {
        return points.compactMap { $0.repIndex }.max() ?? 0
    }
    
    /// Pontos onde repetições foram detectadas
    var repPeaks: [MovementPoint] {
        return points.filter { $0.repIndex != nil }
    }
    
    /// Serializar para JSON Data (para salvar no CoreData)
    func toJSONData() throws -> Data {
        let dictionaries = points.map { $0.toDictionary() }
        return try JSONSerialization.data(withJSONObject: dictionaries)
    }
    
    /// Deserializar de JSON Data (para ler do CoreData)
    static func fromJSONData(_ data: Data) throws -> MovementTimeline {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MLProcessingError.invalidData
        }
        
        let points = jsonArray.compactMap { MovementPoint.fromDictionary($0) }
        
        let totalDuration = points.last?.timestamp ?? 0.0
        let totalReps = points.compactMap { $0.repIndex }.max() ?? 0
        
        return MovementTimeline(
            points: points,
            totalDuration: totalDuration,
            totalReps: totalReps,
            seriesId: "unknown"
        )
    }
}

/// Erros básicos
enum MLProcessingError: Error, LocalizedError {
    case notImplemented
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Modelo ML não implementado"
        case .invalidData:
            return "Dados inválidos"
        }
    }
}

// MARK: - UpdateDataToMLUseCase Implementation

/// Use Case básico para futuro processamento ML
final class UpdateDataToMLUseCase: UpdateDataToMLUseCaseProtocol {
    
    // MARK: - Properties
    
    private let mlModelManager: MLModelManagerProtocol
    private let subscriptionManager: SubscriptionManagerProtocol
    
    // Estado básico
    private var currentSessionId: String?
    private var repTimeline: [RepDetection] = []
    private var totalRepsCount: Int = 0
    
    // Publishers básicos
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var isMLProcessing: Bool = false
    
    // MARK: - Initialization
    
    init(mlModelManager: MLModelManagerProtocol, subscriptionManager: SubscriptionManagerProtocol) {
        self.mlModelManager = mlModelManager
        self.subscriptionManager = subscriptionManager
        print("🤖 [UpdateDataToMLUseCase] Inicializado - Modelo ML não implementado")
    }
    
    // MARK: - Public Methods
    
    /// Processa chunk de dados (não implementado)
    func processChunk(_ chunk: SensorDataChunk) async throws -> MLProcessingResult {
        print("🚫 [UpdateDataToMLUseCase] Modelo ML não implementado para este exercício")
        
        // Verificar nova sessão
        if currentSessionId != chunk.sessionId {
            resetSession()
            currentSessionId = chunk.sessionId
        }
        
        // Sempre retorna resultado vazio
        return MLProcessingResult(
            repsDetected: 0,
            totalReps: 0,
            confidence: 0.0,
            processingTime: 0.001
        )
    }
    
    /// Retorna contagem atual (sempre 0)
    func getCurrentRepsCount() -> Int {
        return 0
    }
    
    /// Retorna timeline (sempre vazia)
    func getRepTimeline() -> [RepDetection] {
        return []
    }
    
    /// Reseta sessão
    func resetSession() {
        print("🔄 [UpdateDataToMLUseCase] Sessão resetada - Modelo ML não implementado")
        currentSessionId = nil
        repTimeline.removeAll()
        totalRepsCount = 0
        Task { @MainActor in currentReps = 0 }
    }
}

// MARK: - Mock Implementation

/// Mock básico para desenvolvimento
final class MockUpdateDataToMLUseCase: UpdateDataToMLUseCaseProtocol {
    
    func processChunk(_ chunk: SensorDataChunk) async throws -> MLProcessingResult {
        print("🚫 [MockUpdateDataToMLUseCase] Modelo ML não implementado para este exercício")
        
        return MLProcessingResult(
            repsDetected: 0,
            totalReps: 0,
            confidence: 0.0,
            processingTime: 0.001
        )
    }
    
    func getCurrentRepsCount() -> Int {
        return 0
    }
    
    func getRepTimeline() -> [RepDetection] {
        return []
    }
    
    func resetSession() {
        print("🔄 [MockUpdateDataToMLUseCase] Sessão resetada - Modelo ML não implementado")
    }
} 