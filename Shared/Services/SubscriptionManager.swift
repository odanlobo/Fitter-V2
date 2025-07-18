import Foundation
import Combine
import CoreData
import RevenueCat

/// **SubscriptionManager.swift**
/// Orquestrador central do sistema de assinaturas premium
/// 
/// **RESPONSABILIDADES:**
/// - Consome RevenueCatService como fonte única de verdade
/// - Expõe publishers simples para toda a UI do app
/// - Integra com CloudSyncManager para sincronização
/// - Atualiza CDAppUser no Core Data após mudanças
/// - Gerencia cache local e estados offline
///
/// **ARQUITETURA:**
/// - Orquestrador puro (não executa operações de compra)
/// - Publishers centralizados para UI reativa
/// - Integração com sistema existente via DI
/// - Thread-safe e async/await
///
/// ⚠️ **REMOVER ANTES DO LANÇAMENTO:** Sistema de admin para desenvolvimento


protocol SubscriptionManagerProtocol {
    var isPremium: Bool { get }
    var subscriptionStatus: SubscriptionStatus { get }
    var isLoading: Bool { get }
    var lastError: Error? { get }
    
    func refreshSubscriptionStatus() async
    func clearSubscriptionData() async
    func getSubscriptionStatus(for user: CDAppUser) async -> SubscriptionStatus
    func updateUserSubscription(_ user: CDAppUser) async
    
    // ✅ ITEM 63: Fluxos completos de monetização com UX otimizada
    func purchase(_ package: Package, showConfirmation: Bool) async throws -> PurchaseResult
    func restorePurchases(showConfirmation: Bool) async throws -> RestoreResult
    func upgradeSubscription(to package: Package, showConfirmation: Bool) async throws -> UpgradeResult
    func downgradeSubscription(to package: Package, showConfirmation: Bool) async throws -> DowngradeResult
    func cancelSubscription(showConfirmation: Bool) async throws -> CancellationResult
    func reactivateSubscription(package: Package) async throws -> ReactivationResult
    
    // ✅ ITEM 63: Validação e eligibilidade para fluxos
    func canPurchase(_ package: Package) async -> PurchaseEligibility
    func canUpgrade(to package: Package) async -> UpgradeEligibility
    func canDowngrade(to package: Package) async -> DowngradeEligibility
    func getRecommendedPackages() async -> [Package]
}

@MainActor
final class SubscriptionManager: ObservableObject, SubscriptionManagerProtocol {
    
    // MARK: - Dependencies
    
    private let revenueCatService: RevenueCatServiceProtocol
    private let cloudSyncManager: CloudSyncManagerProtocol
    private let coreDataService: CoreDataServiceProtocol
    
    // MARK: - Published Properties
    
    /// Status premium do usuário atual
    /// ✅ Publisher central para toda a UI do app
    @Published private(set) var isPremium: Bool = false
    
    /// Status detalhado da assinatura
    /// ✅ Para ProfileView e analytics
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none
    
    /// Indica se está carregando dados
    @Published private(set) var isLoading: Bool = false
    
