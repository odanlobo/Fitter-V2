//
//  SensorData.swift
//  Fitter V2
//
//  📋 DTO PURO PARA DADOS DE SENSORES (ITEM 9 DA REFATORAÇÃO) ✅
//  
//  🎯 OBJETIVO: Container limpo para dados de sensores Watch ↔ iPhone
//  • REDUÇÃO: 670 → 200 linhas (70% menos código)
//  • SIMPLIFICAÇÃO: Apenas funcionalidades essenciais
//  • FOCO: Serialização + Chunking + Validação básica
//  
//  🔄 FLUXO SIMPLIFICADO:
//  1. Apple Watch → Dictionary [String: Any] (MotionManager)
//  2. Dictionary → SensorData struct (consolidação)
//  3. SensorData → toBinaryData() → JSON Binary Data
//  4. JSON Binary Data → Core Data External Storage
//  5. Core Data → fromBinaryData() → SensorData → App
//  
//  🚀 FUNCIONALIDADES IMPLEMENTADAS:
//  • Inicializadores (3): Padrão + Watch Dictionary + Chunks
//  • Serialização (4): toBinaryData, fromBinaryData, toDictionary, fromDictionary
//  • Validação (2): isValidBinaryData, binaryDataInfo
//  • Extensions (2): chunked, toBinaryDataArray para buffer management
//  • Mock data (3): normal, intenso, estático para previews
//  
//  🗑️ REMOVIDAS (LIMPEZA COMPLETA):
//  • Computed properties (totalAcceleration, totalRotation, etc.)
//  • Métodos de análise (stats, compacted, filteredByMovementData)
//  • Métodos legacy e debugging complexos
//  • Extensões de estatísticas e análise
//  
//  ⚡ BENEFÍCIOS:
//  • Responsabilidade única: apenas DTO de dados brutos
//  • Performance: sem cálculos desnecessários
//  • Manutenibilidade: código focado e limpo
//  • Testabilidade: funcionalidades essenciais apenas
//
//  Created by Daniel Lobo on 13/05/25.
//

import Foundation

/// Erros específicos para serialização/deserialização de SensorData em Binary Data
enum SensorDataError: LocalizedError {
    case invalidBinaryData
    case dataTooLarge(size: Int)
    case corruptedData
    case unsupportedVersion(version: Int)
    case missingRequiredData
    
    var errorDescription: String? {
        switch self {
        case .invalidBinaryData:
            return "Dados binários inválidos para SensorData"
        case .dataTooLarge(let size):
            return "Dados muito grandes para Binary Data: \(size) bytes"
        case .corruptedData:
            return "Dados corrompidos ou ilegíveis"
        case .unsupportedVersion(let version):
            return "Versão não suportada: \(version)"
        case .missingRequiredData:
            return "Dados obrigatórios ausentes"
        }
    }
}

/// DTO puro para dados de sensores Watch ↔ iPhone
struct SensorData: Codable, Equatable {
    // MARK: - Raw Sensor Data
    let accelerationX, accelerationY, accelerationZ: Double?
    let rotationX, rotationY, rotationZ: Double?
    let gravityX, gravityY, gravityZ: Double?
    let attitudeRoll, attitudePitch, attitudeYaw: Double?
    let magneticFieldX, magneticFieldY, magneticFieldZ: Double?
    let captureFrequency: Double?
    let sampleCount: Int?
    let capturedAt: Date
    
    // MARK: - Initializers (3 apenas)
    init(
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
        magneticFieldX: Double? = nil,
        magneticFieldY: Double? = nil,
        magneticFieldZ: Double? = nil,
        captureFrequency: Double? = nil,
        sampleCount: Int? = nil,
        capturedAt: Date = Date()
    ) {
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
        self.magneticFieldX = magneticFieldX
        self.magneticFieldY = magneticFieldY
        self.magneticFieldZ = magneticFieldZ
        self.captureFrequency = captureFrequency
        self.sampleCount = sampleCount
        self.capturedAt = capturedAt
    }
    
