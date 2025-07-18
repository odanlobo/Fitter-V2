import Foundation
import GoogleSignIn
import Security
import KeychainAccess

/// Implementação do Google Sign In Service
/// 
/// **Responsabilidade:** Autenticação com Google usando GoogleSignIn SDK
/// - Login/logout com Google Account
/// - Validação de sessão
/// - Persistência de credenciais no Keychain
/// - Tratamento de erros específicos
final class GoogleSignInService: NSObject, GoogleSignInServiceProtocol {
    
    // MARK: - Properties
    
    private let keychain: Keychain
    private var currentCredential: AuthCredentials?
    private var isInitialized: Bool = false
    
    // MARK: - Initialization
    
    override init() {
        self.keychain = Keychain(service: "com.fitter.google-signin")
        super.init()
    }
    
    // MARK: - GoogleSignInServiceProtocol
    
    var isAuthenticated: Bool {
        return GIDSignIn.sharedInstance.currentUser != nil
    }
    
    var isAvailable: Bool {
        return GIDSignIn.sharedInstance.hasPreviousSignIn()
    }
    
    func signIn() async throws -> AuthCredentials {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw GoogleSignInError.notAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: window) { result, error in
                if let error = error {
                    continuation.resume(throwing: GoogleSignInError.failed(error))
                    return
                }
                
                guard let user = result?.user else {
                    continuation.resume(throwing: GoogleSignInError.invalidCredentials)
                    return
                }
                
                let credential = AuthCredentials.google(token: user.userID)
                
                // Salvar credenciais
                Task {
                    do {
                        try await self.storeCredentials(credential)
                        continuation.resume(returning: credential)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func signOut() async throws {
        do {
            GIDSignIn.sharedInstance.signOut()
            try await clearStoredCredentials()
            currentCredential = nil
            
            print("🔍 [GOOGLE SIGN IN] Logout realizado")
        } catch {
            print("❌ [GOOGLE SIGN IN] Erro no logout: \(error)")
            throw GoogleSignInError.failed(error)
        }
    }
    
    func validateSession() async throws -> Bool {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            return false
        }
        
        do {
            // Verificar se o token ainda é válido
            let isValid = try await user.refreshTokensIfNeeded()
            return isValid
        } catch {
            print("❌ [GOOGLE SIGN IN] Erro na validação: \(error)")
            return false
        }
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            return nil
        }
        
        let credential = AuthCredentials.google(token: user.userID)
        currentCredential = credential
        
        print("🔍 [GOOGLE SIGN IN] Credenciais restauradas")
        return credential
    }
    
    func configure(clientID: String) async throws {
        guard !isInitialized else { return }
        
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            isInitialized = true
            
            print("🔍 [GOOGLE SIGN IN] Configurado com clientID")
        } catch {
            print("❌ [GOOGLE SIGN IN] Erro na configuração: \(error)")
            throw GoogleSignInError.configurationError
        }
    }
    
    // MARK: - Private Methods
    
    private func storeCredentials(_ credential: AuthCredentials) async throws {
        guard let token = credential.token else {
            throw GoogleSignInError.invalidCredentials
        }
        
        do {
            try keychain.set(token, key: "google_user_id")
            currentCredential = credential
            
            print("🔍 [GOOGLE SIGN IN] Credenciais salvas no Keychain")
        } catch {
            print("❌ [GOOGLE SIGN IN] Erro ao salvar credenciais: \(error)")
            throw GoogleSignInError.failed(error)
        }
    }
    
    private func clearStoredCredentials() async throws {
        do {
            try keychain.remove("google_user_id")
            print("🔍 [GOOGLE SIGN IN] Credenciais removidas do Keychain")
        } catch {
            print("❌ [GOOGLE SIGN IN] Erro ao remover credenciais: \(error)")
            throw GoogleSignInError.failed(error)
        }
    }
}

// MARK: - Mock Implementation

/// Implementação mock do GoogleSignInService para testes e previews
final class MockGoogleSignInService: GoogleSignInServiceProtocol {
    
    var isAuthenticated: Bool = false
    var isAvailable: Bool = true
    
    private var shouldSucceed: Bool = true
    private var mockError: GoogleSignInError?
    
    func signIn() async throws -> AuthCredentials {
        if !shouldSucceed {
            throw mockError ?? GoogleSignInError.failed(NSError(domain: "Mock", code: -1))
        }
        
        isAuthenticated = true
        let credential = AuthCredentials.google(token: "mock_google_token_123")
        
        print("🎭 [MOCK GOOGLE SIGN IN] Login simulado")
        return credential
    }
    
    func signOut() async throws {
        isAuthenticated = false
        print("🎭 [MOCK GOOGLE SIGN IN] Logout simulado")
    }
    
    func validateSession() async throws -> Bool {
        return isAuthenticated
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        if isAuthenticated {
            return AuthCredentials.google(token: "mock_google_token_123")
        }
        return nil
    }
    
    func configure(clientID: String) async throws {
        print("🎭 [MOCK GOOGLE SIGN IN] Configuração simulada")
    }
    
    // MARK: - Mock Configuration
    
    func configureMock(success: Bool, error: GoogleSignInError? = nil) {
        self.shouldSucceed = success
        self.mockError = error
    }
    
    func resetMock() {
        self.isAuthenticated = false
        self.shouldSucceed = true
        self.mockError = nil
    }
} 