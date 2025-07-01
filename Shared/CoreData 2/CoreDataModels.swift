//
//  CoreDataModels.swift
//  Fitter V2
//
//  📋 EXTENSÕES CORE DATA - MODELO FitterModel OTIMIZADO
//  
//  🎯 OBJETIVO: Extensões mínimas para entidades Core Data
//  • Propriedades computadas convenientes e seguras
//  • Conversões Set → Array para SwiftUI
//  • Métodos de serialização sensorData (JSON ↔ Binary Data)
//  • Computed properties básicas para UI
//  
//  ⚠️ IMPORTANTE: 
//  • NÃO contém lógica de negócio (startWorkout, endSession, etc.)
//  • Lógica de negócio será implementada nos Use Cases
//  • Mantém apenas funcionalidades essenciais do Core Data
//  
//  🔧 COMPATIBILIDADE:
//  • Classes geradas automaticamente (codeGenerationType="class")
//  • Suporte completo a sensorData JSON consolidado
//  • Extensions preparadas para Clean Architecture
//
//  Created by Daniel Lobo on 25/05/25.
//

import Foundation
import CoreData

// MARK: - Core Data Model Extensions
// 
// As classes são geradas automaticamente pelo Core Data (codeGenerationType="class")
// Aqui definimos apenas extensões com funcionalidades úteis

// MARK: - CDAppUser Extensions
/// 📱 Extensões para entidade do usuário principal
extension CDAppUser {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name
    }
    
    /// Email seguro (pode ser vazio)
    var safeEmail: String {
        return email ?? ""
    }
    
    // MARK: - Conversões Set → Array (para SwiftUI)
    
    /// Planos de treino ordenados por posição
    var workoutPlansArray: [CDWorkoutPlan] {
        let set = workoutPlans as? Set<CDWorkoutPlan> ?? []
        return set.sorted { $0.order < $1.order }
    }
    
    /// Histórico de treinos ordenado por data (mais recente primeiro)
    var workoutHistoriesArray: [CDWorkoutHistory] {
        let set = workoutHistories as? Set<CDWorkoutHistory> ?? []
        return set.sorted { $0.date > $1.date }
    }
    

}

// MARK: - CDWorkoutPlan Extensions
/// 📋 Extensões para planos de treino
extension CDWorkoutPlan {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Título automático sempre disponível (Treino A, Treino B, Treino A1...)
    var safeAutoTitle: String {
        return autoTitle
    }
    
    /// Título personalizado totalmente livre (opcional)
    var safeCustomTitle: String? {
        return title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : title
    }
    
    /// Título para exibição na interface
    /// Se personalizado: "Peitoral Heavy (Treino A)"
    /// Se automático: "Treino A"
    var displayTitle: String {
        if let customTitle = safeCustomTitle {
            return "\(customTitle) (\(safeAutoTitle))"
        } else {
            return safeAutoTitle
        }
    }
    
    /// Título para exibição compacta (sem parênteses)
    /// Se personalizado: "Peitoral Heavy"
    /// Se automático: "Treino A"
    var compactTitle: String {
        return safeCustomTitle ?? safeAutoTitle
    }
    
    /// Verifica se o treino tem título personalizado
    var hasCustomTitle: Bool {
        return safeCustomTitle != nil
    }
    
    // MARK: - Conversões Set → Array
    
    /// Exercícios do plano ordenados por posição
    var exercisesArray: [CDPlanExercise] {
        let set = exercises as? Set<CDPlanExercise> ?? []
        return set.sorted { $0.order < $1.order }
    }
    
    // MARK: - Propriedades Computadas para UI
    
    /// Grupos musculares concatenados para exibição
    var muscleGroupsString: String {
        return exercisesArray
            .compactMap { $0.template?.muscleGroup?.capitalized }
            .joined(separator: " + ")
    }
    
    /// Lista única de grupos musculares
    var muscleGroupsList: [String] {
        return exercisesArray.compactMap { 
            $0.template?.muscleGroup 
        }.unique()
    }
}

// MARK: - CDPlanExercise Extensions
/// 🏋️‍♂️ Extensões para exercícios no plano
extension CDPlanExercise {
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
}

