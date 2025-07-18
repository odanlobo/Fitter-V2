import Foundation
import AuthenticationServices

/// Protocolo para autenticação com Apple Sign In
/// Implementa interface limpa para login/logout usando ASAuthorizationAppleIDProvider
protocol AppleSignInServiceProtocol {
    /// Estado atual da autenticação Apple
    var isAuthenticated: Bool { get }
    
    /// Realiza login com Apple ID
    /// - Returns: Resultado da autenticação com credenciais
    func signIn() async throws -> AuthCredentials
    
    /// Realiza logout da conta Apple
    func signOut() async throws
    
    /// Verifica se o dispositivo suporta Apple Sign In
    var isAvailable: Bool { get }
    
    /// Verifica se há uma sessão Apple válida
    func validateSession() async throws -> Bool
    
    /// Recupera credenciais salvas do Keychain
    func restoreCredentials() async throws -> AuthCredentials?
}

/// Erros específicos do Apple Sign In
enum AppleSignInError: LocalizedError {
    case notAvailable
    case cancelled
    case failed(Error)
    case invalidCredentials
    case sessionExpired
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Sign In não está disponível neste dispositivo"
        case .cancelled:
            return "Login com Apple foi cancelado"
        case .failed(let error):
            return "Erro no login com Apple: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Credenciais Apple inválidas"
        case .sessionExpired:
            return "Sessão Apple expirada. Por favor, faça login novamente"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notAvailable:
            return "Verifique se seu dispositivo suporta Apple Sign In e se você está conectado ao iCloud"
        case .cancelled:
            return "Tente fazer login novamente quando desejar"
        case .failed:
            return "Verifique sua conexão e tente novamente"
        case .invalidCredentials:
            return "Faça login novamente com sua conta Apple"
        case .sessionExpired:
            return "Faça login novamente para continuar usando o app"
        }
    }
} 