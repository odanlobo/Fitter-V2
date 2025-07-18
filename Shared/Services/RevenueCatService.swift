import Foundation
import RevenueCat
import Combine
import UIKit

/// **RevenueCatService.swift**
/// Wrapper completo do SDK RevenueCat para integração iOS/watchOS
/// 
/// **RESPONSABILIDADES:**
/// - Configuração e inicialização do SDK RevenueCat
/// - Publishers reativos para status premium e offerings
/// - Métodos para compra, restore e consulta de customer info
/// - Listeners para mudanças de entitlement em tempo real
/// - Integração com AuthUseCase para gestão de usuários
///
/// **ARQUITETURA:**
/// - Service puro sem lógica de negócio
/// - Publishers para UI reativa via @Published
/// - Error handling robusto
/// - Thread-safe e async/await
protocol RevenueCatServiceProtocol: ObservableObject {
    var isPremium: Bool { get }
    var offerings: Offerings? { get }
    var customerInfo: CustomerInfo? { get }
    var isLoading: Bool { get }
    var lastError: Error? { get }
    
    // ✅ Publishers para Clean Architecture com DI
    var isPremiumPublisher: AnyPublisher<Bool, Never> { get }
    var customerInfoPublisher: AnyPublisher<CustomerInfo?, Never> { get }
    var lastErrorPublisher: AnyPublisher<Error?, Never> { get }
    
    func configure(userId: String) async
    func fetchOfferings() async throws -> Offerings
    func purchase(_ package: Package) async throws -> CustomerInfo
    func restorePurchases() async throws -> CustomerInfo
    func getCustomerInfo() async throws -> CustomerInfo
    func reset() async
}

@MainActor
final class RevenueCatService: ObservableObject, RevenueCatServiceProtocol {
    
    // MARK: - Published Properties
    
    /// Status premium do usuário atual
    /// ✅ Fonte única de verdade para toda a UI
    @Published private(set) var isPremium: Bool = false
    
    /// Ofertas disponíveis do RevenueCat
    /// ✅ Carregadas automaticamente e atualizadas conforme necessário
    @Published private(set) var offerings: Offerings?
    
    /// Informações completas do customer
    /// ✅ Inclui entitlements, purchase dates, etc.
    @Published private(set) var customerInfo: CustomerInfo?
    
    /// Indica se está carregando dados
    @Published private(set) var isLoading: Bool = false
    
    /// Último erro ocorrido (para feedback na UI)
    @Published private(set) var lastError: Error?
    
    // MARK: - Publishers para Protocol Compliance
    
    /// Publisher para status premium (Clean Architecture)
    var isPremiumPublisher: AnyPublisher<Bool, Never> {
        $isPremium.eraseToAnyPublisher()
    }
    
    /// Publisher para customer info (Clean Architecture)
    var customerInfoPublisher: AnyPublisher<CustomerInfo?, Never> {
        $customerInfo.eraseToAnyPublisher()
    }
    
    /// Publisher para erros (Clean Architecture)
    var lastErrorPublisher: AnyPublisher<Error?, Never> {
        $lastError.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private let entitlementKey = "premium"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupPurchasesListener()
    }
    
    // MARK: - Public Methods
    
    /// Configura RevenueCat com usuário específico
    /// ✅ Chamado pelo AuthUseCase.signIn após login bem-sucedido
    func configure(userId: String) async {
        print("🔑 [REVENUECAT] Configurando para usuário: \(userId)")
        
        // ✅ Configurar Purchases com userId
        Purchases.shared.logIn(userId) { [weak self] customerInfo, created, error in
            Task { @MainActor in
                if let error = error {
                    print("❌ [REVENUECAT] Erro ao fazer login: \(error)")
                    self?.lastError = error
                    return
                }
                
                if created {
                    print("✅ [REVENUECAT] Novo customer criado: \(userId)")
                } else {
                    print("✅ [REVENUECAT] Customer existente conectado: \(userId)")
                }
                
                // Atualizar estado local
                self?.updateCustomerInfo(customerInfo)
                
                // Carregar offerings
                await self?.loadOfferings()
            }
        }
    }
    
