//
//  SensorData.swift
//  Fitter V2
//
//  📋 STRUCT OTIMIZADA PARA BINARY DATA (ITEM 9 DA REFATORAÇÃO)
//  
//  🎯 OBJETIVO: Eliminar duplicação de dados de sensores no Core Data
//  • ANTES: 18 atributos individuais (9 em CDCurrentSet + 9 em CDHistorySet)
//  • DEPOIS: 2 campos JSON consolidados (sensorData Binary Data + External Storage)
//  • REDUÇÃO: 89% menos complexidade no schema Core Data
//  
//  🔄 FLUXO OTIMIZADO:
//  1. Apple Watch → Dictionary [String: Any] (dados individuais)
//  2. Dictionary → SensorData struct (consolidação)
//  3. SensorData → toBinaryData() → JSON Binary Data
//  4. JSON Binary Data → Core Data External Storage
//  5. Core Data → fromBinaryData() → SensorData struct → App
//  
//  🚀 FUNCIONALIDADES IMPLEMENTADAS:
//  • toBinaryData() / fromBinaryData() para Core Data External Storage
//  • Versionamento para migração futura
//  • Validação de dados para Binary Storage
//  • Mock data para previews e testes
//  • Suporte a Dictionary conversion (para sync Firestore)
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

/// Estrutura para dados de sensores do Apple Watch
/// 🎯 Otimizada para armazenamento em Binary Data (Core Data External Storage)
struct SensorData: Codable, Equatable {
    
    // MARK: - Dados de Sensores (Apple Watch)
    
    /// Acelerômetro (3 eixos)
    let accelerationX: Double?
    let accelerationY: Double?
    let accelerationZ: Double?
    
    /// Giroscópio (3 eixos)
    let rotationX: Double?
    let rotationY: Double?
    let rotationZ: Double?
    
    /// Gravidade (3 eixos)
    let gravityX: Double?
    let gravityY: Double?
    let gravityZ: Double?
    
    /// Orientação (3 eixos)
    let attitudeRoll: Double?
    let attitudePitch: Double?
    let attitudeYaw: Double?
    
    /// Campo magnético (3 eixos)
    let magneticFieldX: Double?
    let magneticFieldY: Double?
    let magneticFieldZ: Double?
    
    // MARK: - Metadados
    let captureFrequency: Double? // Hz de captura
    let sampleCount: Int? // Número de amostras agregadas
    let capturedAt: Date // Timestamp de captura
    
    // MARK: - Initializers
    
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
    
    /// 🔄 TODO: Será implementado quando WatchSensorData estiver disponível
    // init(from watchData: WatchSensorData) { ... }
    
    // MARK: - Binary Data Conversion (Core Data Optimized)
    
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
    
    /// Serialização ultra-compacta removendo valores nulos (para economizar espaço)
    func toCompactBinaryData() throws -> Data {
        guard isValidForBinaryStorage else {
            throw SensorDataError.missingRequiredData
        }
        
        let compactDict = toDictionary()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: compactDict, options: [])
            
            // Validação do tamanho para Binary Data
            if jsonData.count > 1_048_576 { // 1MB
                throw SensorDataError.dataTooLarge(size: jsonData.count)
            }
            
