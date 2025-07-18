import Foundation
import LocalAuthentication
import Security
import KeychainAccess

/// Implementação do Biometric Authentication Service
/// 
/// **Responsabilidade:** Autenticação biométrica usando Face ID/Touch ID
/// - Verificação de disponibilidade biométrica
/// - Autenticação com Face ID/Touch ID
/// - Persistência de tokens seguros no Keychain
/// - Tratamento de erros específicos
final class BiometricAuthService: NSObject, BiometricAuthServiceProtocol {
    
    // MARK: - Properties
    
    private let keychain: Keychain
    private let context: LAContext
    private var currentCredential: AuthCredentials?
    
    // MARK: - Initialization
    
    override init() {
        self.keychain = Keychain(service: "com.fitter.biometric-auth")
        self.context = LAContext()
        super.init()
    }
    
    // MARK: - BiometricAuthServiceProtocol
    
    var isAuthenticated: Bool {
        return hasStoredBiometricToken()
    }
    
    var isAvailable: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func signIn() async throws -> AuthCredentials {
        guard isAvailable else {
            throw BiometricAuthError.notAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let reason = "Autentique-se para acessar o Fitter"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error = error {
                    let biometricError = self.mapLAError(error)
                    continuation.resume(throwing: biometricError)
                    return
                }
                
                guard success else {
                    continuation.resume(throwing: BiometricAuthError.authenticationFailed)
                    return
                }
                
                // Gerar token biométrico
                let biometricData = self.generateBiometricToken()
                let credential = AuthCredentials.biometric(data: biometricData)
                
                // Salvar token
                Task {
                    do {
                        try await self.storeBiometricToken(biometricData)
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
            try await clearStoredBiometricToken()
            print("🔐 [BIOMETRIC AUTH] Logout realizado")
        } catch {
            print("❌ [BIOMETRIC AUTH] Erro no logout: \(error)")
            throw BiometricAuthError.failed(error)
        }
    }
    
    func validateSession() async throws -> Bool {
        return hasStoredBiometricToken()
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        guard let biometricData = try? getStoredBiometricToken() else {
            return nil
        }
        
        let credential = AuthCredentials.biometric(data: biometricData)
        print("🔐 [BIOMETRIC AUTH] Credenciais restauradas")
        return credential
    }
    
    func checkBiometricAvailability() async -> BiometricAvailability {
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                return .unavailable(reason: error.localizedDescription)
            }
            return .unavailable(reason: "Biometria não disponível")
        }
        
        switch context.biometryType {
        case .faceID:
            return .available(type: .faceID)
        case .touchID:
            return .available(type: .touchID)
        case .none:
            return .notEnrolled
        @unknown default:
            return .unavailable(reason: "Tipo biométrico desconhecido")
        }
    }
    
    func enableBiometric(for user: CDAppUser) async throws {
        guard isAvailable else {
            throw BiometricAuthError.notAvailable
        }
        
        do {
            let biometricData = generateBiometricToken()
            try await storeBiometricToken(biometricData)
            
            // Atualizar usuário no Core Data
            user.biometricEnabled = true
            user.lastLoginDate = Date()
            
            print("🔐 [BIOMETRIC AUTH] Biometria habilitada para usuário")
        } catch {
            print("❌ [BIOMETRIC AUTH] Erro ao habilitar biometria: \(error)")
            throw BiometricAuthError.failed(error)
        }
    }
    
