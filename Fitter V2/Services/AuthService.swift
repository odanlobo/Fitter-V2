//
//  AuthService.swift
//  Fitter V2
//
//  Refatorado em 18/01/25 - Item 50
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import CoreData
import KeychainAccess

// MARK: - Protocol

/// Protocolo para AuthService seguindo Clean Architecture
/// 
/// **Responsabilidade:** Implementar AuthServiceProtocol APENAS para métodos CRUD (email/senha)
/// **Limitações:** 
/// - Nenhuma chamada cruzada para provedores sociais
/// - Não contém lógica de orquestração ou navegação
/// - Apenas operações básicas de autenticação Firebase
/// - Testabilidade via dependency injection
protocol AuthServiceProtocol {
    // MARK: - Core Authentication (Email/Password only)
    func signIn(email: String, password: String) async throws -> CDAppUser
    func createAccount(name: String, email: String, password: String) async throws -> CDAppUser
    func signOut() async throws
    func resetPassword(email: String) async throws
    
    // MARK: - Session Management
    func restoreSession() async -> CDAppUser?
    var currentUser: CDAppUser? { get }
    var isAuthenticated: Bool { get }
    
    // MARK: - Keychain & Inactivity (moved from AuthUseCase for separation)
    func checkInactivityTimeout() -> Bool
    func logoutDueToInactivity() async throws
    func updateLastAppOpenDate()
}

// MARK: - Errors

/// Erros específicos do AuthService (apenas email/senha)
enum AuthServiceError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case userNotFound
    case wrongPassword
    case networkError
    case sessionExpired
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "O email fornecido é inválido."
        case .weakPassword:
            return "A senha deve ter pelo menos 6 caracteres."
        case .emailAlreadyInUse:
            return "Este email já está em uso."
        case .userNotFound:
            return "Usuário não encontrado."
        case .wrongPassword:
            return "Senha incorreta."
        case .networkError:
            return "Erro de conexão. Verifique sua internet."
        case .sessionExpired:
            return "Sua sessão expirou. Faça login novamente."
        case .unknownError(let error):
            return "Erro inesperado: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidEmail:
            return "Verifique se o email está no formato correto."
        case .weakPassword:
            return "Use uma senha com pelo menos 6 caracteres."
        case .emailAlreadyInUse:
            return "Tente fazer login ou use outro email."
        case .userNotFound:
            return "Verifique seus dados ou crie uma conta."
        case .wrongPassword:
            return "Verifique se digitou a senha corretamente."
        case .networkError:
            return "Verifique sua conexão com a internet."
        default:
            return nil
        }
    }
}

// MARK: - Implementation

/// Implementação do AuthService refatorada para Clean Architecture
/// 
/// **RESPONSABILIDADE RESTRITA:**
/// - Apenas autenticação email/senha via Firebase
/// - Gestão básica de sessão e Core Data
/// - Controle de inatividade (delegado do AuthUseCase)
/// - SEM lógica de orquestração ou navegação
/// - SEM provedores sociais (delegados para AuthUseCase)
@MainActor
final class AuthService: AuthServiceProtocol {
    
    // MARK: - Dependencies
    
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    private let coreDataService: CoreDataServiceProtocol
    
    // MARK: - Keychain & Inactivity Control
    
    private let keychain = Keychain(service: "com.fitter.auth")
    private let inactivityTimeoutDays = 7
    private let lastAppOpenKey = "lastAppOpenDate"
    private let userSessionKey = "userSession"
    
    // MARK: - Initialization
    
    /// Inicializa AuthService com injeção de dependências
    /// - Parameter coreDataService: Serviço Core Data injetado
    init(coreDataService: CoreDataServiceProtocol = CoreDataService()) {
        self.coreDataService = coreDataService
        
        print("🔐 [AuthService] Inicializado com Core Data Service")
    }
    