    /// Último erro ocorrido
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        revenueCatService: RevenueCatServiceProtocol,
        cloudSyncManager: CloudSyncManagerProtocol,
        coreDataService: CoreDataServiceProtocol
    ) {
        self.revenueCatService = revenueCatService
        self.cloudSyncManager = cloudSyncManager
        self.coreDataService = coreDataService
        
        setupRevenueCatObservers()
    }
    
    // MARK: - Public Methods
    
    /// Atualiza status de assinatura do RevenueCat
    /// ✅ Chamado após login ou mudanças de entitlement
    func refreshSubscriptionStatus() async {
        print("🔄 [SUBSCRIPTION] Atualizando status de assinatura...")
        isLoading = true
        lastError = nil
        
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
        // ✅ VERIFICAÇÃO ADMIN: Se não há usuário atual, tentar RevenueCat
        // Se há usuário atual, verificar se é admin primeiro
        if let currentUser = getCurrentUser() {
            if await self.isAdminUser(currentUser) {
                print("👑 [SUBSCRIPTION] Usuário admin detectado, definindo premium")
                isPremium = true
                subscriptionStatus = .active(type: .lifetime, expiresAt: Date.distantFuture)
                isLoading = false
                return
            }
        }
        
        do {
            let customerInfo = try await revenueCatService.getCustomerInfo()
            await updateSubscriptionStatus(from: customerInfo)
            print("✅ [SUBSCRIPTION] Status atualizado com sucesso")
        } catch {
            print("❌ [SUBSCRIPTION] Erro ao atualizar status: \(error)")
            lastError = error
        }
        
        isLoading = false
    }
    
    /// Limpa dados de assinatura
    /// ✅ Chamado pelo AuthUseCase.logout
    func clearSubscriptionData() async {
        print("🧹 [SUBSCRIPTION] Limpando dados de assinatura...")
        
        // Reset local state
        isPremium = false
        subscriptionStatus = .none
        lastError = nil
        
        // Reset RevenueCat
        await revenueCatService.reset()
        
        print("✅ [SUBSCRIPTION] Dados limpos com sucesso")
    }
    
    /// Obtém status de assinatura para usuário específico
    /// ✅ Para AuthUseCase.checkSubscriptionStatus
    func getSubscriptionStatus(for user: CDAppUser) async -> SubscriptionStatus {
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
        // ✅ VERIFICAÇÃO ADMIN: Bypass para usuários admin/teste
        if await self.isAdminUser(user) {
            print("👑 [SUBSCRIPTION] Usuário admin detectado: \(user.safeName)")
            return .active(type: .lifetime, expiresAt: Date.distantFuture)
        }
        
        // ✅ Verificar se há dados locais atualizados
        if let localStatus = user.subscriptionStatus {
            return localStatus
        }
        
        // ✅ Buscar do RevenueCat se necessário
        do {
            let customerInfo = try await revenueCatService.getCustomerInfo()
            let status = await parseSubscriptionStatus(from: customerInfo)
            
            // ✅ Atualizar usuário local
            await updateUserSubscription(user, with: status)
            
            return status
        } catch {
            print("⚠️ [SUBSCRIPTION] Erro ao buscar status para \(user.safeName): \(error)")
            return .none
        }
    }
    
    /// Atualiza dados de assinatura do usuário no Core Data
    /// ✅ Para sincronização local após mudanças
    func updateUserSubscription(_ user: CDAppUser) async {
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
        // ✅ VERIFICAÇÃO ADMIN: Bypass para usuários admin/teste
        if await self.isAdminUser(user) {
            print("👑 [SUBSCRIPTION] Usuário admin detectado: \(user.safeName)")
            let adminStatus = SubscriptionStatus.active(type: .lifetime, expiresAt: Date.distantFuture)
            await updateUserSubscription(user, with: adminStatus)
            await cloudSyncManager.scheduleUpload(for: user)
            return
        }
        
        do {
            let customerInfo = try await revenueCatService.getCustomerInfo()
            let status = await parseSubscriptionStatus(from: customerInfo)
            
            await updateUserSubscription(user, with: status)
            
            // ✅ Sincronizar com Firestore
            await cloudSyncManager.scheduleUpload(for: user)
            
            print("✅ [SUBSCRIPTION] Usuário \(user.safeName) atualizado com status: \(status)")
        } catch {
            print("❌ [SUBSCRIPTION] Erro ao atualizar usuário: \(error)")
            lastError = error
        }
    }
    
    // MARK: - Private Methods
    
    /// Configura observadores do RevenueCatService
    /// ✅ Clean Architecture - usando publishers do protocol
    private func setupRevenueCatObservers() {
        // ✅ Observar mudanças de isPremium via protocol
        revenueCatService.isPremiumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPremium in
                self?.isPremium = isPremium
                print("🔄 [SUBSCRIPTION] Status premium alterado: \(isPremium)")
            }
            .store(in: &cancellables)
        
        // ✅ Observar mudanças de customerInfo via protocol
        revenueCatService.customerInfoPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] customerInfo in
                Task { @MainActor in
                    await self?.updateSubscriptionStatus(from: customerInfo)
                }
            }
            .store(in: &cancellables)
        
        // ✅ Observar erros do RevenueCat via protocol
        revenueCatService.lastErrorPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.lastError = error
                print("⚠️ [SUBSCRIPTION] Erro do RevenueCat: \(error)")
            }
            .store(in: &cancellables)
    }
    
    /// Atualiza status de assinatura a partir do CustomerInfo
    private func updateSubscriptionStatus(from customerInfo: CustomerInfo) async {
        let newStatus = await parseSubscriptionStatus(from: customerInfo)
        
        // ✅ Atualizar estado local
        subscriptionStatus = newStatus
        isPremium = newStatus.isActive
        
        print("ℹ️ [SUBSCRIPTION] Status atualizado:")
        print("   - Premium: \(isPremium)")
        print("   - Status: \(newStatus)")
    }
    
    /// Converte CustomerInfo para SubscriptionStatus
    /// ✅ Analisa entitlements e datas para determinar status correto
    private func parseSubscriptionStatus(from customerInfo: CustomerInfo) async -> SubscriptionStatus {
        guard let premiumEntitlement = customerInfo.entitlements.active["premium"] else {
            return .none
        }
        
        // ✅ Determinar tipo de assinatura baseado no productId
        let productId = premiumEntitlement.productIdentifier
        let subscriptionType: SubscriptionType
        
        switch productId {
        case "fitter.monthly":
            subscriptionType = .monthly
        case "fitter.yearly":
            subscriptionType = .yearly
        case "fitter.lifetime":
            subscriptionType = .lifetime
        default:
            subscriptionType = .none
        }
        
        // ✅ Verificar se está ativo
        if premiumEntitlement.isActive {
            if let expirationDate = premiumEntitlement.expirationDate {
                // ✅ Assinatura com data de expiração
                if Date() < expirationDate {
                    return .active(type: subscriptionType, expiresAt: expirationDate)
                } else {
                    return .expired(type: subscriptionType, expiredAt: expirationDate)
                }
            } else {
                // ✅ Assinatura vitalícia
                return .active(type: subscriptionType, expiresAt: Date.distantFuture)
            }
        } else {
            // ✅ Assinatura inativa
            if let expirationDate = premiumEntitlement.expirationDate {
                return .expired(type: subscriptionType, expiredAt: expirationDate)
            } else {
                return .none
            }
        }
    }
    
    // MARK: - ITEM 63: Fluxos Completos de Monetização com UX Otimizada
    
    /// Realiza compra com UX otimizada e feedback completo
    /// ✅ Loading states, confirmações, feedback de sucesso/erro
    func purchase(_ package: Package, showConfirmation: Bool = true) async throws -> PurchaseResult {
        print("💰 [SUBSCRIPTION] Iniciando compra com UX otimizada: \(package.storeProduct.localizedTitle)")
        
        // ✅ Verificar elegibilidade
        let eligibility = await canPurchase(package)
        guard eligibility.canPurchase else {
            let error = SubscriptionError.purchaseNotEligible(reason: eligibility.reason)
            lastError = error
            throw error
        }
        
        // ✅ Estado de loading
        isLoading = true
        lastError = nil
        
        do {
            // ✅ Realizar compra via RevenueCat
            let customerInfo = try await revenueCatService.purchase(package)
            
            // ✅ Atualizar status local
            await updateSubscriptionStatus(from: customerInfo)
            
            // ✅ Sincronizar com usuário atual se disponível
            if let currentUser = getCurrentUser() {
                await updateUserSubscription(currentUser)
            }
            
            // ✅ Resultado da compra
            let result = PurchaseResult(
                success: true,
                package: package,
                customerInfo: customerInfo,
                previousStatus: subscriptionStatus,
                newStatus: await parseSubscriptionStatus(from: customerInfo),
                message: "Compra realizada com sucesso! Bem-vindo ao Fitter Premium!"
            )
            
            print("✅ [SUBSCRIPTION] Compra realizada com sucesso: \(package.storeProduct.localizedTitle)")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro na compra: \(error)")
            isLoading = false
            lastError = error
            
            let result = PurchaseResult(
                success: false,
                package: package,
                customerInfo: nil,
                previousStatus: subscriptionStatus,
                newStatus: subscriptionStatus,
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.purchaseFailed(error: error, result: result)
        }
    }
    
    /// Restaura compras com feedback detalhado
    /// ✅ UX otimizada com loading states e mensagens claras
    func restorePurchases(showConfirmation: Bool = true) async throws -> RestoreResult {
        print("🔄 [SUBSCRIPTION] Restaurando compras com UX otimizada...")
        
        isLoading = true
        lastError = nil
        let previousStatus = subscriptionStatus
        
        do {
            let customerInfo = try await revenueCatService.restorePurchases()
            
            // ✅ Atualizar status local
            await updateSubscriptionStatus(from: customerInfo)
            
            // ✅ Sincronizar com usuário atual se disponível
            if let currentUser = getCurrentUser() {
                await updateUserSubscription(currentUser)
            }
            
            let newStatus = await parseSubscriptionStatus(from: customerInfo)
            let hasActivePurchases = newStatus != .none
            
            let result = RestoreResult(
                success: true,
                customerInfo: customerInfo,
                previousStatus: previousStatus,
                newStatus: newStatus,
                hasActivePurchases: hasActivePurchases,
                message: hasActivePurchases ? 
                    "Compras restauradas com sucesso! Acesso premium ativado." :
                    "Não foram encontradas compras anteriores para restaurar."
            )
            
            print("✅ [SUBSCRIPTION] Compras restauradas - Status: \(hasActivePurchases ? "Ativas" : "Nenhuma")")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro ao restaurar: \(error)")
            isLoading = false
            lastError = error
            
            let result = RestoreResult(
                success: false,
                customerInfo: nil,
                previousStatus: previousStatus,
                newStatus: subscriptionStatus,
                hasActivePurchases: false,
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.restoreFailed(error: error, result: result)
        }
    }
    
    /// Upgrade de assinatura com validação automática
    /// ✅ Valida se é realmente um upgrade e gerencia transição
    func upgradeSubscription(to package: Package, showConfirmation: Bool = true) async throws -> UpgradeResult {
        print("⬆️ [SUBSCRIPTION] Upgrade para: \(package.storeProduct.localizedTitle)")
        
        // ✅ Verificar elegibilidade para upgrade
        let eligibility = await canUpgrade(to: package)
        guard eligibility.canUpgrade else {
            let error = SubscriptionError.upgradeNotEligible(reason: eligibility.reason)
            lastError = error
            throw error
        }
        
        isLoading = true
        lastError = nil
        let previousStatus = subscriptionStatus
        
        do {
            // ✅ Para upgrades, RevenueCat gerencia automaticamente
            // A compra normal já faz o upgrade se necessário
            let customerInfo = try await revenueCatService.purchase(package)
            
            // ✅ Atualizar status local
            await updateSubscriptionStatus(from: customerInfo)
            
            // ✅ Sincronizar com usuário atual se disponível
            if let currentUser = getCurrentUser() {
                await updateUserSubscription(currentUser)
            }
            
            let newStatus = await parseSubscriptionStatus(from: customerInfo)
            
            let result = UpgradeResult(
                success: true,
                fromPackage: eligibility.currentPackage,
                toPackage: package,
                customerInfo: customerInfo,
                previousStatus: previousStatus,
                newStatus: newStatus,
                proratedRefund: eligibility.proratedRefund,
                message: "Upgrade realizado com sucesso! Novos recursos disponíveis."
            )
            
            print("✅ [SUBSCRIPTION] Upgrade concluído: \(previousStatus) → \(newStatus)")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro no upgrade: \(error)")
            isLoading = false
            lastError = error
            
            let result = UpgradeResult(
                success: false,
                fromPackage: eligibility.currentPackage,
                toPackage: package,
                customerInfo: nil,
                previousStatus: previousStatus,
                newStatus: subscriptionStatus,
                proratedRefund: 0.0,
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.upgradeFailed(error: error, result: result)
        }
    }
    
    /// Downgrade de assinatura com aviso sobre perda de recursos
    /// ✅ Informa sobre recursos que serão perdidos e timing
    func downgradeSubscription(to package: Package, showConfirmation: Bool = true) async throws -> DowngradeResult {
        print("⬇️ [SUBSCRIPTION] Downgrade para: \(package.storeProduct.localizedTitle)")
        
        // ✅ Verificar elegibilidade para downgrade
        let eligibility = await canDowngrade(to: package)
        guard eligibility.canDowngrade else {
            let error = SubscriptionError.downgradeNotEligible(reason: eligibility.reason)
            lastError = error
            throw error
        }
        
        isLoading = true
        lastError = nil
        let previousStatus = subscriptionStatus
        
        do {
            // ✅ Para downgrades, RevenueCat gerencia automaticamente
            // O downgrade entra em efeito no próximo período de cobrança
            let customerInfo = try await revenueCatService.purchase(package)
            
            // ✅ Atualizar status local
            await updateSubscriptionStatus(from: customerInfo)
            
            // ✅ Sincronizar com usuário atual se disponível
            if let currentUser = getCurrentUser() {
                await updateUserSubscription(currentUser)
            }
            
            let newStatus = await parseSubscriptionStatus(from: customerInfo)
            
            let result = DowngradeResult(
                success: true,
                fromPackage: eligibility.currentPackage,
                toPackage: package,
                customerInfo: customerInfo,
                previousStatus: previousStatus,
                newStatus: newStatus,
                effectiveDate: eligibility.effectiveDate,
                featuresToLose: eligibility.featuresToLose,
                message: "Downgrade programado para \(eligibility.effectiveDate.formatted()). Recursos premium mantidos até lá."
            )
            
            print("✅ [SUBSCRIPTION] Downgrade programado: \(previousStatus) → \(newStatus) em \(eligibility.effectiveDate)")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro no downgrade: \(error)")
            isLoading = false
            lastError = error
            
            let result = DowngradeResult(
                success: false,
                fromPackage: eligibility.currentPackage,
                toPackage: package,
                customerInfo: nil,
                previousStatus: previousStatus,
                newStatus: subscriptionStatus,
                effectiveDate: Date(),
                featuresToLose: [],
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.downgradeFailed(error: error, result: result)
        }
    }
    
    /// Cancela assinatura com informações sobre acesso remanescente
    /// ✅ Informa até quando o acesso premium permanece ativo
    func cancelSubscription(showConfirmation: Bool = true) async throws -> CancellationResult {
        print("❌ [SUBSCRIPTION] Cancelando assinatura...")
        
        isLoading = true
        lastError = nil
        let previousStatus = subscriptionStatus
        
        // ⚠️ NOTA: Cancelamento real deve ser feito via App Store
        // Este método apenas atualiza o status local e informa o usuário
        
        do {
            let customerInfo = try await revenueCatService.getCustomerInfo()
            await updateSubscriptionStatus(from: customerInfo)
            
            let newStatus = await parseSubscriptionStatus(from: customerInfo)
            let accessUntil = customerInfo.entitlements.active["premium"]?.expirationDate
            
            let result = CancellationResult(
                success: true,
                customerInfo: customerInfo,
                previousStatus: previousStatus,
                newStatus: newStatus,
                accessUntil: accessUntil,
                canReactivate: accessUntil != nil && Date() < (accessUntil ?? Date()),
                message: accessUntil != nil ? 
                    "Cancelamento registrado. Acesso premium mantido até \(accessUntil!.formatted())." :
                    "Para cancelar, acesse Configurações > Assinaturas no iOS."
            )
            
            print("✅ [SUBSCRIPTION] Status de cancelamento atualizado")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro ao verificar cancelamento: \(error)")
            isLoading = false
            lastError = error
            
            let result = CancellationResult(
                success: false,
                customerInfo: nil,
                previousStatus: previousStatus,
                newStatus: subscriptionStatus,
                accessUntil: nil,
                canReactivate: false,
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.cancellationFailed(error: error, result: result)
        }
    }
    
    /// Reativa assinatura expirada
    /// ✅ Permite reativar assinatura que foi cancelada mas ainda não expirou
    func reactivateSubscription(package: Package) async throws -> ReactivationResult {
        print("🔄 [SUBSCRIPTION] Reativando assinatura: \(package.storeProduct.localizedTitle)")
        
        isLoading = true
        lastError = nil
        let previousStatus = subscriptionStatus
        
        do {
            let customerInfo = try await revenueCatService.purchase(package)
            
            // ✅ Atualizar status local
            await updateSubscriptionStatus(from: customerInfo)
            
            // ✅ Sincronizar com usuário atual se disponível
            if let currentUser = getCurrentUser() {
                await updateUserSubscription(currentUser)
            }
            
            let newStatus = await parseSubscriptionStatus(from: customerInfo)
            
            let result = ReactivationResult(
                success: true,
                package: package,
                customerInfo: customerInfo,
                previousStatus: previousStatus,
                newStatus: newStatus,
                message: "Assinatura reativada com sucesso! Bem-vindo de volta ao Premium!"
            )
            
            print("✅ [SUBSCRIPTION] Assinatura reativada: \(previousStatus) → \(newStatus)")
            isLoading = false
            return result
            
        } catch {
            print("❌ [SUBSCRIPTION] Erro na reativação: \(error)")
            isLoading = false
            lastError = error
            
            let result = ReactivationResult(
                success: false,
                package: package,
                customerInfo: nil,
                previousStatus: previousStatus,
                newStatus: subscriptionStatus,
                message: getErrorMessage(for: error)
            )
            
            throw SubscriptionError.reactivationFailed(error: error, result: result)
        }
    }
    
    // MARK: - ITEM 63: Validação e Eligibilidade
    
    /// Verifica se usuário pode comprar package específico
    func canPurchase(_ package: Package) async -> PurchaseEligibility {
        // ✅ Se já é premium, só pode fazer upgrade
        if isPremium {
            return PurchaseEligibility(
                canPurchase: false,
                reason: "Você já possui uma assinatura ativa. Use a opção de upgrade."
            )
        }
        
        // ✅ Verificar se package existe nas offerings
        do {
            let offerings = try await revenueCatService.fetchOfferings()
            let availablePackages = offerings.current?.availablePackages ?? []
            
            guard availablePackages.contains(where: { $0.identifier == package.identifier }) else {
                return PurchaseEligibility(
                    canPurchase: false,
                    reason: "Este plano não está mais disponível."
                )
            }
            
            return PurchaseEligibility(
                canPurchase: true,
                reason: "Pronto para assinar!"
            )
        } catch {
            return PurchaseEligibility(
                canPurchase: false,
                reason: "Erro ao verificar ofertas disponíveis."
            )
        }
    }
    
    /// Verifica se usuário pode fazer upgrade para package específico
    func canUpgrade(to package: Package) async -> UpgradeEligibility {
        guard isPremium else {
            return UpgradeEligibility(
                canUpgrade: false,
                reason: "Você precisa ter uma assinatura ativa para fazer upgrade."
            )
        }
        
        // ✅ Verificar se é realmente um upgrade
        let currentType = subscriptionStatus.type
        let targetType = getSubscriptionType(for: package)
        
        guard targetType.isUpgradeFrom(currentType) else {
            return UpgradeEligibility(
                canUpgrade: false,
                reason: "Este não é um upgrade válido do seu plano atual."
            )
        }
        
        // ✅ Calcular reembolso proporcional
        let proratedRefund = calculateProratedRefund(from: currentType, to: targetType)
        
        return UpgradeEligibility(
            canUpgrade: true,
            reason: "Upgrade disponível com reembolso proporcional.",
            currentPackage: getCurrentPackage(),
            proratedRefund: proratedRefund
        )
    }
    
    /// Verifica se usuário pode fazer downgrade para package específico
    func canDowngrade(to package: Package) async -> DowngradeEligibility {
        guard isPremium else {
            return DowngradeEligibility(
                canDowngrade: false,
                reason: "Você precisa ter uma assinatura ativa para fazer downgrade."
            )
        }
        
        // ✅ Verificar se é realmente um downgrade
        let currentType = subscriptionStatus.type
        let targetType = getSubscriptionType(for: package)
        
        guard targetType.isDowngradeFrom(currentType) else {
            return DowngradeEligibility(
                canDowngrade: false,
                reason: "Este não é um downgrade válido do seu plano atual."
            )
        }
        
        // ✅ Calcular quando o downgrade entra em efeito
        let effectiveDate = getNextBillingDate() ?? Date()
        
        // ✅ Listar recursos que serão perdidos
        let featuresToLose = getFeaturesToLose(from: currentType, to: targetType)
        
        return DowngradeEligibility(
            canDowngrade: true,
            reason: "Downgrade será efetivo no próximo período de cobrança.",
            currentPackage: getCurrentPackage(),
            effectiveDate: effectiveDate,
            featuresToLose: featuresToLose
        )
    }
    
    /// Obtém packages recomendados baseado no uso do usuário
    func getRecommendedPackages() async -> [Package] {
        do {
            let offerings = try await revenueCatService.fetchOfferings()
            let allPackages = offerings.current?.availablePackages ?? []
            
            // ✅ Se não é premium, recomendar anual (melhor valor)
            if !isPremium {
                return allPackages.sorted { package1, package2 in
                    let type1 = getSubscriptionType(for: package1)
                    let type2 = getSubscriptionType(for: package2)
                    return type1 == .yearly // Priorizar anual
                }
            }
            
            // ✅ Se já é premium, recomendar upgrades
            return allPackages.filter { package in
                let type = getSubscriptionType(for: package)
                return type.isUpgradeFrom(subscriptionStatus.type)
            }
        } catch {
            print("❌ [SUBSCRIPTION] Erro ao buscar recomendações: \(error)")
            return []
        }
    }
    
    // MARK: - ITEM 63: Helper Methods
    
    /// Obtém mensagem de erro amigável para usuário
    private func getErrorMessage(for error: Error) -> String {
        if let revenueCatError = error as? RevenueCatError {
            return revenueCatError.errorDescription ?? "Erro desconhecido"
        }
        
        if error.localizedDescription.contains("cancelled") {
            return "Compra cancelada pelo usuário"
        }
        
        if error.localizedDescription.contains("network") {
            return "Erro de conexão. Verifique sua internet e tente novamente."
        }
        
        return "Erro inesperado. Tente novamente em alguns momentos."
    }
    
    /// Obtém tipo de assinatura baseado no package
    private func getSubscriptionType(for package: Package) -> SubscriptionType {
        switch package.storeProduct.productIdentifier {
        case "fitter.monthly":
            return .monthly
        case "fitter.yearly":
            return .yearly
        case "fitter.lifetime":
            return .lifetime
        default:
            return .none
        }
    }
    
    /// Obtém package atual do usuário (se premium)
    /// ✅ Busca o package ativo baseado no customerInfo do RevenueCat
    private func getCurrentPackage() -> Package? {
        guard let customerInfo = revenueCatService.customerInfo,
              let premiumEntitlement = customerInfo.entitlements.active["premium"] else {
            return nil
        }
        
        // ✅ Buscar package baseado no productIdentifier
        let productId = premiumEntitlement.productIdentifier
        
        // ✅ Tentar buscar nas offerings atuais
        guard let offerings = revenueCatService.offerings else {
            return nil
        }
        
        return offerings.current?.availablePackages.first { package in
            package.storeProduct.productIdentifier == productId
        }
    }
    
    /// Calcula reembolso proporcional para upgrade
    /// ✅ Cálculo baseado no tempo restante da assinatura atual
    private func calculateProratedRefund(from: SubscriptionType, to: SubscriptionType) -> Double {
        guard let customerInfo = revenueCatService.customerInfo,
              let premiumEntitlement = customerInfo.entitlements.active["premium"],
              let expirationDate = premiumEntitlement.expirationDate else {
            return 0.0
        }
        
        // ✅ Calcular dias restantes
        let now = Date()
        let daysRemaining = max(0, Calendar.current.dateComponents([.day], from: now, to: expirationDate).day ?? 0)
        
        // ✅ Calcular reembolso baseado no tipo de assinatura
        let dailyValue: Double
        switch from {
        case .monthly:
            dailyValue = 9.99 / 30.0  // R$ 9,99 ÷ 30 dias
        case .yearly:
            dailyValue = 99.99 / 365.0  // R$ 99,99 ÷ 365 dias
        case .lifetime:
            return 0.0  // Sem reembolso para lifetime
        case .none:
            return 0.0
        }
        
        let refundAmount = dailyValue * Double(daysRemaining)
        
        print("💰 [SUBSCRIPTION] Reembolso calculado: R$ \(String(format: "%.2f", refundAmount)) para \(daysRemaining) dias")
        return refundAmount
    }
    
    /// Obtém próxima data de cobrança
    /// ✅ Busca a data real do customerInfo ou calcula baseado no período
    private func getNextBillingDate() -> Date? {
        guard let customerInfo = revenueCatService.customerInfo,
              let premiumEntitlement = customerInfo.entitlements.active["premium"] else {
            return nil
        }
        
        // ✅ Se há data de expiração, essa é a próxima cobrança
        if let expirationDate = premiumEntitlement.expirationDate {
            return expirationDate
        }
        
        // ✅ Fallback: calcular baseado no tipo de assinatura
        let calendar = Calendar.current
        let currentType = subscriptionStatus.type
        
        switch currentType {
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: Date())
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: Date())
        case .lifetime:
            return nil  // Não há próxima cobrança para vitalício
        case .none:
            return nil
        }
    }
    
    /// Lista recursos que serão perdidos no downgrade
    /// ✅ Lógica baseada nas diferenças reais entre planos
    private func getFeaturesToLose(from: SubscriptionType, to: SubscriptionType) -> [String] {
        var featuresToLose: [String] = []
        
        // ✅ Recursos perdidos de Premium para Free
        if to == .none {
            featuresToLose.append(contentsOf: [
                "Treinos ilimitados (máximo 4 treinos)",
                "Séries ilimitadas (máximo 3 séries por exercício)",
                "Análise detalhada de sensores",
                "Importação de treinos via câmera/arquivo",
                "Sincronização em nuvem avançada",
                "Gráficos e estatísticas completas",
                "Dados de heart rate e calorias",
                "Localização dos treinos"
            ])
        }
        
        // ✅ Recursos perdidos de Anual para Mensal
        if from == .yearly && to == .monthly {
            featuresToLose.append(contentsOf: [
                "Desconto do plano anual",
                "Prioridade no suporte"
            ])
        }
        
        // ✅ Recursos perdidos de Vitalício para qualquer outro
        if from == .lifetime {
            featuresToLose.append(contentsOf: [
                "Acesso vitalício sem cobrança recorrente",
                "Todas as funcionalidades futuras incluídas",
                "Prioridade máxima no suporte"
            ])
        }
        
        return featuresToLose
    }
    
    // MARK: - ⚠️ SISTEMA ADMIN - REMOVER ANTES DO LANÇAMENTO
    
    /// Obtém usuário atual (para verificação admin)
    /// ✅ Método auxiliar para verificar se usuário atual é admin
    /// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
    private func getCurrentUser() -> CDAppUser? {
        // ✅ Buscar usuário atual no Core Data
        // Você pode implementar isso baseado na sua lógica de AuthUseCase
        // Por enquanto, retorna nil (será implementado quando integrar com AuthUseCase)
        return nil
    }
    
    /// Verifica se o usuário é admin/teste para bypass do RevenueCat
    /// ✅ Para desenvolvimento e testes sem App Store Connect
    /// ⚠️ REMOVER ANTES DO LANÇAMENTO: Sistema de admin apenas para desenvolvimento
    func isAdminUser(_ user: CDAppUser) async -> Bool {
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Lista de emails admin apenas para desenvolvimento
        // ✅ Lista de emails admin (você pode adicionar o seu)
        let adminEmails = [
            "daniel@example.com",  // Substitua pelo seu email
            "admin@fitter.com",
            "test@fitter.com"
        ]
        
        // ✅ Verificar por email
        if let userEmail = user.email, adminEmails.contains(userEmail.lowercased()) {
            return true
        }
        
        // ⚠️ REMOVER ANTES DO LANÇAMENTO: Lista de IDs admin apenas para desenvolvimento
        // ✅ Verificar por ID específico (se necessário)
        let adminUserIds = [
            "V4pKs83V1Dc2yElHZB0ns2PbrIN2",  // Substitua pelos IDs que você quiser
            "ADMIN_USER_ID_2"
        ]
        
        if adminUserIds.contains(user.id.uuidString) {
            return true
        }
        
        // ✅ Verificar campo customizado no Firestore (se existir)
        // Você pode adicionar um campo "isAdmin" no Firestore
        // e verificar aqui se necessário
        
        return false
    }
    
    // MARK: - Private Methods (Produção)
    
    /// Atualiza dados de assinatura do usuário no Core Data
    private func updateUserSubscription(_ user: CDAppUser, with status: SubscriptionStatus) async {
        await coreDataService.performBackgroundTask { context in
            // ✅ Buscar usuário no contexto de background
            guard let backgroundUser = context.object(with: user.objectID) as? CDAppUser else {
                print("❌ [SUBSCRIPTION] Usuário não encontrado no contexto de background")
                return
            }
            
            // ✅ Atualizar campos de assinatura
            backgroundUser.subscriptionType = status.type.rawValue
            
            switch status {
            case .active(_, let expiresAt):
                backgroundUser.subscriptionValidUntil = expiresAt
                backgroundUser.subscriptionStartDate = Date()
            case .expired(_, let expiredAt):
                backgroundUser.subscriptionValidUntil = expiredAt
            case .gracePeriod(_, let expiresAt):
                backgroundUser.subscriptionValidUntil = expiresAt
            case .none:
                backgroundUser.subscriptionValidUntil = nil
                backgroundUser.subscriptionStartDate = nil
            }
            
            // ✅ Salvar mudanças
            do {
                try context.save()
                print("✅ [SUBSCRIPTION] Usuário salvo no Core Data: \(status)")
            } catch {
                print("❌ [SUBSCRIPTION] Erro ao salvar usuário: \(error)")
            }
        }
    }
}

// MARK: - SubscriptionStatus

/// Status detalhado da assinatura do usuário
/// ✅ Definição centralizada em SubscriptionType.swift - duplicação removida 

// MARK: - ITEM 63: Result Types

/// Resultado de uma compra
struct PurchaseResult {
    let success: Bool
    let package: Package
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let message: String
}

/// Resultado de restore de compras
struct RestoreResult {
    let success: Bool
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let hasActivePurchases: Bool
    let message: String
}

/// Resultado de upgrade
struct UpgradeResult {
    let success: Bool
    let fromPackage: Package?
    let toPackage: Package
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let proratedRefund: Double
    let message: String
}

/// Resultado de downgrade
struct DowngradeResult {
    let success: Bool
    let fromPackage: Package?
    let toPackage: Package
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let effectiveDate: Date
    let featuresToLose: [String]
    let message: String
}

/// Resultado de cancelamento
struct CancellationResult {
    let success: Bool
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let accessUntil: Date?
    let canReactivate: Bool
    let message: String
}

/// Resultado de reativação
struct ReactivationResult {
    let success: Bool
    let package: Package
    let customerInfo: CustomerInfo?
    let previousStatus: SubscriptionStatus
    let newStatus: SubscriptionStatus
    let message: String
}

// MARK: - ITEM 63: Eligibility Types

/// Elegibilidade para compra
struct PurchaseEligibility {
    let canPurchase: Bool
    let reason: String
}

/// Elegibilidade para upgrade
struct UpgradeEligibility {
    let canUpgrade: Bool
    let reason: String
    let currentPackage: Package?
    let proratedRefund: Double
    
    init(canUpgrade: Bool, reason: String, currentPackage: Package? = nil, proratedRefund: Double = 0.0) {
        self.canUpgrade = canUpgrade
        self.reason = reason
        self.currentPackage = currentPackage
        self.proratedRefund = proratedRefund
    }
}

/// Elegibilidade para downgrade
struct DowngradeEligibility {
    let canDowngrade: Bool
    let reason: String
    let currentPackage: Package?
    let effectiveDate: Date
    let featuresToLose: [String]
    
    init(canDowngrade: Bool, reason: String, currentPackage: Package? = nil, effectiveDate: Date = Date(), featuresToLose: [String] = []) {
        self.canDowngrade = canDowngrade
        self.reason = reason
        self.currentPackage = currentPackage
        self.effectiveDate = effectiveDate
        self.featuresToLose = featuresToLose
    }
}

// MARK: - ITEM 63: Error Types

enum SubscriptionError: LocalizedError {
    case purchaseNotEligible(reason: String)
    case purchaseFailed(error: Error, result: PurchaseResult)
    case restoreFailed(error: Error, result: RestoreResult)
    case upgradeNotEligible(reason: String)
    case upgradeFailed(error: Error, result: UpgradeResult)
    case downgradeNotEligible(reason: String)
    case downgradeFailed(error: Error, result: DowngradeResult)
    case cancellationFailed(error: Error, result: CancellationResult)
    case reactivationFailed(error: Error, result: ReactivationResult)
    
    var errorDescription: String? {
        switch self {
        case .purchaseNotEligible(let reason):
            return "Compra não permitida: \(reason)"
        case .purchaseFailed(_, let result):
            return "Falha na compra: \(result.message)"
        case .restoreFailed(_, let result):
            return "Falha ao restaurar: \(result.message)"
        case .upgradeNotEligible(let reason):
            return "Upgrade não permitido: \(reason)"
        case .upgradeFailed(_, let result):
            return "Falha no upgrade: \(result.message)"
        case .downgradeNotEligible(let reason):
            return "Downgrade não permitido: \(reason)"
        case .downgradeFailed(_, let result):
            return "Falha no downgrade: \(result.message)"
        case .cancellationFailed(_, let result):
            return "Falha no cancelamento: \(result.message)"
        case .reactivationFailed(_, let result):
            return "Falha na reativação: \(result.message)"
        }
    }
}

// MARK: - ITEM 63: SubscriptionType Extensions

extension SubscriptionType {
    /// Verifica se este tipo é um upgrade do tipo fornecido
    func isUpgradeFrom(_ other: SubscriptionType) -> Bool {
        switch (other, self) {
        case (.none, .monthly), (.none, .yearly), (.none, .lifetime):
            return true
        case (.monthly, .yearly), (.monthly, .lifetime):
            return true
        case (.yearly, .lifetime):
            return true
        default:
            return false
        }
    }
    
    /// Verifica se este tipo é um downgrade do tipo fornecido
    func isDowngradeFrom(_ other: SubscriptionType) -> Bool {
        switch (other, self) {
        case (.monthly, .none), (.yearly, .none), (.lifetime, .none):
            return true
        case (.yearly, .monthly), (.lifetime, .monthly):
            return true
        case (.lifetime, .yearly):
            return true
        default:
            return false
        }
    }
}

// MARK: - Core Data Extensions

/// Extensão para CDAppUser com computed property para SubscriptionStatus
extension CDAppUser {
    /// ✅ Converte dados do Core Data para SubscriptionStatus
    var subscriptionStatus: SubscriptionStatus? {
        // ✅ Converter dados do Core Data para SubscriptionStatus
        guard let type = SubscriptionType(rawValue: self.subscriptionType) else {
            return .none
        }
        
        if type == .none {
            return .none
        }
        
        // ✅ Verificar se há data de expiração
        guard let validUntil = self.subscriptionValidUntil else {
            if type == .lifetime {
                return .active(type: type, expiresAt: Date.distantFuture)
            }
            return .none
        }
        
        // ✅ Verificar se ainda está ativo
        let now = Date()
        if now < validUntil {
            return .active(type: type, expiresAt: validUntil)
        } else {
            return .expired(type: type, expiredAt: validUntil)
        }
    }
    
    // Note: safeName está definido em CoreDataModels.swift
} 