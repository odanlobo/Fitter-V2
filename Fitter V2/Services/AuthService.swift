import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData
import GoogleSignIn
import GoogleSignInSwift
import FirebaseCore
import FacebookLogin

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case userNotFound
    case wrongPassword
    case unknownError
    case networkError
    case googleSignInError
    case facebookSignInError
    case noRootViewController
    
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
        case .googleSignInError:
            return "Erro ao fazer login com Google."
        case .facebookSignInError:
            return "Erro ao fazer login com Facebook."
        case .noRootViewController:
            return "Erro interno do aplicativo."
        case .unknownError:
            return "Ocorreu um erro inesperado."
        }
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()
    
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    private let modelContext = PersistenceController.shared.container.mainContext
    
    private init() {}
    
    // MARK: – Usuário atual mapeado para AppUser
    var currentUser: AppUser? {
        guard let fbUser = auth.currentUser else { return nil }
        
        // extrai o uid para uma String pura
        let fbUid = fbUser.uid
        
        // 1) Cria o predicado do SwiftData
        let predicate = #Predicate<AppUser> { $0.providerId == fbUid }

        // 2) Instancia o FetchDescriptor explicando o tipo <AppUser>
        let request = FetchDescriptor<AppUser>(predicate: predicate)

        // 3) Faz o fetch (throws), então usamos try?
        let results = try? modelContext.fetch(request)

        if let existing = results?.first {
            // Atualiza o último login
            existing.lastLoginDate = Date()
            try? modelContext.save()
            return existing
        }

        // 4) Se não existir, cria um novo AppUser
        let newUser = AppUser(
            name: fbUser.displayName ?? "",
            birthDate: Date(),    // ajuste no seu fluxo
            height: 0,
            weight: 0,
            provider: fbUser.providerID,
            providerId: fbUser.uid,
            email: fbUser.email,
            profilePictureURL: fbUser.photoURL,
            locale: nil,
            gender: nil
        )
        newUser.lastLoginDate = Date()

        modelContext.insert(newUser)
        try? modelContext.save()
        return newUser
    }
    
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("Usuário logado com sucesso: \(result.user.uid)")
            ConnectivityManager.shared.sendAuthStatusToWatch()
        } catch {
            throw mapFirebaseError(error)
        }
    }
    
    func createAccount(name: String, email: String, password: String) async throws {
        do {
            // Criar usuário no Firebase Auth
            let result = try await auth.createUser(withEmail: email, password: password)
            
            // Criar perfil do usuário no Firestore
            let userData: [String: Any] = [
                "name": name,
                "email": email,
                "createdAt": Timestamp(),
                "updatedAt": Timestamp()
            ]
            
            try await firestore
                .collection("users")
                .document(result.user.uid)
                .setData(userData)
            
            // Atualizar o displayName do usuário
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
            
            print("Conta criada com sucesso: \(result.user.uid)")
        } catch {
            throw mapFirebaseError(error)
        }
    }
    
    func signOut() throws {
        do {
            try auth.signOut()
            ConnectivityManager.shared.sendAuthStatusToWatch()
        } catch {
            throw AuthError.unknownError
        }
    }
    
    func resetPassword(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            throw mapFirebaseError(error)
        }
    }
    
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.googleSignInError
        }
        
        // Configurar o Google Sign In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        do {
            // Fazer login com Google
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.googleSignInError
            }
            
            // Criar credencial para o Firebase
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            
            // Fazer login no Firebase
            let authResult = try await auth.signIn(with: credential)
            
            // Criar ou atualizar dados do usuário no Firestore
            let userData: [String: Any] = [
                "name": result.user.profile?.name ?? "",
                "email": result.user.profile?.email ?? "",
                "photoURL": result.user.profile?.imageURL(withDimension: 200)?.absoluteString ?? "",
                "updatedAt": Timestamp()
            ]
            
            try await firestore
                .collection("users")
                .document(authResult.user.uid)
                .setData(userData, merge: true)
            
            print("Login com Google realizado com sucesso: \(authResult.user.uid)")
        } catch {
            throw AuthError.googleSignInError
        }
    }
    
    func signInWithFacebook() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        let loginManager = LoginManager()
        
        return try await withCheckedThrowingContinuation { continuation in
            loginManager.logIn(permissions: ["public_profile", "email"], from: rootViewController) { loginResult, error in
                if error != nil {
                    continuation.resume(throwing: AuthError.facebookSignInError)
                    return
                }
                
                guard let loginResult = loginResult else {
                    continuation.resume(throwing: AuthError.facebookSignInError)
                    return
                }
                
                if loginResult.isCancelled {
                    continuation.resume(throwing: AuthError.facebookSignInError)
                    return
                }
                
                guard let accessToken = AccessToken.current else {
                    continuation.resume(throwing: AuthError.facebookSignInError)
                    return
                }
                
                let credential = FacebookAuthProvider.credential(withAccessToken: accessToken.tokenString)
                
                Task {
                    do {
                        let authResult = try await self.auth.signIn(with: credential)
                        
                        // Criar ou atualizar dados do usuário no Firestore
                        let userData: [String: Any] = [
                            "name": authResult.user.displayName ?? "",
                            "email": authResult.user.email ?? "",
                            "photoURL": authResult.user.photoURL?.absoluteString ?? "",
                            "updatedAt": Timestamp()
                        ]
                        
                        try await self.firestore
                            .collection("users")
                            .document(authResult.user.uid)
                            .setData(userData, merge: true)
                        
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: AuthError.facebookSignInError)
                    }
                }
            }
        }
    }
    
    private func mapFirebaseError(_ error: Error) -> AuthError {
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
            return .unknownError
        }
    }
} 
