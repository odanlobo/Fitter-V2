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

/// Status detalhado da assinatura do usuário
/// ✅ Versão unificada para todo o projeto (AuthUseCase + SubscriptionManager)
enum SubscriptionStatus: Codable, CustomStringConvertible {
    case none
    case active(type: SubscriptionType, expiresAt: Date)
    case expired(type: SubscriptionType, expiredAt: Date)
    case gracePeriod(type: SubscriptionType, expiresAt: Date)
    
    // MARK: - Computed Properties
    
    var isActive: Bool {
        switch self {
        case .active, .gracePeriod: return true
        case .none, .expired: return false
        }
    }
    
    var isPremium: Bool {
        switch self {
        case .active(let type, _), .gracePeriod(let type, _):
            return type != .none
        case .none, .expired:
            return false
        }
    }
    
    var type: SubscriptionType {
        switch self {
        case .active(let type, _), .expired(let type, _), .gracePeriod(let type, _):
            return type
        case .none:
            return .none
        }
    }
    
    var displayName: String {
        switch self {
        case .none:
            return "Sem assinatura"
        case .active(let type, _):
            return "\(type.displayName) Ativa"
        case .expired(let type, _):
            return "\(type.displayName) Expirada"
        case .gracePeriod(let type, _):
            return "\(type.displayName) Grace Period"
        }
    }
    
    var description: String {
        return displayName
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type = "status_type"
        case subscriptionType = "subscription_type"
        case date = "date"
    }
    
    private enum StatusType: String, Codable {
        case none, active, expired, gracePeriod
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let statusType = try container.decode(StatusType.self, forKey: .type)
        
        switch statusType {
        case .none:
            self = .none
        case .active:
            let subscriptionType = try container.decode(SubscriptionType.self, forKey: .subscriptionType)
            let date = try container.decode(Date.self, forKey: .date)
            self = .active(type: subscriptionType, expiresAt: date)
        case .expired:
            let subscriptionType = try container.decode(SubscriptionType.self, forKey: .subscriptionType)
            let date = try container.decode(Date.self, forKey: .date)
            self = .expired(type: subscriptionType, expiredAt: date)
        case .gracePeriod:
            let subscriptionType = try container.decode(SubscriptionType.self, forKey: .subscriptionType)
            let date = try container.decode(Date.self, forKey: .date)
            self = .gracePeriod(type: subscriptionType, expiresAt: date)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .none:
            try container.encode(StatusType.none, forKey: .type)
        case .active(let type, let date):
            try container.encode(StatusType.active, forKey: .type)
            try container.encode(type, forKey: .subscriptionType)
            try container.encode(date, forKey: .date)
        case .expired(let type, let date):
            try container.encode(StatusType.expired, forKey: .type)
            try container.encode(type, forKey: .subscriptionType)
            try container.encode(date, forKey: .date)
        case .gracePeriod(let type, let date):
            try container.encode(StatusType.gracePeriod, forKey: .type)
            try container.encode(type, forKey: .subscriptionType)
            try container.encode(date, forKey: .date)
        }
    }
}

// MARK: - Legacy Support (para compatibilidade com versões anteriores)

extension SubscriptionStatus {
    /// Inicializa a partir de String simples (para compatibilidade com Core Data legado)
    init?(legacyString: String) {
        switch legacyString.lowercased() {
        case "none", "":
            self = .none
        case "active":
            self = .active(type: .monthly, expiresAt: Date.distantFuture) // Fallback
        case "expired":
            self = .expired(type: .monthly, expiredAt: Date.distantPast) // Fallback
        case "grace_period":
            self = .gracePeriod(type: .monthly, expiresAt: Date.distantFuture) // Fallback
        default:
            return nil
        }
    }
    
    /// Converte para String simples (para compatibilidade com Core Data legado)
    var legacyString: String {
        switch self {
        case .none: return "none"
        case .active: return "active"
        case .expired: return "expired"
        case .gracePeriod: return "grace_period"
        }
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