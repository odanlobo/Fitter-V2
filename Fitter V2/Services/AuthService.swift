import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import GoogleSignInSwift
import FirebaseCore
import FacebookLogin
import CoreData

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
final class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    private let auth = Auth.auth()
    private let firestore = Firestore.firestore()
    
    // Core Data context
    private var viewContext: NSManagedObjectContext {
        return CoreDataStack.shared.viewContext
    }
    
    private init() {}
    
    // MARK: – Usuário atual mapeado para CDAppUser
    var currentUser: CDAppUser? {
        guard let fbUser = auth.currentUser else { return nil }
        
        // extrai o uid para uma String pura
        let fbUid = fbUser.uid
        
        // 1) Cria a fetch request do Core Data
        let request: NSFetchRequest<CDAppUser> = CDAppUser.fetchRequest()
        request.predicate = NSPredicate(format: "providerId == %@", fbUid)
        request.fetchLimit = 1

        // 2) Faz o fetch
        let results = try? viewContext.fetch(request)

        if let existing = results?.first {
            // Atualiza o último login e email se necessário
            existing.lastLoginDate = Date()
            if let email = fbUser.email {
                existing.email = email
            }
            if let name = fbUser.displayName, !name.isEmpty {
                existing.name = name
            }
            existing.updatedAt = Date()
            try? viewContext.save()
            return existing
        }

        // 3) Se não existir, cria um novo CDAppUser
        let newUser = CDAppUser(context: viewContext)
        newUser.id = UUID()
        newUser.name = fbUser.displayName ?? ""
        newUser.birthDate = Date()    // ajuste no seu fluxo
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
        newUser.cloudSyncStatus = CloudSyncStatus.synced.rawValue  // Campo obrigatório

        try? viewContext.save()
        return newUser
    }
    
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("Usuário logado com sucesso: \(result.user.uid)")
            
            // Exibe dados do usuário no terminal
            await printUserDataToTerminal()
            
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
            
            // Exibe dados do usuário no terminal
            await printUserDataToTerminal()
            
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
            
            // Exibe dados do usuário no terminal
            await printUserDataToTerminal()
            
            ConnectivityManager.shared.sendAuthStatusToWatch()
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
                        
                        print("Login com Facebook realizado com sucesso: \(authResult.user.uid)")
                        
                        // Exibe dados do usuário no terminal
                        await self.printUserDataToTerminal()
                        
                        ConnectivityManager.shared.sendAuthStatusToWatch()
                        
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
    
    // MARK: - Terminal Data Display
    
    /// Exibe dados do usuário no terminal após login
    private func printUserDataToTerminal() async {
        print("\n" + String(repeating: "=", count: 60))
        print("📱 DADOS DO USUÁRIO LOGADO")
        print(String(repeating: "=", count: 60))
        
        guard let user = currentUser else {
            print("❌ Nenhum usuário encontrado")
            print(String(repeating: "=", count: 60) + "\n")
            return
        }
        
        // Informações básicas do usuário
        print("👤 Nome: \(user.safeName)")
        print("📧 Email: \(user.safeEmail)")
        print("🔑 Provider ID: \(user.providerId ?? "N/A")")
        
        if let createdAt = user.createdAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("📅 Conta criada: \(formatter.string(from: createdAt))")
        }
        
        if let lastLogin = user.lastLoginDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("🕐 Último login: \(formatter.string(from: lastLogin))")
        }
        
        // Busca treinos localmente primeiro
        let localWorkoutCount = await getLocalWorkoutCount(for: user)
        print("🏋️‍♂️ Treinos locais: \(localWorkoutCount)")
        
        // Se não encontrar treinos localmente, busca no Firebase
        if localWorkoutCount == 0 {
            print("🔍 Buscando treinos no Firebase...")
            let firebaseWorkoutCount = await getFirebaseWorkoutCount(for: user)
            print("☁️ Treinos no Firebase: \(firebaseWorkoutCount)")
            
            if firebaseWorkoutCount == 0 {
                print("📊 Total de treinos: 0 treinos")
            } else {
                print("📊 Total de treinos: \(firebaseWorkoutCount) treinos (sincronizando...)")
            }
        } else {
            print("📊 Total de treinos: \(localWorkoutCount) treinos")
        }
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    /// Busca quantidade de treinos localmente no Core Data
    private func getLocalWorkoutCount(for user: CDAppUser) async -> Int {
        let request: NSFetchRequest<CDWorkoutPlan> = CDWorkoutPlan.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        
        do {
            let count = try viewContext.count(for: request)
            return count
        } catch {
            print("❌ Erro ao buscar treinos locais: \(error)")
            return 0
        }
    }
    
    /// Busca quantidade de treinos no Firebase
    private func getFirebaseWorkoutCount(for user: CDAppUser) async -> Int {
        guard let providerId = user.providerId else { return 0 }
        
        do {
            let snapshot = try await firestore
                .collection("users")
                .document(providerId)
                .collection("workoutPlans")
                .getDocuments()
            
            return snapshot.documents.count
        } catch {
            print("❌ Erro ao buscar treinos no Firebase: \(error)")
            return 0
        }
    }
} 