    /// Busca ofertas disponíveis do RevenueCat
    /// ✅ Para PaywallView e onboarding
    func fetchOfferings() async throws -> Offerings {
        isLoading = true
        lastError = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { [weak self] offerings, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        print("❌ [REVENUECAT] Erro ao buscar offerings: \(error)")
                        self?.lastError = error
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let offerings = offerings else {
                        let noOfferingsError = RevenueCatError.noOfferingsAvailable
                        self?.lastError = noOfferingsError
                        continuation.resume(throwing: noOfferingsError)
                        return
                    }
                    
                    print("✅ [REVENUECAT] Offerings carregadas: \(offerings.all.count) disponíveis")
                    self?.offerings = offerings
                    continuation.resume(returning: offerings)
                }
            }
        }
    }
    
    /// Realiza compra de um package específico
    /// ✅ Chamado pelo PaywallView
    func purchase(_ package: Package) async throws -> CustomerInfo {
        print("💰 [REVENUECAT] Iniciando compra: \(package.storeProduct.localizedTitle)")
        isLoading = true
        lastError = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.purchase(package: package) { [weak self] transaction, customerInfo, error, userCancelled in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if userCancelled {
                        print("⏹️ [REVENUECAT] Compra cancelada pelo usuário")
                        let cancelledError = RevenueCatError.purchaseCancelled
                        self?.lastError = cancelledError
                        continuation.resume(throwing: cancelledError)
                        return
                    }
                    
                    if let error = error {
                        print("❌ [REVENUECAT] Erro na compra: \(error)")
                        self?.lastError = error
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let customerInfo = customerInfo else {
                        let noCustomerInfoError = RevenueCatError.noCustomerInfo
                        self?.lastError = noCustomerInfoError
                        continuation.resume(throwing: noCustomerInfoError)
                        return
                    }
                    
                    print("✅ [REVENUECAT] Compra bem-sucedida!")
                    self?.updateCustomerInfo(customerInfo)
                    continuation.resume(returning: customerInfo)
                }
            }
        }
    }
    
    /// Restaura compras anteriores
    /// ✅ Chamado pelo ProfileView
    func restorePurchases() async throws -> CustomerInfo {
        print("🔄 [REVENUECAT] Restaurando compras...")
        isLoading = true
        lastError = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.restorePurchases { [weak self] customerInfo, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        print("❌ [REVENUECAT] Erro ao restaurar: \(error)")
                        self?.lastError = error
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let customerInfo = customerInfo else {
                        let noCustomerInfoError = RevenueCatError.noCustomerInfo
                        self?.lastError = noCustomerInfoError
                        continuation.resume(throwing: noCustomerInfoError)
                        return
                    }
                    
                    print("✅ [REVENUECAT] Compras restauradas com sucesso!")
                    self?.updateCustomerInfo(customerInfo)
                    continuation.resume(returning: customerInfo)
                }
            }
        }
    }
    
    /// Obtém informações atuais do customer
    /// ✅ Para verificação de status
    func getCustomerInfo() async throws -> CustomerInfo {
        isLoading = true
        lastError = nil
        
        return try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        print("❌ [REVENUECAT] Erro ao buscar customer info: \(error)")
                        self?.lastError = error
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let customerInfo = customerInfo else {
                        let noCustomerInfoError = RevenueCatError.noCustomerInfo
                        self?.lastError = noCustomerInfoError
                        continuation.resume(throwing: noCustomerInfoError)
                        return
                    }
                    
                    self?.updateCustomerInfo(customerInfo)
                    continuation.resume(returning: customerInfo)
                }
            }
        }
    }
    
    /// Reset completo do RevenueCat
    /// ✅ Chamado pelo AuthUseCase.logout
    func reset() async {
        print("🔄 [REVENUECAT] Fazendo reset...")
        
        await withCheckedContinuation { continuation in
            Purchases.shared.logOut { [weak self] customerInfo, error in
                Task { @MainActor in
                    if let error = error {
                        print("⚠️ [REVENUECAT] Aviso no logout: \(error)")
                    }
                    
                    // Limpar estado local
                    self?.isPremium = false
                    self?.offerings = nil
                    self?.customerInfo = nil
                    self?.lastError = nil
                    
                    print("✅ [REVENUECAT] Reset concluído")
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Configura listener para mudanças de customer info
    /// ✅ Clean Architecture - Polling strategy para robustez e independência de SDK
    private func setupPurchasesListener() {
        // ✅ ESTRATÉGIA ROBUSTA: Timer-based polling em vez de notifications
        // Esta abordagem é mais robusta e independente das mudanças do SDK RevenueCat
        // Polling a cada 30 segundos quando app está ativo para detectar mudanças
        
        Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // ✅ Verificar mudanças periodicamente apenas quando necessário
                self?.checkForCustomerInfoUpdates()
            }
            .store(in: &cancellables)
        
        // ✅ BACKUP: Verificar também quando app se torna ativo
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkForCustomerInfoUpdates()
            }
            .store(in: &cancellables)
        
        print("✅ [REVENUECAT] Configurado listener robusto com polling strategy")
    }
    
    /// Verifica updates de customer info de forma assíncrona
    /// ✅ Método privado para verificação controlada sem spam de requests
    private func checkForCustomerInfoUpdates() {
        // ✅ Evitar múltiplas chamadas simultâneas
        guard !isLoading else { return }
        
        Task { @MainActor in
            do {
                let currentInfo = try await getCustomerInfo()
                
                // ✅ Verificar se houve mudança real antes de atualizar
                let hasChanged = self.customerInfo?.entitlements.active != currentInfo.entitlements.active
                
                if hasChanged {
                    print("🔔 [REVENUECAT] Customer info mudou, atualizando...")
                    self.updateCustomerInfo(currentInfo)
                }
            } catch {
                // ✅ Log silencioso - polling não deve gerar ruído
                // print("⚠️ [REVENUECAT] Erro no polling: \(error)")
            }
        }
    }
    
    /// Atualiza estado local com customer info
    private func updateCustomerInfo(_ customerInfo: CustomerInfo?) {
        self.customerInfo = customerInfo
        
        // ✅ Atualiza status premium baseado no entitlement
        let wasPremium = isPremium
        isPremium = customerInfo?.entitlements.active[entitlementKey] != nil
        
        if wasPremium != isPremium {
            print("🔄 [REVENUECAT] Status premium alterado: \(wasPremium) → \(isPremium)")
        }
        
        // ✅ Log detalhado para debug
        if let customerInfo = customerInfo {
            print("ℹ️ [REVENUECAT] Customer Info:")
            print("   - Premium: \(isPremium)")
            print("   - Original App User ID: \(customerInfo.originalAppUserId)")
            print("   - Entitlements ativos: \(customerInfo.entitlements.active.keys.joined(separator: ", "))")
            
            if let premiumEntitlement = customerInfo.entitlements.active[entitlementKey] {
                print("   - Premium válido até: \(premiumEntitlement.expirationDate?.description ?? "Vitalício")")
            }
        }
    }
    
    /// Carrega offerings na inicialização
    private func loadOfferings() async {
        do {
            _ = try await fetchOfferings()
        } catch {
            print("⚠️ [REVENUECAT] Falha ao carregar offerings iniciais: \(error)")
        }
    }
}

// MARK: - Error Types

enum RevenueCatError: LocalizedError {
    case noOfferingsAvailable
    case purchaseCancelled
    case noCustomerInfo
    
    var errorDescription: String? {
        switch self {
        case .noOfferingsAvailable:
            return "Nenhuma oferta disponível no momento"
        case .purchaseCancelled:
            return "Compra cancelada pelo usuário"
        case .noCustomerInfo:
            return "Informações do cliente não disponíveis"
        }
    }
} 