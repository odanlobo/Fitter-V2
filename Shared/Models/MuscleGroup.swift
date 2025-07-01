//
//  MuscleGroup.swift
//  Fitter V2
//
//  Created by AI Assistant
//

import Foundation

// MARK: - MuscleGroup Enum
enum MuscleGroup: String, CaseIterable {
    case chest = "chest"
    case back = "back" 
    case legs = "legs"
    case biceps = "biceps"
    case triceps = "triceps"
    case shoulders = "shoulders"
    case core = "core"
    
    var displayName: String {
        switch self {
        case .chest: return "Peito"
        case .back: return "Costas"
        case .legs: return "Pernas"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .shoulders: return "Ombros"
        case .core: return "Abdominal"
        }
    }
} 
