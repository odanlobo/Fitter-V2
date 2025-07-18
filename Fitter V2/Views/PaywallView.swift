import SwiftUI
import RevenueCat

/// **PaywallView.swift**
/// Interface de venda e upgrade para recursos premium
/// 
/// **RESPONSABILIDADES:**
/// - Exibe ofertas/packages vindas do RevenueCat
/// - Mostra trial, promo, valores e ações de compra
/// - Integração com RevenueCatService para operações
/// - Call-to-action para upgrade durante uso do app
/// - Suporte a múltiplas ofertas (onboarding, upgrade, etc.)
///
/// **ARQUITETURA:**
/// - View pura sem lógica de negócio
/// - Consome RevenueCatService via environment
/// - Publishers reativos para UI dinâmica
/// - Suporte a diferentes contextos de exibição
struct PaywallView: View {
    
    // MARK: - Environment
    
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// Contexto de exibição do paywall
    let context: PaywallContext
    
    /// Callback opcional após compra bem-sucedida
    let onPurchaseSuccess: (() -> Void)?
    
    // MARK: - State
    
    @State private var selectedPackage: Package?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // ✅ ITEM 63: Estados adicionais para UX otimizada
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    @State private var availableOfferings: Offerings?
    @State private var isLoadingOfferings = true
    @State private var showUpgradeConfirmation = false
    @State private var showDowngradeWarning = false
    @State private var pendingAction: (() async -> Void)?

    // MARK: - Initialization
    
