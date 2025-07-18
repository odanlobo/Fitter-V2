//
//  CoreDataModels.swift
//  Fitter V2
//
//  📋 EXTENSÕES CORE DATA - MODELO FitterModel OTIMIZADO
//  
//  🎯 OBJETIVO: Extensões mínimas para entidades Core Data
//  • Propriedades computadas convenientes e seguras
//  • Conversões Set → Array para SwiftUI
//  • Métodos de serialização sensorData (JSON ↔ Binary Data) APENAS para histórico
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
        return id ?? UUID()
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name ?? "Usuário"
    }
    
    /// Email seguro (pode ser vazio)
    var safeEmail: String {
        return email ?? ""
    }
    
    // MARK: - Configurações de Treino
    // NOTA: defaultSetsCount e defaultRestTimer são propriedades diretas do Core Data
    // Não redefinimos aqui para evitar recursão infinita
    
    /// Unidade de peso preferida do usuário
    var weightUnitEnum: WeightUnit {
        get { return WeightUnit(rawValue: weightUnit ?? "kg") ?? .kg }
        set { self.weightUnit = newValue.rawValue }
    }
    
    /// Verifica se usa sistema métrico (kg/cm)
    var usesMetricSystem: Bool {
        return weightUnitEnum == .kg
    }
    
    /// Verifica se usa sistema imperial (lbs/ft)
    var usesImperialSystem: Bool {
        return weightUnitEnum == .lbs
    }
    
    /// Formata peso com unidade
    func formatWeight(_ weight: Double) -> String {
        let formatted = String(format: "%.1f", weight)
        return "\(formatted) \(weightUnitEnum.symbol)"
    }
    
    /// Formata timer de descanso padrão (MM:SS)
    var formattedDefaultRestTimer: String {
        let minutes = Int(defaultRestTimer) / 60
        let seconds = Int(defaultRestTimer) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Atualiza configurações de treino
    func updateWorkoutSettings(setsCount: Int32, restTimer: TimeInterval, weightUnit: WeightUnit) {
        self.defaultSetsCount = setsCount
        self.defaultRestTimer = restTimer
        self.weightUnitEnum = weightUnit
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
        return set.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
}

// MARK: - CDWorkoutPlan Extensions
/// 📋 Extensões para planos de treino
extension CDWorkoutPlan {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Título automático sempre disponível (Treino A, Treino B, Treino A1...)
    var safeAutoTitle: String {
        return autoTitle ?? "Treino"
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
        let groups = exercisesArray.compactMap { 
            $0.template?.muscleGroup 
        }
        return Array(Set(groups))
    }
}

// MARK: - CDPlanExercise Extensions
/// 🏋️‍♂️ Extensões para exercícios no plano
extension CDPlanExercise {
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
}

// MARK: - CDExerciseTemplate Extensions
/// 📝 Extensões para templates de exercício
extension CDExerciseTemplate {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name ?? "Exercício"
    }
    
    /// ID do template seguro (sempre disponível)
    var safeTemplateId: String {
        return templateId ?? ""
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
        return id ?? UUID()
    }
    
    /// Data segura (sempre disponível)
    var safeDate: Date {
        return date ?? Date()
    }
    
    // MARK: - Conversões Set → Array
    
    /// Exercícios do histórico ordenados por posição
    var exercisesArray: [CDHistoryExercise] {
        let set = exercises as? Set<CDHistoryExercise> ?? []
        return set.sorted { $0.order < $1.order }
    }
    
    // MARK: - Propriedades de Localização
    
    /// Verifica se o histórico possui dados de localização
    var hasLocationData: Bool {
        // No Core Data com usesScalarValueType="YES", os valores padrão podem ser 0.0
        // Consideramos válido apenas se ambos forem diferentes de 0.0
        return latitude != 0.0 && longitude != 0.0
    }
    
    /// Coordenadas do treino (se disponíveis)
    var coordinates: (latitude: Double, longitude: Double)? {
        guard hasLocationData else { return nil }
        return (latitude: latitude, longitude: longitude)
    }
    
    /// Precisão da localização (se disponível)
    var locationAccuracyValue: Double? {
        // locationAccuracy pode ser 0.0 como valor padrão
        return locationAccuracy > 0.0 ? locationAccuracy : nil
    }
    
    /// Descrição da localização para debug
    var locationDescription: String {
        guard hasLocationData else { return "Localização não disponível" }
        return "📍 \(latitude), \(longitude) (±\(locationAccuracy)m)"
    }
}

