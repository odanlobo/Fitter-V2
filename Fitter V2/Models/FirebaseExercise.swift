/*
 * FirebaseExercise.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Modelo simples alinhado com estrutura real do Firebase
 *                   Usado apenas para leitura da coleção "exercisesList"
 *
 * ESTRUTURA REAL DO FIREBASE:
 * {
 *   "createdAt": "2025-06-14T22:38:22.227Z",
 *   "description": "Com uma barra nas costas, dê um passo à frente...",
 *   "equipment": "Barra",
 *   "gripVariation": "",
 *   "legSubgroup": "Quadríceps",  // apenas para exercícios de perna
 *   "muscleGroup": "legs",
 *   "name": "Afundo",
 *   "templateId": "legs_001",
 *   "updatedAt": "2025-07-01T18:22:56.084Z",
 *   "videoURL": ""
 * }
 *
 * CAMPOS IMPLEMENTADOS:
 * - ✅ description: String - Descrição detalhada do exercício
 * - ✅ createdAt: Date - Data de criação no Firebase
 * - ✅ updatedAt: Date - Data de última atualização
 * - ✅ videoURL: String? - URL do vídeo (pode estar vazio)
 * - ✅ legSubgroup: String? - Apenas para exercícios de perna
 * - 🗑️ imageName removido - Não existe mais no Firebase
 *
 * CONVERSÃO CORE DATA:
 * - toCDExerciseTemplate() - Converte APENAS quando exercício é salvo no treino
 * - Preserva todos os campos Firebase → Core Data
 * - Compatibilidade com CloudSyncStatus
 *
 * REFATORAÇÃO ITEM 32/101:
 * ✅ Atualizar modelo para estrutura real Firebase
 * ✅ Adicionar campos description, createdAt, updatedAt, videoURL
 * ✅ Remover imageName completamente
 * ✅ legSubgroup apenas para exercícios de perna
 * ✅ Conversão completa para CDExerciseTemplate
 */

import Foundation
import FirebaseFirestore
import CoreData

// MARK: - FirebaseExercise Model

/// Modelo para exercícios armazenados no Firebase Firestore
/// Alinhado com estrutura real da coleção "exercisesList"
struct FirebaseExercise: Identifiable, Codable, Hashable {
    let id: String
    let templateId: String
    let name: String
    let description: String
    let muscleGroup: String
    let legSubgroup: String?  // Apenas para exercícios de perna
    let equipment: String
    let gripVariation: String?
    let videoURL: String?
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - Computed Properties para Compatibilidade
    
    /// Template ID seguro para identificação
    var safeTemplateId: String { templateId }
    
    /// Nome seguro para exibição
    var safeName: String { name }
    
    /// Descrição segura para exibição
    var safeDescription: String { description }
    