    func disableBiometric(for user: CDAppUser) async throws {
        do {
            try await clearStoredBiometricToken()
            
            // Atualizar usuário no Core Data
            user.biometricEnabled = false
            
            print("🔐 [BIOMETRIC AUTH] Biometria desabilitada para usuário")
        } catch {
            print("❌ [BIOMETRIC AUTH] Erro ao desabilitar biometria: \(error)")
            throw BiometricAuthError.failed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func generateBiometricToken() -> Data {
        // Gerar token único para biometria
        let uuid = UUID().uuidString
        return uuid.data(using: .utf8) ?? Data()
    }
    
    private func storeBiometricToken(_ token: Data) async throws {
        do {
            try keychain.set(token, key: "biometric_token")
            print("🔐 [BIOMETRIC AUTH] Token biométrico salvo no Keychain")
        } catch {
            print("❌ [BIOMETRIC AUTH] Erro ao salvar token: \(error)")
            throw BiometricAuthError.failed(error)
        }
    }
    
    private func getStoredBiometricToken() throws -> Data? {
        return try keychain.getData("biometric_token")
    }
    
    private func hasStoredBiometricToken() -> Bool {
        return (try? getStoredBiometricToken()) != nil
    }
    
    private func clearStoredBiometricToken() async throws {
        do {
            try keychain.remove("biometric_token")
            print("🔐 [BIOMETRIC AUTH] Token biométrico removido do Keychain")
        } catch {
            print("❌ [BIOMETRIC AUTH] Erro ao remover token: \(error)")
            throw BiometricAuthError.failed(error)
        }
    }
    
    private func mapLAError(_ error: Error) -> BiometricAuthError {
        if let laError = error as? LAError {
            switch laError.code {
            case .authenticationFailed:
                return .authenticationFailed
            case .userCancel:
                return .cancelled
            case .userFallback:
                return .fallbackRequired
            case .systemCancel:
                return .cancelled
            case .passcodeNotSet:
                return .passcodeNotSet
            case .biometryNotAvailable:
                return .notAvailable
            case .biometryNotEnrolled:
                return .notEnrolled
            case .biometryLockout:
                return .lockedOut
            case .appCancel:
                return .cancelled
            case .invalidContext:
                return .invalidContext
            case .notInteractive:
                return .notInteractive
            @unknown default:
                return .failed(error)
            }
        }
        return .failed(error)
    }
}

// MARK: - Mock Implementation

/// Implementação mock do BiometricAuthService para testes e previews
final class MockBiometricAuthService: BiometricAuthServiceProtocol {
    
    var isAuthenticated: Bool = false
    var isAvailable: Bool = true
    
    private var shouldSucceed: Bool = true
    private var mockError: BiometricAuthError?
    private var mockBiometricType: LABiometryType = .faceID
    
    func signIn() async throws -> AuthCredentials {
        if !shouldSucceed {
            throw mockError ?? BiometricAuthError.failed(NSError(domain: "Mock", code: -1))
        }
        
        isAuthenticated = true
        let biometricData = "mock_biometric_token_123".data(using: .utf8) ?? Data()
        let credential = AuthCredentials.biometric(data: biometricData)
        
        print("🎭 [MOCK BIOMETRIC AUTH] Login simulado")
        return credential
    }
    
    func signOut() async throws {
        isAuthenticated = false
        print("🎭 [MOCK BIOMETRIC AUTH] Logout simulado")
    }
    
    func validateSession() async throws -> Bool {
        return isAuthenticated
    }
    
    func restoreCredentials() async throws -> AuthCredentials? {
        if isAuthenticated {
            let biometricData = "mock_biometric_token_123".data(using: .utf8) ?? Data()
            return AuthCredentials.biometric(data: biometricData)
        }
        return nil
    }
    
    func checkBiometricAvailability() async -> BiometricAvailability {
        if isAvailable {
            return .available(type: mockBiometricType)
        } else {
            return .unavailable(reason: "Biometria mock indisponível")
        }
    }
    
    func enableBiometric(for user: CDAppUser) async throws {
        if !shouldSucceed {
            throw mockError ?? BiometricAuthError.failed(NSError(domain: "Mock", code: -1))
        }
        
        user.biometricEnabled = true
        print("🎭 [MOCK BIOMETRIC AUTH] Biometria habilitada")
    }
    
    func disableBiometric(for user: CDAppUser) async throws {
        if !shouldSucceed {
            throw mockError ?? BiometricAuthError.failed(NSError(domain: "Mock", code: -1))
        }
        
        user.biometricEnabled = false
        print("🎭 [MOCK BIOMETRIC AUTH] Biometria desabilitada")
    }
    
    // MARK: - Mock Configuration
    
    func configureMock(success: Bool, error: BiometricAuthError? = nil, biometricType: LABiometryType = .faceID) {
        self.shouldSucceed = success
        self.mockError = error
        self.mockBiometricType = biometricType
    }
    
    func resetMock() {
        self.isAuthenticated = false
        self.shouldSucceed = true
        self.mockError = nil
        self.mockBiometricType = .faceID
    }
} 