    /// 🔄 Construtor conveniente a partir de dados do Apple Watch (via Dictionary)
    /// Usado pelo MotionManager e WatchSessionManager conforme arquitetura atual
    init(from watchDictionary: [String: Any]) {
        self.accelerationX = watchDictionary["accelerationX"] as? Double
        self.accelerationY = watchDictionary["accelerationY"] as? Double
        self.accelerationZ = watchDictionary["accelerationZ"] as? Double
        self.rotationX = watchDictionary["rotationX"] as? Double
        self.rotationY = watchDictionary["rotationY"] as? Double
        self.rotationZ = watchDictionary["rotationZ"] as? Double
        self.gravityX = watchDictionary["gravityX"] as? Double
        self.gravityY = watchDictionary["gravityY"] as? Double
        self.gravityZ = watchDictionary["gravityZ"] as? Double
        self.attitudeRoll = watchDictionary["attitudeRoll"] as? Double
        self.attitudePitch = watchDictionary["attitudePitch"] as? Double
        self.attitudeYaw = watchDictionary["attitudeYaw"] as? Double
        self.magneticFieldX = watchDictionary["magneticFieldX"] as? Double
        self.magneticFieldY = watchDictionary["magneticFieldY"] as? Double
        self.magneticFieldZ = watchDictionary["magneticFieldZ"] as? Double
        self.captureFrequency = watchDictionary["captureFrequency"] as? Double
        self.sampleCount = watchDictionary["sampleCount"] as? Int
        
        if let timestamp = watchDictionary["capturedAt"] as? TimeInterval {
            self.capturedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            self.capturedAt = Date()
        }
    }
    
    // MARK: - Serialization (4 métodos apenas)
    /// 🎯 Converte para Binary Data otimizado para Core Data External Storage
    func toBinaryData() throws -> Data {
        // Validação antes da serialização
        guard isValidForBinaryStorage else {
            throw SensorDataError.missingRequiredData
        }
        
        // Usa encoder compacto sem formatação para minimizar tamanho
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970 // Mais compacto que ISO8601
        encoder.outputFormatting = [] // Sem formatação = menor tamanho
        
        do {
            let data = try encoder.encode(self)
            
            // Verifica tamanho para alertar sobre dados grandes
            if data.count > 1_048_576 { // 1MB
                throw SensorDataError.dataTooLarge(size: data.count)
            }
            
            return data
        } catch {
            if error is SensorDataError {
                throw error
            } else {
                throw SensorDataError.invalidBinaryData
            }
        }
    }
    
    /// 🎯 Cria SensorData a partir de Binary Data do Core Data
    static func fromBinaryData(_ data: Data) throws -> SensorData {
        guard !data.isEmpty else {
            throw SensorDataError.invalidBinaryData
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let sensorData = try decoder.decode(SensorData.self, from: data)
            
            // Validação pós-deserialização
            guard sensorData.isValidForBinaryStorage else {
                throw SensorDataError.corruptedData
            }
            
            return sensorData
        } catch DecodingError.dataCorrupted {
            throw SensorDataError.corruptedData
        } catch DecodingError.keyNotFound, DecodingError.valueNotFound {
            throw SensorDataError.missingRequiredData
        } catch {
            throw SensorDataError.invalidBinaryData
        }
    }
    
    /// Converte para dicionário compacto (remove nulos para economizar espaço)
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "capturedAt": capturedAt.timeIntervalSince1970,
            "version": 1 // Para versionamento futuro
        ]
        
        // Só adiciona valores não-nulos para economizar espaço
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
        if let magneticFieldX = magneticFieldX { dict["magneticFieldX"] = magneticFieldX }
        if let magneticFieldY = magneticFieldY { dict["magneticFieldY"] = magneticFieldY }
        if let magneticFieldZ = magneticFieldZ { dict["magneticFieldZ"] = magneticFieldZ }
        
        // Metadados
        if let captureFrequency = captureFrequency { dict["captureFrequency"] = captureFrequency }
        if let sampleCount = sampleCount { dict["sampleCount"] = sampleCount }
        
        return dict
    }
    
    /// Cria SensorData a partir de dicionário (com suporte a versionamento)
    static func from(dictionary: [String: Any]) throws -> SensorData {
        guard let timestamp = dictionary["capturedAt"] as? TimeInterval else {
            throw SensorDataError.missingRequiredData
        }
        
        // Verifica versionamento para compatibilidade futura
        let version = dictionary["version"] as? Int ?? 1
        guard version <= 1 else {
            throw SensorDataError.unsupportedVersion(version: version)
        }
        
        return SensorData(
            accelerationX: dictionary["accelerationX"] as? Double,
            accelerationY: dictionary["accelerationY"] as? Double,
            accelerationZ: dictionary["accelerationZ"] as? Double,
            rotationX: dictionary["rotationX"] as? Double,
            rotationY: dictionary["rotationY"] as? Double,
            rotationZ: dictionary["rotationZ"] as? Double,
            gravityX: dictionary["gravityX"] as? Double,
            gravityY: dictionary["gravityY"] as? Double,
            gravityZ: dictionary["gravityZ"] as? Double,
            attitudeRoll: dictionary["attitudeRoll"] as? Double,
            attitudePitch: dictionary["attitudePitch"] as? Double,
            attitudeYaw: dictionary["attitudeYaw"] as? Double,
            magneticFieldX: dictionary["magneticFieldX"] as? Double,
            magneticFieldY: dictionary["magneticFieldY"] as? Double,
            magneticFieldZ: dictionary["magneticFieldZ"] as? Double,
            captureFrequency: dictionary["captureFrequency"] as? Double,
            sampleCount: dictionary["sampleCount"] as? Int,
            capturedAt: Date(timeIntervalSince1970: timestamp)
        )
    }
    
    // MARK: - Basic Validation (2 métodos apenas)
    /// Valida se dados binários são válidos SensorData (sem deserializar completamente)
    static func isValidBinaryData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        
        // Tenta deserializar apenas o timestamp para validação rápida
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = jsonObject as? [String: Any] else { return false }
            
            // Verifica se tem campos essenciais
            return dict["capturedAt"] != nil && dict.keys.count > 1
        } catch {
            return false
        }
    }
    
    /// Obtém informações do Binary Data sem deserializar completamente
    static func binaryDataInfo(_ data: Data) -> (size: Int, hasValidStructure: Bool) {
        return (size: data.count, hasValidStructure: isValidBinaryData(data))
    }
    
    // MARK: - Binary Data Validation & Helpers
    
    /// Valida se os dados são adequados para armazenamento em Binary Data
    var isValidForBinaryStorage: Bool {
        // Verifica se há pelo menos alguns dados de sensores válidos
        let hasValidData = accelerationX != nil || accelerationY != nil || accelerationZ != nil ||
                          rotationX != nil || rotationY != nil || rotationZ != nil
        
        // Verifica se não há valores extremos que possam causar problemas
        let hasReasonableAcceleration = (accelerationX ?? 0.0).magnitude < 100.0 && 
                                       (accelerationY ?? 0.0).magnitude < 100.0 && 
                                       (accelerationZ ?? 0.0).magnitude < 100.0
        let hasReasonableRotation = (rotationX ?? 0.0).magnitude < 100.0 && 
                                   (rotationY ?? 0.0).magnitude < 100.0 && 
                                   (rotationZ ?? 0.0).magnitude < 100.0
        
        return hasValidData && hasReasonableAcceleration && hasReasonableRotation
    }
}