// MARK: - CDExerciseTemplate Extensions
/// 📝 Extensões para templates de exercício
extension CDExerciseTemplate {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name
    }
    
    /// ID do template seguro (sempre disponível)
    var safeTemplateId: String {
        return templateId
    }
    
    // MARK: - Conversões Set → Array
    
    /// Exercícios do plano que usam este template
    var planExercisesArray: [CDPlanExercise] {
        let set = planExercises as? Set<CDPlanExercise> ?? []
        return set.sorted { $0.order < $1.order }
    }
}

// MARK: - CDWorkoutHistory Extensions
/// 📊 Extensões para histórico de treinos
extension CDWorkoutHistory {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Data segura (sempre disponível)
    var safeDate: Date {
        return date
    }
    
    // MARK: - Conversões Set → Array
    
    /// Exercícios do histórico ordenados por posição
    var exercisesArray: [CDHistoryExercise] {
        let set = exercises as? Set<CDHistoryExercise> ?? []
        return set.sorted { $0.order < $1.order }
    }
}

// MARK: - CDHistoryExercise Extensions
/// 🏋️‍♂️ Extensões para exercícios no histórico
extension CDHistoryExercise {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name
    }
    
    // MARK: - Conversões Set → Array
    
    /// Séries do exercício ordenadas por posição
    var setsArray: [CDHistorySet] {
        let set = sets as? Set<CDHistorySet> ?? []
        return set.sorted { $0.order < $1.order }
    }
}

// MARK: - CDHistorySet Extensions
/// 📈 Extensões para séries do histórico com suporte a sensorData JSON
extension CDHistorySet {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Timestamp seguro (sempre disponível)
    var safeTimestamp: Date {
        return timestamp
    }
    
    /// Duração da série (se startTime e endTime existirem)
    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    // MARK: - Gerenciamento sensorData JSON
    // 🎯 Métodos específicos para Binary Data consolidado
    
    /// Deserializa dados de sensores do JSON armazenado
    /// - Returns: Struct SensorData ou nil se inválido
    var sensorDataObject: SensorData? {
        guard let data = sensorData else { return nil }
        do {
            return try SensorData.fromBinaryData(data)
        } catch {
            print("❌ Erro ao deserializar SensorData: \(error)")
            return nil
        }
    }
    
    /// Serializa dados de sensores para JSON Binary Data
    /// - Parameter sensors: Struct SensorData a ser armazenado
    func updateSensorData(_ sensors: SensorData) {
        do {
            self.sensorData = try sensors.toBinaryData()
        } catch {
            print("❌ Erro ao serializar SensorData: \(error)")
        }
    }
 

// MARK: - Entidades Current (Estado Ativo)

// MARK: - CDCurrentSession Extensions
/// ⚡ Extensões para sessão ativa (treino em andamento)
extension CDCurrentSession {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Tempo de início seguro (sempre disponível)
    var safeStartTime: Date {
        return startTime
    }
    
    /// Duração da sessão até agora
    var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(safeStartTime)
    }
    

}

// MARK: - CDCurrentExercise Extensions
/// 🏋️‍♂️ Extensões para exercício ativo
extension CDCurrentExercise {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Tempo de início seguro (sempre disponível)
    var safeStartTime: Date {
        return startTime
    }
    
    /// Duração do exercício até agora
    var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(safeStartTime)
    }
    

}

// MARK: - CDCurrentSet Extensions
/// 📊 Extensões para série ativa com suporte a sensorData JSON
extension CDCurrentSet {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id
    }
    
    /// Timestamp seguro (sempre disponível)
    var safeTimestamp: Date {
        return timestamp
    }
    
    /// Duração da série (se startTime e endTime existirem)
    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    // MARK: - Gerenciamento sensorData JSON
    // 🎯 Idêntico ao CDHistorySet (mesmo modelo de dados)
    
    /// Deserializa dados de sensores do JSON armazenado
    /// - Returns: Struct SensorData ou nil se inválido
    var sensorDataObject: SensorData? {
        guard let data = sensorData else { return nil }
        do {
            return try SensorData.fromBinaryData(data)
        } catch {
            print("❌ Erro ao deserializar SensorData: \(error)")
            return nil
        }
    }
    
    /// Serializa dados de sensores para JSON Binary Data
    /// - Parameter sensors: Struct SensorData a ser armazenado
    func updateSensorData(_ sensors: SensorData) {
        do {
            self.sensorData = try sensors.toBinaryData()
            self.timestamp = Date() // Atualiza timestamp quando há novos dados
        } catch {
            print("❌ Erro ao serializar SensorData: \(error)")
        }
    }
}

// MARK: - Array Extensions
private extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