            return jsonData
        } catch {
            if error is SensorDataError {
                throw error
            } else {
                throw SensorDataError.invalidBinaryData
            }
        }
    }
    
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
    
    /// 🔄 Métodos legacy para compatibilidade (serão removidos futuramente)
    @available(*, deprecated, message: "Use toBinaryData() instead")
    func toData() throws -> Data {
        return try toBinaryData()
    }
    
    @available(*, deprecated, message: "Use fromBinaryData(_:) instead")
    static func from(data: Data) throws -> SensorData {
        return try fromBinaryData(data)
    }
    
    // MARK: - Binary Data Validation & Helpers
    
    /// Valida se os dados são adequados para armazenamento em Binary Data
    var isValidForBinaryStorage: Bool {
        // Verifica se há pelo menos alguns dados de sensores válidos
        let hasValidData = accelerationX != nil || accelerationY != nil || accelerationZ != nil ||
                          rotationX != nil || rotationY != nil || rotationZ != nil
        
        // Verifica se não há valores extremos que possam causar problemas
        let hasReasonableValues = totalAcceleration < 100.0 && totalRotation < 100.0
        
        return hasValidData && hasReasonableValues
    }
    
    /// Calcula o tamanho estimado em Binary Data
    var estimatedBinarySize: Int {
        do {
            let data = try toBinaryData()
            return data.count
        } catch {
            return 0
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
    
    /// Método legacy para compatibilidade (sem tratamento de erros)
    @available(*, deprecated, message: "Use from(dictionary:) throws instead")
    static func fromDictionary(_ dictionary: [String: Any]) -> SensorData? {
        return try? from(dictionary: dictionary)
    }
    

    
    // MARK: - Debug & Binary Data Info
    
    var debugDescription: String {
        return """
        SensorData(
            acceleration: (\(accelerationX ?? 0), \(accelerationY ?? 0), \(accelerationZ ?? 0)) = \(String(format: "%.3f", totalAcceleration)),
            rotation: (\(rotationX ?? 0), \(rotationY ?? 0), \(rotationZ ?? 0)) = \(String(format: "%.3f", totalRotation)),
            gravity: (\(gravityX ?? 0), \(gravityY ?? 0), \(gravityZ ?? 0)) = \(String(format: "%.3f", totalGravity)),
            magnetic: (\(magneticFieldX ?? 0), \(magneticFieldY ?? 0), \(magneticFieldZ ?? 0)) = \(String(format: "%.3f", totalMagneticField)),
                        attitude: (\(attitudeRoll ?? 0), \(attitudePitch ?? 0), \(attitudeYaw ?? 0)),
            binarySize: \(estimatedBinarySize) bytes,
            validForStorage: \(isValidForBinaryStorage),
            capturedAt: \(capturedAt)
        )
        """
    }
    
    /// Resumo para logs de Binary Data
    var binaryDataSummary: String {
        let size = estimatedBinarySize
        let sizeStr = size > 1024 ? "\(size/1024)KB" : "\(size)B"
        return "SensorData(\(sizeStr), valid: \(isValidForBinaryStorage))"
    }
}



// MARK: - Collection Extensions

extension Array where Element == SensorData {
    
    /// Calcula a média dos dados de sensores
    var average: SensorData? {
        guard !isEmpty else { return nil }
        
        let count = Double(self.count)
        
        let avgAccX = compactMap { $0.accelerationX }.reduce(0, +) / count
        let avgAccY = compactMap { $0.accelerationY }.reduce(0, +) / count
        let avgAccZ = compactMap { $0.accelerationZ }.reduce(0, +) / count
        
        let avgRotX = compactMap { $0.rotationX }.reduce(0, +) / count
        let avgRotY = compactMap { $0.rotationY }.reduce(0, +) / count
        let avgRotZ = compactMap { $0.rotationZ }.reduce(0, +) / count
        
        let avgGravX = compactMap { $0.gravityX }.reduce(0, +) / count
        let avgGravY = compactMap { $0.gravityY }.reduce(0, +) / count
        let avgGravZ = compactMap { $0.gravityZ }.reduce(0, +) / count
        
        let avgAttRoll = compactMap { $0.attitudeRoll }.reduce(0, +) / count
        let avgAttPitch = compactMap { $0.attitudePitch }.reduce(0, +) / count
        let avgAttYaw = compactMap { $0.attitudeYaw }.reduce(0, +) / count
        
        return SensorData(
            accelerationX: avgAccX,
            accelerationY: avgAccY,
            accelerationZ: avgAccZ,
            rotationX: avgRotX,
            rotationY: avgRotY,
            rotationZ: avgRotZ,
            gravityX: avgGravX,
            gravityY: avgGravY,
            gravityZ: avgGravZ,
            attitudeRoll: avgAttRoll,
            attitudePitch: avgAttPitch,
            attitudeYaw: avgAttYaw,
            captureFrequency: nil,
            sampleCount: self.count,
            capturedAt: last?.capturedAt ?? Date()
        )
    }
    

}

// MARK: - Preview/Testing Support

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