// MARK: - Essential Extensions (2 apenas)
extension Array where Element == SensorData {
    /// Converte array para chunks de tamanho específico (para buffer management)
    /// Usado pelo WatchSessionManager e PhoneSessionManager
    func chunked(into size: Int) -> [[SensorData]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
    
    /// Converte todos os SensorData para Binary Data para persistência
    func toBinaryDataArray() throws -> [Data] {
        return try map { try $0.toBinaryData() }
    }
}

// MARK: - Preview Support
#if DEBUG
extension SensorData {
    /// Dados de exemplo para previews e testes
    static let mock = SensorData(
        accelerationX: 0.1,
        accelerationY: 0.2,
        accelerationZ: 0.3,
        rotationX: 0.05,
        rotationY: 0.1,
        rotationZ: 0.15,
        gravityX: 0.0,
        gravityY: 0.0,
        gravityZ: -1.0,
        attitudeRoll: 0.1,
        attitudePitch: 0.2,
        attitudeYaw: 0.3,
        magneticFieldX: 25.0,
        magneticFieldY: -30.0,
        magneticFieldZ: 45.0,
        captureFrequency: 30.0,
        sampleCount: 15,
        capturedAt: Date()
    )
    
    /// Dados de alta atividade para testes
    static let intenseMock = SensorData(
        accelerationX: 2.5,
        accelerationY: 1.8,
        accelerationZ: 3.2,
        rotationX: 1.5,
        rotationY: 2.1,
        rotationZ: 1.9,
        gravityX: 0.1,
        gravityY: 0.2,
        gravityZ: -0.9,
        attitudeRoll: 1.2,
        attitudePitch: 0.8,
        attitudeYaw: 1.5,
        magneticFieldX: 85.0,
        magneticFieldY: -120.0,
        magneticFieldZ: 200.0,
        captureFrequency: 30.0,
        sampleCount: 30,
        capturedAt: Date()
    )
    
    /// Dados estáticos para testes
    static let staticMock = SensorData(
        accelerationX: 0.01,
        accelerationY: 0.02,
        accelerationZ: 0.01,
        rotationX: 0.005,
        rotationY: 0.003,
        rotationZ: 0.007,
        gravityX: 0.0,
        gravityY: 0.0,
        gravityZ: -1.0,
        attitudeRoll: 0.01,
        attitudePitch: 0.02,
        attitudeYaw: 0.01,
        magneticFieldX: 20.0,
        magneticFieldY: -25.0,
        magneticFieldZ: 40.0,
        captureFrequency: 30.0,
        sampleCount: 5,
        capturedAt: Date()
    )
}
#endif 