    /// Verifica se tem vídeo disponível
    var hasVideo: Bool {
        guard let videoURL = videoURL else { return false }
        return !videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Verifica se é exercício de perna (tem legSubgroup)
    var isLegExercise: Bool {
        return muscleGroup.lowercased() == "legs" && legSubgroup != nil
    }
    
    /// Converte o grupo muscular string para enum (se válido)
    var muscleGroupEnum: MuscleGroup? {
        MuscleGroup(rawValue: muscleGroup)
    }
    
    // MARK: - Inicializadores
    
    /// Inicializador customizado para criação manual
    init(
        id: String = UUID().uuidString,
        templateId: String,
        name: String,
        description: String,
        muscleGroup: String,
        legSubgroup: String? = nil,
        equipment: String,
        gripVariation: String? = nil,
        videoURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.description = description
        self.muscleGroup = muscleGroup
        self.legSubgroup = legSubgroup
        self.equipment = equipment
        self.gripVariation = gripVariation
        self.videoURL = videoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Inicializa a partir de um documento do Firestore
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        // Campos obrigatórios
        guard let templateId = data["templateId"] as? String,
              let name = data["name"] as? String,
              let description = data["description"] as? String,
              let muscleGroup = data["muscleGroup"] as? String,
              let equipment = data["equipment"] as? String else {
            print("❌ FirebaseExercise: Campos obrigatórios faltando no documento \(document.documentID)")
            return nil
        }
        
        // Parse de datas
        let createdAt: Date
        let updatedAt: Date
        
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else if let createdAtString = data["createdAt"] as? String {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = Date()
        }
        
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            updatedAt = updatedAtTimestamp.dateValue()
        } else if let updatedAtString = data["updatedAt"] as? String {
            let formatter = ISO8601DateFormatter()
            updatedAt = formatter.date(from: updatedAtString) ?? Date()
        } else {
            updatedAt = Date()
        }
        
        self.id = document.documentID
        self.templateId = templateId
        self.name = name
        self.description = description
        self.muscleGroup = muscleGroup
        self.legSubgroup = data["legSubgroup"] as? String  // Apenas para pernas
        self.equipment = equipment
        self.gripVariation = data["gripVariation"] as? String
        self.videoURL = data["videoURL"] as? String
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Core Data Conversion
    
    /// Converte para CDExerciseTemplate para salvamento local
    /// APENAS chamado quando exercício é adicionado a um treino
    func toCDExerciseTemplate(context: NSManagedObjectContext) -> CDExerciseTemplate {
        let template = CDExerciseTemplate(context: context)
        template.id = UUID()
        template.templateId = self.templateId
        template.name = self.name
        template.description = self.description
        template.muscleGroup = self.muscleGroup
        template.legSubgroup = self.legSubgroup  // Apenas para pernas
        template.equipment = self.equipment
        template.gripVariation = self.gripVariation
        template.videoURL = self.videoURL
        template.createdAt = self.createdAt
        template.updatedAt = self.updatedAt
        template.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        
        print("✅ FirebaseExercise → CDExerciseTemplate: \(self.safeName)")
        return template
    }
    
    // MARK: - Firestore Conversion
    
    /// Converte para dicionário para salvamento no Firestore
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "templateId": templateId,
            "name": name,
            "description": description,
            "muscleGroup": muscleGroup,
            "equipment": equipment,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        // Campos opcionais
        if let legSubgroup = legSubgroup {
            dict["legSubgroup"] = legSubgroup
        }
        
        if let gripVariation = gripVariation {
            dict["gripVariation"] = gripVariation
        }
        
        if let videoURL = videoURL {
            dict["videoURL"] = videoURL
        }
        
        return dict
    }
    
    // MARK: - Hashable & Equatable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(templateId)
    }
    
    static func == (lhs: FirebaseExercise, rhs: FirebaseExercise) -> Bool {
        lhs.templateId == rhs.templateId
    }
}

// MARK: - ExerciseDisplayable Conformance

extension FirebaseExercise: ExerciseDisplayable {
    var displayMuscleGroup: String? { self.muscleGroup }
    var displayLegSubgroup: String? { self.legSubgroup }
    var displayEquipment: String? { self.equipment }
    var displayGripVariation: String? { self.gripVariation }
    var displayDescription: String? { self.description }
    var displayVideoURL: String? { self.videoURL }
    var displayHasVideo: Bool { self.hasVideo }
}

// MARK: - Mock Data for Previews

#if DEBUG
extension FirebaseExercise {
    
    static let mockChestExercise = FirebaseExercise(
        templateId: "chest_001",
        name: "Supino Reto",
        description: "Exercício fundamental para o desenvolvimento do peitoral maior, realizado com barra ou halteres.",
        muscleGroup: "chest",
        equipment: "Barra",
        gripVariation: "Pronada",
        videoURL: "https://firebasestorage.googleapis.com/v0/b/fitter-app/supino-reto.mp4"
    )
    
    static let mockLegExercise = FirebaseExercise(
        templateId: "legs_001",
        name: "Afundo",
        description: "Com uma barra nas costas, dê um passo à frente e flexione ambos os joelhos até formarem aproximadamente 90 graus. Foco em quadríceps e glúteos.",
        muscleGroup: "legs",
        legSubgroup: "Quadríceps",
        equipment: "Barra",
        videoURL: nil
    )
    
    static let mockBackExercise = FirebaseExercise(
        templateId: "back_008",
        name: "Encolhimento",
        description: "Segurando um halter em cada mão, eleve os ombros verticalmente, focando na contração do trapézio.",
        muscleGroup: "back",
        equipment: "Halteres",
        gripVariation: "Neutra",
        videoURL: ""
    )
    
    static let mockExercises = [mockChestExercise, mockLegExercise, mockBackExercise]
}
#endif 