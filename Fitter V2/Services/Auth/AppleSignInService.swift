import Foundation
import AuthenticationServices
import Security
import KeychainAccess

/// Implementação do Apple Sign In Service
/// 
/// **Responsabilidade:** Autenticação com Apple ID usando ASAuthorizationAppleIDProvider
/// - Login/logout com Apple ID
/// - Validação de sessão
/// - Persistência de credenciais no Keychain
/// - Tratamento de erros específicos
final class AppleSignInService: NSObject, AppleSignInServiceProtocol {
    
    // MARK: - Properties
    
    private let keychain: Keychain
    private let appleIDProvider: ASAuthorizationAppleIDProvider
    private var currentCredential: AuthCredentials?
    
    // MARK: - Initialization
    
    override init() {
        self.keychain = Keychain(service: "com.fitter.apple-signin")
        self.appleIDProvider = ASAuthorizationAppleIDProvider()
        super.init()
    }
    
    // MARK: - AppleSignInServiceProtocol
    
    var isAuthenticated: Bool {
        return currentCredential != nil
    }
    
    var isAvailable: Bool {
        return ASAuthorizationAppleIDProvider.self.isSupported
    }
    
    func signIn() async throws -> AuthCredentials {
        guard isAvailable else {
            throw AppleSignInError.notAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = AppleSignInDelegate(continuation: continuation)
            authorizationController.presentationContextProvider = AppleSignInDelegate(continuation: continuation)
            authorizationController.performRequests()
        }
    }
    
    func signOut() async throws {
        // Apple Sign In não requer logout explícito
        // Apenas limpar credenciais locais
        try await clearStoredCredentials()
        currentCredential = nil
        
        print("🍎 [APPLE SIGN IN] Logout realizado")
    }
    
    func validateSession() async throws -> Bool {
        guard let credential = currentCredential,
              let token = credential.token else {
            return false
        }
        
        do {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.user = token
            
            // Tentar renovar credenciais
            let result = try await ASAuthorizationAppleIDProvider().createCredentialState(forUserID: token)
            return result == .authorized
        } catch {
            print("❌ [APPLE SIGN IN] Erro na validação: \(error)")
            return false
        }
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        do {
            guard let token = try keychain.get("apple_user_id") else {
                return nil
            }
            
            let credential = AuthCredentials.apple(token: token)
            currentCredential = credential
            
            print("🍎 [APPLE SIGN IN] Credenciais restauradas")
            return credential
        } catch {
            print("❌ [APPLE SIGN IN] Erro ao restaurar credenciais: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func storeCredentials(_ credential: AuthCredentials) async throws {
        guard let token = credential.token else {
            throw AppleSignInError.invalidCredentials
        }
        
        do {
            try keychain.set(token, key: "apple_user_id")
            currentCredential = credential
            
            print("🍎 [APPLE SIGN IN] Credenciais salvas no Keychain")
        } catch {
            print("❌ [APPLE SIGN IN] Erro ao salvar credenciais: \(error)")
            throw AppleSignInError.failed(error)
        }
    }
    
    private func clearStoredCredentials() async throws {
        do {
            try keychain.remove("apple_user_id")
            print("🍎 [APPLE SIGN IN] Credenciais removidas do Keychain")
        } catch {
            print("❌ [APPLE SIGN IN] Erro ao remover credenciais: \(error)")
            throw AppleSignInError.failed(error)
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate & ASAuthorizationControllerPresentationContextProviding

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    private let continuation: CheckedContinuation<AuthCredentials, Error>
    
    init(continuation: CheckedContinuation<AuthCredentials, Error>) {
        self.continuation = continuation
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: AppleSignInError.invalidCredentials)
            return
        }
        
        let credential = AuthCredentials.apple(token: appleIDCredential.user)
        
        // Salvar credenciais no Keychain
        Task {
            do {
                try await storeCredentials(credential)
                continuation.resume(returning: credential)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                continuation.resume(throwing: AppleSignInError.cancelled)
            case .failed:
                continuation.resume(throwing: AppleSignInError.failed(error))
            case .invalidResponse:
                continuation.resume(throwing: AppleSignInError.invalidCredentials)
            case .notHandled:
                continuation.resume(throwing: AppleSignInError.failed(error))
            case .unknown:
                continuation.resume(throwing: AppleSignInError.failed(error))
            @unknown default:
                continuation.resume(throwing: AppleSignInError.failed(error))
            }
        } else {
            continuation.resume(throwing: AppleSignInError.failed(error))
        }
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("Nenhuma janela disponível para apresentação")
        }
        return window
    }
    
    private func storeCredentials(_ credential: AuthCredentials) async throws {
        // Implementação simplificada para o delegate
        // Em uma implementação real, isso seria feito no serviço principal
        print("🍎 [APPLE SIGN IN] Credenciais processadas")
    }
}

// MARK: - Mock Implementation

/// Implementação mock do AppleSignInService para testes e previews
final class MockAppleSignInService: AppleSignInServiceProtocol {
    
    var isAuthenticated: Bool = false
    var isAvailable: Bool = true
    
    private var shouldSucceed: Bool = true
    private var mockError: AppleSignInError?
    
    func signIn() async throws -> AuthCredentials {
        if !shouldSucceed {
            throw mockError ?? AppleSignInError.failed(NSError(domain: "Mock", code: -1))
        }
        
        isAuthenticated = true
        let credential = AuthCredentials.apple(token: "mock_apple_token_123")
        
        print("🎭 [MOCK APPLE SIGN IN] Login simulado")
        return credential
    }
    
    func signOut() async throws {
        isAuthenticated = false
        print("🎭 [MOCK APPLE SIGN IN] Logout simulado")
    }
    
    func validateSession() async throws -> Bool {
        return isAuthenticated
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        if isAuthenticated {
            return AuthCredentials.apple(token: "mock_apple_token_123")
        }
        return nil
    }
    
    // MARK: - Mock Configuration
    
    func configureMock(success: Bool, error: AppleSignInError? = nil) {
        self.shouldSucceed = success
        self.mockError = error
    }
    
    func resetMock() {
        self.isAuthenticated = false
        self.shouldSucceed = true
        self.mockError = nil
    }
} 