//
//  AuthUseCase.swift
//  Fitter V2
//
//  Created by Daniel Lobo on 18/01/25.
//

import Foundation
import CoreData
import LocalAuthentication
import Security
import KeychainAccess

// MARK: - Protocols

/// Protocolo para AuthUseCase seguindo Clean Architecture
/// 
/// **Responsabilidade:** Orquestrar todos fluxos de autenticação
/// - Apple, Google, Facebook, Email, Biometria
/// - Login automático com biometria
/// - Histórico de provedores utilizados
/// - Logout por inatividade (7 dias)
/// - Integração com SubscriptionManager
protocol AuthUseCaseProtocol {
    // MARK: - Authentication
    func signIn(with credentials: AuthCredentials) async throws -> AuthResult
    func signUp(with registration: AuthRegistration) async throws -> AuthResult
    func signOut() async throws
    func resetPassword(email: String) async throws
    
    // MARK: - Biometric Authentication
    func isBiometricAvailable() async -> BiometricAvailability
    func enableBiometric(for user: CDAppUser) async throws
    func disableBiometric(for user: CDAppUser) async throws
    func authenticateWithBiometric() async throws -> CDAppUser?
    
    // MARK: - Session Management
    func restoreSession() async -> CDAppUser?
    func checkInactivityTimeout() -> Bool
    func logoutDueToInactivity() async throws
    func updateLastAppOpenDate()
    
    // MARK: - Provider History
    func getProviderHistory(for user: CDAppUser) -> [AuthProvider]
    func recordProviderUsage(_ provider: AuthProvider, for user: CDAppUser)
    
    // MARK: - Premium Integration
    func checkSubscriptionStatus(for user: CDAppUser) async -> SubscriptionStatus
}

// MARK: - Input/Output Models

/// Credenciais de autenticação unificadas
struct AuthCredentials {
    let provider: AuthProvider
    let email: String?
    let password: String?
    let token: String?
    let biometricData: Data?
    
    // Convenience initializers
    static func email(_ email: String, password: String) -> AuthCredentials {
        return AuthCredentials(provider: .email, email: email, password: password, token: nil, biometricData: nil)
    }
    
    static func google(token: String) -> AuthCredentials {
        return AuthCredentials(provider: .google, email: nil, password: nil, token: token, biometricData: nil)
    }
    
    static func apple(token: String) -> AuthCredentials {
        return AuthCredentials(provider: .apple, email: nil, password: nil, token: token, biometricData: nil)
    }
    
    static func facebook(token: String) -> AuthCredentials {
        return AuthCredentials(provider: .facebook, email: nil, password: nil, token: token, biometricData: nil)
    }
    
    static func biometric(data: Data) -> AuthCredentials {
        return AuthCredentials(provider: .biometric, email: nil, password: nil, token: nil, biometricData: data)
    }
}

/// Dados de registro de usuário
struct AuthRegistration {
    let name: String
    let email: String
    let password: String
    let provider: AuthProvider
    let agreeToTerms: Bool
    let allowMarketing: Bool
}

/// Resultado de autenticação
struct AuthResult {
    let user: CDAppUser
    let isFirstLogin: Bool
    let provider: AuthProvider
    let biometricEnabled: Bool
    let subscriptionStatus: SubscriptionStatus
}

/// Provedores de autenticação suportados
enum AuthProvider: String, CaseIterable {
    case email = "email"
    case google = "google"
    case apple = "apple"
    case facebook = "facebook"
    case biometric = "biometric"
    
    var displayName: String {
        switch self {
        case .email: return "Email"
        case .google: return "Google"
        case .apple: return "Apple"
        case .facebook: return "Facebook"
        case .biometric: return "Face ID / Touch ID"
        }
    }
    
    var icon: String {
        switch self {
        case .email: return "envelope.fill"
        case .google: return "Icon Google"
        case .apple: return "Icon Apple"
        case .facebook: return "Icon FB"
        case .biometric: return "faceid"
        }
    }
}

/// Disponibilidade de autenticação biométrica
enum BiometricAvailability {
    case available(type: LABiometryType)
    case unavailable(reason: String)
    case notEnrolled
    case denied
    
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
    
    var displayName: String {
        switch self {
        case .available(let type):
            return type == .faceID ? "Face ID" : "Touch ID"
        case .unavailable(let reason):
            return "Indisponível: \(reason)"
        case .notEnrolled:
            return "Não configurado"
        case .denied:
            return "Negado"
        }
    }
}