    /// Singleton para compatibilidade temporária
    /// ⚠️ SERÁ REMOVIDO: Substituído por dependency injection
    static let shared = AuthService()
    
    // MARK: - Session Management Properties
    
    /// Usuário atual mapeado para CDAppUser
    /// ⚠️ CLEAN ARCHITECTURE: Apenas via AuthService, não diretamente do Firebase
    var currentUser: CDAppUser? {
        guard let fbUser = auth.currentUser else { return nil }
        
        let fbUid = fbUser.uid
        
        // 1) Busca usuário existente via CoreDataService
        let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        request.predicate = NSPredicate(format: "providerId == %@", fbUid)
        request.fetchLimit = 1

        do {
            let results = try coreDataService.fetch(request)

            if let existing = results.first {
                // Atualiza dados do último login
            existing.lastLoginDate = Date()
            if let email = fbUser.email {
                existing.email = email
            }
            if let name = fbUser.displayName, !name.isEmpty {
                existing.name = name
            }
            existing.updatedAt = Date()
                
                try coreDataService.save()
            return existing
            }
        } catch {
            print("❌ [AuthService] Erro ao buscar usuário: \(error)")
        }

        // 2) Se não existir, cria novo CDAppUser via CoreDataService
        do {
            let newUser: CDAppUser = coreDataService.create()
        newUser.id = UUID()
        newUser.name = fbUser.displayName ?? ""
            newUser.birthDate = Date()
        newUser.height = 0
        newUser.weight = 0
        newUser.provider = fbUser.providerID
        newUser.providerId = fbUser.uid
        newUser.email = fbUser.email
        newUser.profilePictureURL = fbUser.photoURL
        newUser.locale = nil
        newUser.gender = nil
        newUser.createdAt = Date()
        newUser.updatedAt = Date()
        newUser.lastLoginDate = Date()
            newUser.cloudSyncStatus = CloudSyncStatus.synced.rawValue
            
            // Configuração inicial de assinatura
            newUser.subscriptionType = SubscriptionType.none.rawValue

            try coreDataService.save()
            print("✅ [AuthService] Novo usuário criado: \(newUser.safeName)")
            
        return newUser
        } catch {
            print("❌ [AuthService] Erro ao criar usuário: \(error)")
            return nil
        }
    }
    
    /// Indica se o usuário está autenticado
    var isAuthenticated: Bool {
        return currentUser != nil
    }
    
    // MARK: - Core Authentication (Email/Password only)
    
