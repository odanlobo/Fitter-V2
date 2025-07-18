import Foundation

/// Unidades de peso suportadas pelo app
enum WeightUnit: String, CaseIterable {
    case kg = "kg"
    case lbs = "lbs"
    
    /// Nome de exibição da unidade
    var displayName: String {
        switch self {
        case .kg: return "kg"
        case .lbs: return "lbs"
        }
    }
    
    /// Símbolo da unidade
    var symbol: String {
        return rawValue
    }
    
    /// Conversão para quilogramas
    func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lbs: return value * 0.453592
        }
    }
    
    /// Conversão de quilogramas para esta unidade
    func fromKg(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lbs: return value / 0.453592
        }
    }
    
    /// Conversão entre unidades
    func convert(_ value: Double, to unit: WeightUnit) -> Double {
        let kg = toKg(value)
        return unit.fromKg(kg)
    }
} 