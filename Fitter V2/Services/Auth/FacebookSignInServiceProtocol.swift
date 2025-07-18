import Foundation

/// Protocolo para autenticação com Facebook
/// Implementa interface limpa para login/logout usando Facebook SDK
protocol FacebookSignInServiceProtocol {
    /// Estado atual da autenticação Facebook
    var isAuthenticated: Bool { get }
    
    /// Realiza login com Facebook
    /// - Returns: Resultado da autenticação com credenciais
    func signIn() async throws -> AuthCredentials
    
    /// Realiza logout da conta Facebook
    func signOut() async throws
    
    /// Verifica se o dispositivo tem o app do Facebook instalado
    var isAvailable: Bool { get }
    
    /// Verifica se há uma sessão Facebook válida
    func validateSession() async throws -> Bool
    
    /// Recupera credenciais salvas do Keychain
    func restoreCredentials() async throws -> AuthCredentials?
    
    /// Desconecta completamente a conta Facebook
    func disconnect() async throws
    
    /// Solicita permissões adicionais do Facebook
    /// - Parameter permissions: Array de permissões a serem solicitadas
    func requestAdditionalPermissions(_ permissions: [String]) async throws
}

/// Erros específicos do Facebook Sign In
enum FacebookSignInError: LocalizedError {
    case notAvailable
    case cancelled
    case failed(Error)
    case invalidCredentials
    case sessionExpired
    case permissionDenied
    case networkError
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Facebook Sign In não está disponível"
        case .cancelled:
            return "Login com Facebook foi cancelado"
        case .failed(let error):
            return "Erro no login com Facebook: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Credenciais Facebook inválidas"
        case .sessionExpired:
            return "Sessão Facebook expirada. Por favor, faça login novamente"
        case .permissionDenied:
            return "Permissões necessárias não foram concedidas"
        case .networkError:
            return "Erro de conexão ao fazer login com Facebook"
        case .serverError:
            return "Erro no servidor do Facebook"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notAvailable:
            return "Verifique se o app do Facebook está instalado e tente novamente"
        case .cancelled:
            return "Tente fazer login novamente quando desejar"
        case .failed:
            return "Verifique sua conexão e tente novamente"
        case .invalidCredentials:
            return "Faça login novamente com sua conta Facebook"
        case .sessionExpired:
            return "Faça login novamente para continuar usando o app"
        case .permissionDenied:
            return "Revise as permissões solicitadas e tente novamente"
        case .networkError:
            return "Verifique sua conexão com a internet e tente novamente"
        case .serverError:
            return "Tente novamente mais tarde"
        }
    }
} 