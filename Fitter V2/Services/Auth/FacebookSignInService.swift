import Foundation
import FBSDKLoginKit
import Security
import KeychainAccess

/// Implementação do Facebook Sign In Service
/// 
/// **Responsabilidade:** Autenticação com Facebook usando FBSDKLoginKit
/// - Login/logout com Facebook Account
/// - Validação de sessão
/// - Persistência de credenciais no Keychain
/// - Tratamento de erros específicos
final class FacebookSignInService: NSObject, FacebookSignInServiceProtocol {
    
    // MARK: - Properties
    
    private let keychain: Keychain
    private var currentCredential: AuthCredentials?
    private var loginManager: LoginManager
    
    // MARK: - Initialization
    
    override init() {
        self.keychain = Keychain(service: "com.fitter.facebook-signin")
        self.loginManager = LoginManager()
        super.init()
    }
    
    // MARK: - FacebookSignInServiceProtocol
    
    var isAuthenticated: Bool {
        return AccessToken.current != nil
    }
    
    var isAvailable: Bool {
        return AccessToken.current != nil
    }
    
    func signIn() async throws -> AuthCredentials {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw FacebookSignInError.notAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            loginManager.logIn(permissions: ["public_profile", "email"], from: window) { result, error in
                if let error = error {
                    continuation.resume(throwing: FacebookSignInError.failed(error))
                    return
                }
                
                guard let result = result, !result.isCancelled else {
                    continuation.resume(throwing: FacebookSignInError.cancelled)
                    return
                }
                
                guard let accessToken = result.token else {
                    continuation.resume(throwing: FacebookSignInError.invalidCredentials)
                    return
                }
                
                let credential = AuthCredentials.facebook(token: accessToken.tokenString)
                
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
            loginManager.logOut()
            try await clearStoredCredentials()
            currentCredential = nil
            
            print("📘 [FACEBOOK SIGN IN] Logout realizado")
        } catch {
            print("❌ [FACEBOOK SIGN IN] Erro no logout: \(error)")
            throw FacebookSignInError.failed(error)
        }
    }
    
    func validateSession() async throws -> Bool {
        guard let accessToken = AccessToken.current else {
            return false
        }
        
        do {
            // Verificar se o token ainda é válido
            let isValid = !accessToken.isExpired
            return isValid
        } catch {
            print("❌ [FACEBOOK SIGN IN] Erro na validação: \(error)")
            return false
        }
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        guard let accessToken = AccessToken.current else {
            return nil
        }
        
        let credential = AuthCredentials.facebook(token: accessToken.tokenString)
        currentCredential = credential
        
        print("📘 [FACEBOOK SIGN IN] Credenciais restauradas")
        return credential
    }
    
    func configure(appID: String) async throws {
        do {
            // Configuração do Facebook SDK
            Settings.appID = appID
            Settings.displayName = "Fitter"
            
            print("📘 [FACEBOOK SIGN IN] Configurado com appID")
        } catch {
            print("❌ [FACEBOOK SIGN IN] Erro na configuração: \(error)")
            throw FacebookSignInError.configurationError
        }
    }
    
    // MARK: - Private Methods
    
    private func storeCredentials(_ credential: AuthCredentials) async throws {
        guard let token = credential.token else {
            throw FacebookSignInError.invalidCredentials
        }
        
        do {
            try keychain.set(token, key: "facebook_user_id")
            currentCredential = credential
            
            print("📘 [FACEBOOK SIGN IN] Credenciais salvas no Keychain")
        } catch {
            print("❌ [FACEBOOK SIGN IN] Erro ao salvar credenciais: \(error)")
            throw FacebookSignInError.failed(error)
        }
    }
    
    private func clearStoredCredentials() async throws {
        do {
            try keychain.remove("facebook_user_id")
            print("📘 [FACEBOOK SIGN IN] Credenciais removidas do Keychain")
        } catch {
            print("❌ [FACEBOOK SIGN IN] Erro ao remover credenciais: \(error)")
            throw FacebookSignInError.failed(error)
        }
    }
}

// MARK: - Mock Implementation

/// Implementação mock do FacebookSignInService para testes e previews
final class MockFacebookSignInService: FacebookSignInServiceProtocol {
    
    var isAuthenticated: Bool = false
    var isAvailable: Bool = true
    
    private var shouldSucceed: Bool = true
    private var mockError: FacebookSignInError?
    
    func signIn() async throws -> AuthCredentials {
        if !shouldSucceed {
            throw mockError ?? FacebookSignInError.failed(NSError(domain: "Mock", code: -1))
        }
        
        isAuthenticated = true
        let credential = AuthCredentials.facebook(token: "mock_facebook_token_123")
        
        print("🎭 [MOCK FACEBOOK SIGN IN] Login simulado")
        return credential
    }
    
    func signOut() async throws {
        isAuthenticated = false
        print("🎭 [MOCK FACEBOOK SIGN IN] Logout simulado")
    }
    
    func validateSession() async throws -> Bool {
        return isAuthenticated
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        if isAuthenticated {
            return AuthCredentials.facebook(token: "mock_facebook_token_123")
        }
        return nil
    }
    
    func configure(appID: String) async throws {
        print("🎭 [MOCK FACEBOOK SIGN IN] Configuração simulada")
    }
    
    // MARK: - Mock Configuration
    
    func configureMock(success: Bool, error: FacebookSignInError? = nil) {
        self.shouldSucceed = success
        self.mockError = error
    }
    
    func resetMock() {
        self.isAuthenticated = false
        self.shouldSucceed = true
        self.mockError = nil
    }
} 