// MARK: - CDHistoryExercise Extensions
/// 🏋️‍♂️ Extensões para exercícios no histórico
extension CDHistoryExercise {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Nome seguro (sempre disponível)
    var safeName: String {
        return name ?? "Exercício"
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
        return id ?? UUID()
    }
    
    /// Timestamp seguro (sempre disponível)
    var safeTimestamp: Date {
        return timestamp ?? Date()
    }
    
    /// Duração da série (se startTime e endTime existirem)
    var duration: TimeInterval? {
        guard let start = self.startTime, let end = self.endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    // MARK: - Gerenciamento sensorData JSON
    
    /// Deserializa dados de sensores do JSON armazenado
    /// - Returns: Struct SensorData ou nil se inválido
    var sensorDataObject: SensorData? {
        guard let data = self.sensorData else { return nil }
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
}

// MARK: - CDCurrentSession Extensions
/// ⚡ Extensões para sessão ativa (treino em andamento)
extension CDCurrentSession {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Tempo de início seguro (sempre disponível)
    var safeStartTime: Date {
        return startTime ?? Date()
    }
    
    /// Duração da sessão até agora
    var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(safeStartTime)
    }
    
    // MARK: - Propriedades de Localização
    
    /// Verifica se a sessão possui dados de localização
    var hasLocationData: Bool {
        // No Core Data com usesScalarValueType="YES", os valores padrão podem ser 0.0
        // Consideramos válido apenas se ambos forem diferentes de 0.0
        return latitude != 0.0 && longitude != 0.0
    }
    
    /// Coordenadas da sessão (se disponíveis)
    var coordinates: (latitude: Double, longitude: Double)? {
        guard hasLocationData else { return nil }
        return (latitude: latitude, longitude: longitude)
    }
    
    /// Precisão da localização (se disponível)
    var locationAccuracyValue: Double? {
        // locationAccuracy pode ser 0.0 como valor padrão
        return locationAccuracy > 0.0 ? locationAccuracy : nil
    }
    
    /// Descrição da localização para debug
    var locationDescription: String {
        guard hasLocationData else { return "Localização não disponível" }
        return "📍 \(latitude), \(longitude) (±\(locationAccuracy)m)"
    }
}

// MARK: - CDCurrentExercise Extensions
/// 🏋️‍♂️ Extensões para exercício ativo
extension CDCurrentExercise {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Tempo de início seguro (sempre disponível)
    var safeStartTime: Date {
        return startTime ?? Date()
    }
    
    /// Duração do exercício até agora
    var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(safeStartTime)
    }
    
    // MARK: - Conversões Set → Array (para múltiplas séries)
    
    /// Séries do exercício ativo ordenadas por posição
    var currentSetsArray: [CDCurrentSet] {
        let set = currentSets as? Set<CDCurrentSet> ?? []
        return set.sorted { $0.order < $1.order }
    }
    
    /// Série ativa atual (baseada em currentSetIndex)
    var activeSet: CDCurrentSet? {
        let setsArray = currentSetsArray
        guard currentSetIndex >= 0 && currentSetIndex < setsArray.count else { return nil }
        return setsArray[Int(currentSetIndex)]
    }
    
    /// Próxima série a ser executada
    var nextSet: CDCurrentSet? {
        let setsArray = currentSetsArray
        let nextIndex = currentSetIndex + 1
        guard nextIndex >= 0 && nextIndex < setsArray.count else { return nil }
        return setsArray[Int(nextIndex)]
    }
    
    /// Número total de séries configuradas
    var totalSets: Int {
        return currentSetsArray.count
    }
    
    /// Número de séries concluídas (endTime != nil)
    var completedSetsCount: Int {
        return currentSetsArray.filter { $0.endTime != nil }.count
    }
    
    /// Progresso das séries (0.0 a 1.0)
    var setsProgress: Double {
        guard totalSets > 0 else { return 0.0 }
        return Double(completedSetsCount) / Double(totalSets)
    }
    
    /// Verifica se todas as séries foram concluídas
    var isCompleted: Bool {
        return completedSetsCount == totalSets && totalSets > 0
    }
}

// MARK: - CDCurrentSet Extensions
/// 📊 Extensões para série ativa (SEM sensorData - apenas dados básicos)
extension CDCurrentSet {
    
    // MARK: - Propriedades Convenientes
    
    /// ID seguro (sempre disponível)
    var safeId: UUID {
        return id ?? UUID()
    }
    
    /// Timestamp seguro (sempre disponível)
    var safeTimestamp: Date {
        return timestamp ?? Date()
    }
    
    /// Duração da série (se startTime e endTime existirem)
    var duration: TimeInterval? {
        guard let start = self.startTime, let end = self.endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

