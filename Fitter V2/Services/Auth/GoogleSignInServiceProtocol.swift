import Foundation

/// Protocolo para autenticação com Google Sign In
/// Implementa interface limpa para login/logout usando GoogleSignIn SDK
protocol GoogleSignInServiceProtocol {
    /// Estado atual da autenticação Google
    var isAuthenticated: Bool { get }
    
    /// Realiza login com Google
    /// - Returns: Resultado da autenticação com credenciais
    func signIn() async throws -> AuthCredentials
    
    /// Realiza logout da conta Google
    func signOut() async throws
    
    /// Verifica se o dispositivo tem o app do Google instalado
    var isAvailable: Bool { get }
    
    /// Verifica se há uma sessão Google válida
    func validateSession() async throws -> Bool
    
    /// Recupera credenciais salvas do Keychain
    func restoreCredentials() async throws -> AuthCredentials?
    
    /// Desconecta completamente a conta Google
    func disconnect() async throws
}

/// Erros específicos do Google Sign In
enum GoogleSignInError: LocalizedError {
    case notAvailable
    case cancelled
    case failed(Error)
    case invalidCredentials
    case sessionExpired
    case networkError
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Google Sign In não está disponível"
        case .cancelled:
            return "Login com Google foi cancelado"
        case .failed(let error):
            return "Erro no login com Google: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Credenciais Google inválidas"
        case .sessionExpired:
            return "Sessão Google expirada. Por favor, faça login novamente"
        case .networkError:
            return "Erro de conexão ao fazer login com Google"
        case .serverError:
            return "Erro no servidor do Google"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notAvailable:
            return "Verifique se o app do Google está instalado e tente novamente"
        case .cancelled:
            return "Tente fazer login novamente quando desejar"
        case .failed:
            return "Verifique sua conexão e tente novamente"
        case .invalidCredentials:
            return "Faça login novamente com sua conta Google"
        case .sessionExpired:
            return "Faça login novamente para continuar usando o app"
        case .networkError:
            return "Verifique sua conexão com a internet e tente novamente"
        case .serverError:
            return "Tente novamente mais tarde"
        }
    }
} 