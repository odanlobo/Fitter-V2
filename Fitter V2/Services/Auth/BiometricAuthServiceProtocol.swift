import Foundation
import LocalAuthentication

/// Protocolo para autenticação biométrica
/// Implementa interface limpa para autenticação via Face ID/Touch ID
protocol BiometricAuthServiceProtocol {
    /// Verifica se a autenticação biométrica está disponível
    var isAvailable: Bool { get }
    
    /// Verifica se a autenticação biométrica está ativada para o usuário atual
    var isAuthenticated: Bool { get }
    
    /// Realiza login biométrico
    /// - Returns: Credenciais da autenticação biométrica
    func signIn() async throws -> AuthCredentials
    
    /// Realiza logout biométrico
    func signOut() async throws
    
    /// Verifica se há uma sessão biométrica válida
    func validateSession() async throws -> Bool
    
    /// Recupera credenciais biométricas do Keychain
    func restoreCredentials() async throws -> AuthCredentials?
    
    /// Verifica disponibilidade detalhada de biometria
    func checkBiometricAvailability() async -> BiometricAvailability
    
    /// Ativa autenticação biométrica para o usuário
    /// - Parameter user: Usuário para configurar biometria
    func enableBiometric(for user: CDAppUser) async throws
    
    /// Desativa autenticação biométrica para o usuário
    /// - Parameter user: Usuário para remover biometria
    func disableBiometric(for user: CDAppUser) async throws
}

/// Erros específicos da autenticação biométrica
enum BiometricAuthError: LocalizedError {
    case notAvailable
    case notEnrolled
    case cancelled
    case failed(Error)
    case lockout
    case invalidToken
    case keychain(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Autenticação biométrica não disponível neste dispositivo"
        case .notEnrolled:
            return "Nenhuma biometria cadastrada no dispositivo"
        case .cancelled:
            return "Autenticação biométrica cancelada"
        case .failed(let error):
            return "Erro na autenticação biométrica: \(error.localizedDescription)"
        case .lockout:
            return "Autenticação biométrica bloqueada por muitas tentativas"
        case .invalidToken:
            return "Token biométrico inválido"
        case .keychain(let error):
            return "Erro no Keychain: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notAvailable:
            return "Este dispositivo não suporta autenticação biométrica"
        case .notEnrolled:
            return "Configure Face ID/Touch ID nas configurações do seu iPhone"
        case .cancelled:
            return "Tente novamente quando desejar"
        case .failed:
            return "Verifique se seu rosto/dedo está posicionado corretamente"
        case .lockout:
            return "Use sua senha do iPhone para desbloquear a autenticação biométrica"
        case .invalidToken:
            return "Faça login novamente para reativar a autenticação biométrica"
        case .keychain:
            return "Tente desativar e ativar novamente a autenticação biométrica"
        }
    }
} 