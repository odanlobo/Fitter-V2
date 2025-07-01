/*
 * SubscriptionType.swift
 * Fitter V2
 *
 * RESPONSABILIDADE: Enum para tipos de assinatura com compatibilidade Core Data
 *                   Definir tipos de assinatura (none, monthly, yearly, lifetime)
 *
 * CONFORMIDADES:
 * - Int16: Compatibilidade com Core Data (CDAppUser.subscriptionType)
 * - CaseIterable: Para enumeração em UI 
 * - Codable: Para serialização JSON/Firestore
 * - CustomStringConvertible: Para debugging e logs
 *
 * TIPOS DISPONÍVEIS:
 * - none (0): Usuário gratuito sem assinatura
 * - monthly (1): Assinatura mensal R$9,99/mês
 * - yearly (2): Assinatura anual R$99,99/ano
 * - lifetime (3): Compra única R$199,99
 *
 * COMPUTED PROPERTIES:
 * - isSubscriber: Verifica se possui assinatura ativa
 * - isActive: Verifica se assinatura é válida (para monthly/yearly)
 * - displayName: Nome amigável para UI
 * - description: Descrição detalhada
 *
 * REFATORAÇÃO ITEM 55/101:
 * ✅ Criar enum SubscriptionType
 * ✅ Compatibilidade Core Data Int16
 * ✅ Computed properties para UI
 * 🔄 Integração com SubscriptionManager (item 54)
 */

import Foundation

// MARK: - SubscriptionType Enum

enum SubscriptionType: Int16, CaseIterable, Codable, CustomStringConvertible {
    case none = 0
    case monthly = 1
    case yearly = 2
    case lifetime = 3
    
    // MARK: - Computed Properties
    
    /// Verifica se o usuário possui alguma assinatura
    var isSubscriber: Bool {
        return self != .none
    }
    
    /// Nome amigável para exibição na UI
    var displayName: String {
        switch self {
        case .none:
            return "Gratuito"
        case .monthly:
            return "Mensal"
        case .yearly:
            return "Anual"
        case .lifetime:
            return "Vitalício"
        }
    }
    
    /// Descrição detalhada para UI
    var description: String {
        switch self {
        case .none:
            return "Acesso gratuito com limitações"
        case .monthly:
            return "Assinatura mensal - R$ 9,99/mês"
        case .yearly:
            return "Assinatura anual - R$ 99,99/ano"
        case .lifetime:
            return "Compra única - R$ 199,99"
        }
    }
    
    /// Preço em reais (para referência)
    var priceInReais: Decimal? {
        switch self {
        case .none:
            return 0.00
        case .monthly:
            return 9.99
        case .yearly:
            return 99.99
        case .lifetime:
            return 199.99
        }
    }
    
    /// Product ID para App Store Connect
    var productId: String? {
        switch self {
        case .none:
            return nil
        case .monthly:
            return "fitter.monthly"
        case .yearly:
            return "fitter.yearly"
        case .lifetime:
            return "fitter.lifetime"
        }
    }
    
    /// Duração em dias (para cálculos de expiração)
    var durationInDays: Int? {
        switch self {
        case .none, .lifetime:
            return nil // Sem expiração
        case .monthly:
            return 30
        case .yearly:
            return 365
        }
    }
}

// MARK: - Extensions para CDAppUser

extension SubscriptionType {
    
    /// Verifica se a assinatura está ativa baseada na data de validade
    func isActive(validUntil: Date?) -> Bool {
        switch self {
        case .none:
            return false
        case .lifetime:
            return true // Vitalício nunca expira
        case .monthly, .yearly:
            guard let validUntil = validUntil else { return false }
            return validUntil > Date()
        }
    }
    
    /// Calcula dias restantes até expiração
    func daysUntilExpiration(validUntil: Date?) -> Int? {
        switch self {
        case .none:
            return nil
        case .lifetime:
            return nil // Nunca expira
        case .monthly, .yearly:
            guard let validUntil = validUntil else { return 0 }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: validUntil).day ?? 0
            return max(0, days)
        }
    }
}

// MARK: - Status da Assinatura

enum SubscriptionStatus: String, CaseIterable, Codable {
    case none = "none"
    case active = "active"
    case expired = "expired"
    case gracePeriod = "grace_period"
    case billingRetry = "billing_retry"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .none:
            return "Sem assinatura"
        case .active:
            return "Ativa"
        case .expired:
            return "Expirada"
        case .gracePeriod:
            return "Período de graça"
        case .billingRetry:
            return "Tentando cobrança"
        case .cancelled:
            return "Cancelada"
        }
    }
    
    var isValid: Bool {
        return self == .active || self == .gracePeriod
    }
}

// MARK: - Helper Methods para Core Data

extension SubscriptionType {
    
    /// Inicializa a partir de Int16 (Core Data)
    init?(rawValue: Int16) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .monthly  
        case 2: self = .yearly
        case 3: self = .lifetime
        default: return nil
        }
    }
    
    /// Converte para Int16 (Core Data)
    var int16Value: Int16 {
        return self.rawValue
    }
}

// MARK: - Mock Data para Preview

#if DEBUG
extension SubscriptionType {
    static let mockNone = SubscriptionType.none
    static let mockMonthly = SubscriptionType.monthly
    static let mockYearly = SubscriptionType.yearly
    static let mockLifetime = SubscriptionType.lifetime
    
    static func mockValidUntil(for type: SubscriptionType) -> Date? {
        switch type {
        case .none:
            return nil
        case .monthly:
            return Calendar.current.date(byAdding: .day, value: 30, to: Date())
        case .yearly:
            return Calendar.current.date(byAdding: .day, value: 365, to: Date())
        case .lifetime:
            return nil
        }
    }
}
#endif 