    /// Realiza login com email e senha via Firebase
    /// - Parameters:
    ///   - email: Email do usuário
    ///   - password: Senha do usuário
    /// - Returns: CDAppUser autenticado
    /// - Throws: AuthServiceError em caso de falha
    func signIn(email: String, password: String) async throws -> CDAppUser {
        print("🔐 [AuthService] Iniciando login com email: \(email)")
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("✅ [AuthService] Login Firebase realizado: \(result.user.uid)")
            
            // Salva/atualiza dados do usuário no Firestore
            try await saveUserToFirestore(result.user)
            
            // Busca/cria usuário no Core Data
            guard let user = currentUser else {
                throw AuthServiceError.userNotFound
            }
            
            // Salva sessão no Keychain para restauração
            saveUserSession(user)
            
            print("✅ [AuthService] Login completo: \(user.safeName)")
            return user
            
        } catch {
            print("❌ [AuthService] Erro no login: \(error)")
            throw mapFirebaseError(error)
        }
    }
    
    /// Cria nova conta com email e senha
    /// - Parameters:
    ///   - name: Nome do usuário
    ///   - email: Email do usuário
    ///   - password: Senha do usuário
    /// - Returns: CDAppUser criado
    /// - Throws: AuthServiceError em caso de falha
    func createAccount(name: String, email: String, password: String) async throws -> CDAppUser {
        print("📝 [AuthService] Criando conta para: \(email)")
        
        // Validações básicas
        guard email.contains("@") && email.contains(".") else {
            throw AuthServiceError.invalidEmail
        }
        
        guard password.count >= 6 else {
            throw AuthServiceError.weakPassword
        }
        
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            print("✅ [AuthService] Conta Firebase criada: \(result.user.uid)")
            
            // Atualiza perfil com nome
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
            
            // Salva dados no Firestore
            try await saveUserToFirestore(result.user, name: name)
            
            // Busca/cria usuário no Core Data
            guard let user = currentUser else {
                throw AuthServiceError.unknownError(NSError(domain: "AuthService", code: -1))
            }
            
            // Salva sessão no Keychain
            saveUserSession(user)
            
            print("✅ [AuthService] Conta criada com sucesso: \(user.safeName)")
            return user
            
        } catch {
            print("❌ [AuthService] Erro ao criar conta: \(error)")
            throw mapFirebaseError(error)
        }
    }
    
    /// Realiza logout do usuário
    func signOut() async throws {
        print("🚪 [AuthService] Realizando logout")
        
        do {
            try auth.signOut()
            
            // Remove sessão do Keychain
            clearUserSession()
            
            print("✅ [AuthService] Logout realizado com sucesso")
            
        } catch {
            print("❌ [AuthService] Erro no logout: \(error)")
            throw AuthServiceError.unknownError(error)
        }
    }
    
    /// Envia email de reset de senha
    /// - Parameter email: Email para envio do reset
    func resetPassword(email: String) async throws {
        print("📧 [AuthService] Enviando reset de senha para: \(email)")
        
        guard email.contains("@") && email.contains(".") else {
            throw AuthServiceError.invalidEmail
        }
        
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("✅ [AuthService] Email de reset enviado com sucesso")
            
        } catch {
            print("❌ [AuthService] Erro ao enviar reset: \(error)")
            throw mapFirebaseError(error)
        }
    }
    
    // MARK: - Session Management
    
    /// Restaura sessão do usuário salva no Keychain
    /// - Returns: CDAppUser se sessão válida, nil caso contrário
    func restoreSession() async -> CDAppUser? {
        print("🔄 [AuthService] Restaurando sessão...")
        
        // Verifica inatividade primeiro
        if checkInactivityTimeout() {
            print("⚠️ [AuthService] Sessão expirada por inatividade")
            try? await logoutDueToInactivity()
            return nil
        }
        
        // Verifica se há usuário no Firebase Auth
        guard auth.currentUser != nil else {
            print("❌ [AuthService] Nenhuma sessão Firebase ativa")
            clearUserSession()
            return nil
        }
        
        // Busca dados do usuário no Core Data
        let user = currentUser
        
        if let user = user {
            print("✅ [AuthService] Sessão restaurada: \(user.safeName)")
            updateLastAppOpenDate()
        } else {
            print("❌ [AuthService] Usuário não encontrado no Core Data")
            clearUserSession()
        }
        
        return user
    }
    
    // MARK: - Inactivity Control
    
    /// Verifica se passou do limite de inatividade (7 dias)
    func checkInactivityTimeout() -> Bool {
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
            print("⚠️ [AuthService] Inatividade detectada: \(daysSinceLastOpen) dias")
        }
        
        return isInactive
    }
    
    /// Executa logout devido à inatividade
    func logoutDueToInactivity() async throws {
        print("🔒 [AuthService] Logout automático por inatividade (\(inactivityTimeoutDays)+ dias)")
        
        // Logout normal
        try await signOut()
        
        // Remove timestamp de última abertura
        keychain[lastAppOpenKey] = nil
        
        throw AuthServiceError.sessionExpired
    }
    
    /// Atualiza timestamp da última abertura do app
    func updateLastAppOpenDate() {
        let now = Date()
        keychain[lastAppOpenKey] = String(now.timeIntervalSince1970)
        print("🕐 [AuthService] Última abertura atualizada: \(now)")
    }
    
    // MARK: - Private Methods
    
    /// Salva dados do usuário no Firestore
    private func saveUserToFirestore(_ fbUser: User, name: String? = nil) async throws {
                        let userData: [String: Any] = [
            "name": name ?? fbUser.displayName ?? "",
            "email": fbUser.email ?? "",
            "photoURL": fbUser.photoURL?.absoluteString ?? "",
            "provider": fbUser.providerID,
            "updatedAt": Timestamp(),
            "lastLoginDate": Timestamp()
                        ]
                        
        try await firestore
                            .collection("users")
            .document(fbUser.uid)
                            .setData(userData, merge: true)
                        
        print("💾 [AuthService] Dados salvos no Firestore: \(fbUser.uid)")
    }
    
    /// Salva sessão do usuário no Keychain
    private func saveUserSession(_ user: CDAppUser) {
        let sessionData: [String: Any] = [
            "userId": user.safeId.uuidString,
            "email": user.safeEmail,
            "lastLogin": Date().timeIntervalSince1970
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: sessionData),
           let sessionString = String(data: data, encoding: .utf8) {
            keychain[userSessionKey] = sessionString
            print("💾 [AuthService] Sessão salva no Keychain")
        }
    }
    
    /// Remove sessão do usuário do Keychain
    private func clearUserSession() {
        keychain[userSessionKey] = nil
        print("🗑️ [AuthService] Sessão removida do Keychain")
    }
    
    /// Mapeia erros do Firebase para AuthServiceError
    private func mapFirebaseError(_ error: Error) -> AuthServiceError {
        let authError = error as NSError
        
        switch authError.code {
        case AuthErrorCode.invalidEmail.rawValue:
            return .invalidEmail
        case AuthErrorCode.weakPassword.rawValue:
            return .weakPassword
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return .emailAlreadyInUse
        case AuthErrorCode.userNotFound.rawValue:
            return .userNotFound
        case AuthErrorCode.wrongPassword.rawValue:
            return .wrongPassword
        case AuthErrorCode.networkError.rawValue:
            return .networkError
        default:
            return .unknownError(error)
        }
        }
    }
    