/// Status de assinatura do usuário
/// ✅ Definição centralizada em SubscriptionType.swift - remover duplicação

// MARK: - Errors

/// Erros específicos do AuthUseCase
enum AuthUseCaseError: LocalizedError {
    case invalidCredentials
    case userNotFound
    case emailAlreadyExists
    case weakPassword
    case networkError
    case biometricNotAvailable
    case biometricAuthenticationFailed
    case sessionExpired
    case inactivityTimeout
    case providerError(String)
    case subscriptionRequired
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Credenciais inválidas. Verifique seu email e senha."
        case .userNotFound:
            return "Usuário não encontrado. Verifique seus dados ou crie uma conta."
        case .emailAlreadyExists:
            return "Este email já está em uso. Tente fazer login ou use outro email."
        case .weakPassword:
            return "A senha deve ter pelo menos 6 caracteres."
        case .networkError:
            return "Erro de conexão. Verifique sua internet e tente novamente."
        case .biometricNotAvailable:
            return "Autenticação biométrica não está disponível neste dispositivo."
        case .biometricAuthenticationFailed:
            return "Falha na autenticação biométrica. Tente novamente."
        case .sessionExpired:
            return "Sua sessão expirou. Faça login novamente."
        case .inactivityTimeout:
            return "Por segurança, você foi deslogado após 7 dias de inatividade."
        case .providerError(let message):
            return "Erro no provedor de autenticação: \(message)"
        case .subscriptionRequired:
            return "Esta funcionalidade requer uma assinatura premium."
        case .unknownError(let error):
            return "Erro inesperado: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Verifique se digitou corretamente seu email e senha."
        case .networkError:
            return "Verifique sua conexão com a internet."
        case .biometricAuthenticationFailed:
            return "Use sua senha como alternativa."
        case .inactivityTimeout:
            return "Faça login novamente para continuar usando o app."
        default:
            return nil
        }
    }
}

// MARK: - Implementation

/// Implementação do AuthUseCase seguindo Clean Architecture
/// 
/// **Arquitetura:**
/// - Injeção de dependências via protocolos
/// - Único ponto de decisão para login/cadastro/logout
/// - Orquestração de múltiplos provedores
/// - Integração com SubscriptionManager
/// - Controle de inatividade e segurança
@MainActor
final class AuthUseCase: AuthUseCaseProtocol {
    
    // MARK: - Dependencies
    
    private let authService: AuthServiceProtocol
    private let appleSignInService: AppleSignInServiceProtocol?
    private let googleSignInService: GoogleSignInServiceProtocol?
    private let facebookSignInService: FacebookSignInServiceProtocol?
    private let biometricAuthService: BiometricAuthServiceProtocol?
    private let subscriptionManager: SubscriptionManagerProtocol?
    
    // MARK: - Internal State
    
    private nonisolated let keychain = Keychain(service: "com.fitter.auth")
    private let inactivityTimeoutDays = 7
    private let lastAppOpenKey = "lastAppOpenDate"
    private let providerHistoryKey = "providerHistory"
    private let biometricEnabledKey = "biometricEnabled"
    
    // MARK: - Initialization
    
    /// Inicializa AuthUseCase com injeção de dependências
    /// - Parameters:
    ///   - authService: Serviço base de autenticação (obrigatório)
    ///   - appleSignInService: Serviço Apple Sign In (opcional)
    ///   - googleSignInService: Serviço Google Sign In (opcional)
    ///   - facebookSignInService: Serviço Facebook Login (opcional)
    ///   - biometricAuthService: Serviço de autenticação biométrica (opcional)
    ///   - subscriptionManager: Gerenciador de assinaturas (opcional)
    init(
        authService: AuthServiceProtocol,
        appleSignInService: AppleSignInServiceProtocol? = nil,
        googleSignInService: GoogleSignInServiceProtocol? = nil,
        facebookSignInService: FacebookSignInServiceProtocol? = nil,
        biometricAuthService: BiometricAuthServiceProtocol? = nil,
        subscriptionManager: SubscriptionManagerProtocol? = nil
    ) {
        self.authService = authService
        self.appleSignInService = appleSignInService
        self.googleSignInService = googleSignInService
        self.facebookSignInService = facebookSignInService
        self.biometricAuthService = biometricAuthService
        self.subscriptionManager = subscriptionManager
        
        print("🔐 AuthUseCase inicializado com provedores:")
        print("   📧 Email: ✅")
        print("   🍎 Apple: \(appleSignInService != nil ? "✅" : "❌")")
        print("   🔍 Google: \(googleSignInService != nil ? "✅" : "❌")")
        print("   📘 Facebook: \(facebookSignInService != nil ? "✅" : "❌")")
        print("   🔒 Biométrica: \(biometricAuthService != nil ? "✅" : "❌")")
        print("   💳 Assinatura: \(subscriptionManager != nil ? "✅" : "❌")")
    }
    