    init(
        context: PaywallContext = .upgrade,
        onPurchaseSuccess: (() -> Void)? = nil
    ) {
        self.context = context
        self.onPurchaseSuccess = onPurchaseSuccess
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Features
                    featuresSection
                    
                    // Pricing
                    pricingSection
                    
                    // Action Buttons
                    actionButtonsSection
                    
                    // Footer
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Fitter Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .task {
                await loadOfferings()
            }
        }
        .alert("Erro", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
        .alert("Sucesso!", isPresented: $showSuccessMessage) {
            Button("Continuar") { 
                showSuccessMessage = false
                onPurchaseSuccess?()
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .confirmationDialog("Confirmar Upgrade", isPresented: $showUpgradeConfirmation) {
            Button("Confirmar Upgrade") {
                if let action = pendingAction {
                    Task { await action() }
                }
            }
            Button("Cancelar", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Tem certeza que deseja fazer upgrade do seu plano? As mudanças entram em efeito imediatamente.")
        }
        .confirmationDialog("Atenção: Downgrade", isPresented: $showDowngradeWarning) {
            Button("Confirmar Downgrade") {
                if let action = pendingAction {
                    Task { await action() }
                }
            }
            Button("Cancelar", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("O downgrade entrará em efeito no próximo período de cobrança. Você manterá acesso aos recursos premium até lá.")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo/Icon
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title
            Text(context.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Subtitle
            Text(context.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(spacing: 16) {
            Text("O que você ganha:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "infinity",
                    title: "Treinos Ilimitados",
                    description: "Crie quantos treinos quiser"
                )
                
                FeatureRow(
                    icon: "figure.strengthtraining.traditional",
                    title: "Exercícios Ilimitados",
                    description: "Até 6 exercícios por treino"
                )
                
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Análise Detalhada",
                    description: "Repetições em tempo real e gráficos"
                )
                
                FeatureRow(
                    icon: "arrow.up.arrow.down",
                    title: "Séries Ilimitadas",
                    description: "Quantas séries quiser por exercício"
                )
                
                FeatureRow(
                    icon: "icloud.and.arrow.up",
                    title: "Importação Avançada",
                    description: "Importe múltiplos treinos de uma vez"
                )
            }
        }
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(spacing: 16) {
            Text("Escolha seu plano:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isLoadingOfferings {
                ProgressView("Carregando ofertas...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if availablePackages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("Não foi possível carregar as ofertas")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Verifique sua conexão e tente novamente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Tentar Novamente") {
                        Task { await loadOfferings() }
                    }
                    .font(.footnote)
                    .foregroundColor(.blue)
                }
                .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(availablePackages, id: \.identifier) { package in
                        PackageCard(
                            package: package,
                            isSelected: selectedPackage?.identifier == package.identifier,
                            isRecommended: isRecommended(package),
                            discount: getDiscount(for: package),
                            onTap: {
                                selectedPackage = package
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Purchase Button
            Button(action: handlePurchase) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Assinar Agora")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canPurchase ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canPurchase || isLoading)
            
            // Restore Button
            Button("Restaurar Compras") {
                handleRestore()
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Cancelamento a qualquer momento")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Assinatura renovada automaticamente")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var availablePackages: [Package] {
        // ✅ ITEM 63: Usar offerings reais do RevenueCat
        guard let offerings = availableOfferings else { return [] }
        
        let packages = offerings.current?.availablePackages ?? []
        
        // ✅ Ordenar packages: yearly primeiro (melhor valor), depois monthly, depois lifetime
        return packages.sorted { package1, package2 in
            let type1 = getSubscriptionType(for: package1)
            let type2 = getSubscriptionType(for: package2)
            
            switch (type1, type2) {
            case (.yearly, _):
                return true
            case (_, .yearly):
                return false
            case (.monthly, .lifetime):
                return true
            case (.lifetime, .monthly):
                return false
            default:
                return false
            }
        }
    }
    
    private var canPurchase: Bool {
        return selectedPackage != nil && !subscriptionManager.isPremium
    }
    
    // MARK: - Actions
    
    private func handlePurchase() {
        guard let package = selectedPackage else { return }
        
        // ✅ ITEM 63: Validar elegibilidade antes de comprar
        Task {
            // Se usuário já é premium, mostrar opções de upgrade/downgrade
            if subscriptionManager.isPremium {
                await handleUpgradeDowngrade(package: package)
            } else {
                await performPurchase(package: package)
            }
        }
    }
    
    /// Realiza compra para usuário não-premium
    private func performPurchase(package: Package) async {
        isLoading = true
        
        do {
            let result = try await subscriptionManager.purchase(package, showConfirmation: false)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    successMessage = result.message
                    showSuccessMessage = true
                } else {
                    errorMessage = result.message
                    showError = true
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    /// Gerencia upgrade/downgrade para usuário premium
    private func handleUpgradeDowngrade(package: Package) async {
        let currentType = subscriptionManager.subscriptionStatus.type
        let targetType = getSubscriptionType(for: package)
        
        if targetType.isUpgradeFrom(currentType) {
            // ✅ É um upgrade
            pendingAction = { [weak self] in
                await self?.performUpgrade(package: package)
            }
            showUpgradeConfirmation = true
        } else if targetType.isDowngradeFrom(currentType) {
            // ✅ É um downgrade
            pendingAction = { [weak self] in
                await self?.performDowngrade(package: package)
            }
            showDowngradeWarning = true
        } else {
            // ✅ Não é upgrade nem downgrade válido
            errorMessage = "Este plano não é um upgrade ou downgrade válido do seu plano atual."
            showError = true
        }
    }
    
    /// Realiza upgrade de assinatura
    private func performUpgrade(package: Package) async {
        isLoading = true
        
        do {
            let result = try await subscriptionManager.upgradeSubscription(to: package, showConfirmation: false)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    successMessage = result.message
                    showSuccessMessage = true
                } else {
                    errorMessage = result.message
                    showError = true
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        
        pendingAction = nil
    }
    
    /// Realiza downgrade de assinatura
    private func performDowngrade(package: Package) async {
        isLoading = true
        
        do {
            let result = try await subscriptionManager.downgradeSubscription(to: package, showConfirmation: false)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    successMessage = result.message
                    showSuccessMessage = true
                } else {
                    errorMessage = result.message
                    showError = true
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        
        pendingAction = nil
    }
    
    private func handleRestore() {
        isLoading = true
        
        Task {
            do {
                // ✅ ITEM 63: Usar método melhorado com feedback detalhado
                let result = try await subscriptionManager.restorePurchases(showConfirmation: false)
                
                await MainActor.run {
                    isLoading = false
                    
                    if result.success {
                        if result.hasActivePurchases {
                            successMessage = result.message
                            showSuccessMessage = true
                        } else {
                            errorMessage = result.message
                            showError = true
                        }
                    } else {
                        errorMessage = result.message
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - ITEM 63: Helper Methods
    
    /// Carrega ofertas do RevenueCat
    private func loadOfferings() async {
        isLoadingOfferings = true
        
        do {
            let offerings = try await subscriptionManager.revenueCatService.fetchOfferings()
            
            await MainActor.run {
                self.availableOfferings = offerings
                isLoadingOfferings = false
                
                // ✅ Selecionar package recomendado automaticamente
                if let recommended = getRecommendedPackage() {
                    selectedPackage = recommended
                }
            }
        } catch {
            await MainActor.run {
                isLoadingOfferings = false
                print("❌ [PAYWALL] Erro ao carregar offerings: \(error)")
            }
        }
    }
    
    /// Obtém package recomendado baseado no contexto
    private func getRecommendedPackage() -> Package? {
        let packages = availablePackages
        
        switch context {
        case .onboarding:
            // Para onboarding, recomendar anual (melhor valor)
            return packages.first { getSubscriptionType(for: $0) == .yearly }
        case .upgrade:
            // Para upgrade, recomendar o próximo nível
            if !subscriptionManager.isPremium {
                return packages.first { getSubscriptionType(for: $0) == .yearly }
            } else {
                return packages.first { package in
                    let type = getSubscriptionType(for: package)
                    return type.isUpgradeFrom(subscriptionManager.subscriptionStatus.type)
                }
            }
        case .seriesLimit, .importLimit:
            // Para limites, recomendar menor plano que resolve
            return packages.first { getSubscriptionType(for: $0) == .monthly }
        }
    }
    
    /// Verifica se package é recomendado
    private func isRecommended(_ package: Package) -> Bool {
        let type = getSubscriptionType(for: package)
        
        switch context {
        case .onboarding, .upgrade:
            return type == .yearly // Anual tem melhor valor
        case .seriesLimit, .importLimit:
            return type == .monthly // Menor comprometimento para resolver limite
        }
    }
    
    /// Calcula desconto do package (se aplicável)
    private func getDiscount(for package: Package) -> String? {
        let type = getSubscriptionType(for: package)
        
        // ✅ Calcular desconto anual vs mensal
        if type == .yearly {
            let monthlyPrice = availablePackages
                .first { getSubscriptionType(for: $0) == .monthly }?
                .storeProduct.price ?? 0
            
            let yearlyPrice = package.storeProduct.price
            let monthlyEquivalent = NSDecimalNumber(decimal: yearlyPrice.decimalValue)
                .dividing(by: NSDecimalNumber(value: 12))
            
            if monthlyPrice > 0 {
                let savings = monthlyPrice.subtracting(monthlyEquivalent)
                let percentage = savings.dividing(by: monthlyPrice)
                    .multiplying(by: NSDecimalNumber(value: 100))
                
                return "Economize \(Int(percentage.doubleValue))%"
            }
        }
        
        // ✅ Verificar se há trial/promo
        if let discount = package.storeProduct.introductoryDiscount {
            switch discount.type {
            case .freeTrial:
                return "Teste grátis"
            case .payAsYouGo:
                return "Desconto por tempo limitado"
            case .payUpFront:
                return "Oferta especial"
            @unknown default:
                return nil
            }
        }
        
        return nil
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
}

// MARK: - Supporting Views

/// Linha de feature individual
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

/// Card de package individual
struct PackageCard: View {
    let package: Package
    let isSelected: Bool
    let isRecommended: Bool
    let discount: String?
    let onTap: () -> Void
    
    init(package: Package, isSelected: Bool, isRecommended: Bool = false, discount: String? = nil, onTap: @escaping () -> Void) {
        self.package = package
        self.isSelected = isSelected
        self.isRecommended = isRecommended
        self.discount = discount
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(package.storeProduct.localizedTitle)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if isRecommended {
                                Text("RECOMENDADO")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                        }
                        
                        if let description = package.storeProduct.localizedDescription, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let discount = discount {
                            Text(discount)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(package.localizedPriceString)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if let period = package.storeProduct.subscriptionPeriod {
                            Text("/ \(period.localizedDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // ✅ Mostrar trial se disponível
                        if let introDiscount = package.storeProduct.introductoryDiscount,
                           introDiscount.type == .freeTrial {
                            Text("Teste grátis: \(introDiscount.subscriptionPeriod.localizedDescription)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // ✅ Indicador de seleção melhorado
                if isSelected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                        Text("Selecionado")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: isSelected ? 4 : 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - PaywallContext

/// Contexto de exibição do paywall
enum PaywallContext {
    case onboarding
    case upgrade
    case seriesLimit
    case importLimit
    
    var title: String {
        switch self {
        case .onboarding:
            return "Desbloqueie Todo o Potencial"
        case .upgrade:
            return "Upgrade para Premium"
        case .seriesLimit:
            return "Mais Séries Disponíveis"
        case .importLimit:
            return "Importação Ilimitada"
        }
    }
    
    var subtitle: String {
        switch self {
        case .onboarding:
            return "Comece sua jornada fitness com recursos premium"
        case .upgrade:
            return "Acesse todos os recursos avançados"
        case .seriesLimit:
            return "Adicione quantas séries quiser aos seus exercícios"
        case .importLimit:
            return "Importe múltiplos treinos de uma vez"
        }
    }
}

// MARK: - Preview

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(context: .upgrade)
            .environmentObject(SubscriptionManager(
                revenueCatService: MockRevenueCatService(),
                cloudSyncManager: MockCloudSyncManager(),
                coreDataService: MockCoreDataService()
            ))
    }
}

// MARK: - Mock Services for Preview

private class MockRevenueCatService: RevenueCatServiceProtocol {
    @Published var isPremium = false
    @Published var offerings: Offerings?
    @Published var customerInfo: CustomerInfo?
    @Published var isLoading = false
    @Published var lastError: Error?
    
    func configure(userId: String) async {}
    func fetchOfferings() async throws {}
    func purchase(_ package: Package) async throws -> Bool { return false }
    func restorePurchases() async throws -> Bool { return false }
    func getCustomerInfo() async throws -> CustomerInfo { throw NSError() }
    func reset() async {}
}

private class MockCloudSyncManager: CloudSyncManagerProtocol {
    func configure(for user: CDAppUser) async {}
    func scheduleUpload(for user: CDAppUser) async {}
    func disconnect() async {}
}

private class MockCoreDataService: CoreDataServiceProtocol {
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) async throws -> T) async throws -> T {
        throw NSError()
    }
} 