// MARK: - Mock Implementation

#if DEBUG
/// Mock AuthService para previews e testes
final class MockAuthService: AuthServiceProtocol {
    
    private(set) var currentUser: CDAppUser?
    
    var isAuthenticated: Bool {
        return currentUser != nil
    }
    
    func signIn(email: String, password: String) async throws -> CDAppUser {
        // TODO: Implementar mock com PersistenceController quando disponível
        // Por enquanto, cria usuário temporário
        let user = CDAppUser()
        user.id = UUID()
        user.name = "Usuario Mock"
        user.email = email
        user.createdAt = Date()
        user.lastLoginDate = Date()
        user.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        user.subscriptionType = SubscriptionType.none.rawValue
        
        currentUser = user
        return user
    }
    
    func createAccount(name: String, email: String, password: String) async throws -> CDAppUser {
        // TODO: Implementar mock com PersistenceController quando disponível
        // Por enquanto, cria usuário temporário
        let user = CDAppUser()
        user.id = UUID()
        user.name = name
        user.email = email
        user.createdAt = Date()
        user.lastLoginDate = Date()
        user.cloudSyncStatus = CloudSyncStatus.synced.rawValue
        user.subscriptionType = SubscriptionType.none.rawValue
        
        currentUser = user
        return user
    }
    
    func signOut() async throws {
        currentUser = nil
    }
    
    func resetPassword(email: String) async throws {
        // Mock implementation
    }
    
    func restoreSession() async -> CDAppUser? {
        return currentUser
    }
    
    func checkInactivityTimeout() -> Bool {
        return false
    }
    
    func logoutDueToInactivity() async throws {
        currentUser = nil
    }
    
    func updateLastAppOpenDate() {
        // Mock implementation
        }
    }
#endif 