    // MARK: - Authentication
    
    /// Realiza login com credenciais unificadas
    func signIn(with credentials: AuthCredentials) async throws -> AuthResult {
        print("🔐 [AUTH] Iniciando login com \(credentials.provider.displayName)")
        
        var user: CDAppUser
        
        // Delega para o provedor apropriado
        switch credentials.provider {
        case .email:
            guard let email = credentials.email, let password = credentials.password else {
                throw AuthUseCaseError.invalidCredentials
            }
            user = try await authService.signIn(email: email, password: password)
            
        case .google:
            guard let service = googleSignInService else {
                throw AuthUseCaseError.providerError("Google Sign In não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .google)
            
        case .apple:
            guard let service = appleSignInService else {
                throw AuthUseCaseError.providerError("Apple Sign In não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .apple)
            
        case .facebook:
            guard let service = facebookSignInService else {
                throw AuthUseCaseError.providerError("Facebook Login não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .facebook)
            
        case .biometric:
            guard let authenticatedUser = try await authenticateWithBiometric() else {
                throw AuthUseCaseError.biometricAuthenticationFailed
            }
            user = authenticatedUser
        }
        
        // Atualiza dados de sessão
        updateLastAppOpenDate()
        recordProviderUsage(credentials.provider, for: user)
        
        // ✅ Inicializa RevenueCat com usuário autenticado
        if let manager = subscriptionManager {
            await manager.refreshSubscriptionStatus()
            let userName: String = user.name ?? "Usuário"
            print("💳 [AUTH] RevenueCat inicializado para \(userName)")
        }
        
        // Verifica status de assinatura
        let subscriptionStatus = await checkSubscriptionStatus(for: user)
        
        // Verifica se é primeiro login
        let isFirstLogin = user.lastLoginDate == nil || 
                          Calendar.current.isDate(user.lastLoginDate!, inSameDayAs: user.createdAt ?? Date())
        
        // Verifica se biometria está habilitada
        let biometricEnabled = isBiometricEnabled(for: user)
        
        let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Login realizado com sucesso: \(userName)")
        
        return AuthResult(
            user: user,
            isFirstLogin: isFirstLogin,
            provider: credentials.provider,
            biometricEnabled: biometricEnabled,
            subscriptionStatus: subscriptionStatus
        )
    }
    
    /// Realiza cadastro de novo usuário
    func signUp(with registration: AuthRegistration) async throws -> AuthResult {
        print("📝 [AUTH] Iniciando cadastro com \(registration.provider.displayName)")
        
        // Validações
        guard registration.agreeToTerms else {
            throw AuthUseCaseError.providerError("É necessário aceitar os termos de uso")
        }
        
        guard registration.password.count >= 6 else {
            throw AuthUseCaseError.weakPassword
        }
        
        // Cria usuário via provedor apropriado
        let user: CDAppUser
        
        switch registration.provider {
        case .email:
            user = try await authService.createAccount(
                name: registration.name,
                email: registration.email,
                password: registration.password
            )
            
        case .google:
            guard let service = googleSignInService else {
                throw AuthUseCaseError.providerError("Google Sign In não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .google, name: registration.name, email: registration.email)
            
        case .apple:
            guard let service = appleSignInService else {
                throw AuthUseCaseError.providerError("Apple Sign In não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .apple, name: registration.name, email: registration.email)
            
        case .facebook:
            guard let service = facebookSignInService else {
                throw AuthUseCaseError.providerError("Facebook Login não disponível")
            }
            let authCredentials = try await service.signIn()
            user = try await convertAuthCredentials(authCredentials, provider: .facebook, name: registration.name, email: registration.email)
            
        case .biometric:
            throw AuthUseCaseError.providerError("Cadastro via biometria não suportado")
        }
        
        // Configura dados iniciais
        updateLastAppOpenDate()
        recordProviderUsage(registration.provider, for: user)
        
        // ✅ Inicializa RevenueCat com novo usuário
        if let manager = subscriptionManager {
            await manager.refreshSubscriptionStatus()
            let userName: String = user.name ?? "Usuário"
            print("💳 [AUTH] RevenueCat inicializado para novo usuário: \(userName)")
        }
        
        // Status inicial de assinatura
        let subscriptionStatus = await checkSubscriptionStatus(for: user)
        
        let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Cadastro realizado com sucesso: \(userName)")
        
        return AuthResult(
            user: user,
            isFirstLogin: true,
            provider: registration.provider,
            biometricEnabled: false,
            subscriptionStatus: subscriptionStatus
        )
    }
    
    /// Realiza logout do usuário
    func signOut() async throws {
        print("🚪 [AUTH] Realizando logout")
        
        // ✅ Limpa dados de assinatura ANTES do logout
        if let manager = subscriptionManager {
            await manager.clearSubscriptionData()
            print("🧹 [AUTH] Dados de assinatura limpos")
        }
        
        // Logout dos provedores
        try await authService.signOut()
        
        // Limpa dados sensíveis do Keychain
        clearBiometricData()
        
        print("✅ [AUTH] Logout realizado com sucesso")
    }
    
    /// Envia email de reset de senha
    func resetPassword(email: String) async throws {
        print("📧 [AUTH] Enviando reset de senha para: \(email)")
        
        try await authService.resetPassword(email: email)
        
        print("✅ [AUTH] Email de reset enviado com sucesso")
    }
    
    // MARK: - Biometric Authentication
    
    /// Verifica disponibilidade de autenticação biométrica
    func isBiometricAvailable() async -> BiometricAvailability {
        guard let service = biometricAuthService else {
            return .unavailable(reason: "Serviço biométrico não disponível")
        }
        
        return await service.checkBiometricAvailability()
    }
    
    /// Habilita autenticação biométrica para usuário
    func enableBiometric(for user: CDAppUser) async throws {
        guard let service = biometricAuthService else {
            throw AuthUseCaseError.biometricNotAvailable
        }
        
        let availability = await service.checkBiometricAvailability()
        guard availability.isAvailable else {
            throw AuthUseCaseError.biometricNotAvailable
        }
        
        // Autentica primeiro para confirmar
        let authCredentials = try await service.signIn()
        
        // Salva dados biométricos seguros
        try await service.enableBiometric(for: user)
        keychain["\(biometricEnabledKey)_\(user.safeId)"] = "true"
        
        let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Biometria habilitada para \(userName)")
    }
    
    /// Desabilita autenticação biométrica para usuário
    func disableBiometric(for user: CDAppUser) async throws {
        guard let service = biometricAuthService else { return }
        
        // Remove dados biométricos
        try await service.disableBiometric(for: user)
        keychain["\(biometricEnabledKey)_\(user.safeId)"] = nil
        
        let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Biometria desabilitada para \(userName)")
    }
    
    /// Autentica com biometria
    func authenticateWithBiometric() async throws -> CDAppUser? {
        guard let service = biometricAuthService else {
            throw AuthUseCaseError.biometricNotAvailable
        }
        
        let availability = await service.checkBiometricAvailability()
        guard availability.isAvailable else {
            throw AuthUseCaseError.biometricNotAvailable
        }
        
        // Autentica
        let authCredentials = try await service.signIn()
        
        // Recupera usuário dos dados biométricos
        let user = try await getBiometricUser(from: authCredentials)
        
        if let user = user {
            let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Login biométrico realizado: \(userName)")
            updateLastAppOpenDate()
            recordProviderUsage(.biometric, for: user)
        }
        
        return user
    }
    
    // MARK: - Session Management
    
    /// Restaura sessão do usuário
    func restoreSession() async -> CDAppUser? {
        print("🔄 [AUTH] Restaurando sessão...")
        
        // Verifica timeout de inatividade primeiro
        if checkInactivityTimeout() {
            print("⚠️ [AUTH] Sessão expirada por inatividade")
            try? await logoutDueToInactivity()
            return nil
        }
        
        // Tenta restaurar via AuthService
        let user = await authService.restoreSession()
        
        if let user = user {
            let userName: String = user.name ?? "Usuário"
        print("✅ [AUTH] Sessão restaurada: \(userName)")
            updateLastAppOpenDate()
            
            // ✅ Inicializa RevenueCat com usuário restaurado
            if let manager = subscriptionManager {
                await manager.refreshSubscriptionStatus()
                let userName: String = user.name ?? "Usuário"
            print("💳 [AUTH] RevenueCat inicializado para sessão restaurada: \(userName)")
            }
        } else {
            print("❌ [AUTH] Nenhuma sessão válida encontrada")
        }
        
        return user
    }
    
    /// Verifica se passou do limite de inatividade (7 dias)
    nonisolated func checkInactivityTimeout() -> Bool {
        guard let lastOpenString = keychain[lastAppOpenKey],
              let lastOpenTimestamp = Double(lastOpenString) else {
            // Primeira vez - atualiza timestamp
            updateLastAppOpenDate()
            return false
        }
        
        let lastOpenDate = Date(timeIntervalSince1970: lastOpenTimestamp)
        let daysSinceLastOpen = Calendar.current.dateComponents([.day], 
                                                               from: lastOpenDate, 
                                                               to: Date()).day ?? 0
        
        let isInactive = daysSinceLastOpen >= inactivityTimeoutDays
        
        if isInactive {
            print("⚠️ [AUTH] Inatividade detectada: \(daysSinceLastOpen) dias")
        }
        
        return isInactive
    }
    
    /// Executa logout devido à inatividade
    func logoutDueToInactivity() async throws {
        print("🔒 [AUTH] Logout automático por inatividade (\(inactivityTimeoutDays)+ dias)")
        
        // ✅ Limpa dados de assinatura ANTES do logout
        if let manager = subscriptionManager {
            await manager.clearSubscriptionData()
            print("🧹 [AUTH] Dados de assinatura limpos por inatividade")
        }
        
        // Logout normal
        try await signOut()
        
        // Remove timestamp de última abertura
        keychain[lastAppOpenKey] = nil
        
        throw AuthUseCaseError.inactivityTimeout
    }
    
    /// Atualiza timestamp da última abertura do app
    nonisolated func updateLastAppOpenDate() {
        let now = Date()
        keychain[lastAppOpenKey] = String(now.timeIntervalSince1970)
        print("🕐 [AUTH] Última abertura atualizada: \(now)")
    }
    
    // MARK: - Provider History
    
    /// Obtém histórico de provedores utilizados
    nonisolated func getProviderHistory(for user: CDAppUser) -> [AuthProvider] {
        let key = "\(providerHistoryKey)_\(user.safeId)"
        
        guard let historyString = keychain[key],
              let historyData = historyString.data(using: .utf8),
              let providers = try? JSONDecoder().decode([String].self, from: historyData) else {
            return []
        }
        
        return providers.compactMap { AuthProvider(rawValue: $0) }
    }
    
    /// Registra uso de provedor
    nonisolated func recordProviderUsage(_ provider: AuthProvider, for user: CDAppUser) {
        let key = "\(providerHistoryKey)_\(user.safeId)"
        
        var history = getProviderHistory(for: user)
        
        // Remove provider se já existir e adiciona no início
        history.removeAll { $0 == provider }
        history.insert(provider, at: 0)
        
        // Manter apenas os últimos 5 provedores
        if history.count > 5 {
            history = Array(history.prefix(5))
        }
        
        // Salva no Keychain
        let providerStrings = history.map { $0.rawValue }
        if let historyData = try? JSONEncoder().encode(providerStrings),
           let historyString = String(data: historyData, encoding: .utf8) {
            keychain[key] = historyString
        }
        
        print("📝 [AUTH] Provedor registrado: \(provider.displayName)")
    }
    
    // MARK: - Premium Integration
    
    /// Verifica status de assinatura
    func checkSubscriptionStatus(for user: CDAppUser) async -> SubscriptionStatus {
        guard let manager = subscriptionManager else {
            return .none
        }
        
        return await manager.getSubscriptionStatus(for: user)
    }
    
    // MARK: - Private Methods
    
    /// Verifica se biometria está habilitada para usuário
    private func isBiometricEnabled(for user: CDAppUser) -> Bool {
        let key = "\(biometricEnabledKey)_\(user.safeId)"
        return keychain[key] == "true"
    }
    
    /// Limpa dados biométricos sensíveis
    private func clearBiometricData() {
        // Remove chaves relacionadas a biometria
        let allKeys = keychain.allKeys()
        
        for key in allKeys {
            if key.contains(biometricEnabledKey) {
                keychain[key] = nil
            }
        }
        
        print("🗑️ [AUTH] Dados biométricos limpos")
    }
    
    /// Converte AuthCredentials para CDAppUser (bridge method)
    private func convertAuthCredentials(_ credentials: AuthCredentials, provider: AuthProvider, name: String? = nil, email: String? = nil) async throws -> CDAppUser {
        // Verifica se já existe um usuário com essas credenciais
        let existingUser = try await findExistingUser(for: credentials, provider: provider)
        
        if let user = existingUser {
            // Atualiza dados de login
            user.lastLoginDate = Date()
            user.provider = provider.rawValue
            return user
        }
        
        // Cria novo usuário se não existir
        return try await createNewUser(from: credentials, provider: provider, name: name, email: email)
    }
    
    /// Busca usuário existente com base nas credenciais
    private func findExistingUser(for credentials: AuthCredentials, provider: AuthProvider) async throws -> CDAppUser? {
        // Busca usuário existente no Core Data baseado no provider e token/email
        switch provider {
        case .google, .apple, .facebook:
            guard let email = credentials.email else { return nil }
            return try await findUserByEmail(email)
        case .email:
            guard let email = credentials.email else { return nil }
            return try await findUserByEmail(email)
        default:
            return nil
        }
    }
    
    /// Cria novo usuário com base nas credenciais
    private func createNewUser(from credentials: AuthCredentials, provider: AuthProvider, name: String?, email: String?) async throws -> CDAppUser {
        // Delega para AuthService criar usuário
        let userName = name ?? "Usuário \(provider.displayName)"
        let userEmail = email ?? "\(UUID().uuidString)@\(provider.rawValue).com"
        
        let user = try await authService.createAccount(
            name: userName,
            email: userEmail,
            password: "" // Sem senha para provedores externos
        )
        
        // Define o provider após criar o usuário
        user.provider = provider.rawValue
        
        return user
    }
    
    /// Recupera usuário dos dados biométricos
    private func getBiometricUser(from credentials: AuthCredentials) async throws -> CDAppUser? {
        guard let biometricData = credentials.biometricData else {
            throw AuthUseCaseError.biometricAuthenticationFailed
        }
        
        // Busca usuário salvo para autenticação biométrica no Keychain
        if let userIdString = keychain["biometric_user_id"],
           let userId = UUID(uuidString: userIdString) {
            return try await findUserById(userId)
        }
        
        return nil
    }
    
    // MARK: - Core Data Helpers
    
    /// Busca usuário por email no Core Data
    private func findUserByEmail(_ email: String) async throws -> CDAppUser? {
        let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        request.predicate = NSPredicate(format: "email == %@", email)
        request.fetchLimit = 1
        
        let users = try CoreDataService().fetch(request)
        return users.first
    }
    
    /// Busca usuário por ID no Core Data
    private func findUserById(_ userId: UUID) async throws -> CDAppUser? {
        let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", userId as CVarArg)
        request.fetchLimit = 1
        
        let users = try CoreDataService().fetch(request)
        return users.first
    }
}

// MARK: - Convenience Methods

extension AuthUseCase {
    
    /// Login rápido com email/senha
    func signInWithEmail(_ email: String, password: String) async throws -> AuthResult {
        return try await signIn(with: .email(email, password: password))
    }
    
    /// Login com Google
    func signInWithGoogle(token: String) async throws -> AuthResult {
        return try await signIn(with: .google(token: token))
    }
    
    /// Login com Apple
    func signInWithApple(token: String) async throws -> AuthResult {
        return try await signIn(with: .apple(token: token))
    }
    
    /// Login com Facebook  
    func signInWithFacebook(token: String) async throws -> AuthResult {
        return try await signIn(with: .facebook(token: token))
    }
    
    /// Login com biometria
    func signInWithBiometric() async throws -> AuthResult {
        let user = try await authenticateWithBiometric()
        
        guard let user = user else {
            throw AuthUseCaseError.biometricAuthenticationFailed
        }
        
        let subscriptionStatus = await checkSubscriptionStatus(for: user)
        
        return AuthResult(
            user: user,
            isFirstLogin: false,
            provider: .biometric,
            biometricEnabled: true,
            subscriptionStatus: subscriptionStatus
        )
    }
    
    /// Cadastro rápido com email/senha
    func signUpWithEmail(name: String, email: String, password: String) async throws -> AuthResult {
        let registration = AuthRegistration(
            name: name,
            email: email,
            password: password,
            provider: .email,
            agreeToTerms: true,
            allowMarketing: false
        )
        
        return try await signUp(with: registration)
    }
}
