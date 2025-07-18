import Foundation

/// Protocolo para padronizar a exibição de exercícios
/// Permite que tanto CDExerciseTemplate quanto exercícios do Firebase sejam exibidos da mesma forma
/// 
/// REFATORAÇÃO ITEM 41/101:
/// ✅ Remover displayImageName completamente (obsoleto)
/// ✅ Adicionar campos de vídeo: displayDescription, displayVideoURL, displayHasVideo
/// ✅ Corrigir CDExerciseTemplate extension (remover self.imageName)
/// ✅ Manter compatibilidade com FirebaseExercise extension existente
/// ✅ Preparar para migração dos componentes que usam displayImageName
protocol ExerciseDisplayable {
    var safeTemplateId: String { get }
    var safeName: String { get }
    var displayMuscleGroup: String? { get }
    var displayLegSubgroup: String? { get }
    var displayEquipment: String? { get }
    var displayGripVariation: String? { get }
    
    // MARK: - Campos de Vídeo (Novos)
    var displayDescription: String? { get }
    var displayVideoURL: String? { get }
    var displayHasVideo: Bool { get }
}

// MARK: - Extensions para conformidade

extension CDExerciseTemplate: ExerciseDisplayable {
    // NOTA: safeName e safeTemplateId já estão definidas em CoreDataModels.swift
    
    var displayMuscleGroup: String? { self.muscleGroup }
    var displayLegSubgroup: String? { self.legSubgroup }
    var displayEquipment: String? { self.equipment }
    var displayGripVariation: String? { self.gripVariation }
    
    // MARK: - Campos de Vídeo
    var displayDescription: String? { self.description }
    var displayVideoURL: String? { self.videoURL }
    var displayHasVideo: Bool {
        guard let videoURL = self.videoURL else { return false }
        return !videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - FirebaseExercise Extension (já implementada corretamente)
// Esta extensão já existe em FirebaseExercise.swift e está correta:
// extension FirebaseExercise: ExerciseDisplayable {
//     var displayMuscleGroup: String? { self.muscleGroup }
//     var displayLegSubgroup: String? { self.legSubgroup }
//     var displayEquipment: String? { self.equipment }
//     var displayGripVariation: String? { self.gripVariation }
//     var displayDescription: String? { self.description }
//     var displayVideoURL: String? { self.videoURL }
//     var displayHasVideo: Bool { self.hasVideo }
// } 